"""Pins `triage_service.propagate` — the one round of weighted message passing.

Every assertion here is hand-computed from the stated parameters
(`PROPAGATION_EDGE_WEIGHTS` high/moderate/low = 1.00/0.50/0.25 and
`PROPAGATION_DECAY` = 0.10), not read back off the implementation. The point of a
propagation term is that a neighbour's *severity* informs the scored region; the
tests therefore pin both that it fires when it should and that it stays silent
when there is nothing to carry (no severity, no edge, two hops away). The silent
cases matter as much as the firing ones: a message pass that invents a signal
from mere adjacency would be the fixed bump again under a new name.
"""
from __future__ import annotations

import json

import pytest

from app.schemas import TriageCreate
from app.services import triage_service
from app.services.triage_service import (
    PROPAGATION_DECAY,
    _round2_half_up,
    propagate,
)


def _rows(contributions):
    return {c["factor"]: c["contribution"] for c in contributions}


def test_parameters_are_the_stated_values():
    # If either constant moves, every hand-computed expectation below is wrong
    # and the paper's stated parameters are wrong too - so pin them.
    assert PROPAGATION_DECAY == 0.10
    assert triage_service.PROPAGATION_EDGE_WEIGHTS == {
        "high": 1.00,
        "moderate": 0.50,
        "low": 0.25,
    }


def test_adjacent_neighbour_emits_a_named_path_row():
    rows = propagate("Chest / Heart", ["Left Arm / Shoulder"], {"Left Arm / Shoulder": 9})
    assert len(rows) == 1
    # The row names the path, which is what makes the referral auditable.
    assert rows[0]["factor"] == "Chest / Heart → Left Arm / Shoulder referral"
    # high edge 1.00 x severity 9/10 x decay 0.10 = 0.09
    assert rows[0]["contribution"] == pytest.approx(0.09)
    assert rows[0]["impact"] == "+"


def test_concern_grades_scale_the_same_signal():
    # Same severity, three different edges: high must outweigh moderate must
    # outweigh low, which is the whole reason the concern grade exists. Neck is
    # the region used because it is one of the few carrying all three grades
    # (Chest = high, Headache = moderate, Upper Back = low).
    high = _rows(propagate("Neck", ["Chest / Heart"], {"Chest / Heart": 10}))
    moderate = _rows(propagate("Neck", ["Headache / Cranial"], {"Headache / Cranial": 10}))
    low = _rows(propagate("Neck", ["Back Pain (Upper)"], {"Back Pain (Upper)": 10}))

    high_v = high["Neck → Chest / Heart referral"]
    mod_v = moderate["Neck → Headache / Cranial referral"]
    low_v = low["Neck → Back Pain (Upper) referral"]

    assert high_v == pytest.approx(0.10)   # 1.00 x 1.0 x 0.10
    assert mod_v == pytest.approx(0.05)    # 0.50 x 1.0 x 0.10
    assert low_v == pytest.approx(0.03)    # 0.25 x 1.0 x 0.10 = 0.025 -> half up 0.03
    assert high_v > mod_v > low_v


def test_half_up_rounding_matches_the_dart_port():
    # 0.025 is the tie the two languages disagree on: Python's round() gives 0.03
    # here only by float accident, Dart's roundToDouble() gives 0.03 always. The
    # explicit helper is what makes that agreement a property instead of luck.
    assert _round2_half_up(0.025) == pytest.approx(0.03)
    assert _round2_half_up(0.015) == pytest.approx(0.02)
    assert _round2_half_up(0.09) == pytest.approx(0.09)


def test_two_hop_neighbour_sends_nothing():
    # Headache -> Neck -> Left Shoulder. Left Shoulder is adjacent to Neck, not to
    # Headache, so a one-round pass cannot reach it.
    assert propagate("Headache / Cranial", ["Neck"], {"Neck": 9})
    assert propagate("Headache / Cranial", ["Left Shoulder"], {"Left Shoulder": 9}) == []


def test_missing_or_zero_severity_sends_nothing():
    # No severity means the neighbour has nothing to say - adjacency alone is the
    # fixed co-report bump's job, not propagation's.
    assert propagate("Chest / Heart", ["Left Arm / Shoulder"], {}) == []
    assert propagate("Chest / Heart", ["Left Arm / Shoulder"], {"Left Arm / Shoulder": 0}) == []


def test_referral_must_either_region_list_the_other():
    # Non-adjacent, far pair: nothing travels.
    assert propagate("Left Foot", ["Chest / Heart"], {"Chest / Heart": 10}) == []


def test_self_region_is_ignored():
    assert propagate("Neck", ["Neck"], {"Neck": 10}) == []


def test_duplicate_siblings_emit_one_row():
    rows = propagate(
        "Chest / Heart",
        ["Left Arm / Shoulder", "Left Arm / Shoulder"],
        {"Left Arm / Shoulder": 5},
    )
    assert len(rows) == 1


