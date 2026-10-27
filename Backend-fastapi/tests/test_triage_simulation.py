"""Pins the triage simulation harness: coverage, conformance, and the honesty guard.

These tests do not re-derive the kappa arithmetic (that is
`tests/test_evaluation.py`'s job against a hand-computed table). They pin the
properties that make the emitted `docs/results/triage-simulation.*` defensible:
the category coverage, the engine-lands-on-intended-tier conformance claim, and —
most importantly — the guard that refuses to present a tool-vs-design-target
number as an inter-rater statistic when there is only one non-clinician author.
"""
from __future__ import annotations

import pytest

from scripts import triage_simulation as sim


@pytest.fixture(scope="module")
def fixture_data():
    return sim.load_fixture()


@pytest.fixture(scope="module")
def report(fixture_data):
    return sim.build_report(fixture_data)


def test_total_is_150(report):
    assert report["n_cases"] == 150


def test_at_least_30_per_category(report):
    for tier in ("red", "orange", "yellow", "green"):
        assert report["counts"][tier] >= 30, f"{tier} under-covered"


def test_engine_matches_every_intended_tier(report):
    # Specification conformance: no vignette lands off the tier it was built for.
    assert report["conformance_mismatches"] == []


def test_reference_is_design_target_not_clinician(report):
    assert report["reference_label"] == "design_target"
    assert report["guard"]["interpretation"] == (
        "tool-vs-design-target specification conformance"
    )


def test_provenance_header_stays_honest(fixture_data):
    prov = fixture_data["provenance"]
    assert prov["clinician_label"] is False
    assert prov["second_labeler_id"] is None
    assert prov["reference_kind"] == "design_target"


def test_every_co_reported_region_is_a_real_graph_key(fixture_data):
    # `find_connection` matches region names exactly while `_region_weight`
    # matches on keywords, so a label can spell the right weight band and still
    # match no edge. That is how the multi-region cases silently stopped
    # bumping: "Left Arm" scored like "Left Arm / Shoulder" but was not a
    # neighbour of anything.
    from app.data.body_graph import BODY_GRAPH

    bad = [
        (case["id"], sibling)
        for case in fixture_data["cases"]
        for sibling in case["input"]["siblings"]
        if sibling not in BODY_GRAPH
    ]
    assert bad == [], f"siblings that are not graph keys: {bad}"


def test_a_declared_sibling_always_has_a_severity(fixture_data):
    # The referral term needs the neighbour's report. A sibling with no severity
    # can only fire the older fixed bump, which is a weaker claim than the case
    # appears to make.
    missing = [
        (case["id"], sibling)
        for case in fixture_data["cases"]
        for sibling in case["input"]["siblings"]
        if not case["input"].get("sibling_severities", {}).get(sibling)
    ]
    assert missing == [], f"siblings with no declared severity: {missing}"


def test_guard_refuses_inter_rater_kappa(report):
    guard = report["guard"]
    assert guard["clinician_label"] is False
    assert guard["second_labeler_id"] is None
    assert guard["inter_rater_kappa_available"] is False
    # The refusal is a real code path, and the reason is recorded, not fabricated.
    assert report["inter_rater"]["available"] is False
    assert "second labeler" in report["inter_rater"]["reason"]


def test_inter_rater_kappa_call_raises_without_second_labeler(fixture_data):
    pairs = [(c["intended_tier"], c["intended_tier"]) for c in fixture_data["cases"]]
    with pytest.raises(sim.InterRaterUnavailable):
        sim.inter_rater_kappa(pairs, fixture_data["provenance"])


def test_agreement_is_perfect_on_the_conformant_set(report):
    agreement = report["agreement"]
    assert agreement["n"] == 150
    assert agreement["weighted_kappa"] == pytest.approx(1.0)
    assert agreement["cohen_kappa"] == pytest.approx(1.0)
    assert agreement["red_boundary_kappa"] == pytest.approx(1.0)
    assert agreement["exact"] == 150
    assert agreement["under"] == 0
    assert agreement["over"] == 0


