"""Who is allowed to do what.

Registration used to be the whole security model: reach the endpoint, become a
doctor, and a doctor could read every patient record and every patient's full
identity. These tests pin the replacement contract:

* a new account is inert until an administrator approves it;
* only an administrator can approve, promote or deactivate;
* revoking access takes effect on the very next request, not fifteen minutes
  later when the access token happens to expire;
* nobody can lock the deployment out by demoting themselves; and
* approval status is not disclosed to a caller who does not know the password.
"""

from fastapi.testclient import TestClient

from app.core.database import SessionLocal
from app.main import app
from app.models.doctor import ACCESS_ADMIN, ACCESS_PRACTITIONER, Doctor
from app.models.refresh_token import RefreshToken
from tests.conftest import (
    DOCTOR_LOGIN,
    PRACTITIONER_EMAIL,
    PRACTITIONER_LOGIN,
    doctor_headers,
    practitioner_headers,
    seed_practitioner,
)

client = TestClient(app)

REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
DOCTORS_URL = "/api/v1/auth/doctors"

NEW_EMAIL = "newcomer@simtack.com"
NEW_PASSWORD = "Newcomer123!"


def _register(email: str = NEW_EMAIL, password: str = NEW_PASSWORD, **extra) -> dict:
    body = {"email": email, "password": password, "full_name": "New Comer", **extra}
    response = client.post(REGISTER_URL, json=body)
    assert response.status_code == 201, response.text
    return response.json()


def _login(email: str, password: str):
    return client.post(LOGIN_URL, data={"username": email, "password": password})


def _account_id(email: str) -> int:
    db = SessionLocal()
    try:
        doctor = db.query(Doctor).filter(Doctor.email == email).first()
        assert doctor is not None
        return doctor.id
    finally:
        db.close()


def _practitioner_id() -> int:
    """The seeded non-admin account, created on demand."""
    seed_practitioner()
    return _account_id(PRACTITIONER_LOGIN["username"])


def _set_account(email: str, **fields) -> None:
    """Reaches past the API to arrange state the API would refuse to create."""
    db = SessionLocal()
    try:
        doctor = db.query(Doctor).filter(Doctor.email == email).first()
        assert doctor is not None
        for key, value in fields.items():
            setattr(doctor, key, value)
        db.commit()
    finally:
        db.close()


def _wipe_all_accounts() -> None:
    """Empties the doctors table so the bootstrap path can be exercised."""
    db = SessionLocal()
    try:
        db.query(RefreshToken).delete()
        db.query(Doctor).delete()
        db.commit()
    finally:
        db.close()


# --------------------------------------------------------------------------
# The approval gate
# --------------------------------------------------------------------------

def test_first_account_on_a_fresh_database_becomes_an_approved_admin():
    """Without this bootstrap nobody could ever approve anybody, and closing
    the door would lock the deployment out of itself."""
    _wipe_all_accounts()

    created = _register()
    assert created["is_approved"] is True
    assert created["access_level"] == ACCESS_ADMIN
    assert _login(NEW_EMAIL, NEW_PASSWORD).status_code == 200


def test_a_later_registration_cannot_sign_in_until_approved():
    created = _register()
    assert created["is_approved"] is False

    blocked = _login(NEW_EMAIL, NEW_PASSWORD)
    assert blocked.status_code == 403
    assert "awaiting administrator approval" in blocked.json()["detail"].lower()

    # And it holds no token of any kind, so there is nothing to refresh with.
    assert "access_token" not in blocked.json()


def test_approval_lets_the_account_sign_in():
    _register()
    account_id = _account_id(NEW_EMAIL)

    approved = client.patch(
        f"{DOCTORS_URL}/{account_id}",
        json={"is_approved": True},
        headers=doctor_headers(client),
    )
    assert approved.status_code == 200
    assert approved.json()["is_approved"] is True

    assert _login(NEW_EMAIL, NEW_PASSWORD).status_code == 200


def test_registration_cannot_self_promote():
    """`access_level` is not part of the registration schema, so sending it
    must be ignored rather than honoured."""
    created = _register(access_level=ACCESS_ADMIN, is_approved=True)
    assert created["access_level"] == ACCESS_PRACTITIONER
    assert created["is_approved"] is False


def test_pending_status_is_not_disclosed_without_the_correct_password():
    """A wrong password must look identical whether or not the account is
    approved — otherwise this endpoint enumerates unapproved accounts."""
    _register()

    wrong = _login(NEW_EMAIL, "TotallyWrong123!")
    assert wrong.status_code == 401
    assert wrong.json()["detail"] == "Incorrect email or password"


# --------------------------------------------------------------------------
# Only administrators administer
# --------------------------------------------------------------------------

