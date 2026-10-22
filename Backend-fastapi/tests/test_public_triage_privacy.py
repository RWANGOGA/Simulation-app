"""Privacy boundary of the unauthenticated patient lookup.

`GET /triage/patient/{code}` has to stay open — the anonymous code is the
patient's credential and they reach it by scanning a QR with no account.
But the code is also screenshotted, printed and handed to strangers, so the
response must never carry the patient's identity. These tests pin that
boundary in both directions: redacted anonymously, complete for a
signed-in practitioner.
"""

import uuid
from fastapi.testclient import TestClient

from app.main import app
from app.core.database import SessionLocal
from app.models.patient import Patient
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)

IDENTITY_FIELDS = (
    "patient_name",
    "patient_date_of_birth",
    "patient_phone",
    "patient_address",
    "patient_next_of_kin_name",
    "patient_next_of_kin_phone",
    "patient_hospital_name",
)

# Identity the patient handed over at intake, which must not leak.
IDENTITY_VALUES = {
    "full_name": "Amina Nakato",
    "date_of_birth": "1986-04-12",
    "phone": "+256700111222",
    "address": "14 Bukoto Street, Kampala",
    "next_of_kin_name": "Joseph Nakato",
    "next_of_kin_phone": "+256700333444",
    "hospital_name": "Mulago Referral Hospital",
}


def _doctor_headers() -> dict:
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _patient_with_identity() -> dict:
    response = client.post(
        "/api/v1/patients/",
        json={"age": 40, "gender": "Female", "weight": 68.0, "height": 162.0,
              **IDENTITY_VALUES},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _submit(patient_id: int, region: str = "Chest") -> dict:
    db = SessionLocal()
    patient = db.get(Patient, patient_id)
    db.close()
    assert patient is not None
    response = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient_id,
            "body_region": region,
            "pain_type": "throbbing",
            "severity": 6,
            "visit_id": uuid.uuid4().hex,
        },
        headers={"X-Patient-Code": patient.anonymous_code},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_public_lookup_hides_identity_but_keeps_the_clinical_record():
    patient = _patient_with_identity()
    _submit(patient["id"])

    response = client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}")
    assert response.status_code == 200
    sessions = response.json()
    assert len(sessions) == 1
    session = sessions[0]

    for field in IDENTITY_FIELDS:
        assert session.get(field) is None, f"{field} leaked on the public route"

    # The report itself must still render for the patient.
    assert session["body_region"] == "Chest"
    assert session["severity"] == 6
    assert session["risk_score"] is not None
    assert session["anonymous_code"] == patient["anonymous_code"]
    assert session["patient_age"] == 40
    assert session["patient_gender"] == "Female"


def test_public_lookup_never_contains_the_phone_or_address_substrings():
    """Guards against a future refactor that re-adds the fields in another
    key name — the values themselves must not appear anywhere."""
    patient = _patient_with_identity()
    _submit(patient["id"])

    body = client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}").text
    for value in IDENTITY_VALUES.values():
        assert value not in body, f"identity value {value!r} leaked"


def test_practitioner_history_still_returns_the_full_record():
    patient = _patient_with_identity()
    _submit(patient["id"])

    response = client.get(
        f"/api/v1/triage/patient/{patient['anonymous_code']}/history",
        headers=_doctor_headers(),
    )
    assert response.status_code == 200
    session = response.json()[0]
    assert session["patient_name"] == IDENTITY_VALUES["full_name"]
    assert session["patient_phone"] == IDENTITY_VALUES["phone"]
    assert session["patient_address"] == IDENTITY_VALUES["address"]
    assert session["patient_next_of_kin_name"] == IDENTITY_VALUES["next_of_kin_name"]


def test_public_lookup_of_unknown_code_is_404():
    assert client.get("/api/v1/triage/patient/P-DOESNOTEXIST").status_code == 404
