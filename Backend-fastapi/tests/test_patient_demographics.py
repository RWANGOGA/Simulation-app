import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

FULL_DEMOGRAPHICS = {
    "age": 8,
    "gender": "Female",
    "weight": 28.0,
    "height": 130.0,
    "full_name": "Amara Nansubuga",
    "date_of_birth": "2018-03-14",
    "phone": "+256700123456",
    "address": "Plot 12, Kampala Road",
    "next_of_kin_name": "Grace Nansubuga",
    "next_of_kin_phone": "+256700654321",
    "hospital_name": "Mulago National Referral Hospital",
}


def test_create_patient_stores_demographics():
    response = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS)
    assert response.status_code == 201
    data = response.json()
    assert data["full_name"] == "Amara Nansubuga"
    assert data["date_of_birth"] == "2018-03-14"
    assert data["phone"] == "+256700123456"
    assert data["next_of_kin_phone"] == "+256700654321"
    assert data["hospital_name"] == "Mulago National Referral Hospital"


def test_get_patient_by_code_returns_demographics():
    created = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS).json()
    fetched = client.get(f"/api/v1/patients/{created['anonymous_code']}")
    assert fetched.status_code == 200
    data = fetched.json()
    assert data["full_name"] == "Amara Nansubuga"
    assert data["address"] == "Plot 12, Kampala Road"


def test_patient_demographics_optional_for_anonymous_walkins():
    # The intake flow must still work with only vitals — no demographics.
    response = client.post(
        "/api/v1/patients/",
        json={"age": 30, "gender": "Male", "weight": 70.0, "height": 175.0},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["full_name"] is None
    assert data["phone"] is None


def test_triage_response_carries_patient_demographics():
    patient = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS).json()
    response = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Head",
            "pain_type": "throbbing",
            "severity": 6,
        },
    )
    assert response.status_code == 201
    data = response.json()
    # The QR-scan report lookup relies on these joined fields.
    assert data["patient_name"] == "Amara Nansubuga"
    assert data["patient_date_of_birth"] == "2018-03-14"
    assert data["patient_phone"] == "+256700123456"
    assert data["patient_next_of_kin_name"] == "Grace Nansubuga"
    assert data["patient_next_of_kin_phone"] == "+256700654321"
    assert data["patient_hospital_name"] == "Mulago National Referral Hospital"


def test_register_stores_contact_and_hospital():
    email = f"newdoc-{uuid.uuid4().hex[:8]}@simtack.com"
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "Secure123",
            "full_name": "Dr. Contact",
            "role": "Doctor",
            "license_number": "LIC-9",
            "phone": "+256772000000",
            "hospital_name": "Rubaga Hospital",
            "date_of_birth": "1985-06-01",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["phone"] == "+256772000000"
    assert data["hospital_name"] == "Rubaga Hospital"
    assert data["date_of_birth"] == "1985-06-01"