def test_confusion_is_pure_diagonal(report):
    matrix = report["agreement"]["confusion"]
    for tool in sim.TIER_ORDER:
        for ref in sim.TIER_ORDER:
            if tool == ref:
                assert matrix[tool][ref] == report["counts"][tool]
            else:
                assert matrix[tool][ref] == 0


def test_red_sensitivity_is_complete_with_valid_ci(report):
    red = report["agreement"]["red_sensitivity"]
    assert red["denominator"] == report["counts"]["red"]
    assert red["hits"] == red["denominator"]
    assert red["sensitivity"] == pytest.approx(1.0)
    lo, hi = red["ci95"]
    assert 0.0 <= lo <= hi <= 1.0


def test_worked_cases_cover_distinct_deciding_rules(report):
    labels = {w["label"] for w in report["worked_cases"]}
    assert "red by vital-sign floor" in labels
    assert "orange by score on a concerning region" in labels
    assert "green by below urgent band" in labels
    for worked in report["worked_cases"]:
        assert worked["intended_tier"] == worked["tool_tier"]


def test_sensitivity_baseline_reproduces_the_fixture_counts(report):
    # The engine's own tier distribution over the set equals the intended counts,
    # because conformance is perfect — the ablation is measured off a correct base.
    sens = report["sensitivity"]
    assert sens["baseline_distribution"] == report["counts"]
    assert sum(sens["baseline_distribution"].values()) == report["n_cases"]


def test_heart_rate_ablation_only_ever_moves_toward_less_urgent(report):
    hr = report["sensitivity"]["heart_rate_ablation"]
    # Removing a risk-raising input (the HR bump and the HR red flags) cannot
    # make any case *more* urgent, so every flip is an under-triage direction.
    assert hr["tier_changes"] == hr["under_triage_flips"]
    assert hr["tier_changes"] > 0, "HR should be load-bearing on this set"
    assert sum(hr["distribution"].values()) == report["n_cases"]


def test_score_cap_ablation_moves_no_category(report):
    cap = report["sensitivity"]["score_cap_ablation"]
    # Every band is a lower bound and the cap bites only at/above 1.00, so
    # un-clamping can never cross a threshold downward.
    assert cap["tier_changes"] == 0
    assert cap["capped_cases"] >= 1, "fixture should exercise the cap at least once"


def test_graph_propagation_ablation_measures_the_real_mechanism(report):
    graph = report["sensitivity"]["graph_propagation"]
    assert graph["available"] is True
    assert "message passing" in graph["mechanism"]

    # The term has to actually fire on this set, or the ablation is measuring
    # nothing: the vignettes that declare a neighbour severity must carry a
    # referral row.
    assert graph["cases_carrying_a_referral"] > 0
    assert graph["max_referral_added"] > 0

    # Every referral amount is bounded by the strongest possible message:
    # high edge 1.00 x severity 10/10 x decay 0.10.
    assert graph["max_referral_added"] <= 0.10
    assert graph["total_referral_added"] <= 0.10 * report["n_cases"]


def test_graph_propagation_score_moves_are_accounted_for(report):
    # Each case either moves the displayed score or has its arithmetic absorbed
    # by the 1.00 clamp — never both, never neither, when a referral exists.
    graph = report["sensitivity"]["graph_propagation"]
    assert (
        graph["cases_where_the_displayed_score_moves"]
        + graph["cases_absorbed_by_the_cap"]
        == graph["cases_carrying_a_referral"]
    )


def test_graph_propagation_cannot_make_a_case_less_urgent(report):
    # The term only ever adds to a score, so ablating it can only produce a tie
    # or a less-urgent tier. A flip *toward* more urgency without the term would
    # mean the term had a negative weight somewhere.
    graph = report["sensitivity"]["graph_propagation"]
    assert graph["under_triage_flips"] == graph["tier_changes"]
