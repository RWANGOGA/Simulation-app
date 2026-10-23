"""Retrieval quality gate for the anatomy knowledge base.

This is the measurement layer that has to exist before a retriever change can
be called a fix. It replays `tests/fixtures/retrieval_eval_cases.json` - clinical
expectations written from the knowledge base's own content, not from what the
retriever happens to return - through `anatomy_retriever.retrieve`, with no LLM,
no network and no randomness, so the numbers mean the same thing in CI as on a
laptop.

Two ideas are doing the work here:

**Floors, not ceilings.** The metric test asserts the retriever is no worse than
the last reviewed state. Improving past a floor is free; regressing is a build
failure. The values are the baseline measured on the day this file was written.

**A ratchet on the debt.** Everything the retriever currently gets wrong is
named explicitly below. A new failure fails the build. A failure that quietly
disappears *also* fails the build, until the entry is deleted - which forces a
human to look at the improvement, confirm it was deliberate, and tighten the
ceiling. Clinical systems should not be able to get better by accident.

`scripts/eval_retrieval.py` prints the full report:

    venv/bin/python -m scripts.eval_retrieval --verbose
"""
import json
from pathlib import Path

import pytest

from scripts.eval_retrieval import DEFAULT_K, DEFAULT_WINDOW, evaluate, load_cases

# ---------------------------------------------------------------------------
# Measured on 34-chunk anatomy_kb.json, k=3, window=6. Set from
# `python -m scripts.eval_retrieval`. Raise these when a change earns it.
# ---------------------------------------------------------------------------
FLOORS = {
    "top1_accuracy": 0.86,
    "mrr": 0.88,
    "recall_at_k": 0.75,
    "recall_at_window": 0.85,
    "ndcg_at_k": 0.79,
    "referral_coverage": 0.83,
}

# Cases that must NEVER be allowed to fail: the complaints whose whole purpose is
# to reach a red flag. A regression here is a patient being handed the wrong
# information about an emergency, so these are asserted individually rather than
# averaged into a metric where one loss would be invisible.
CLINICAL_INVARIANTS = [
    "redflag-sah-meningism",
    "redflag-mi-presentation",
    "redflag-scaphoid-fall",
    "redflag-ectopic",
    "redflag-neck-weak-arm",
    "redflag-infected-hand-bite",
    "redflag-achilles-pop",
]

# Clinically wrong content served inside the window the model is asked to trust,
# and what it was served for. Adding to this list is a build failure; so is an
# entry that stops being true without being deleted from it.
KNOWN_SAFETY_DEBT = {
    # Laterality is a scoring nudge rather than a filter, so the mirror-image
    # chunk survives into the top 3 - and for the upper limb the two sides carry
    # different referred-pain content (left: cardiac, right: gallbladder).
    "bare-right-shoulder": ["left_arm_shoulder"],
    "bare-left-arm-shoulder": ["right_arm_shoulder"],
    "bare-right-thigh": ["left_thigh"],
    "bare-left-knee": ["right_leg_knee"],
    "bare-right-shin-calf": ["left_shin_calf"],
    "bare-left-ankle": ["right_ankle"],
    "bare-right-foot": ["left_foot"],
    "refer-right-shoulder-gallbladder": ["left_arm_shoulder"],
    "refer-left-arm-cardiac": ["right_arm_shoulder"],
    "right-shoulder-no-cardiac-left-arm": ["left_arm_shoulder"],
    "left-knee-both-knees": ["right_knee", "right_leg_knee"],
    "abdomen-right-not-left": ["abdomen_lower_left"],
    # No stemming: "toes" never matches the foot chunk's "toe", so the word
    # "sharp" decides and the cardiac monograph wins a complaint about toes.
    "toes-not-cardiac": ["chest_heart"],
}

