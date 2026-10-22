"""
Anatomy assistant endpoints (Step 7.4).

Exposes:
  GET  /anatomy/regions   - list all known regions (id, region, system)
  POST /anatomy/ask       - retriever + LLM call, returns structured JSON
  POST /anatomy/clear     - clear conversation history

**These stay reachable without a token, on purpose.** The body map is part of
anonymous patient intake: a patient presenting at triage has no account and no
JWT, so guarding `/ask` the way `/auth/me` is guarded would remove the feature
from the people it exists for. What is guarded instead:

  * Cost - `/ask` spends real money at the LLM provider, so it is throttled
    per client IP (see `ANATOMY_RATE_LIMIT` in `app/services/throttle.py`).
  * Ownership - conversation ids arrive from the client, so the store key is
    derived by `_conversation_key()`: an HMAC over the caller's scope and the
    id. One caller can no longer address, clear, or read into another's turns.
  * Memory - the store expires entries and has a hard ceiling, so a stream of
    distinct ids cannot grow it without limit.

A caller that *does* hold a practitioner token is scoped to that account,
which keeps conversations apart on a shared address such as a hospital's NAT.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import time
from collections import deque
from functools import lru_cache
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
# Aliased: this module defines a `status()` route below, which would otherwise
# shadow the `fastapi.status` module and turn every code constant into an
# AttributeError.
from fastapi import status as http_status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.v1.endpoints.auth import get_current_doctor
from app.core.config import settings
from app.core.database import get_db
from app.models import Doctor
from app.services import anatomy_retriever, throttle
from app.services.anatomy_retriever import RetrievalHit
from app.services.llm_client import (
    GROQ_CHAT_COMPLETIONS_URL,
    is_configured,
    summarize_with_llm,
)


logger = logging.getLogger(__name__)

router = APIRouter(prefix="/anatomy", tags=["anatomy"])

SECRET_KEY = settings.SECRET_KEY

# Bounds on client-supplied input. The id is opaque and short; the history is
# accepted from the caller and has to be capped before it becomes a prompt.
MAX_CONVERSATION_ID_CHARS = 128
MAX_HISTORY_TURNS = 12
MAX_HISTORY_CHARS = 500


# ── Conversation Memory ───────────────────────────────────────────────────


class _ConversationStore:
    """Simple in-memory conversation history store.
    
    In production, replace this with Redis or database-backed storage.
    Each conversation retains the last N turns for context.
    """

    def __init__(
        self,
        max_turns: int = 10,
        ttl_seconds: int = 3600,
        max_conversations: int = 512,
    ):
        # A plain dict, not a defaultdict: membership used to be created by a
        # read, so every id a client invented stayed resident for the life of
        # the process. The ceiling and the expiry below are what bound it now.
        self._store: Dict[str, deque] = {}
        self._timestamps: Dict[str, float] = {}
        self._max_turns = max_turns
        self._ttl = ttl_seconds
        self._max_conversations = max_conversations

    def __len__(self) -> int:
        return len(self._store)

    def get(self, key: str) -> List[Dict[str, str]]:
        self._maintain()
        entry = self._store.get(key)
        return list(entry) if entry else []

    def append(self, key: str, role: str, content: str) -> None:
        self._maintain()
        turns = self._store.setdefault(key, deque())
        turns.append({"role": role, "content": content})
        self._timestamps[key] = time.time()
        while len(turns) > self._max_turns:
            turns.popleft()
        self._evict_overflow()

    def clear(self, key: str) -> None:
        self._store.pop(key, None)
        self._timestamps.pop(key, None)

    def _maintain(self) -> None:
        """Expires the whole store, not only the key being touched.

        `_cleanup` ran for the id in hand alone, so conversations nobody came
        back to were never collected.
        """
        now = time.time()
        for key in [k for k, seen in self._timestamps.items() if now - seen > self._ttl]:
            self.clear(key)

    def _evict_overflow(self) -> None:
        """Hard ceiling on resident conversations; least recently used goes."""
        while len(self._store) > self._max_conversations and self._timestamps:
            self.clear(min(self._timestamps, key=self._timestamps.get))


_conversation_store = _ConversationStore()


# ── Caller identity ───────────────────────────────────────────────────────

_optional_oauth2 = OAuth2PasswordBearer(
    tokenUrl="/api/v1/auth/login", auto_error=False
)


def _optional_doctor(
    token: Optional[str] = Depends(_optional_oauth2),
    db: Session = Depends(get_db),
) -> Optional[Doctor]:
    """The caller when they present a valid token, otherwise None.

    Deliberately not `get_current_doctor`: that raises 401 when credentials are
    absent, and the body map has to work for a patient who has no account. An
    expired token is treated as anonymous for the same reason - a patient
    mid-intake should not be stopped by a session that lapsed while they were
    answering questions.
    """
    if not token:
        return None
    try:
        return get_current_doctor(token=token, db=db)
    except HTTPException:
        return None


def _caller_scope(request: Optional[Request], doctor: Optional[Doctor]) -> str:
    """The identity a conversation belongs to.

    Signed-in callers are scoped to their account, which matters on a shared
    address such as a hospital's NAT egress. Everyone else is scoped to a hash
    of the client IP: enough to keep one patient's turns away from another's,
    and it degrades to "no history" - never to an error - if a mobile
    connection changes address mid-conversation.
    """
    if doctor is not None:
        return f"doc:{doctor.id}"
    host = request.client.host if request is not None and request.client else "unknown"
    return "ip:" + hashlib.sha256(host.encode("utf-8")).hexdigest()[:16]


def _conversation_key(
    request: Optional[Request], doctor: Optional[Doctor], conversation_id: str
) -> str:
    """Store key for one caller's conversation.

    An HMAC over (scope, id) rather than the raw id: the value cannot be
    reconstructed by someone who saw a conversation id elsewhere, two callers
    using the same id land on different entries, and nothing a client types
    becomes a dictionary key.
    """
    material = f"{_caller_scope(request, doctor)}\x00{conversation_id}"
    return hmac.new(
        SECRET_KEY.encode("utf-8"), material.encode("utf-8"), hashlib.sha256
    ).hexdigest()[:32]


# ── Throttling ────────────────────────────────────────────────────────────


def _check_rate_limit(request: Request, db: Session) -> None:
    """Anonymous callers share one bill, so `/ask` is limited per client IP."""
    allowed = throttle.allow(
        db,
        throttle.bucket_for(request, "anatomy"),
        limit=throttle.ANATOMY_RATE_LIMIT,
        window_seconds=throttle.ANATOMY_RATE_WINDOW_SECONDS,
    )
    if allowed:
        return
    raise HTTPException(
        status_code=http_status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Too many anatomy requests. Please wait a moment and try again.",
        headers={"Retry-After": str(throttle.ANATOMY_RATE_WINDOW_SECONDS)},
    )


def _sanitise_history(
    history: Optional[List[Dict[str, str]]],
) -> Optional[List[Dict[str, str]]]:
    """Bounds client-supplied context before it reaches the prompt.

    `history` comes from the caller, so an unauthenticated request could
    otherwise stuff thousands of turns into the prompt - a simple way to run up
    a bill - or hand the model a `system` role it was never entitled to set.
    """
    if not history:
        return None
    cleaned: List[Dict[str, str]] = []
    for turn in history[-MAX_HISTORY_TURNS:]:
        if not isinstance(turn, dict):
            continue
        role = str(turn.get("role") or "").strip().lower()
        content = str(turn.get("content") or "").strip()
        if role not in ("user", "assistant") or not content:
            continue
        cleaned.append({"role": role, "content": content[:MAX_HISTORY_CHARS]})
    return cleaned or None


@router.post("/clear")
def clear_conversation(
    request: Request,
    conversation_id: str = Query(max_length=MAX_CONVERSATION_ID_CHARS),
    doctor: Optional[Doctor] = Depends(_optional_doctor),
):
    """Clear this caller's conversation history.

    The response echoes the id the caller sent, but what is cleared is the
    scoped key - asking for someone else's id clears nothing of theirs.
    """
    _conversation_store.clear(_conversation_key(request, doctor, conversation_id))
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
        max_length=MAX_CONVERSATION_ID_CHARS,
        description="Opaque conversation id from the client; scoped per caller server-side.",
    )
    history: Optional[List[Dict[str, str]]] = Field(
        default=None,
        description="Optional conversation history override (bounded server-side).",
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
def ask(
    req: AnatomyAskRequest,
    request: Request,
    db: Session = Depends(get_db),
    doctor: Optional[Doctor] = Depends(_optional_doctor),
):
    region = (req.region or "").strip() or None
    complaint = (req.complaint or "").strip()

    if not region and not complaint:
        raise HTTPException(
            status_code=400,
            detail="Provide at least a region or a complaint.",
        )

    _check_rate_limit(request, db)

    conversation_key = (
        _conversation_key(request, doctor, req.conversation_id)
        if req.conversation_id
        else None
    )
    history_turns = _sanitise_history(req.history)
    cache_key = _make_cache_key(region, complaint, req.top_k)
    
    if conversation_key or history_turns:
        info_before = _cached_ask.cache_info()
        result = _run_ask(
            region=region,
            complaint=complaint,
            top_k=req.top_k,
            conversation_id=conversation_key,
            history=history_turns,
        )
        was_cached = False
    else:
        info_before = _cached_ask.cache_info()
        result = _cached_ask(*cache_key)
        info_after = _cached_ask.cache_info()
        was_cached = info_after.hits > info_before.hits
    
    result["cached"] = was_cached
    return result
