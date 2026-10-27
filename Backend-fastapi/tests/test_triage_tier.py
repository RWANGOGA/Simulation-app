"""Triage tier (triage_service.triage_tier) — the four SATS categories.

The score band answers "how big is the number" and the red-flag screen answers
"does one finding need care now". Neither is a category a referral can carry, and
neither can be compared with a clinician's judgement, which is what the paper has
to do. These tests pin the mapping, and pin the two properties that make it worth
having: rules decide before the score does, and nothing here moves a stored score.
"""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.schemas import TriageCreate, TriageDecisionUpdate
from app.services import triage_service

client = TestClient(app)


def _point(**overrides):
    """A benign pain point, so each test states only the finding it changes."""
    defaults = {
        "body_region": "Left Leg",
        "pain_type": "Dull",
        "severity": 3,
        "heart_rate": None,
        "direction": None,
    }
    return SimpleNamespace(**{**defaults, **overrides})


def _tier(source, risk):
    return triage_service.triage_tier(source, risk)["tier"]


# ── the anchors ───────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "risk,overrides,expected",
    [
        # Both score anchors are inclusive: 0.40 is Urgent, not Routine, and
        # 0.70 in a concerning region is Very Urgent. Off-by-one here silently
        # moves every borderline patient one category.
        (0.0, {}, "green"),
        (0.39, {}, "green"),
        (0.40, {}, "yellow"),
        (0.69, {}, "yellow"),
        # 0.70 alone is not enough for orange: the region has to be one whose
        # referred pain matters, or a bad total for a toe reads as very urgent.
        (0.70, {"body_region": "Left Leg"}, "yellow"),
        (0.70, {"body_region": "Chest / Heart"}, "orange"),
        (1.0, {"body_region": "Abdomen (Upper)"}, "orange"),
        # An urgent red flag outranks a score that has not reached 0.70.
        (0.50, {"severity": 10}, "orange"),
        (0.20, {"heart_rate": 110.0}, "orange"),
        # An emergency flag outranks any score, including a calm one.
        (0.05, {"body_region": "Chest / Heart", "pain_type": "Crushing"}, "red"),
        (0.20, {"heart_rate": 130.0}, "red"),
        (0.20, {"heart_rate": 45.0}, "red"),
        (1.0, {"body_region": "Headache / Cranial", "severity": 10}, "red"),
    ],
)
def test_tier_anchors(risk, overrides, expected):
    assert _tier(_point(**overrides), risk) == expected


@pytest.mark.parametrize(
    "rate,expected",
    [
        # 50 and 120 bpm are *not* critical - the rules read "< 50" and "> 120".
        (50.0, "yellow"),
        (49.9, "red"),
        # 120 is high without being critical, which is an urgent flag, so the
        # category is Very Urgent rather than a score-only Urgent.
        (120.0, "orange"),
        (120.1, "red"),
    ],
)
def test_critical_heart_rate_thresholds_are_exclusive(rate, expected):
    """Pinned as numbers rather than prose because the same two values decide the
    score bump, the red flag and the tier.

    A `>=` slipped into one of them would move a category at the exact rate a
    triage form is likely to record, and the three answers would still agree with
    each other often enough to pass a test that only checks one of them.
    """
    assert _tier(_point(heart_rate=rate), 0.45) == expected


def test_a_zero_heart_rate_is_no_measurement_at_all():
    """0 bpm must change nothing: not the score, not the flag, not the tier.

    Unit 4 is off the plan, so the camera never sends a rate today - but the field
    is reachable through the API, and a failed capture reported as 0 used to score
    the critical bump (+0.15) while the tier refused to call it an emergency. One
    input, two answers, in the same record.
    """
    source = _point(heart_rate=0.0)
    zero = TriageCreate(body_region="Left Leg", pain_type="Dull", severity=3, heart_rate=0.0)
    none = TriageCreate(body_region="Left Leg", pain_type="Dull", severity=3, heart_rate=None)

    risk_zero, _ = triage_service.compute_risk(zero)
    risk_none, _ = triage_service.compute_risk(none)

    assert risk_zero == risk_none
    assert triage_service.escalation_for(source)["level"] == "routine"
    assert _tier(source, risk_zero) == "green"


def test_missing_fields_do_not_raise():
    assert triage_service.triage_tier(SimpleNamespace(), None)["tier"] == "green"


# ── auditability ──────────────────────────────────────────────────────────

