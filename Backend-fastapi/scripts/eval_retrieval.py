"""Retrieval quality measurement for the anatomy knowledge base.

Why this exists before any retriever change does
------------------------------------------------
Until ranking is measured, "improving the retriever" is a guess. This module
turns the anatomy assistant into something you can chart: it replays a frozen
set of clinically-authored cases against `anatomy_retriever.retrieve` and
reports the standard information-retrieval metrics plus two that are specific
to a clinical system - safety violations (content served that would be wrong to
act on) and evidence-free results (context handed to the LLM that matched none
of the patient's words).

Three properties matter here:

* **Deterministic and offline.** No LLM call, no network, no database. It runs
  in CI and on a laptop with no `GROQ_API_KEY`, which is the only way the
  numbers stay comparable between runs.
* **Independent of the code under test.** Relevance is judged against the raw
  `app/data/anatomy_kb.json` fields, and tokenisation here is a plain word
  split that does *not* apply the retriever's synonym expansion. A harness that
  imports the system's own scoring logic cannot detect that logic's bugs.
* **Expectations are clinical, not observational.** The cases describe what a
  clinician would accept as the right chunk for a complaint. Several of them
  fail today. That is the point - see `KNOWN_DEBT` in
  `tests/test_retrieval_quality.py`, which is a ratchet: the listed failures
  may not grow, and each one removed is a proven fix.

Run it:

    venv/bin/python -m scripts.eval_retrieval              # summary
    venv/bin/python -m scripts.eval_retrieval --verbose    # every case
    venv/bin/python -m scripts.eval_retrieval --json /tmp/base.json

The `--json` output is what you diff between changes to see whether a fix
helped the ranking or just moved the failure somewhere else.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence

BACKEND_DIR = Path(__file__).resolve().parent.parent
KB_PATH = BACKEND_DIR / "app" / "data" / "anatomy_kb.json"
CASES_PATH = BACKEND_DIR / "tests" / "fixtures" / "retrieval_eval_cases.json"

# The k the endpoint actually shows the model: `_run_ask` asks for top_k*2, then
# narrows to `top_k` (default 3). Retrieval quality is therefore judged at 3,
# while recall@window measures the ceiling the re-ranking stage starts from.
DEFAULT_K = 3
DEFAULT_WINDOW = 6

# Duplicated from the retriever on purpose, and deliberately *without* its
# synonym expansion: these are the words a patient's complaint leaves behind
# once ordinary grammar is stripped.
_WORD_RE = re.compile(r"[a-z0-9]+")
_STOPWORDS = frozenset(
    {
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "has", "have", "in", "is", "it", "of", "on", "or", "that", "the",
        "to", "was", "were", "will", "with", "this", "any", "can", "may",
        "their", "they", "you", "your", "patient", "patients", "feel", "feeling",
    }
)


def plain_tokens(text: str) -> set[str]:
    """Content words of a string, with no query expansion applied."""
    return {
        tok
        for tok in _WORD_RE.findall((text or "").lower())
        if tok not in _STOPWORDS and len(tok) >= 3
    }


# ── Data ──────────────────────────────────────────────────────────────────


@dataclass
class Case:
    id: str
    group: str
    region: Optional[str]
    query: str
    top1_acceptable: List[str] = field(default_factory=list)
    should_include: List[str] = field(default_factory=list)
    must_not_include: List[str] = field(default_factory=list)
    expect_no_match: bool = False
    # `should_include` may hold alternatives as a nested list - a biliary
    # complaint may legitimately be carried by either shoulder chunk. The flat
    # set feeds recall; the groups are what the pass gate has to satisfy.
    should_groups: List[set] = field(default_factory=list)

    @property
    def relevant(self) -> set[str]:
        """Everything a good answer for this case needs in the window."""
        return set(self.top1_acceptable) | set(self.should_include)

    @property
    def graded(self) -> Dict[str, int]:
        """Chunk id -> relevance grade. The clinically-correct region scores 2,
        a chunk that earns its place by spanning the picture scores 1."""
        grades = {cid: 1 for cid in self.should_include}
        grades.update({cid: 2 for cid in self.top1_acceptable})
        return grades


@dataclass
class CaseResult:
    case: Case
    retrieved: List[str]
    scores: List[float]
    rank_of_first_relevant: int
    hits_at_k: int
    ndcg_at_k: float
    violations: List[str]
    top1_evidence_free: bool
    abstained: Optional[bool]

    @property
    def top1_correct(self) -> bool:
        if not self.retrieved:
            return False
        return self.retrieved[0] in set(self.case.top1_acceptable)

    @property
    def passed(self) -> bool:
        case = self.case
        if case.expect_no_match:
            return bool(self.abstained)
        if self.violations:
            return False
        if not self.top1_correct:
            return False
        served = set(self.retrieved)
        return all(group & served for group in case.should_groups)

    def as_row(self) -> Dict[str, object]:
        return {
            "id": self.case.id,
            "group": self.case.group,
            "passed": self.passed,
            "top1_correct": self.top1_correct,
            "reciprocal_rank": (
                1.0 / self.rank_of_first_relevant if self.rank_of_first_relevant else 0.0
            ),
            "violations": self.violations,
            "top1_evidence_free": self.top1_evidence_free,
            "abstained": self.abstained,
            "retrieved": self.retrieved,
        }


@dataclass
class Report:
    k: int
    window: int
    results: List[CaseResult]

    # ── aggregates ────────────────────────────────────────────────────────
    def scored(self) -> List[CaseResult]:
        """Cases that expect an answer. The out-of-scope ones are scored as
        abstention, not ranking, and must not dilute these numbers."""
        return [r for r in self.results if not r.case.expect_no_match]

    def scope_cases(self) -> List[CaseResult]:
        return [r for r in self.results if r.case.expect_no_match]

    def _mean(self, values: Sequence[float]) -> float:
        return sum(values) / len(values) if values else 0.0

    @property
    def top1_accuracy(self) -> float:
        rows = self.scored()
        return self._mean([1.0 if r.top1_correct else 0.0 for r in rows])

    @property
    def mrr(self) -> float:
        rows = self.scored()
        return self._mean(
            [1.0 / r.rank_of_first_relevant if r.rank_of_first_relevant else 0.0 for r in rows]
        )

    @property
    def recall_at_k(self) -> float:
        rows = self.scored()
        return self._mean(
            [
                (
                    r.hits_at_k / len(r.case.relevant))
                if r.case.relevant
                else 0.0
                for r in rows
            ]
        )

    @property
    def recall_at_window(self) -> float:
        """What the re-ranking stage is handed. The gap to recall_at_k is what
        a better second stage could recover - and if this is already low, no
        re-ranker can fix it."""
        rows = self.scored()
        return self._mean(
            [
                (
                    len(set(r.retrieved[: self.window]) & r.case.relevant)
                    / len(r.case.relevant)
                )
                if r.case.relevant
                else 0.0
                for r in rows
            ]
        )

    @property
    def ndcg_at_k(self) -> float:
        return self._mean([r.ndcg_at_k for r in self.scored()])

    @property
    def referral_coverage(self) -> float:
        """Of the cases whose picture spans more than one region, how many
        actually got the second region into the window. This is the metric the
        body-graph concept is supposed to move."""
        rows = [r for r in self.scored() if r.case.should_include]
        if not rows:
            return 0.0
        return self._mean(
            [
                1.0
                if set(r.case.should_include) & set(r.retrieved)
                else 0.0
                for r in rows
            ]
        )

    @property
    def safety_violations(self) -> List[str]:
        return [
            f"{r.case.id}: {cid}"
            for r in self.results
            for cid in r.violations
        ]

    @property
    def evidence_free_rate(self) -> float:
        """Of the cases where the patient actually used words, how often the
        chunk put first shares not one content word with them.

        Bare region taps are excluded: they carry no words to match, so scoring
        them as evidence-free would flatter this number's meaning. Their own
        story is told by `bare_taps_without_text`.
        """
        rows = [
            r
            for r in self.scored()
            if not r.case.expect_no_match and r.case.query.strip()
        ]
        return self._mean([1.0 if r.top1_evidence_free else 0.0 for r in rows])

    @property
    def bare_taps_without_text(self) -> int:
        return sum(
            1
            for r in self.scored()
            if not r.case.query.strip() and r.retrieved
        )

    @property
    def abstention_accuracy(self) -> float:
        rows = self.scope_cases()
        if not rows:
            return 1.0
        return self._mean([1.0 if r.abstained else 0.0 for r in rows])

    @property
    def pass_rate(self) -> float:
        return self._mean([1.0 if r.passed else 0.0 for r in self.results])

    def by_group(self) -> Dict[str, Dict[str, float]]:
        out: Dict[str, Dict[str, float]] = {}
        for group in sorted({r.case.group for r in self.results}):
            rows = [r for r in self.results if r.case.group == group]
            ranking = [r for r in rows if not r.case.expect_no_match]
            out[group] = {
                "cases": len(rows),
                "passed": sum(1 for r in rows if r.passed),
                "top1_accuracy": (
                    self._mean([1.0 if r.top1_correct else 0.0 for r in ranking])
                    if ranking
                    else self._mean([1.0 if r.abstained else 0.0 for r in rows])
                ),
                "violations": sum(len(r.violations) for r in rows),
                "evidence_free": sum(1 for r in ranking if r.top1_evidence_free),
            }
        return out

    def summary(self) -> Dict[str, object]:
        return {
            "k": self.k,
            "window": self.window,
            "cases": len(self.results),
            "pass_rate": round(self.pass_rate, 4),
            "top1_accuracy": round(self.top1_accuracy, 4),
            "mrr": round(self.mrr, 4),
            "recall_at_k": round(self.recall_at_k, 4),
            "recall_at_window": round(self.recall_at_window, 4),
            "ndcg_at_k": round(self.ndcg_at_k, 4),
            "referral_coverage": round(self.referral_coverage, 4),
            "evidence_free_top1_rate": round(self.evidence_free_rate, 4),
            "bare_taps_served_without_text": self.bare_taps_without_text,
            "abstention_accuracy": round(self.abstention_accuracy, 4),
            "safety_violations": self.safety_violations,
        }

    def as_json(self) -> Dict[str, object]:
        return {
            "summary": self.summary(),
            "by_group": self.by_group(),
            "cases": [r.as_row() for r in self.results],
        }


# ── Measurement ───────────────────────────────────────────────────────────


def _flatten_groups(value: Sequence) -> tuple[List[str], List[set]]:
    """Accept `"a"` or `["a", "b"]` (alternatives) inside a list, and return the
    flat union for recall plus one group per entry for the pass gate."""
    flat: List[str] = []
    groups: List[set] = []
    for item in value or []:
        if isinstance(item, list):
            alternatives = set(item)
            flat.extend(sorted(alternatives))
        else:
            alternatives = {item}
            flat.append(item)
        groups.append(alternatives)
    return flat, groups


def load_cases(path: Path = CASES_PATH) -> List[Case]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    cases: List[Case] = []
    for entry in raw["cases"]:
        should_include, should_groups = _flatten_groups(entry.get("should_include", []))
        case = Case(
            id=entry["id"],
            group=entry.get("group", "un_grouped"),
            region=entry.get("region"),
            query=entry.get("query", ""),
            top1_acceptable=list(entry.get("top1_acceptable", [])),
            should_include=should_include,
            should_groups=should_groups,
            must_not_include=list(entry.get("must_not_include", [])),
            expect_no_match=bool(entry.get("expect_no_match", False)),
        )
        if not case.top1_acceptable and not case.expect_no_match:
            raise ValueError(f"case {case.id} has no expectation")
        cases.append(case)
    return cases


def load_kb_documents(path: Path = KB_PATH) -> Dict[str, set[str]]:
    """Chunk id -> content words of the raw record. Read from the JSON rather
    than from the retriever's assembled vector so an evidence check here cannot
    be satisfied by whatever the index decided to add."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    documents: Dict[str, set[str]] = {}
    for entry in raw["regions"]:
        parts: List[str] = [entry.get("text", "")]
        for key in (
            "structures",
            "common_conditions",
            "red_flags",
            "suggested_questions",
            "region",
        ):
            value = entry.get(key)
            if isinstance(value, list):
                parts.extend(str(item) for item in value)
            else:
                parts.append(str(value or ""))
        documents[entry["id"]] = plain_tokens(" ".join(parts))
    return documents


