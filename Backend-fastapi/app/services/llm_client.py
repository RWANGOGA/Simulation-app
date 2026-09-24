"""
Groq LLM client for the Simtack anatomy assistant.

Free tier: https://console.groq.com — sign up, create an API key, drop it
into GROQ_API_KEY in `.env`. We default to `llama-3.1-8b-instant` because
it is fast and has a generous free quota. Swap GROQ_MODEL in `.env` if you
prefer a different one.

The Groq API is OpenAI-compatible, so the request/response shape is the
same — we just point httpx at `https://api.groq.com/openai/v1/chat/completions`.

The client is intentionally minimal: build a strict JSON prompt, POST it,
parse the first completion, and return the parsed dict. If parsing fails
or the API is unavailable, callers fall back to the raw retrieved chunks
so the UI never has to render an error state for missing AI.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional

import httpx

from app.core.config import settings
from app.services.anatomy_retriever import RetrievalHit


logger = logging.getLogger(__name__)


GROQ_CHAT_COMPLETIONS_URL = f"{settings.GROQ_BASE_URL}/chat/completions"


# ── Prompt ────────────────────────────────────────────────────────────────


SYSTEM_PROMPT = (
    "You are a clinical anatomy assistant supporting a triage workflow. "
    "You are NOT a doctor. You help a clinician by summarizing what is "
    "anatomically and clinically relevant to a patient who has reported "
    "pain in a given body region. "
    "Use ONLY the provided context chunks. If the context does not contain "
    "the answer, say so explicitly. Do not invent causes, medications, or "
    "dosages. Always include a 'disclaimer' field reminding the clinician "
    "that the output is supportive information and not a diagnosis. "
    "Return strict JSON with the keys: summary, structures, "
    "likely_conditions (each with name and rationale), red_flags, "
    "suggested_questions, disclaimer."
)


def _build_user_prompt(
    region: Optional[str],
    complaint: str,
    hits: List[RetrievalHit],
    history: Optional[List[Dict[str, str]]] = None,
) -> str:
    """Compose the user-side prompt with grounded context."""
    ctx_lines: List[str] = []
    for i, hit in enumerate(hits, start=1):
        chunk = hit.chunk
        ctx_lines.append(
            f"[Chunk {i} | region={chunk.region} | system={chunk.system} | "
            f"score={hit.score:.2f}]\n"
            f"Text: {chunk.text}\n"
            f"Structures: {', '.join(chunk.structures)}\n"
            f"Common conditions: {', '.join(chunk.common_conditions)}\n"
            f"Red flags: {', '.join(chunk.red_flags)}\n"
            f"Suggested questions: {', '.join(chunk.suggested_questions)}"
        )
    context = "\n\n".join(ctx_lines) if ctx_lines else "(no context)"

    history_text = ""
    if history:
        history_lines = []
        for turn in history[-6:]:  # last 3 turns max
            role = turn.get("role", "user")
            content = turn.get("content", "")
            if role == "user":
                history_lines.append(f"Patient: {content}")
            else:
                history_lines.append(f"Assistant: {content}")
        history_text = "\n".join(history_lines) + "\n\n"

    return (
        f"{history_text}"
        f"Patient region tapped: {region or 'unspecified'}\n"
        f"Patient complaint: {complaint or '(none provided)'}\n\n"
        f"Context (use only this):\n{context}\n\n"
        "Respond with strict JSON only. No prose, no markdown fences."
    )


# ── Response parsing ──────────────────────────────────────────────────────


_JSON_OBJECT_RE = re.compile(r"\{.*\}", re.DOTALL)


def _extract_json(text: str) -> Dict[str, Any]:
    """Some models wrap JSON in code fences or prefix prose; be lenient."""
    if not text:
        raise ValueError("empty model response")
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?", "", cleaned).strip()
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3].strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        match = _JSON_OBJECT_RE.search(cleaned)
        if match:
            return json.loads(match.group(0))
        raise


def _normalize(parsed: Dict[str, Any]) -> Dict[str, Any]:
    """Ensure the returned dict has the shape the UI expects."""
    def _list_of(value: Any) -> List[Any]:
        if value is None:
            return []
        if isinstance(value, list):
            return value
        if isinstance(value, str):
            return [v.strip() for v in value.split("\n") if v.strip()]
        return [str(value)]

    def _list_of_dicts(value: Any) -> List[Dict[str, str]]:
        if not value:
            return []
        if isinstance(value, list):
            out: List[Dict[str, str]] = []
            for item in value:
                if isinstance(item, dict):
                    name = str(item.get("name", "")).strip()
                    rationale = str(item.get("rationale", "")).strip()
                    if name:
                        out.append({"name": name, "rationale": rationale})
                elif isinstance(item, str):
                    s = item.strip()
                    if s:
                        out.append({"name": s, "rationale": ""})
            return out
        if isinstance(value, str):
            return [
                {"name": s.strip(), "rationale": ""}
                for s in value.split("\n")
                if s.strip()
            ]
        return []

    summary = parsed.get("summary")
    if not isinstance(summary, str):
        summary = ""

    return {
        "summary": summary.strip(),
        "structures": _list_of(parsed.get("structures")),
        "likely_conditions": _list_of_dicts(parsed.get("likely_conditions")),
        "red_flags": _list_of(parsed.get("red_flags")),
        "suggested_questions": _list_of(parsed.get("suggested_questions")),
        "disclaimer": str(
            parsed.get("disclaimer")
            or "This is supportive information for the clinician, not a "
            "diagnosis. Final decisions remain with the treating practitioner."
        ).strip(),
    }


# ── Public API ────────────────────────────────────────────────────────────


def is_configured() -> bool:
    """True when GROQ_API_KEY is set. Lets the endpoint short-circuit
    gracefully in dev environments without a key."""
    return bool(settings.GROQ_API_KEY)


def summarize_with_llm(
    region: Optional[str],
    complaint: str,
    hits: List[RetrievalHit],
    history: Optional[List[Dict[str, str]]] = None,
) -> Optional[Dict[str, Any]]:
    """Call Groq and return a normalized dict, or None on any failure.

    Never raises: callers fall back to `hits` as plain context, so the UI
    always has something to show.
    """
    if not is_configured():
        logger.info("Groq not configured; skipping LLM call.")
        return None

    user_prompt = _build_user_prompt(region, complaint, hits, history)
    payload = {
        "model": settings.GROQ_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": f"Bearer {settings.GROQ_API_KEY}",
        "Content-Type": "application/json",
    }

    try:
        with httpx.Client(timeout=settings.GROQ_TIMEOUT_SECONDS) as client:
            response = client.post(
                GROQ_CHAT_COMPLETIONS_URL, json=payload, headers=headers
            )
        if response.status_code >= 400:
            logger.warning(
                "Groq returned %s: %s", response.status_code, response.text[:300]
            )
            return None
        body = response.json()
        content = (
            body.get("choices", [{}])[0].get("message", {}).get("content", "")
        )
        parsed = _extract_json(content)
        return _normalize(parsed)
    except (httpx.HTTPError, ValueError, KeyError, json.JSONDecodeError) as exc:
        logger.warning("Groq call failed: %s", exc)
        return None