def test_practitioner_cannot_list_accounts():
    response = client.get(DOCTORS_URL, headers=practitioner_headers(client))
    assert response.status_code == 403
    assert "Administrator" in response.json()["detail"]


def test_practitioner_cannot_approve_anyone():
    _register()
    account_id = _account_id(NEW_EMAIL)

    response = client.patch(
        f"{DOCTORS_URL}/{account_id}",
        json={"is_approved": True},
        headers=practitioner_headers(client),
    )
    assert response.status_code == 403
    # Still pending, so the refusal actually did something.
    assert _login(NEW_EMAIL, NEW_PASSWORD).status_code == 403


def test_account_listing_requires_a_token():
    assert client.get(DOCTORS_URL).status_code == 401


def test_admin_sees_pending_accounts_and_can_filter_to_them():
    _register()
    headers = doctor_headers(client)

    pending = client.get(f"{DOCTORS_URL}?pending_only=true", headers=headers).json()
    assert [row["email"] for row in pending] == [NEW_EMAIL]

    everything = client.get(DOCTORS_URL, headers=headers).json()
    assert {row["email"] for row in everything} >= {NEW_EMAIL, DOCTOR_LOGIN["username"]}


def test_admin_can_promote_a_practitioner_to_admin():
    headers = doctor_headers(client)
    practitioner_id = _practitioner_id()

    response = client.patch(
        f"{DOCTORS_URL}/{practitioner_id}",
        json={"access_level": ACCESS_ADMIN},
        headers=headers,
    )
    assert response.status_code == 200
    # The promoted account now gets through the audit gate it was refused by
    # before (practitioner_headers re-reads the role on every login).
    assert (
        client.get(
            "/api/v1/audit/logs", headers=practitioner_headers(client)
        ).status_code
        == 200
    )


def test_unknown_access_level_is_rejected():
    headers = doctor_headers(client)
    practitioner_id = _practitioner_id()

    response = client.patch(
        f"{DOCTORS_URL}/{practitioner_id}",
        json={"access_level": "superuser"},
        headers=headers,
    )
    assert response.status_code == 400


def test_empty_patch_is_rejected():
    headers = doctor_headers(client)
    practitioner_id = _practitioner_id()

    assert (
        client.patch(f"{DOCTORS_URL}/{practitioner_id}", json={}, headers=headers).status_code
        == 400
    )


def test_admin_cannot_demote_themselves():
    """The only admin demoting themselves leaves nobody able to approve
    accounts, and the fix is a manual SQL statement."""
    headers = doctor_headers(client)
    my_id = _account_id(DOCTOR_LOGIN["username"])

    response = client.patch(
        f"{DOCTORS_URL}/{my_id}",
        json={"access_level": ACCESS_PRACTITIONER},
        headers=headers,
    )
    assert response.status_code == 400
    assert "own administrator" in response.json()["detail"]


def test_admin_cannot_deactivate_themselves():
    headers = doctor_headers(client)
    my_id = _account_id(DOCTOR_LOGIN["username"])

    response = client.patch(
        f"{DOCTORS_URL}/{my_id}",
        json={"is_active": False},
        headers=headers,
    )
    assert response.status_code == 400


# --------------------------------------------------------------------------
# Revocation is immediate
# --------------------------------------------------------------------------

def test_deactivating_an_account_ends_its_session_on_the_next_request():
    headers = practitioner_headers(client)
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 200

    practitioner_id = _account_id(PRACTITIONER_EMAIL)
    admin = doctor_headers(client)
    client.patch(
        f"{DOCTORS_URL}/{practitioner_id}", json={"is_active": False}, headers=admin
    )

    # The access token is still cryptographically valid for ~15 minutes; the
    # point is that the server stops honouring it immediately.
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_revoking_approval_ends_its_session_on_the_next_request():
    headers = practitioner_headers(client)
    practitioner_id = _account_id(PRACTITIONER_EMAIL)
    admin = doctor_headers(client)

    client.patch(
        f"{DOCTORS_URL}/{practitioner_id}", json={"is_approved": False}, headers=admin
    )

    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_revoked_account_cannot_refresh_its_way_back_in():
    """A refresh token outlives the access token by days, so revocation has
    to be checked there too or a deactivated clinician keeps working."""
    _register()
    account_id = _account_id(NEW_EMAIL)
    client.patch(
        f"{DOCTORS_URL}/{account_id}",
        json={"is_approved": True},
        headers=doctor_headers(client),
    )

    tokens = _login(NEW_EMAIL, NEW_PASSWORD).json()
    assert tokens["refresh_token"]

    _set_account(NEW_EMAIL, is_approved=False)

    refreshed = client.post(
        "/api/v1/auth/refresh", data={"refresh_token": tokens["refresh_token"]}
    )
    assert refreshed.status_code == 401