def _dcg(grades: List[int]) -> float:
    return sum(
        (2**grade - 1) / math.log2(position + 2)
        for position, grade in enumerate(grades)
    )


def measure_case(
    case: Case,
    retrieve: Callable[..., List],
    k: int,
    window: int,
    documents: Dict[str, set[str]],
) -> CaseResult:
    hits = retrieve(region=case.region, query=case.query, top_k=window)
    retrieved = [hit.chunk.id for hit in hits]
    scores = [float(hit.score) for hit in hits]

    relevant = case.relevant
    ranked = retrieved[:k]
    first = next(
        (i + 1 for i, cid in enumerate(retrieved) if cid in relevant), 0
    )

    grades = [case.graded.get(cid, 0) for cid in ranked]
    ideal = sorted(case.graded.values(), reverse=True)[:k]
    ideal_dc = _dcg(ideal) if ideal else 0.0
    ndcg = (_dcg(grades) / ideal_dc) if ideal_dc > 0 else 0.0

    violations = [cid for cid in case.must_not_include if cid in ranked]

    query_words = plain_tokens(case.query)
    # A bare region tap has no words at all, so it is evidence-free by
    # construction - a true statement about handing the model a chunk that
    # nothing in the request actually selected.
    top1_words = documents.get(retrieved[0], set()) if retrieved else set()
    evidence_free = bool(retrieved) and (
        not query_words or not (query_words & top1_words)
    )

    abstained: Optional[bool] = None
    if case.expect_no_match:
        # Correct abstention means nothing shown to the model was genuinely
        # about the words used. A stray shared common word ("night", "fever")
        # is exactly the noise that would otherwise let the system invent an
        # answer for a complaint this knowledge base does not cover.
        abstained = not ranked or not any(
            query_words & documents.get(cid, set()) for cid in ranked
        )

    return CaseResult(
        case=case,
        retrieved=retrieved,
        scores=scores,
        rank_of_first_relevant=first,
        hits_at_k=len(set(ranked) & relevant),
        ndcg_at_k=ndcg,
        violations=violations,
        top1_evidence_free=evidence_free,
        abstained=abstained,
    )


