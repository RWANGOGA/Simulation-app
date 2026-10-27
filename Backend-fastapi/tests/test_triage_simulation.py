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
