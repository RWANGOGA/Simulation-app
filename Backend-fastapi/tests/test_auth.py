import uuid
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.core.config import settings
from tests.conftest import DOCTOR_EMAIL, DOCTOR_LOGIN

client = TestClient(app)

def test_login_success():
    response = client.post(
        "/api/v1/auth/login",
        data=DOCTOR_LOGIN
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"

def test_login_invalid_password():
    response = client.post(
        "/api/v1/auth/login",
        data={"username": DOCTOR_EMAIL, "password": "WrongPassword!"}
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Incorrect email or password"

def test_read_users_me_success():
    login_response = client.post(
        "/api/v1/auth/login",
        data=DOCTOR_LOGIN
    )
    token = login_response.json()["access_token"]
    
    headers = {"Authorization": f"Bearer {token}"}
    response = client.get("/api/v1/auth/me", headers=headers)
    
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == DOCTOR_EMAIL


def _unique_email() -> str:
    domain = DOCTOR_EMAIL.split("@")[1]
    return f"newdoc-{uuid.uuid4().hex[:8]}@{domain}"


def test_register_success_with_professional_fields():
    email = _unique_email()
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "Secure123",
            "full_name": "Jane New",
            "role": "Doctor",
            "license_number": "LIC-2026-001",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == email
    assert data["role"] == "Doctor"
    assert data["license_number"] == "LIC-2026-001"
    assert "hashed_password" not in data
    # The fresh account can immediately log in.
    login = client.post(
        "/api/v1/auth/login", data={"username": email, "password": "Secure123"}
    )
    assert login.status_code == 200


def test_register_duplicate_email_conflict():
    email = _unique_email()
    body = {"email": email, "password": "Secure123", "full_name": "Twice Doc"}
    assert client.post("/api/v1/auth/register", json=body).status_code == 201
    dup = client.post("/api/v1/auth/register", json=body)
    assert dup.status_code == 409


def test_register_rejects_weak_password():
    for weak in ("short1", "onlyletters", "12345678"):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": _unique_email(), "password": weak, "full_name": "Weak Doc"},
        )
        assert response.status_code == 400
        assert "letter and a number" in response.json()["detail"]


def test_register_rejects_invalid_email():
    local = DOCTOR_EMAIL.split("@")[0]
    for bad in ("not-an-email", f"{local}@simtack", f"{local} simtack.com"):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": bad, "password": "Secure123", "full_name": "Bad Email"},
        )
        assert response.status_code == 400
        assert "valid email" in response.json()["detail"]


def test_register_rejects_blank_name():
    response = client.post(
        "/api/v1/auth/register",
        json={"email": _unique_email(), "password": "Secure123", "full_name": "   "},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Full name is required"


@pytest.fixture
def invite_code_required():
    """Temporarily requires an invite code, restoring the original
    (open-by-default) setting afterward regardless of test outcome."""
    original = settings.INVITE_CODE
    settings.INVITE_CODE = "LET-ME-IN"
    yield "LET-ME-IN"
    settings.INVITE_CODE = original


def test_register_open_when_invite_code_unset():
    assert settings.INVITE_CODE == ""
    response = client.post(
        "/api/v1/auth/register",
        json={"email": _unique_email(), "password": "Secure123", "full_name": "No Gate"},
    )
    assert response.status_code == 201


def test_register_rejects_missing_invite_code(invite_code_required):
    response = client.post(
        "/api/v1/auth/register",
        json={"email": _unique_email(), "password": "Secure123", "full_name": "Gate Test"},
    )
    assert response.status_code == 403


def test_register_rejects_wrong_invite_code(invite_code_required):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": _unique_email(),
            "password": "Secure123",
            "full_name": "Gate Test",
            "invite_code": "WRONG-CODE",
        },
    )
    assert response.status_code == 403


def test_register_accepts_correct_invite_code(invite_code_required):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": _unique_email(),
            "password": "Secure123",
            "full_name": "Gate Test",
            "invite_code": invite_code_required,
        },
    )
    assert response.status_code == 201
