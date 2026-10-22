"""Red-flag escalation (triage_service.escalation_for).

The weighted score answers "how concerning is this overall" and is clamped at
1.0, so a single dangerous finding can hide inside a medium total. These tests
pin the rules that surface it, and pin the fact that they do not move the score.
"""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.schemas import TriageCreate
from app.services import triage_service

client = TestClient(app)


def _point(**overrides):
    """A benign pain point, so each test states only the finding it is about."""
    defaults = {
        "body_region": "Left Leg",
        "pain_type": "Dull",
        "severity": 3,
        "heart_rate": None,
        "direction": None,
    }
    return SimpleNamespace(**{**defaults, **overrides})


def _codes(escalation):
    return [trigger["code"] for trigger in escalation["triggers"]]


# ── the rules ─────────────────────────────────────────────────────────────

def test_benign_finding_stays_routine():
    result = triage_service.escalation_for(_point())

    assert result["level"] == triage_service.ESCALATION_ROUTINE
    assert result["action"] == triage_service.ACTION_ROUTINE_REVIEW
    assert result["triggers"] == []


@pytest.mark.parametrize(
    "overrides,expected_code",
    [
        # Chest findings: the character of the pain, where it travels, and how
        # bad it is each stand alone - none of them needs the others to alarm.
        (
            {"body_region": "Chest / Heart", "pain_type": "Crushing", "severity": 2},
            "chest_pain_crushing",
        ),
        (
            {
                "body_region": "Chest",
                "pain_type": "Dull",
                "severity": 2,
                "direction": "Radiating Down",
            },
            "chest_pain_radiating",
        ),
        (
            {"body_region": "Chest", "pain_type": "Dull", "severity": 8},
            "chest_pain_severe",
        ),
        # Both ends of the dangerous heart-rate range.
        ({"heart_rate": 132}, "heart_rate_critical"),
        ({"heart_rate": 44}, "heart_rate_critical"),
        # Worst-possible pain in a region where it may be something else.
        (
            {"body_region": "Abdomen (Upper)", "severity": 10},
            "pain_maximum_high_concern_region",
        ),
        # The urgent tier.
        ({"heart_rate": 110}, "heart_rate_high"),
        ({"severity": 10}, "pain_maximum"),
        ({"body_region": "Head", "severity": 9}, "head_pain_severe"),
    ],
)
def test_rule_fires(overrides, expected_code):
    assert expected_code in _codes(triage_service.escalation_for(_point(**overrides)))


@pytest.mark.parametrize(
    "overrides",
    [
        {"heart_rate": 110},
        {"severity": 10},
        {"body_region": "Head", "severity": 9},
    ],
)
def test_urgent_tier_does_not_claim_emergency(overrides):
    result = triage_service.escalation_for(_point(**overrides))

    assert result["level"] == triage_service.ESCALATION_URGENT
    assert result["action"] == triage_service.ACTION_SEEK_URGENT_CARE


def test_emergency_outranks_urgent_and_is_listed_first():
    result = triage_service.escalation_for(
        _point(body_region="Chest", pain_type="Crushing", severity=8, heart_rate=110)
    )

    assert result["level"] == triage_service.ESCALATION_EMERGENCY
    assert result["action"] == triage_service.ACTION_SEEK_EMERGENCY_CARE
    assert _codes(result)[0] == "chest_pain_crushing"
    assert "heart_rate_high" in _codes(result)


def test_missing_clinical_fields_do_not_raise():
    """Rows created before heart_rate/direction were collected must still score."""
    bare = SimpleNamespace(body_region="Chest", pain_type="Crushing", severity=9)
    assert triage_service.escalation_for(bare)["level"] == (
        triage_service.ESCALATION_EMERGENCY
    )

    nothing = SimpleNamespace(body_region=None, pain_type=None, severity=None)
    assert triage_service.escalation_for(nothing)["level"] == (
        triage_service.ESCALATION_ROUTINE
    )


# ── independence from the score ───────────────────────────────────────────

def test_escalation_catches_what_the_score_lets_through():
    """The point of the rules: mild but crushing chest pain lands in the medium
    band, yet it is an emergency. If this ever stops holding, the rules have
    been folded back into the score."""
    data = TriageCreate(body_region="Chest / Heart", pain_type="Crushing", severity=1)
    risk, _ = triage_service.compute_risk(data)

    assert triage_service.risk_level(risk) == "medium"
    assert triage_service.escalation_for(data)["level"] == "emergency"


def test_escalation_never_mutates_the_score():
    data = TriageCreate(body_region="Chest", pain_type="Crushing", severity=9)
    before, _ = triage_service.compute_risk(data)

    triage_service.escalation_for(data)
    after, _ = triage_service.compute_risk(data)

    assert before == after


# ── through the API ───────────────────────────────────────────────────────

def _create(body_region, pain_type, severity, **extra):
    response = client.post(
        "/api/v1/triage/",
        json={
            "body_region": body_region,
            "pain_type": pain_type,
            "severity": severity,
            **extra,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_create_returns_escalation_beside_an_unchanged_score():
    created = _create("Chest / Heart", "Crushing", 1)

    assert created["escalation"]["level"] == "emergency"
    assert created["escalation"]["triggers"][0]["code"] == "chest_pain_crushing"
    # Still exactly what compute_risk produced - escalation must not inflate it.
    assert created["risk_score"] == pytest.approx(0.65, abs=0.01)


def test_benign_create_reports_routine():
    created = _create("Left Leg", "Dull", 2)

    assert created["escalation"]["level"] == "routine"
    assert created["escalation"]["triggers"] == []


def test_redacted_public_payload_still_warns_the_patient():
    """The anonymous report lookup drops identity fields. A red flag is clinical
    information, so it has to survive redaction - the patient reading their own
    report is exactly who needs to see it."""
    created = _create("Chest", "Crushing", 9)

    listing = client.get(f"/api/v1/triage/patient/{created['anonymous_code']}")

    assert listing.status_code == 200, listing.text
    session = next(row for row in listing.json() if row["id"] == created["id"])
    assert session["escalation"]["level"] == "emergency"
    # `_public_session_payload` pops the identity fields and the response model
    # fills them back in as null, so the check is on the value, not the key.
    assert session["patient_name"] is None
    assert session["patient_phone"] is None
    assert session["patient_address"] is None
