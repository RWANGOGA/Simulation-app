import uuid
from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import DOCTOR_EMAIL, DOCTOR_LOGIN

client = TestClient(app)


def _doctor_headers() -> dict:
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

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

# Everything that must never leave the server unauthenticated.
IDENTITY_FIELDS = (
    "full_name",
    "date_of_birth",
    "phone",
    "address",
    "next_of_kin_name",
    "next_of_kin_phone",
    "hospital_name",
    "notes",
)

IDENTITY_VALUES = (
    FULL_DEMOGRAPHICS["full_name"],
    FULL_DEMOGRAPHICS["date_of_birth"],
    FULL_DEMOGRAPHICS["phone"],
    FULL_DEMOGRAPHICS["address"],
    FULL_DEMOGRAPHICS["next_of_kin_name"],
    FULL_DEMOGRAPHICS["next_of_kin_phone"],
    FULL_DEMOGRAPHICS["hospital_name"],
)


def test_create_patient_stores_demographics():
    response = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS)
    assert response.status_code == 201
    data = response.json()
    assert data["full_name"] == "Amara Nansubuga"
    assert data["date_of_birth"] == "2018-03-14"
    assert data["phone"] == "+256700123456"
    assert data["next_of_kin_phone"] == "+256700654321"
    assert data["hospital_name"] == "Mulago National Referral Hospital"


def test_get_patient_by_code_returns_clinical_fields_only():
    """The lookup is unauthenticated — the code is the credential and it
    gets screenshotted, printed and shown to strangers, so it must not
    publish who the person is."""
    created = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS).json()
    fetched = client.get(f"/api/v1/patients/{created['anonymous_code']}")
    assert fetched.status_code == 200
    data = fetched.json()

    for field in IDENTITY_FIELDS:
        assert field not in data, f"{field} was published on the unauthenticated route"

    # The record itself still has to come back for the intake flow.
    assert data["anonymous_code"] == created["anonymous_code"]
    assert data["age"] == 8
    assert data["gender"] == "Female"
    assert data["weight"] == 28.0


def test_get_patient_by_code_never_contains_identity_values():
    """Guards against a future refactor that republishes the same data
    under a different key name."""
    created = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS).json()
    body = client.get(f"/api/v1/patients/{created['anonymous_code']}").text
    for value in IDENTITY_VALUES:
        assert value not in body, f"identity value {value!r} leaked"


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
        headers={"X-Patient-Code": patient["anonymous_code"]},
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
    domain = DOCTOR_EMAIL.split("@")[1]
    email = f"newdoc-{uuid.uuid4().hex[:8]}@{domain}"
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "Secure123!xY",
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


def test_update_patient_corrects_a_single_field():
    patient = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS).json()
    response = client.patch(
        f"/api/v1/patients/{patient['anonymous_code']}",
        json={"phone": "+256700999999"},
        headers=_doctor_headers(),
    )
    assert response.status_code == 200
    data = response.json()
    assert data["phone"] == "+256700999999"
    # Untouched fields must survive an update that only sent one field.
    assert data["full_name"] == "Amara Nansubuga"
    assert data["hospital_name"] == "Mulago National Referral Hospital"


def test_update_patient_requires_jwt():
    patient = client.post("/api/v1/patients/", json=FULL_DEMOGRAPHICS).json()
    response = client.patch(
        f"/api/v1/patients/{patient['anonymous_code']}",
        json={"phone": "+256700999999"},
    )
    assert response.status_code == 401


def test_update_patient_unknown_code_404():
    response = client.patch(
        "/api/v1/patients/P-DOESNOTEXIST",
        json={"phone": "+256700999999"},
        headers=_doctor_headers(),
    )
    assert response.status_code == 404
