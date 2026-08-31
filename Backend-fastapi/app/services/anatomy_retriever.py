"""
Anatomy retriever.

Loads the anatomy knowledge base (app/data/anatomy_kb.json) once at import
time, builds a simple bag-of-words vector for each chunk, and exposes
`retrieve(region, query, top_k)` for the /anatomy/ask endpoint.

This is the "Step 7.2" of the RAG plan: a deterministic, offline, zero-cost
retriever that runs in a few microseconds. The LLM in Step 7.3 will use the
chunks returned here as grounded context.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional


# ── Data model ────────────────────────────────────────────────────────────


@dataclass
class AnatomyChunk:
    id: str
    region: str
    system: str
    text: str
    structures: List[str]
    common_conditions: List[str]
    red_flags: List[str]
    suggested_questions: List[str]
    # Lower-cased, deduplicated tokens used for cosine similarity. Built once.
    tokens: List[str]


@dataclass
class RetrievalHit:
    chunk: AnatomyChunk
    score: float


# ── Knowledge base loading ────────────────────────────────────────────────


_KB_PATH = Path(__file__).resolve().parent.parent / "data" / "anatomy_kb.json"


def _tokenize(text: str) -> List[str]:
    """Lower-cased, alphanumeric-only tokens, deduped, stopwords removed.

    Bag-of-words is plenty for a 14-chunk knowledge base: the LLM does the
    semantic heavy lifting; we just need a fast, deterministic prior that
    boosts the right region when a query mentions keywords.
    """
    if not text:
        return []
    raw = re.findall(r"[a-z0-9]+", text.lower())
    stop = {
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "has", "have", "in", "is", "it", "of", "on", "or", "that", "the",
        "to", "was", "were", "will", "with", "this", "any", "can", "may",
        "their", "they", "you", "your", "patient", "patients",
    }
    seen: set[str] = set()
    out: List[str] = []
    for tok in raw:
        if tok in stop or len(tok) < 3:
            continue
        if tok in seen:
            continue
        seen.add(tok)
        out.append(tok)
    return out


def _chunk_to_text(chunk: dict) -> str:
    """Concatenate every field that should be retrievable for this chunk."""
    parts: List[str] = [chunk.get("text", "")]
    parts.extend(chunk.get("structures", []))
    parts.extend(chunk.get("common_conditions", []))
    parts.extend(chunk.get("red_flags", []))
    parts.extend(chunk.get("suggested_questions", []))
    return " ".join(parts)


@lru_cache(maxsize=1)
def load_kb() -> Dict[str, AnatomyChunk]:
    """Load and cache the knowledge base on first call."""
    with _KB_PATH.open("r", encoding="utf-8") as f:
        raw = json.load(f)
    chunks: Dict[str, AnatomyChunk] = {}
    for entry in raw.get("regions", []):
        text = _chunk_to_text(entry)
        chunk = AnatomyChunk(
            id=entry["id"],
            region=entry["region"],
            system=entry.get("system", ""),
            text=entry.get("text", ""),
            structures=entry.get("structures", []),
            common_conditions=entry.get("common_conditions", []),
            red_flags=entry.get("red_flags", []),
            suggested_questions=entry.get("suggested_questions", []),
            tokens=_tokenize(text),
        )
        chunks[chunk.id] = chunk
    return chunks


# ── Vector math ───────────────────────────────────────────────────────────


def _term_freq(tokens: List[str]) -> Dict[str, float]:
    """tf(t, d) = count(t in d), not normalized (cosine handles length)."""
    tf: Dict[str, float] = {}
    for t in tokens:
        tf[t] = tf.get(t, 0.0) + 1.0
    return tf


def _build_idf(chunks: Dict[str, AnatomyChunk]) -> Dict[str, float]:
    """idf(t) = log(N / (1 + df(t))) — smoothed, deterministic."""
    n = max(1, len(chunks))
    df: Dict[str, int] = {}
    for chunk in chunks.values():
        for tok in set(chunk.tokens):
            df[tok] = df.get(tok, 0) + 1
    return {tok: math.log(n / (1.0 + d)) for tok, d in df.items()}


def _vectorize(
    tokens: List[str], idf: Dict[str, float]
) -> Dict[str, float]:
    """tf-idf vector as a sparse dict."""
    tf = _term_freq(tokens)
    return {tok: count * idf.get(tok, 0.0) for tok, count in tf.items()}


def _cosine(a: Dict[str, float], b: Dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    dot = 0.0
    for tok, weight in a.items():
        if tok in b:
            dot += weight * b[tok]
    norm_a = math.sqrt(sum(w * w for w in a.values()))
    norm_b = math.sqrt(sum(w * w for w in b.values()))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


# ── Retrieval ─────────────────────────────────────────────────────────────


@lru_cache(maxsize=1)
def _index() -> tuple[Dict[str, Dict[str, float]], Dict[str, AnatomyChunk]]:
    """Builds and caches the tf-idf vectors for every chunk."""
    chunks = load_kb()
    idf = _build_idf(chunks)
    vectors = {cid: _vectorize(c.tokens, idf) for cid, c in chunks.items()}
    return vectors, chunks


def retrieve(
    region: Optional[str] = None,
    query: str = "",
    top_k: int = 3,
) -> List[RetrievalHit]:
    """Return the top-k chunks most relevant to (region, query).

    A region match is a strong prior: if `region` matches a chunk's region
    string (case-insensitive), that chunk is boosted into the result set
    even when its cosine score is lower. This keeps the LLM grounded in the
    anatomy the patient actually tapped, while still letting query keywords
    surface specific conditions across regions.
    """
    vectors, chunks = _index()
    query_tokens = _tokenize(query or "")
    idf = _build_idf(chunks)
    q_vec = _vectorize(query_tokens, idf)

    region_norm = (region or "").strip().lower()

    scored: List[RetrievalHit] = []
    for cid, chunk in chunks.items():
        base_score = _cosine(q_vec, vectors[cid])
        # Strong prior when the region matches exactly.
        if region_norm and chunk.region.lower() == region_norm:
            base_score += 0.5
        scored.append(RetrievalHit(chunk=chunk, score=base_score))

    scored.sort(key=lambda h: h.score, reverse=True)
    return scored[: max(1, top_k)]


def list_regions() -> List[dict]:
    """Public list of regions for clients that want to render a picker."""
    return [
        {
            "id": c.id,
            "region": c.region,
            "system": c.system,
        }
        for c in load_kb().values()
    ]
