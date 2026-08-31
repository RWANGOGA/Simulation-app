"""
Anatomy assistant endpoints (Step 7.4).

Exposes:
  GET  /anatomy/regions   - list all known regions (id, region, system)
  POST /anatomy/ask       - retriever + LLM call, returns structured JSON

The endpoint is publicly readable (no auth) for now so the patient-side
body map can call it without holding a practitioner token. If you want to
lock it down later, wrap the handlers with the same `get_current_doctor`
dependency used by `/auth/me`.
"""

from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any, Dict, List, Optional, Tuple

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.services import anatomy_retriever
from app.services.llm_client import is_configured, summarize_with_llm


logger = logging.getLogger(__name__)

router = APIRouter(prefix="/anatomy", tags=["anatomy"])


# ── Schemas ───────────────────────────────────────────────────────────────


class AnatomyAskRequest(BaseModel):
    region: Optional[str] = Field(
        default=None,
        description="Region label tapped on the body map, e.g. 'Chest / Heart'.",
    )
    complaint: str = Field(
        default="",
        max_length=1000,
        description="Short description of the patient's complaint.",
    )
    top_k: int = Field(default=3, ge=1, le=6)


class RetrievedChunk(BaseModel):
    id: str
    region: str
    system: str
    score: float
    text: str
    structures: List[str]
    common_conditions: List[str]
    red_flags: List[str]
    suggested_questions: List[str]


class AnatomyAskResponse(BaseModel):
    region: Optional[str]
    complaint: str
    llm_used: bool
    cached: bool
    summary: str
    structures: List[str]
    likely_conditions: List[Dict[str, str]]
    red_flags: List[str]
    suggested_questions: List[str]
    disclaimer: str
    sources: List[RetrievedChunk]


# ── Caching ───────────────────────────────────────────────────────────────


@lru_cache(maxsize=256)
def _cached_ask(
    region_key: str, complaint_key: str, top_k: int
) -> Dict[str, Any]:
    """Cache the full response payload (retrieval + LLM) per
    (region, complaint, top_k). Keeps the endpoint fast on repeated taps
    and avoids burning Groq quota."""
    return _run_ask(
        region=region_key or None,
        complaint=complaint_key,
        top_k=top_k,
    )


def _make_cache_key(
    region: Optional[str], complaint: str, top_k: int
) -> Tuple[str, str, int]:
    return (
        (region or "").strip(),
        complaint.strip(),
        top_k,
    )


# ── Core logic ────────────────────────────────────────────────────────────


def _hit_to_chunk(hit) -> RetrievedChunk:
    c = hit.chunk
    return RetrievedChunk(
        id=c.id,
        region=c.region,
        system=c.system,
        score=round(float(hit.score), 4),
        text=c.text,
        structures=c.structures,
        common_conditions=c.common_conditions,
        red_flags=c.red_flags,
        suggested_questions=c.suggested_questions,
    )


def _run_ask(
    region: Optional[str], complaint: str, top_k: int
) -> Dict[str, Any]:
    hits = anatomy_retriever.retrieve(region=region, query=complaint, top_k=top_k)
    sources = [_hit_to_chunk(h).model_dump() for h in hits]

    summary = summarize_with_llm(region=region, complaint=complaint, hits=hits)
    llm_used = summary is not None

    # Either an LLM-shaped dict, or a fallback built from the top chunk
    # so the UI always has a `summary` to display.
    if summary is None:
        top = hits[0].chunk if hits else None
        summary = {
            "summary": (
                f"Possible structures and conditions in the {region or 'selected'} "
                f"region based on the knowledge base."
                if top
                else "No matching anatomy context was found."
            ),
            "structures": top.structures if top else [],
            "likely_conditions": [
                {"name": c, "rationale": ""} for c in (top.common_conditions if top else [])
            ],
            "red_flags": top.red_flags if top else [],
            "suggested_questions": top.suggested_questions if top else [],
            "disclaimer": (
                "This is supportive information for the clinician, not a "
                "diagnosis. The knowledge base was used directly because the "
                "AI summarizer is unavailable."
            ),
        }

    return {
        "region": region,
        "complaint": complaint,
        "llm_used": llm_used,
        "cached": False,  # set by caller before returning
        **summary,
        "sources": sources,
    }


# ── Routes ────────────────────────────────────────────────────────────────


@router.get("/regions")
def list_regions():
    """All anatomy regions the body map can ask about."""
    return {"regions": anatomy_retriever.list_regions()}


@router.get("/status")
def status():
    """Lightweight health for the anatomy subsystem — useful for the
    Flutter app to decide whether to show an 'AI' badge or a 'KB only'
    badge before the user taps."""
    return {
        "kb_loaded": bool(anatomy_retriever.load_kb()),
        "llm_configured": is_configured(),
    }


@router.post("/ask", response_model=AnatomyAskResponse)
def ask(req: AnatomyAskRequest):
    region = (req.region or "").strip() or None
    complaint = (req.complaint or "").strip()

    if not region and not complaint:
        raise HTTPException(
            status_code=400,
            detail="Provide at least a region or a complaint.",
        )

    cache_key = _make_cache_key(region, complaint, req.top_k)
    info_before = _cached_ask.cache_info()
    result = _cached_ask(*cache_key)
    info_after = _cached_ask.cache_info()
    # A genuine hit is when lru_cache served the value from memory without
    # having to recompute, which it reports as `hits` going up.
    was_cached = info_after.hits > info_before.hits
    result["cached"] = was_cached
    return result