# Every case that fails today, with the reason. Same ratchet semantics.
KNOWN_RANKING_DEBT = {
    "bare-right-shoulder": "contralateral shoulder/arm content in the window",
    "bare-left-arm-shoulder": "contralateral shoulder/arm content in the window",
    "bare-right-thigh": "contralateral thigh served; the `thighs` chunk carrying the DVT red flags is unreachable from a thigh tap",
    "bare-left-knee": "contralateral leg/knee content in the window",
    "bare-right-shin-calf": "contralateral shin/calf content in the window",
    "bare-left-ankle": "contralateral ankle content in the window",
    "bare-right-foot": "contralateral foot content in the window",
    "lay-crushing-chest-to-arm": "a textbook infarction presentation ranks a frozen-shoulder monograph first",
    "lay-fatty-food-upper-abdomen": "biliary referral to the right shoulder is never retrieved",
    "jargon-dyspnea-exertion": "no lexical match for medical jargon: retrieval returns nothing at all",
    "jargon-pleuritic": "arm chunks outrank the chest for pleuritic pain",
    "jargon-hematochezia-llq": "left lower quadrant bleeding retrieved the right side first",
    "jargon-hepatic-colic": "no lexical match for medical jargon: retrieval returns nothing at all",
    "jargon-odynophagia": "no lexical match for medical jargon: retrieval returns nothing at all",
    "refer-right-shoulder-gallbladder": "contralateral cardiac content displaces the gallbladder link",
    "refer-left-arm-cardiac": "the chest chunk is absent from the window for radiating arm pain",
    "refer-renal-to-left-leg": "renal referral to the back is missed; a cranial chunk is served",
    "toes-not-cardiac": "wrong top-1 for a foot complaint",
    "right-shoulder-no-cardiac-left-arm": "contralateral cardiac content in the window",
    "left-knee-both-knees": "contralateral knee content in the window",
    "abdomen-right-not-left": "contralateral abdominal chunk in the window",
    # The knowledge base describes no ear, paediatric, mental-health, wound-care
    # or dosing content, so the only correct answer is "not covered". Today the
    # retriever always produces context, and the prompt tells the model to use
    # only that context - so it manufactures an answer.
    "scope-paediatric-feeding": "no abstain path",
    "scope-wound-closure": "no abstain path",
    "scope-mental-health": "no abstain path",
    "scope-dosing": "no abstain path",
    "scope-ear": "no abstain path",
    "scope-skin-lesion": "no abstain path",
}


@pytest.fixture(scope="module")
def report():
    from app.services import anatomy_retriever

    return evaluate(anatomy_retriever.retrieve, k=DEFAULT_K, window=DEFAULT_WINDOW)


# ── the fixture itself ────────────────────────────────────────────────────


def test_case_ids_are_unique():
    cases = load_cases()
    ids = [case.id for case in cases]
    assert len(ids) == len(set(ids)), f"duplicate case ids: {ids}"


def test_every_referenced_chunk_exists():
    """A deleted or renamed chunk id in the fixture would otherwise make a case
    unsatisfiable and quietly lower the floors forever."""
    kb_path = Path(__file__).resolve().parent.parent / "app" / "data" / "anatomy_kb.json"
    known = {entry["id"] for entry in json.loads(kb_path.read_text())["regions"]}
    dangling = {}
    for case in load_cases():
        for cid in (
            set(case.top1_acceptable)
            | set(case.should_include)
            | set(case.must_not_include)
        ):
            if cid not in known:
                dangling.setdefault(case.id, []).append(cid)
    assert not dangling, f"cases name chunks the knowledge base does not have: {dangling}"


def test_debt_lists_only_reference_real_cases():
    cases = {case.id for case in load_cases()}
    assert set(KNOWN_SAFETY_DEBT) <= cases
    assert set(KNOWN_RANKING_DEBT) <= cases
    assert set(CLINICAL_INVARIANTS) <= cases
    for case_id, reason in KNOWN_RANKING_DEBT.items():
        assert reason, f"{case_id} has no recorded reason"


# ── the gate ──────────────────────────────────────────────────────────────


