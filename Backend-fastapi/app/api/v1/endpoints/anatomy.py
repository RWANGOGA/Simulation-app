"""
Anatomy assistant endpoints (Step 7.4).

Exposes:
  GET  /anatomy/regions   - list all known regions (id, region, system)
  POST /anatomy/ask       - retriever + LLM call, returns structured JSON
  POST /anatomy/clear     - clear conversation history

The endpoint is publicly readable (no auth) for now so the patient-side
body map can call it without holding a practitioner token. If you want to
lock it down later, wrap the handlers with the same `get_current_doctor`
dependency used by `/auth/me`.
"""

from __future__ import annotations

import logging
import time
from collections import defaultdict, deque
from functools import lru_cache
from typing import Any, Dict, List, Optional, Tuple

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.services import anatomy_retriever
from app.services.llm_client import is_configured, summarize_with_llm


logger = logging.getLogger(__name__)

router = APIRouter(prefix="/anatomy", tags=["anatomy"])


# ── Conversation Memory ───────────────────────────────────────────────────


class _ConversationStore:
    """Simple in-memory conversation history store.
    
    In production, replace this with Redis or database-backed storage.
    Each conversation retains the last N turns for context.
    """

    def __init__(self, max_turns: int = 10, ttl_seconds: int = 3600):
        self._store: Dict[str, deque] = defaultdict(deque)
        self._timestamps: Dict[str, float] = {}
        self._max_turns = max_turns
        self._ttl = ttl_seconds

    def get(self, conversation_id: str) -> List[Dict[str, str]]:
        self._cleanup(conversation_id)
        return list(self._store[conversation_id])

    def append(self, conversation_id: str, role: str, content: str) -> None:
        self._cleanup(conversation_id)
        self._store[conversation_id].append({"role": role, "content": content})
        self._timestamps[conversation_id] = time.time()
        while len(self._store[conversation_id]) > self._max_turns:
            self._store[conversation_id].popleft()

    def clear(self, conversation_id: str) -> None:
        self._store.pop(conversation_id, None)
        self._timestamps.pop(conversation_id, None)

    def _cleanup(self, conversation_id: str) -> None:
        if conversation_id in self._timestamps:
            if time.time() - self._timestamps[conversation_id] > self._ttl:
                self.clear(conversation_id)


_conversation_store = _ConversationStore()


@router.post("/clear")
def clear_conversation(conversation_id: str):
    """Clear conversation history for a given conversation ID."""
    _conversation_store.clear(conversation_id)
    return {"cleared": conversation_id}


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
    conversation_id: Optional[str] = Field(
        default=None,
        description="Optional conversation ID for multi-turn context.",
    )
    history: Optional[List[Dict[str, str]]] = Field(
        default=None,
        description="Optional conversation history override.",
    )


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


class Citation(BaseModel):
    """Verbatim quote from a retrieved chunk with source attribution."""
    text: str
    region: str
    system: str
    chunk_id: str


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
    citations: List[Citation]


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
    region: Optional[str], complaint: str, top_k: int,
    conversation_id: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Dict[str, Any]:
    hits = anatomy_retriever.retrieve(region=region, query=complaint, top_k=top_k * 2)
    
    # Rerank with LLM if configured and we have enough chunks
    if is_configured() and len(hits) > top_k:
        hits = _rerank_with_llm(complaint, hits, top_k)
    else:
        hits = hits[:top_k]
    
    sources = [_hit_to_chunk(h).model_dump() for h in hits]

    # Citations: verbatim text from top chunks for clinical traceability
    citations = [
        Citation(
            text=h.chunk.text[:500] + ("..." if len(h.chunk.text) > 500 else ""),
            region=h.chunk.region,
            system=h.chunk.system,
            chunk_id=h.chunk.id,
        ).model_dump()
        for h in hits[:3]
    ]

    # Build conversation history
    conv_history = history
    if conversation_id and not conv_history:
        conv_history = _conversation_store.get(conversation_id)
    
    summary = summarize_with_llm(
        region=region, complaint=complaint, hits=hits, history=conv_history
    )
    llm_used = summary is not None

    # Store this turn in conversation history
    if conversation_id:
        _conversation_store.append(conversation_id, "user", f"{region or ''}: {complaint}")
        if summary and isinstance(summary, dict):
            _conversation_store.append(conversation_id, "assistant", summary.get("summary", ""))

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
        "citations": citations,
    }


def _rerank_with_llm(
    complaint: str,
    hits: List[RetrievalHit],
    top_k: int,
) -> List[RetrievalHit]:
    """Use the LLM to rerank retrieved chunks by relevance to the query.
    
    Sends the query and chunk texts to Groq and asks for a ranked list
    of chunk IDs. Falls back to original order on any failure.
    """
    if not is_configured() or len(hits) <= top_k:
        return hits[:top_k]

    chunk_descriptions = []
    for i, h in enumerate(hits):
        chunk_descriptions.append(
            f"Chunk {i}: [region={h.chunk.region}] {h.chunk.text[:200]}..."
        )

    rerank_prompt = (
        f"Query: {complaint}\n\n"
        f"Rank the following chunks by relevance to the query. "
        f"Return ONLY a comma-separated list of chunk indices in order of relevance.\n\n"
        + "\n".join(chunk_descriptions)
    )

    try:
        with httpx.Client(timeout=settings.GROQ_TIMEOUT_SECONDS) as client:
            response = client.post(
                GROQ_CHAT_COMPLETIONS_URL,
                json={
                    "model": settings.GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": "You are a medical relevance ranker. Return only chunk indices in order, comma-separated."},
                        {"role": "user", "content": rerank_prompt},
                    ],
                    "temperature": 0.0,
                    "max_tokens": 20,
                },
                headers={
                    "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
            )
        if response.status_code == 200:
            content = response.json().get("choices", [{}])[0].get("message", {}).get("content", "")
            indices = [int(x.strip()) for x in content.split(",") if x.strip().isdigit()]
            ranked = [hits[i] for i in indices if 0 <= i < len(hits)]
            if ranked:
                return ranked[:top_k]
    except Exception as exc:
        logger.warning("Reranking failed: %s", exc)

    return hits[:top_k]


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
    
    if req.conversation_id or req.history:
        info_before = _cached_ask.cache_info()
        result = _run_ask(
            region=region,
            complaint=complaint,
            top_k=req.top_k,
            conversation_id=req.conversation_id,
            history=req.history,
        )
        was_cached = False
    else:
        info_before = _cached_ask.cache_info()
        result = _cached_ask(*cache_key)
        info_after = _cached_ask.cache_info()
        was_cached = info_after.hits > info_before.hits
    
    result["cached"] = was_cached
    return result