def test_the_scale_and_its_categories_are_named_once():
    result = triage_service.triage_tier(_point(), 0.45)

    assert result["scale"] == triage_service.TRIAGE_SCALE == "SATS"
    assert set(triage_service.TIER_CATEGORIES) == set(triage_service.TIERS)
    assert result["category"] == triage_service.TIER_CATEGORIES[result["tier"]]
    # Most urgent first: clients draw this as a strip and kappa weights read it
    # as an ordinal axis, so the order is part of the contract.
    assert triage_service.TIERS == ("red", "orange", "yellow", "green")


def test_every_tier_names_the_rules_that_decided_it():
    """`decided_by` is never empty, and never cites a code that is not one.

    A tier nobody can trace is the claim the paper cannot make: "Red" without the
    finding that produced it is the same black box as a score without factors.
    """
    cases = [
        (_point(), 0.45),
        (_point(), 0.2),
        (_point(body_region="Chest / Heart", pain_type="Stabbing", direction="Radiating down"), 0.9),
        (_point(body_region="Headache / Cranial", severity=8), 0.8),
        (_point(severity=10, heart_rate=130.0), 1.0),
    ]
    # The finding codes are taken from `escalation_for` over the same cases rather
    # than typed out here, so adding a red flag cannot make this pass by being
    # missing from an allow-list nobody maintains.
    trigger_codes = {
        trigger["code"]
        for source, _ in cases
        for trigger in triage_service.escalation_for(source)["triggers"]
    }
    score_codes = {
        triage_service.TIER_RULE_SCORE_CONCERNING_REGION,
        triage_service.TIER_RULE_SCORE_URGENT_BAND,
        triage_service.TIER_RULE_SCORE_BELOW_URGENT_BAND,
    }

    for source, risk in cases:
        result = triage_service.triage_tier(source, risk)
        assert result["decided_by"], result
        assert set(result["decided_by"]) <= trigger_codes | score_codes, result
        assert len(result["decided_by"]) == len(set(result["decided_by"])), result


def test_the_score_only_decides_when_nothing_has_fired():
    result = triage_service.triage_tier(_point(body_region="Chest / Heart", severity=10), 1.0)

    # Every reason is a finding; the band is not cited once a flag has fired.
    assert result["decided_by"] == [
        "chest_pain_severe",
        "pain_maximum_high_concern_region",
    ]


# ── independence from the stored score ────────────────────────────────────

def test_computing_a_tier_never_mutates_the_score_or_the_row():
    data = TriageCreate(body_region="Chest", pain_type="Crushing", severity=9)
    before, contributions_before = triage_service.compute_risk(data)
    snapshot = dict(data.__dict__)

    triage_service.triage_tier(data, before)

    after, contributions_after = triage_service.compute_risk(data)
    assert before == after
    assert contributions_before == contributions_after
    assert data.__dict__ == snapshot


def test_the_legacy_band_mapping_is_one_to_many_and_true():
    """`LEGACY_BAND_TIERS` documents what a stored band can mean today.

    Swept rather than asserted from the table: the mapping is a claim about every
    historical row, so it is checked against a grid of findings, and any (band,
    tier) pair the engine produces outside the documented set fails here.
    """
    regions = [
        "Chest / Heart", "Headache / Cranial", "Abdomen (Upper)", "Neck",
        "Left Arm / Shoulder", "Left Leg", "",
    ]
    pain_types = ["Crushing", "Stabbing", "Sharp", "Dull"]
    severities = [1, 5, 8, 10]
    heart_rates = [None, 45.0, 110.0, 130.0]

    observed = {}
    for region in regions:
        for pain_type in pain_types:
            for severity in severities:
                for heart_rate in heart_rates:
                    data = TriageCreate(
                        body_region=region,
                        pain_type=pain_type,
                        severity=severity,
                        heart_rate=heart_rate,
                    )
                    risk, _ = triage_service.compute_risk(data)
                    band = triage_service.risk_level(risk)
                    tier = triage_service.triage_tier(data, risk)["tier"]
                    observed.setdefault(band, set()).add(tier)
                    assert tier in triage_service.LEGACY_BAND_TIERS[band], (
                        f"{band} band produced {tier}, which the documented "
                        f"mapping does not allow"
                    )

    # The point of the whole exercise, stated as an assertion: no band maps to one
    # tier, so reading the band as the category would have been wrong everywhere.
    assert all(len(tiers) > 1 for tiers in observed.values())


