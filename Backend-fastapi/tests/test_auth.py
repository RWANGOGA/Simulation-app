import uuid
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.core.config import settings
from app.core.database import SessionLocal
from app.api.v1.endpoints.auth import create_access_token, get_password_hash
from app.models.doctor import Doctor
from app.models.refresh_token import RefreshToken
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


def test_refresh_token_returns_new_access_token():
    login = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    assert login.status_code == 200
    refresh_token = login.json()["refresh_token"]

    response = client.post(
        "/api/v1/auth/refresh",
        params={"refresh_token": refresh_token},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["access_token"]
    assert data["token_type"] == "bearer"


def test_refresh_token_accepted_from_form_body():
    """The Flutter client posts the token as a form field, not a query
    parameter. Both shapes must work or the app can never refresh."""
    login = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    assert login.status_code == 200
    refresh_token = login.json()["refresh_token"]

    response = client.post(
        "/api/v1/auth/refresh",
        data={"refresh_token": refresh_token},
    )
    assert response.status_code == 200
    assert response.json()["access_token"]


def test_refresh_token_accepted_from_json_body():
    login = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    assert login.status_code == 200
    refresh_token = login.json()["refresh_token"]

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert response.status_code == 200
    assert response.json()["access_token"]


def test_refresh_without_token_is_401_not_422():
    response = client.post("/api/v1/auth/refresh")
    assert response.status_code == 401


def test_refresh_with_bogus_token_is_401():
    response = client.post(
        "/api/v1/auth/refresh",
        data={"refresh_token": "not-a-real-token"},
    )
    assert response.status_code == 401


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
            "password": "Secure123!xY",
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
        "/api/v1/auth/login", data={"username": email, "password": "Secure123!xY"}
    )
    assert login.status_code == 200


def test_register_duplicate_email_conflict():
    email = _unique_email()
    body = {"email": email, "password": "Secure123!xY", "full_name": "Twice Doc"}
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
        assert "Password" in response.json()["detail"]


def test_register_rejects_invalid_email():
    local = DOCTOR_EMAIL.split("@")[0]
    for bad in ("not-an-email", f"{local}@simtack", f"{local} simtack.com"):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": bad, "password": "Secure123!xY", "full_name": "Bad Email"},
        )
        assert response.status_code == 400
        assert "valid email" in response.json()["detail"]


def test_register_rejects_blank_name():
    response = client.post(
        "/api/v1/auth/register",
        json={"email": _unique_email(), "password": "Secure123!xY", "full_name": "   "},
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
        json={"email": _unique_email(), "password": "Secure123!xY", "full_name": "No Gate"},
    )
    assert response.status_code == 201


def test_register_rejects_missing_invite_code(invite_code_required):
    response = client.post(
        "/api/v1/auth/register",
        json={"email": _unique_email(), "password": "Secure123!xY", "full_name": "Gate Test"},
    )
    assert response.status_code == 403


def test_register_rejects_wrong_invite_code(invite_code_required):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": _unique_email(),
            "password": "Secure123!xY",
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
            "password": "Secure123!xY",
            "full_name": "Gate Test",
            "invite_code": invite_code_required,
        },
    )
    assert response.status_code == 201


def test_read_users_me_unauthorized():
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401


def test_inactive_doctor_cannot_login_or_use_existing_token():
    email = _unique_email()
    db = SessionLocal()
    doctor = Doctor(
        email=email,
        hashed_password=get_password_hash("Secure123!xY"),
        full_name="Inactive Doctor",
        is_active=True,
    )
    db.add(doctor)
    db.commit()
    db.refresh(doctor)
    try:
        login = client.post(
            "/api/v1/auth/login",
            data={"username": email, "password": "Secure123!xY"},
        )
        assert login.status_code == 200
        access_token = login.json()["access_token"]

        doctor.is_active = False
        db.commit()

        assert client.post(
            "/api/v1/auth/login",
            data={"username": email, "password": "Secure123!xY"},
        ).status_code == 401
        assert client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {access_token}"},
        ).status_code == 401
    finally:
        db.query(RefreshToken).filter(RefreshToken.doctor_id == doctor.id).delete()
        db.delete(doctor)
        db.commit()
        db.close()


def test_update_users_me_success():
    login_response = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    response = client.patch(
        "/api/v1/auth/me",
        headers=headers,
        json={
            "full_name": "Dr. Updated Name",
            "hospital_name": "City General Hospital",
            "phone": "+1234567890",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["full_name"] == "Dr. Updated Name"
    assert data["hospital_name"] == "City General Hospital"
    assert data["phone"] == "+1234567890"


def test_update_users_me_rejects_blank_full_name():
    login_response = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    response = client.patch(
        "/api/v1/auth/me",
        headers=headers,
        json={"full_name": "   "},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Full name is required"


# ---------------------------------------------------------------------------
# Refresh-token rotation
# ---------------------------------------------------------------------------

def _login_tokens() -> dict:
    response = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    assert response.status_code == 200
    return response.json()


def _refresh(token: str):
    return client.post("/api/v1/auth/refresh", data={"refresh_token": token})


def test_refresh_rotates_the_refresh_token():
    original = _login_tokens()["refresh_token"]

    response = _refresh(original)
    assert response.status_code == 200
    rotated = response.json()["refresh_token"]

    assert rotated
    assert rotated != original, "the presented token must not be handed back"

    db = SessionLocal()
    try:
        old_row = db.query(RefreshToken).filter(RefreshToken.token == original).first()
        new_row = db.query(RefreshToken).filter(RefreshToken.token == rotated).first()
    finally:
        db.close()
    # The old row keeps the moment it was consumed, not a bare "true".
    assert old_row.revoked != "false"
    assert old_row.revoked != "true"
    assert new_row.revoked == "false"


def test_refresh_within_the_grace_window_allows_a_retry():
    """A response lost to a network drop must not sign the clinician out:
    retrying with the same token inside the window still works."""
    original = _login_tokens()["refresh_token"]

    first = _refresh(original)
    second = _refresh(original)

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["access_token"]


def test_replaying_a_consumed_token_ends_the_whole_session(monkeypatch):
    from app.api.v1.endpoints import auth as auth_module

    # Collapse the grace window so a replay is unambiguous.
    monkeypatch.setattr(auth_module, "REFRESH_ROTATION_GRACE_SECONDS", 0)

    original = _login_tokens()["refresh_token"]
    rotated = _refresh(original).json()["refresh_token"]

    replay = _refresh(original)
    assert replay.status_code == 401
    assert "security" in replay.json()["detail"].lower()

    # The legitimate successor is killed too: we cannot tell which holder
    # was the real client, so neither keeps the session.
    assert _refresh(rotated).status_code == 401


def test_logout_revokes_the_refresh_token(monkeypatch):
    from app.api.v1.endpoints import auth as auth_module

    monkeypatch.setattr(auth_module, "REFRESH_ROTATION_GRACE_SECONDS", 0)
    token = _login_tokens()["refresh_token"]

    assert client.post("/api/v1/auth/logout", data={"refresh_token": token}).status_code == 204
    assert _refresh(token).status_code == 401


def test_logout_is_idempotent_and_forgiving():
    assert client.post("/api/v1/auth/logout").status_code == 204
    assert client.post(
        "/api/v1/auth/logout", data={"refresh_token": "never-existed"}
    ).status_code == 204