def test_multiple_siblings_are_deterministic_and_sorted():
    rows = propagate(
        "Chest / Heart",
        ["Neck", "Left Arm / Shoulder", "Abdomen (Upper)"],
        {"Neck": 5, "Left Arm / Shoulder": 5, "Abdomen (Upper)": 5},
    )
    names = [r["factor"] for r in rows]
    # Sorted by neighbour region name, so a diff between runs is stable.
    assert names == [
        "Chest / Heart → Abdomen (Upper) referral",
        "Chest / Heart → Left Arm / Shoulder referral",
        "Chest / Heart → Neck referral",
    ]


def test_every_amount_is_a_two_decimal_multiple():
    # Keeps the sum's rounding free of half-way ties, which is the invariant the
    # existing score already relies on for cross-language parity.
    for severity in range(1, 11):
        for neighbor in ("Left Arm / Shoulder", "Abdomen (Upper)", "Left Armpit"):
            for row in propagate("Chest / Heart", [neighbor], {neighbor: severity}):
                scaled = row["contribution"] * 100.0
                assert abs(scaled - round(scaled)) < 1e-9


def test_compute_risk_adds_propagation_as_a_separate_factor():
    payload = TriageCreate(
        body_region="Chest / Heart", pain_type="Pressure", severity=4
    )
    risk_on, rows_on = triage_service.compute_risk(
        payload,
        sibling_regions=["Left Arm / Shoulder"],
        sibling_severities={"Left Arm / Shoulder": 9},
    )
    risk_off, rows_off = triage_service.compute_risk(
        payload,
        sibling_regions=["Left Arm / Shoulder"],
        sibling_severities={"Left Arm / Shoulder": 9},
        include_propagation=False,
    )

    on = _rows(rows_on)
    off = _rows(rows_off)
    referral = "Chest / Heart → Left Arm / Shoulder referral"

    assert referral in on
    assert referral not in off
    # The ablation removes only the message-pass term: the fixed co-report bump
    # must survive, or there would be nothing left to compare against.
    assert any(f.startswith("Connected to reported") for f in off)
    assert any(f.startswith("Connected to reported") for f in on)
    assert risk_on == pytest.approx(risk_off + 0.09)


def test_compute_risk_without_severity_map_still_applies_the_co_report_bump():
    # Backwards compatibility: a caller that only has adjacency (the old contract)
    # keeps exactly the old behaviour.
    payload = TriageCreate(
        body_region="Chest / Heart", pain_type="Pressure", severity=4
    )
    risk, rows = triage_service.compute_risk(
        payload, sibling_regions=["Left Arm / Shoulder"]
    )
    factors = [r["factor"] for r in rows]
    assert any(f.startswith("Connected to reported") for f in factors)
    assert not any("referral" in f for f in factors)
    assert risk == pytest.approx(0.90)


def test_the_endpoint_threads_visit_severities_into_the_score():
    """End-to-end: a patient who reports an arm and then a chest gets the
    referral, and it reaches the stored explanation a clinician reads.

    The mechanism is only worth claiming if the visit's other pain point's
    severity actually arrives from the database, not merely from a function
    argument a test passes in.
    """
    import uuid

    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    visit_id = uuid.uuid4().hex
    patient = client.post(
        "/api/v1/patients/",
        json={"age": 44, "gender": "Female", "weight": 70.0, "height": 165.0},
    ).json()
    headers = {"X-Patient-Code": patient["anonymous_code"]}

    # First pain point: the arm, rated 9/10.
    client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Left Arm / Shoulder",
            "pain_type": "Sharp",
            "severity": 9,
            "visit_id": visit_id,
        },
        headers=headers,
    )
    # Second: the chest, in the same visit.
    second = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Chest / Heart",
            "pain_type": "Sharp",
            "severity": 4,
            "visit_id": visit_id,
        },
        headers=headers,
    ).json()

    explanation = second["shap_explanation"]
    # Parsed, not substring-matched: `explain()` serialises with ensure_ascii, so
    # the arrow in the path is stored as an escape and a raw-text search would
    # fail on a row that is actually correct.
    factors = [row["factor"] for row in json.loads(explanation)]
    assert "Chest / Heart → Left Arm / Shoulder referral" in factors
    # The arm was rated 9/10, so the message is the maximum a high edge can
    # carry: 1.00 x 0.9 x 0.10.
    row = next(r for r in json.loads(explanation) if "referral" in r["factor"])
    assert row["contribution"] == pytest.approx(0.09)


def test_the_endpoint_leaves_a_lone_complaint_alone():
    # The first pain point of a visit has no neighbour to hear from, so its score
    # must not contain a referral - otherwise the term would be inventing one.
    import uuid

    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    patient = client.post(
        "/api/v1/patients/",
        json={"age": 30, "gender": "Male", "weight": 75.0, "height": 178.0},
    ).json()
    only = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Chest / Heart",
            "pain_type": "Sharp",
            "severity": 4,
            "visit_id": uuid.uuid4().hex,
        },
        headers={"X-Patient-Code": patient["anonymous_code"]},
    ).json()

    factors = [row["factor"] for row in json.loads(only["shap_explanation"])]
    assert not any("referral" in f for f in factors)

