"""
Anatomy retriever.

Loads the anatomy knowledge base (app/data/anatomy_kb.json) once at import
time, builds a bag-of-words vector for each chunk, and exposes
`retrieve(region, query, top_k)` for the /anatomy/ask endpoint.

Retrieval has two stages, and they answer different questions:

1. *Which chunks are eligible at all.* The body part the patient tapped, and
   which side of the body it is on, are facts - not hints. A chunk describing
   the opposite limb is never shown as context for this complaint.
2. *How strongly each eligible chunk matches the words used.* BM25 lexical
   scoring and TF-IDF cosine similarity, fused with Reciprocal Rank Fusion.

Keeping those apart matters because the left and right sides of the body carry
different clinical meaning in this knowledge base: `left_arm_shoulder` is
labelled cardiovascular and warns about referred cardiac pain, while
`right_arm_shoulder` is musculoskeletal and mentions gallbladder referral.
Blending region into the score as a magnitude cannot express "not this one", so
it used to let the wrong side through.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, FrozenSet, List, Optional, Tuple


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


# ── Medical Synonym Dictionary for Query Expansion ───────────────────────
#
# Read this as a *translation table between how people describe a complaint and
# how the monographs are written*, not as a thesaurus. Entries are deliberately
# asymmetric in style but are applied symmetrically (see _synonym_table): a
# monograph that says "abdomen" must be reachable from "tummy", and one that
# says "back" must be reachable from "lumbar".
MEDICAL_SYNONYMS: Dict[str, List[str]] = {
    "migraine": ["headache", "cranial", "head", "neurological"],
    "headache": ["migraine", "cranial", "head"],
    "head": ["headache", "cranial"],
    "tummy": ["abdomen", "stomach", "gut", "abdominal"],
    "belly": ["abdomen", "stomach", "gut", "abdominal"],
    "stomach": ["abdomen", "tummy", "belly", "abdominal"],
    "gut": ["abdomen", "stomach"],
    "breathless": ["dyspnea", "respiratory", "chest", "breath"],
    "angina": ["cardiac", "chest", "heart", "coronary"],
    "heart": ["cardiac", "chest", "angina"],
    "dizzy": ["cranial", "neurological", "vertigo", "lightheaded"],
    "lightheaded": ["cranial", "neurological", "vertigo", "dizzy"],
    "knee": ["leg", "knee", "joint"],
    "leg": ["leg", "knee", "thigh"],
    "shoulder": ["arm", "shoulder", "joint"],
    "arm": ["arm", "shoulder"],
    "backache": ["back", "lumbar", "spine"],
    "back": ["spine", "lumbar", "backache"],
    # Clinical vocabulary. The monographs are written in plain prose - the words
    # 'dyspnea', 'hematochezia', 'crepitus' and 'hepatic' do not occur anywhere
    # in them - so a clinician typing the proper term reached nothing at all.
    # Targets below are chosen from words the corpus actually uses; a target that
    # no monograph contains scores idf 0 and is dead weight
    # (test_expansion_reaches_the_corpus enforces that at least one target per
    # group lands).
    "dyspnea": ["breath", "shortness", "chest"],
    "exertion": ["breath", "shortness", "chest"],
    "orthopnea": ["breath", "lying", "chest"],
    "pleuritic": ["pleura", "breath", "chest", "rib"],
    "hematemesis": ["blood", "vomiting", "stomach"],
    "hematochezia": ["blood", "stool", "bowel"],
    "melena": ["black", "tarry", "stool", "blood"],
    "odynophagia": ["throat", "esophagus", "gerd"],
    "dysphagia": ["throat", "esophagus"],
    "hepatic": ["liver", "gallbladder", "pancreas"],
    "biliary": ["gallbladder", "gallstones", "liver"],
    "cholelithiasis": ["gallstones", "gallbladder"],
    "colic": ["cramp", "gallstones", "stone", "kidney", "back", "waves"],
    "renal": ["kidney", "ureter", "stone", "back", "groin", "side"],
    "diaphoresis": ["sweat", "sweating"],
    "syncope": ["fainting", "faint", "dizzy"],
    "crepitus": ["joint", "knee", "grinding", "osteoarthritis"],
    "edema": ["swelling", "swollen", "ankle"],
    "ambulate": ["bear", "weight", "leg"],
    "flank": ["side", "back", "kidney", "groin"],
    "emesis": ["vomiting", "nausea"],
    # Regional relations: the patient names a part, the monograph is written
    # about the region that owns it.
    "heel": ["foot", "plantar", "arch", "steps"],
    "ankle": ["foot", "leg", "shin"],
    "shin": ["leg", "calf", "ankle"],
    "instep": ["foot", "ankle"],
    "groin": ["hip", "testicle", "abdomen", "pubic"],
    "jaw": ["mouth", "neck", "teeth"],
}


@lru_cache(maxsize=1)
def _synonym_table() -> Dict[str, Tuple[str, ...]]:
    """Symmetric (key <-> target) expansion edges, one hop only.

    The declared dictionary only maps lay-term -> document-term, so a clinician
    typing the document term ("lumbar", "abdominal", "dyspnea") got no bridge at
    all; each pair is therefore made bidirectional.

    Bidirectional by *edge*, not by group: members of a group do not inherit each
    other's targets. Measured on the eval fixture that choice is worth two cases
    (pass 0.857 against 0.841: redflag-achilles-pop and unanchored-sore-throat).
    Sharing the whole group widened 'chest' from 7 expansion terms to 15 and 'back'
    to 14, and the added terms were the generic ones - 'activity', 'rib', 'lying' -
    which are not translations of anything, they are vocabulary drift. 'arm'
    cannot reach 'leg' through 'joint' either way, so an upper-limb complaint never
    becomes a lower-limb one.
    """
    table: Dict[str, set] = {}
    for term, synonyms in MEDICAL_SYNONYMS.items():
        table.setdefault(term, set()).update(synonyms)
        for synonym in synonyms:
            table.setdefault(synonym, set()).add(term)
    return {member: tuple(sorted(others - {member})) for member, others in table.items()}


# Words that carry no clinical information about a complaint. This list matters
# more than it looks: without stemming or a real language model, a function word
# is indistinguishable from a symptom, and "I can't breathe when I walk up the
# stairs" once retrieved the *abdomen* monograph on the strength of "when" alone.
#
# Deliberately absent: "pain", "sharp", "night", "walk". Those are content, and
# the mechanism that should neutralise the non-discriminative ones ("pain" is in
# every chunk) is inverse document frequency, not a blacklist.
_STOPWORDS = frozenset(
    {
        # articles, prepositions, conjunctions
        "a", "an", "and", "as", "at", "by", "for", "from", "in", "into", "of",
        "on", "onto", "or", "over", "since", "that", "the", "their", "them",
        "then", "than", "this", "those", "to", "under", "upon", "with",
        "within", "without", "yet",
        # auxiliary and copular verbs
        "am", "are", "been", "being", "be", "been", "did", "does", "doing",
        "done", "get", "gets", "getting", "got", "had", "has", "have", "having",
        "is", "may", "might", "must", "was", "were", "will", "would", "should",
        "could", "used", "cannot", "cant", "can", "doesnt", "didnt", "dont",
        "isnt", "wont", "arent", "wasnt", "havent", "hasnt", "hadnt",
        "wouldnt", "couldnt", "shouldnt",
        # pronouns and possessives
        "he", "him", "his", "her", "hers", "herself", "i", "it", "its", "me",
        "mine", "my", "ours", "our", "she", "theirs", "they", "us", "you",
        "your", "yours",
        # question and filler words
        "any", "anyone", "anything", "because", "before", "both", "each",
        "else", "enough", "even", "every", "how", "just", "like", "much",
        "mostly", "no", "not", "only", "own", "quite", "rather", "really",
        "same", "some", "such", "though", "through", "very", "what", "when",
        "whenever", "where", "whether", "which", "who", "whom", "whose", "why",
        # verbs of reporting and everyday action that appear in patient prose
        "always", "asked", "came", "comes", "coming", "come", "feel", "feeling",
        "felt", "go", "goes", "going", "gone", "make", "makes", "made", "need",
        "needed", "needs", "often", "patient", "patients", "say", "said", "says",
        "seems", "take", "takes", "taking", "told", "wants", "wanted", "was",
        "usually", "sometimes",
    }
)


def _surface_tokens(text: str) -> List[str]:
    """Lower-cased alphanumeric content words: stopwords and 1-2 character
    fragments dropped, order preserved, duplicates removed.
    """
    if not text:
        return []
    seen: set[str] = set()
    out: List[str] = []
    for tok in re.findall(r"[a-z0-9]+", text.lower()):
        if tok in _STOPWORDS or len(tok) < 3:
            continue
        if tok not in seen:
            seen.add(tok)
            out.append(tok)
    return out


def _expand_query(tokens: List[str]) -> List[str]:
    """Add the synonym group of every query word.

    Expansion belongs on the query side ONLY. Indexing the expansions as well
    (the previous behaviour) put invented words into the documents themselves,
    which inflated their document frequency and silently weakened idf, so a term
    like 'back' stopped discriminating anything. It also made every monograph
    look like every other monograph -- the corpus stopped being evidence about
    word rarity and became a list of everything a thesaurus could reach.
    """
    table = _synonym_table()
    seen: set[str] = set(tokens)
    out = list(tokens)
    for tok in tokens:
        for syn in table.get(tok, ()):
            if syn not in seen:
                seen.add(syn)
                out.append(syn)
    return out


# ── Morphological normalisation ───────────────────────────────────────────
#
# Deliberately not Porter/Snowball stemming. Those algorithms are tuned for
# general English and damage biomedical text: they cut the plural of "diabetes"
# down to a non-word, treat "-us"/"-ial" as suffixes, and fold anatomical terms
# onto stems no clinician would recognise, which is why clinical NLP (MetaMap)
# normalises against a controlled vocabulary instead. A 34-monograph corpus can
# afford the same trick outright: a form is collapsed onto another only when
# *both* forms occur in the corpus, so a merge can never invent a stem and can
# never quietly join two different words.
#
# What this buys is the inflection families that actually broke retrieval here:
# "thighs" vs the tapped region "Thigh", "toes" vs the foot monograph's "toe",
# "swellings", "fractures", "sprains".
_IRREGULAR_FORMS: Dict[str, str] = {
    # Suppletive and Latin/Greek plurals, where no suffix rule can help.
    # Entries whose base form is absent from the corpus are ignored (see
    # canonical_form), so this table cannot invent vocabulary.
    "feet": "foot",
    "teeth": "tooth",
    "calves": "calf",
    "menisci": "meniscus",
    "phalanges": "phalanx",
    "ligaments": "ligament",
}

_S_SUFFIX_EXCLUSIONS = ("ss", "us", "is", "xs")  # gas, corpus, axis, taxes-shaped


def canonical_form(token: str) -> str:
    """Base form of an inflected word, using only vocabulary the corpus owns."""
    vocab = _raw_corpus_terms()
    irregular = _IRREGULAR_FORMS.get(token)
    if irregular is not None and irregular in vocab:
        return irregular
    if len(token) > 4 and token.endswith("ies"):
        base = token[:-3] + "y"
        if base in vocab:
            return base
    if len(token) > 4 and token.endswith("es") and token[:-2] in vocab:
        return token[:-2]
    if (
        len(token) > 3
        and token.endswith("s")
        and not token.endswith(_S_SUFFIX_EXCLUSIONS)
        and token[:-1] in vocab
    ):
        return token[:-1]
    return token


def _normalise(tokens: List[str]) -> List[str]:
    """Collapse inflections, then drop the duplicates the collapse creates."""
    seen: set[str] = set()
    out: List[str] = []
    for token in tokens:
        base = canonical_form(token)
        if base not in seen:
            seen.add(base)
            out.append(base)
    return out


@lru_cache(maxsize=1)
def _raw_kb_entries() -> tuple:
    """The knowledge base as stored on disk, before any normalisation."""
    with _KB_PATH.open("r", encoding="utf-8") as f:
        raw = json.load(f)
    return tuple(raw.get("regions", []))


@lru_cache(maxsize=1)
def _raw_corpus_terms() -> FrozenSet[str]:
    """Every surface word in the corpus, region titles included.

    Titles are part of the *vocabulary* even though they are not part of the
    searchable text, so that 'Thighs' and 'thigh' are understood to be the same
    body part by the structured region filter as well as by the text match.
    """
    words: set[str] = set()
    for entry in _raw_kb_entries():
        words.update(_surface_tokens(_chunk_to_text(entry)))
        words.update(_surface_tokens(entry.get("region", "")))
    return frozenset(words)


def _tokenize(text: str) -> List[str]:
    """Query-side tokenisation: content words, synonym bridge, inflections folded."""
    return _normalise(_expand_query(_surface_tokens(text)))


def _chunk_to_text(chunk: dict) -> str:
    """Concatenate fields with heavy weighting on structures, conditions, and red flags.

    The region title is deliberately NOT part of the searchable text. Indexing it
    was measured on the eval fixture and changed no ranking: fusion is by rank, so
    lifting a monograph that is already first in both lists buys nothing. Its only
    observable effect was harmful -- the raw label made 'right'/'left' heavily
    repeated search terms and let the right-knee monograph out-rank the upper
    abdomen one for gallbladder referral pain. Laterality is decided by the
    structured filter, once.
    """
    parts: List[str] = [chunk.get("text", "")]
    # Double-weight critical medical terms for stronger TF-IDF vectors
    parts.extend(chunk.get("structures", []) * 2)
    parts.extend(chunk.get("common_conditions", []) * 2)
    parts.extend(chunk.get("red_flags", []) * 2)
    parts.extend(chunk.get("suggested_questions", []))
    return " ".join(parts)


@lru_cache(maxsize=1)
def load_kb() -> Dict[str, AnatomyChunk]:
    """Load and cache the knowledge base on first call."""
    chunks: Dict[str, AnatomyChunk] = {}
    for entry in _raw_kb_entries():
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
            # Documents are indexed exactly as written: no synonym expansion,
            # only inflections folded onto the corpus's own base forms.
            tokens=_normalise(_surface_tokens(text)),
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
    """idf(t) = log(1 + (N - df + 0.5) / (df + 0.5)) - the non-negative form.

    The textbook Robertson-Sparck Jones idf, `log(N / (1 + df))`, is negative for
    any term in two or more chunks. Here "pain" appears in all 34, so every chunk
    containing it was scored *below* a chunk that did not - the ranking was
    actively inverted for the most common symptom word in the knowledge base.

    This form is always positive, is still ~0 for a term in every document (which
    is the correct message: a word that discriminates nothing should decide
    nothing), and rises steeply for rare clinical terms such as "fatty" or
    "crepitus".
    """
    n = max(1, len(chunks))
    df: Dict[str, int] = {}
    for chunk in chunks.values():
        for tok in set(chunk.tokens):
            df[tok] = df.get(tok, 0) + 1
    return {tok: math.log(1.0 + (n - d + 0.5) / (d + 0.5)) for tok, d in df.items()}


# ── Region structure ──────────────────────────────────────────────────────
#
# The body map sends free-text labels ("Left Arm / Shoulder", "Abdomen (Lower
# Right)", "Thighs", and UI variants like "Knee (Left)"). Everything the
# retriever needs from a label is which side it is on and which body parts it
# names, so labels are parsed into that shape once rather than compared as
# strings - which is how "thigh" came to fail against "thighs" and how the
# mirror-image chunk came to survive.

_SIDE_WORDS = ("left", "right")
# Words that locate a region without naming a body part. Counting them as parts
# would make every quadrant of the abdomen "the same region".
_NON_PART_WORDS = frozenset(
    {"left", "right", "upper", "lower", "pain", "side", "anterior", "posterior"}
)


@dataclass(frozen=True)
class RegionKey:
    """The parts of a region label the retriever can reason about.

    `side` is which half of the body it is, `parts` are the body parts named, and
    `locators` are the words that subdivide a part without naming another one -
    so "Back (Upper)" and "Back (Lower)" share `parts` but differ in `locators`
    and are therefore *not* the same region.
    """

    side: Optional[str]
    parts: FrozenSet[str]
    locators: FrozenSet[str]


@lru_cache(maxsize=128)
def _region_key(region: Optional[str]) -> RegionKey:
    cleaned = re.sub(r"[^a-z0-9 ]", " ", (region or "").strip().lower())
    # Folded through the same normalisation as text, so a tap on "Thighs" and a
    # monograph titled "Thighs" agree about which body part is meant.
    words = [canonical_form(word) for word in cleaned.split() if len(word) > 2]
    side = next((word for word in words if word in _SIDE_WORDS), None)
    parts = frozenset(word for word in words if word not in _NON_PART_WORDS)
    locators = frozenset(word for word in words if word in _NON_PART_WORDS)
    return RegionKey(side=side, parts=parts, locators=locators)


@lru_cache(maxsize=128)
def _chunk_region_key(chunk_id: str) -> RegionKey:
    return _region_key(load_kb()[chunk_id].region)


def _side_compatible(query: RegionKey, chunk: RegionKey) -> bool:
    """False only when both sides are known and they differ.

    A complaint that names no side ("knee pain", or the region left unset) keeps
    both limbs in play, which is correct - nothing has ruled either out. Once a
    side *is* known, the other side's monograph is not context for it.
    """
    if query.side is None or chunk.side is None:
        return True
    return query.side == chunk.side


def _region_tier(query: RegionKey, chunk: RegionKey) -> int:
    """How directly a chunk is about the region that was tapped.

    0  the same region: same parts, same side, same subdivision
    1  the same part of the body, differently subdivided (upper vs lower back)
    2  a chunk that names one of the same parts (a knee monograph for a
       "Leg / Knee" tap, the two-chunk families the body map overlaps)
    3  nothing about the tapped region at all - reachable only on evidence
    """
    if not query.parts:
        # No region was tapped: the retriever has no opinion and pure evidence
        # decides. Ranking everything as equally region-relevant would be a
        # fiction, and "the patient selected nothing" must not bias any chunk.
        return 3
    same_part = query.parts == chunk.parts
    same_side = query.side == chunk.side
    if same_part and same_side:
        return 0 if query.locators == chunk.locators else 1
    if query.parts & chunk.parts:
        return 2
    return 3


# The tier is a prior on rank, not a magnitude added to a score. Its size is set
# against what Reciprocal Rank Fusion can actually produce here: a chunk first in
# both the BM25 and the TF-IDF list earns 2/(60+1) ~ 0.033, and a chunk that
# matched one incidental word earns roughly 0.016. Against that, 0.0305 means:
#
#   * the monograph of the region the patient tapped outranks anything that only
#     matched an incidental word - the tap is the strongest single fact given;
#   * it does *not* outrank a chunk that led both ranking methods on the strength
#     of the complaint's own words, so a description of a textbook infarction
#     reported against an arm tap can still bring the chest monograph above it.
#
# The nearer tiers are spaced by roughly a factor of three, which is enough to
# win ties between them without any of them being able to bury real evidence.
_TIER_PRIOR = {0: 0.0305, 1: 0.0100, 2: 0.0030, 3: 0.0}

# Chunks at or below this tier are the region the patient pointed at and its
# family; they qualify on the tap alone. Above it a chunk needs the words.
_REGION_FAMILY_TIER = 2

# The largest score the fusion can produce: first place in both ranked lists,
# plus the strongest region prior. Dividing by it turns the fused score into an
# absolute confidence that means the same thing for every query, which is what
# `sources[].score` and the prompt's `score=` line should be. A bare tap with no
# words puts its own monograph at about 0.48 - honest, since being the part the
# patient pointed at is real evidence, just not the whole story - and a chunk the
# words match as well as the tap does approaches 1.0.
_MAX_FUSED = 2.0 / (60.0 + 1.0) + _TIER_PRIOR[0]


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
def _index() -> tuple[Dict[str, Dict[str, float]], Dict[str, AnatomyChunk], Dict[str, float]]:
    """Builds and caches the tf-idf vectors for every chunk.

    The idf table is part of the cached index because it is a property of the
    knowledge base, not of a query: rebuilding it per call made every lookup do
    a full pass over every chunk's tokens for no reason.
    """
    chunks = load_kb()
    idf = _build_idf(chunks)
    vectors = {cid: _vectorize(c.tokens, idf) for cid, c in chunks.items()}
    return vectors, chunks, idf


def _bm25_score(
    query_tokens: List[str],
    chunk: AnatomyChunk,
    avgdl: float,
    idf: Dict[str, float],
) -> float:
    """BM25 lexical score for a chunk against a query."""
    k1 = 1.5
    b = 0.75
    dl = len(chunk.tokens)
    score = 0.0
    for qt in query_tokens:
        tf = chunk.tokens.count(qt)
        if tf == 0:
            continue
        idf_val = idf.get(qt, 0.0)
        numerator = tf * (k1 + 1.0)
        denominator = tf + k1 * (1.0 - b + b * (dl / avgdl))
        score += idf_val * numerator / denominator
    return score


def _rrf_fuse(
    ranked_lists: List[List[Tuple[str, float]]],
    k: int = 60,
) -> List[Tuple[str, float]]:
    """Reciprocal Rank Fusion over multiple ranked lists.
    
    Each list is a list of (chunk_id, score) tuples ordered by relevance.
    Returns a fused ranking of (chunk_id, fused_score).
    """
    fusion: Dict[str, float] = {}
    for ranked in ranked_lists:
        for rank, (cid, _) in enumerate(ranked, start=1):
            fusion[cid] = fusion.get(cid, 0.0) + 1.0 / (k + rank)
    return sorted(fusion.items(), key=lambda x: x[1], reverse=True)


@lru_cache(maxsize=128)
def _retrieve_cached_chunk_ids(
    region_key: str, query_key: str, top_k: int
) -> Tuple[Tuple[str, float], ...]:
    """Rank the side-compatible chunks against the words of the complaint.

    Returns (chunk_id, score) already in the order the caller should use, and the
    score is monotonic in that order: a chunk never reports a larger number while
    being placed below a smaller one, which is what made the old blended score
    unusable both to the model (it is printed into the prompt) and to the client
    (it is returned as `sources[].score`).
    """
    vectors, chunks, idf = _index()
    query_tokens = _tokenize(query_key or "")
    q_vec = _vectorize(query_tokens, idf)

    region = _region_key(region_key)
    total_length = sum(len(c.tokens) for c in chunks.values())
    avgdl = total_length / max(1, len(chunks))
    has_words = bool(query_tokens)

    bm25_ranked: List[Tuple[str, float]] = []
    tfidf_ranked: List[Tuple[str, float]] = []
    eligible: List[Tuple[str, int]] = []
    for cid, chunk in chunks.items():
        chunk_region = _chunk_region_key(cid)
        if not _side_compatible(region, chunk_region):
            continue
        tier = _region_tier(region, chunk_region)
        # The region that was tapped and its family qualify on the tap alone. A
        # complaint with no words behind it gets nothing else at all: on a bare
        # ankle tap, padding the window with the cardiac monograph would be an
        # invented relevance that the model is then told to trust.
        if tier > _REGION_FAMILY_TIER and not has_words:
            continue
        lexical = _bm25_score(query_tokens, chunk, avgdl, idf)
        if lexical > 0.0:
            bm25_ranked.append((cid, lexical))
        cosine = _cosine(q_vec, vectors[cid])
        if cosine > 0.0:
            tfidf_ranked.append((cid, cosine))
        if tier <= _REGION_FAMILY_TIER or lexical > 0.0 or cosine > 0.0:
            eligible.append((cid, tier))

    bm25_ranked.sort(key=lambda x: x[1], reverse=True)
    tfidf_ranked.sort(key=lambda x: x[1], reverse=True)
    fused = dict(_rrf_fuse([bm25_ranked, tfidf_ranked]))

    ranked: List[Tuple[str, float]] = []
    for cid, tier in eligible:
        ranked.append((cid, fused.get(cid, 0.0) + _TIER_PRIOR[tier]))
    # Python's sort is stable, so equal scores keep knowledge-base order and the
    # result is reproducible across runs.
    ranked.sort(key=lambda x: x[1], reverse=True)
    scaled = [
        (cid, min(1.0, score / _MAX_FUSED)) for cid, score in ranked
    ]
    return tuple(scaled[: max(1, top_k)])


def retrieve(
    region: Optional[str] = None,
    query: str = "",
    top_k: int = 3,
) -> List[RetrievalHit]:
    """Return the chunks that should ground an answer about this complaint.

    Two things decide, in this order:

    1. **Eligibility.** A chunk describing the opposite side of the body to the
       region that was tapped is never returned. This is a filter, not a penalty,
       because the two sides mean different things clinically - see the module
       docstring.
    2. **Evidence.** BM25 and TF-IDF cosine over the complaint's words, fused with
       Reciprocal Rank Fusion, with a small prior for the tapped region and its
       neighbouring parts.

    `score` is an absolute confidence in [0, 1]: 1.0 is a chunk that is both the
    region that was tapped and first in both ranking methods for a complaint that
    matches it well, and a chunk that only qualified because it is the region that
    got tapped sits near 0.48. It is comparable between queries, and results are
    ordered by it.

    With no words in the query only the tapped region and chunks naming the same
    body part are returned; with words, a chunk that matches none of them is only
    returned if it is the tapped region or its family.

    Results are cached per (region, query, top_k) tuple.
    """
    chunks = load_kb()
    r_key = (region or "").strip().lower()
    q_key = (query or "").strip().lower()

    cached_hits = _retrieve_cached_chunk_ids(r_key, q_key, top_k)
    return [
        RetrievalHit(chunk=chunks[cid], score=score)
        for cid, score in cached_hits
        if cid in chunks
    ]


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
