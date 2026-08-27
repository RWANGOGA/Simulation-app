import json
import uuid
from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)


def _doctor_headers() -> dict:
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _new_patient() -> dict:
    return client.post(
        "/api/v1/patients/",
        json={"age": 40, "gender": "Male", "weight": 80.0, "height": 180.0},
    ).json()


def _submit(patient_id: int, visit_id: str, region: str = "Head") -> dict:
    return client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient_id,
            "body_region": region,
            "pain_type": "throbbing",
            "severity": 5,
            "visit_id": visit_id,
        },
    ).json()


def test_history_returns_all_visits_newest_first():
    patient = _new_patient()
    v1 = uuid.uuid4().hex
    v2 = uuid.uuid4().hex
    _submit(patient["id"], v1, region="Head")
    _submit(patient["id"], v1, region="Chest")
    _submit(patient["id"], v2, region="Left Arm")

    response = client.get(
        f"/api/v1/triage/patient/{patient['anonymous_code']}/history",
        headers=_doctor_headers(),
    )
    assert response.status_code == 200
    sessions = response.json()
    assert len(sessions) == 3
    # Newest first: the single-session visit v2 was submitted last.
    assert sessions[0]["visit_id"] == v2
    assert {s["visit_id"] for s in sessions[1:]} == {v1}
    # Full payload shape (demographics join included).
    assert sessions[0]["anonymous_code"] == patient["anonymous_code"]
    assert sessions[0]["patient_age"] == 40


def test_history_requires_jwt():
    patient = _new_patient()
    _submit(patient["id"], uuid.uuid4().hex)
    response = client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}/history")
    assert response.status_code == 401


def test_history_unknown_patient_404():
    response = client.get("/api/v1/triage/patient/P-NOPE/history", headers=_doctor_headers())
    assert response.status_code == 404


def test_shap_explanation_now_carries_impact_sign():
    patient = _new_patient()
    session = _submit(patient["id"], uuid.uuid4().hex)
    factors = json.loads(session["shap_explanation"])
    assert factors and all("impact" in f for f in factors)
    assert all(f["impact"] in ("+", "-") for f in factors)