def test_the_tier_and_the_band_disagree_on_a_mild_crushing_chest_pain():
    data = TriageCreate(body_region="Chest / Heart", pain_type="Crushing", severity=1)
    risk, _ = triage_service.compute_risk(data)

    assert triage_service.risk_level(risk) == "medium"
    assert triage_service.triage_tier(data, risk)["tier"] == "red"


# ── through the API ───────────────────────────────────────────────────────

def _create(**fields):
    body = {"body_region": "Left Leg", "pain_type": "Dull", "severity": 3}
    body.update(fields)
    response = client.post("/api/v1/triage/", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def _auth_headers():
    from tests.conftest import DOCTOR_LOGIN

    login = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def test_create_returns_the_tier_beside_an_unchanged_score():
    created = _create(body_region="Chest / Heart", pain_type="Crushing", severity=1)

    assert created["tier"]["tier"] == "red"
    assert created["tier"]["scale"] == "SATS"
    assert "chest_pain_crushing" in created["tier"]["decided_by"]
    # The score is exactly what compute_risk produced - a tier never inflates it.
    assert created["risk_score"] == pytest.approx(0.65, abs=0.01)


def test_the_public_report_keeps_the_category():
    """Redaction drops what identifies the patient, not what tells them what to do."""
    created = _create(body_region="Chest / Heart", pain_type="Crushing", severity=9)

    listing = client.get(f"/api/v1/triage/patient/{created['anonymous_code']}")
    assert listing.status_code == 200, listing.text
    row = next(item for item in listing.json() if item["id"] == created["id"])

    assert row["tier"]["tier"] == "red"
    assert row["patient_name"] is None


def test_clinician_tier_roundtrips_without_touching_the_tools_answer():
    session = _create(body_region="Headache / Cranial", severity=6, pain_type="Dull")
    assert session["clinician_tier"] is None, "a new row must not borrow a judgement"

    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"clinician_tier": "yellow", "status": "closed"},
        headers=_auth_headers(),
    )
    assert response.status_code == 200, response.text
    data = response.json()

    # The human's category and the tool's category are two fields, and disagreeing
    # is the expected state - that difference is the measurement, not an error.
    assert data["clinician_tier"] == "yellow"
    assert data["tier"]["tier"] == session["tier"]["tier"]
    assert data["risk_score"] == session["risk_score"]


@pytest.mark.parametrize("tier", ["red", "orange", "yellow", "green"])
def test_clinician_tier_accepts_every_category_on_the_scale(tier):
    session = _create()

    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"clinician_tier": tier},
        headers=_auth_headers(),
    )

    assert response.status_code == 200, response.text
    assert response.json()["clinician_tier"] == tier


@pytest.mark.parametrize("tier", ["purple", "HIGH", "", "moderate"])
def test_clinician_tier_rejects_anything_off_the_scale(tier):
    """A free-text category would end the comparison the field exists to enable.

    `priority` already shows what free text does to a triage record: nobody can
    count it, and it cannot be scored against anything.
    """
    session = _create()

    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"clinician_tier": tier},
        headers=_auth_headers(),
    )

    assert response.status_code == 422, response.text


def test_an_omitted_category_leaves_the_recorded_one_alone():
    """`clinician_tier` has patch semantics, so nothing erases it by accident.

    The decision form sends the fields it owns; a null meaning "wipe the column"
    would let one careless save delete the reference standard the agreement
    measurement is computed on. The Flutter chips therefore record a category and
    offer no way to un-record one, which is why the control and this rule are
    documented together instead of being left to diverge.
    """
    session = _create()
    recorded = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"clinician_tier": "orange", "status": "closed"},
        headers=_auth_headers(),
    )
    assert recorded.status_code == 200, recorded.text
    assert recorded.json()["clinician_tier"] == "orange"

    untouched = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"status": "open", "clinical_notes": "reviewed on the ward"},
        headers=_auth_headers(),
    )
    assert untouched.status_code == 200, untouched.text
    assert untouched.json()["clinician_tier"] == "orange"


def test_the_api_cannot_accept_a_category_the_engine_cannot_emit():
    """The schema validates against `triage_service.TIERS`, not a second list.

    Two lists of the same four words is how a scale drifts: the engine emits a
    category the API rejects, or the API stores one nothing can score.
    """
    for tier in triage_service.TIERS:
        assert TriageDecisionUpdate(clinician_tier=tier).clinician_tier == tier

    with pytest.raises(ValueError):
        TriageDecisionUpdate(clinician_tier="black")