def evaluate(
    retrieve: Callable[..., List],
    cases: Optional[List[Case]] = None,
    k: int = DEFAULT_K,
    window: Optional[int] = None,
) -> Report:
    cases = cases if cases is not None else load_cases()
    window = window if window is not None else max(k, DEFAULT_WINDOW)
    documents = load_kb_documents()
    return Report(
        k=k,
        window=window,
        results=[
            measure_case(case, retrieve, k, window, documents) for case in cases
        ],
    )


# ── CLI ───────────────────────────────────────────────────────────────────


def format_report(report: Report, verbose: bool = False) -> str:
    lines: List[str] = []
    summary = report.summary()
    violations = summary.pop("safety_violations")
    lines.append(
        f"anatomy retrieval evaluation - {summary['cases']} cases, "
        f"judged at k={summary['k']} over a {summary['window']}-chunk window"
    )
    lines.append("")
    for key, value in summary.items():
        if key in ("k", "window", "cases"):
            continue
        lines.append(f"  {key:26} {value:>8.3f}" if isinstance(value, float) else f"  {key:26} {value}")
    lines.append(f"  {'safety_violations':26} {len(violations):>8}")

    lines.append("")
    lines.append("  by group")
    lines.append(f"    {'group':24} {'cases':>6} {'pass':>6} {'top1':>7} {'viol':>6} {'no-ev':>6}")
    for group, stats in report.by_group().items():
        lines.append(
            f"    {group:24} {stats['cases']:>6} {stats['passed']:>6} "
            f"{stats['top1_accuracy']:>7.3f} {stats['violations']:>6} "
            f"{stats['evidence_free']:>6}"
        )

    if violations:
        lines.append("")
        lines.append("  safety violations (clinically wrong content in the window)")
        for violation in violations:
            lines.append(f"    - {violation}")

    failures = [r for r in report.results if not r.passed]
    if failures:
        lines.append("")
        lines.append(f"  failing cases ({len(failures)})")
        for row in failures:
            got = ", ".join(row.retrieved[:3]) or "(nothing)"
            want = ", ".join(row.case.top1_acceptable) or "(abstain)"
            notes = []
            if row.violations:
                notes.append(f"FORBIDDEN {', '.join(row.violations)}")
            if not row.top1_correct and not row.case.expect_no_match:
                notes.append("wrong top-1")
            if row.abstained is False:
                notes.append("should have abstained")
            missing = [
                "/".join(sorted(group - set(row.retrieved)))
                for group in row.case.should_groups
                if not group & set(row.retrieved)
            ]
            if missing:
                notes.append("missing " + "; ".join(m for m in missing if m))
            lines.append(
                f"    {row.case.id:34} [{row.case.group}] want {want}"
            )
            lines.append(f"      got  {got}   ({'; '.join(notes)})")

    if verbose:
        lines.append("")
        lines.append("  every case")
        for row in report.results:
            flag = "ok " if row.passed else "FAIL"
            lines.append(
                f"    {flag} {row.case.id:34} {(row.retrieved[:3] or ['(none)'])}"
            )

    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--k", type=int, default=DEFAULT_K)
    parser.add_argument("--window", type=int, default=DEFAULT_WINDOW)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--json", dest="json_out", type=Path, default=None)
    args = parser.parse_args(argv)

    sys.path.insert(0, str(BACKEND_DIR))
    from app.services.anatomy_retriever import retrieve

    report = evaluate(retrieve, k=args.k, window=args.window)
    print(format_report(report, verbose=args.verbose))

    if args.json_out:
        args.json_out.write_text(
            json.dumps(report.as_json(), indent=2, sort_keys=True), encoding="utf-8"
        )
        print(f"\nwrote {args.json_out}")

    # Non-zero on a safety violation so this can gate a pipeline directly.
    return 1 if report.safety_violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