def test_metrics_do_not_regress(report):
    """Compared against FLOORS, not recomputed from a snapshot file, so the
    threshold stays something a human has signed off on."""
    summary = report.summary()
    failures = {
        name: (summary[name], floor)
        for name, floor in FLOORS.items()
        if summary[name] < floor
    }
    assert not failures, "retrieval quality regressed: " + ", ".join(
        f"{name} {value:.3f} < floor {floor:.3f}" for name, (value, floor) in failures.items()
    )


def test_safety_debt_has_not_grown(report):
    current = {}
    for row in report.results:
        if row.violations:
            current[row.case.id] = sorted(row.violations)
    new = set(current) - set(KNOWN_SAFETY_DEBT)
    assert not new, (
        f"the retriever is now serving clinically wrong context for {sorted(new)}. "
        "Fix the retrieval, or explain the debt in KNOWN_SAFETY_DEBT before merging."
    )


def test_safety_debt_is_still_true(report):
    """Passing by accident is not a fix. If a violation stopped happening, the
    entry has to be deleted and the reason understood."""
    current = {row.case.id for row in report.results if row.violations}
    resolved = set(KNOWN_SAFETY_DEBT) - current
    assert not resolved, (
        f"{sorted(resolved)} no longer violate anything. Delete them from "
        "KNOWN_SAFETY_DEBT and raise the floors if the metrics moved with them."
    )


def test_no_undeclared_failures(report):
    undeclared = {
        row.case.id for row in report.results if not row.passed
    } - set(KNOWN_RANKING_DEBT)
    assert not undeclared, (
        f"cases now failing with no recorded reason: {sorted(undeclared)}"
    )


def test_declared_failures_still_fail(report):
    resolved = set(KNOWN_RANKING_DEBT) - {
        row.case.id for row in report.results if not row.passed
    }
    assert not resolved, (
        f"{sorted(resolved)} now pass. Delete them from KNOWN_RANKING_DEBT, and "
        "from KNOWN_SAFETY_DEBT too if that is why, then tighten the floors."
    )


@pytest.mark.parametrize("case_id", CLINICAL_INVARIANTS)
def test_red_flag_content_is_reachable(report, case_id):
    """Pinned individually: these must pass with no debt entry, ever."""
    by_id = {row.case.id: row for row in report.results}
    assert case_id in by_id, f"{case_id} is not in the case fixture"
    row = by_id[case_id]
    assert row.passed, (
        f"{case_id} is a clinical invariant. It expects "
        f"{row.case.top1_acceptable} (plus {row.case.should_groups}) and got "
        f"{row.retrieved[:3]}. Red-flag reachability is not allowed into the "
        "debt list - fix the retrieval."
    )


def test_medical_jargon_is_not_silently_dropped(report):
    """The jargon group is where retrieval returns *nothing*, which is the most
    dangerous failure the endpoint can produce: `_run_ask` then sends
    "(no context)" and the system prompt forbids anything else. Counted
    separately so a fix that only reorders never hides it."""
    jargon = [r for r in report.results if r.case.group == "clinical_jargon"]
    empty = [r.case.id for r in jargon if not r.retrieved]
    assert len(empty) <= 3, (
        f"{len(empty)} of {len(jargon)} medical-vocabulary cases retrieved no "
        f"chunk at all ({empty}). Every one added is a question the assistant "
        "cannot answer at all."
    )


def test_out_of_scope_complaints_are_recorded_as_unanswered(report):
    """Nothing in this knowledge base covers these, and the retriever has no
    abstain path yet. Asserting the count is 0 keeps the gap visible instead of
    letting it read as a retrieval success."""
    scope = [r for r in report.results if r.case.expect_no_match]
    assert scope, "the fixture lost its out-of-scope cases"
    assert all(r.abstained is False for r in scope), (
        f"out-of-scope handling changed: {[r.case.id for r in scope if r.abstained]} "
        "now abstain. If the abstain path has been built, delete these cases from "
        "KNOWN_RANKING_DEBT and assert abstention_accuracy == 1.0 instead."
    )
    assert report.abstention_accuracy == 0.0
