"""The administrator console API.

These tests pin the contract the Flutter console depends on: the routes are
administrator-only, the overview is computed from the same rules the
practitioner sees, the activity feed is the audit trail, and the session list
is an operational view rather than a second clinical chart.
"""

from fastapi.testclient import TestClient

from app.core.database import SessionLocal
from app.main import app
from app.models.doctor import ACCESS_ADMIN, Doctor
from tests.conftest import doctor_headers, practitioner_headers

client = TestClient(app)

ADMIN_URL = "/api/v1/admin"
REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"

PENDING_EMAIL = "pending@simtack.com"
PENDING_PASSWORD = "Pending123!"


def _register_pending(email: str = PENDING_EMAIL) -> dict:
    response = client.post(
        REGISTER_URL,
        json={
            "email": email,
            "password": PENDING_PASSWORD,
            "full_name": "Pending Person",
            "hospital_name": "St. Mary's",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _account_id(email: str) -> int:
    db = SessionLocal()
    try:
        doctor = db.query(Doctor).filter(Doctor.email == email).first()
        assert doctor is not None
        return doctor.id
    finally:
        db.close()


def _submit(
    region: str = "Chest / Heart",
    pain_type: str = "Crushing",
    severity: int = 9,
    patient_id: int | None = None,
    patient_code: str | None = None,
    status: str | None = None,
) -> dict:
    response = client.post(
        "/api/v1/triage/",
        json={
            "body_region": region,
            "pain_type": pain_type,
            "severity": severity,
            "patient_id": patient_id,
        },
        headers={"X-Patient-Code": patient_code} if patient_code else None,
    )
    assert response.status_code == 201, response.text
    session = response.json()
    if status is not None:
        patch = client.patch(
            f"/api/v1/triage/{session['id']}/decision",
            json={"status": status},
            headers=doctor_headers(client),
        )
        assert patch.status_code == 200, patch.text
    return session


def _create_patient(**fields) -> dict:
    response = client.post("/api/v1/patients/", json=fields)
    assert response.status_code == 201, response.text
    return response.json()


# --------------------------------------------------------------------------
# Authorisation
# --------------------------------------------------------------------------

def test_admin_routes_require_authentication():
    for path in ("overview", "users", "activity", "sessions"):
        response = client.get(f"{ADMIN_URL}/{path}")
        assert response.status_code == 401, (path, response.text)


def test_admin_routes_reject_a_signed_in_practitioner():
    headers = practitioner_headers(client)
    for path in ("overview", "users", "activity", "sessions"):
        response = client.get(f"{ADMIN_URL}/{path}", headers=headers)
        assert response.status_code == 403, (path, response.text)


# --------------------------------------------------------------------------
# Overview
# --------------------------------------------------------------------------

def test_overview_counts_users_patients_and_sessions():
    headers = doctor_headers(client)
    before = client.get(f"{ADMIN_URL}/overview", headers=headers).json()

    _register_pending()
    patient = _create_patient(full_name="Amina Nakato", age=41)
    _submit(patient_id=patient["id"], patient_code=patient["anonymous_code"])

    after = client.get(f"{ADMIN_URL}/overview", headers=headers).json()

    assert after["users"]["total"] == before["users"]["total"] + 1
    assert after["users"]["pending"] == before["users"]["pending"] + 1
    assert after["patients"]["total"] == before["patients"]["total"] + 1
    assert after["triage"]["total"] == before["triage"]["total"] + 1
    assert after["triage"]["today"] >= 1
    assert after["triage"]["last_7_days"] >= 1

    # Every band and every tier is present even at zero, so the client never
    # has to distinguish "missing" from "none happened".
    assert set(after["triage"]["by_tier"]) == {"red", "orange", "yellow", "green"}
    assert set(after["triage"]["by_escalation"]) == {
        "emergency",
        "urgent",
        "routine",
    }
    assert after["triage"]["high_risk"] >= 1
    assert after["triage"]["by_tier"]["red"] >= 1
    assert after["triage"]["by_escalation"]["emergency"] >= 1
    assert after["triage"]["by_region"][0]["count"] >= 1


def test_overview_returns_a_stable_envelope():
    headers = doctor_headers(client)
    payload = client.get(f"{ADMIN_URL}/overview", headers=headers).json()

    assert payload["generated_at"]
    assert payload["environment"]
    assert payload["version"]
    assert isinstance(payload["activity"]["recent"], list)
    assert "denied" in payload["activity"]


# --------------------------------------------------------------------------
# Users
# --------------------------------------------------------------------------

def test_users_list_marks_pending_accounts_and_carries_counts():
    headers = doctor_headers(client)
    _register_pending()

    payload = client.get(f"{ADMIN_URL}/users", headers=headers).json()

    pending = [item for item in payload["items"] if item["email"] == PENDING_EMAIL]
    assert len(pending) == 1
    assert pending[0]["is_approved"] is False
    assert pending[0]["is_admin"] is False
    assert payload["counts"]["pending"] >= 1
    assert payload["counts"]["admins"] >= 1
    assert payload["pagination"]["total"] >= 2


def test_users_can_be_filtered_to_pending():
    headers = doctor_headers(client)
    _register_pending()

    payload = client.get(
        f"{ADMIN_URL}/users?status=pending", headers=headers
    ).json()

    assert payload["items"]
    assert all(item["is_approved"] is False for item in payload["items"])
    assert any(item["email"] == PENDING_EMAIL for item in payload["items"])


def test_users_can_be_searched_by_email_or_hospital():
    headers = doctor_headers(client)
    _register_pending()

    by_email = client.get(
        f"{ADMIN_URL}/users?q=pending@", headers=headers
    ).json()
    assert [item["email"] for item in by_email["items"]] == [PENDING_EMAIL]

    by_hospital = client.get(
        f"{ADMIN_URL}/users?q=St.%20Mary", headers=headers
    ).json()
    assert any(item["email"] == PENDING_EMAIL for item in by_hospital["items"])


def test_admin_can_approve_an_account_through_the_admin_route():
    headers = doctor_headers(client)
    _register_pending()
    account_id = _account_id(PENDING_EMAIL)

    response = client.patch(
        f"{ADMIN_URL}/users/{account_id}",
        json={"is_approved": True},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    assert response.json()["is_approved"] is True

    # The account can now obtain a token.
    login = client.post(
        LOGIN_URL,
        data={"username": PENDING_EMAIL, "password": PENDING_PASSWORD},
    )
    assert login.status_code == 200, login.text


def test_admin_can_promote_and_deactivate_another_account():
    headers = doctor_headers(client)
    _register_pending()
    account_id = _account_id(PENDING_EMAIL)

    promoted = client.patch(
        f"{ADMIN_URL}/users/{account_id}",
        json={"access_level": ACCESS_ADMIN},
        headers=headers,
    )
    assert promoted.status_code == 200
    assert promoted.json()["access_level"] == ACCESS_ADMIN
    assert promoted.json()["is_admin"] is True

    deactivated = client.patch(
        f"{ADMIN_URL}/users/{account_id}",
        json={"is_active": False},
        headers=headers,
    )
    assert deactivated.status_code == 200
    assert deactivated.json()["is_active"] is False


def test_admin_cannot_demote_themselves():
    headers = doctor_headers(client)
    me = client.get("/api/v1/auth/me", headers=headers).json()

    response = client.patch(
        f"{ADMIN_URL}/users/{me['id']}",
        json={"access_level": "practitioner"},
        headers=headers,
    )
    assert response.status_code == 400
    assert "administrator access" in response.json()["detail"].lower()


# --------------------------------------------------------------------------
# Activity
# --------------------------------------------------------------------------

def test_activity_feed_is_the_audit_trail_and_records_admin_reads():
    headers = doctor_headers(client)
    client.get(f"{ADMIN_URL}/overview", headers=headers)

    first = client.get(f"{ADMIN_URL}/activity", headers=headers).json()
    assert first["items"]
    assert first["pagination"]["total"] >= 1

    # The read above is itself an audit event, so the next page must contain it.
    second = client.get(f"{ADMIN_URL}/activity", headers=headers).json()
    assert any(
        item["resource_type"] == "audit_log" for item in second["items"]
    )


def test_activity_can_be_filtered_by_outcome_and_action():
    headers = doctor_headers(client)
    client.get(f"{ADMIN_URL}/overview", headers=headers)

    denied = client.get(
        f"{ADMIN_URL}/activity?outcome=denied", headers=headers
    ).json()
    assert all(item["outcome"] == "denied" for item in denied["items"])

    reads = client.get(
        f"{ADMIN_URL}/activity?action=read", headers=headers
    ).json()
    assert all(item["action"] == "read" for item in reads["items"])


# --------------------------------------------------------------------------
# Sessions
# --------------------------------------------------------------------------

def test_session_list_redacts_identity_and_derives_tier():
    headers = doctor_headers(client)
    patient = _create_patient(full_name="Secret Person", phone="+256700000000")
    submitted = _submit(
        patient_id=patient["id"],
        patient_code=patient["anonymous_code"],
        region="Chest / Heart",
    )

    payload = client.get(f"{ADMIN_URL}/sessions", headers=headers).json()
    item = next(row for row in payload["items"] if row["id"] == submitted["id"])

    assert item["patient_code"] == patient["anonymous_code"]
    assert item["risk_level"] == "high"
    assert item["tier"] == "red"
    assert item["escalation"] == "emergency"
    # The operational view carries no patient name or contact details.
    assert "full_name" not in item
    assert "phone" not in item


def test_eight_character_password_is_the_minimum():
    # The rule is eight characters everywhere: backend validation, the
    # Flutter registration form and the documented default. Seven must fail,
    # eight must succeed, without changing any existing account's password.
    import uuid
    suffix = uuid.uuid4().hex[:8]
    short = client.post(
        REGISTER_URL,
        json={
            "email": f"short-{suffix}@simtack.com",
            "password": "Abc1234",
            "full_name": "Short Password",
        },
    )
    assert short.status_code in (400, 422)

    ok = client.post(
        REGISTER_URL,
        json={
            "email": f"eight-{suffix}@simtack.com",
            "password": "Abc1234!",
            "full_name": "Eight Password",
        },
    )
    assert ok.status_code == 201


def test_overview_carries_real_trend_and_activity_breakdowns():
    headers = doctor_headers(client)
    payload = client.get(f"{ADMIN_URL}/overview", headers=headers).json()

    trend = payload["triage"]["trend"]
    assert len(trend) == 14
    assert all("date" in day and "count" in day for day in trend)
    assert sum(day["count"] for day in trend) <= payload["triage"]["total"]

    activity = payload["activity"]
    for key in ("by_action", "by_outcome", "by_actor_type"):
        assert isinstance(activity[key], dict)
        assert sum(activity[key].values()) == activity["total"]


def test_patient_register_shows_real_records_and_session_facts():
    headers = doctor_headers(client)
    patient = _create_patient(
        full_name="Register Person", phone="+256700000123", age=33
    )
    _submit(
        patient_id=patient["id"],
        patient_code=patient["anonymous_code"],
        region="Left Knee",
        pain_type="Dull",
        severity=3,
    )

    payload = client.get(f"{ADMIN_URL}/patients", headers=headers).json()
    row = next(item for item in payload["items"] if item["id"] == patient["id"])

    assert row["anonymous_code"] == patient["anonymous_code"]
    assert row["full_name"] == "Register Person"
    assert row["phone"] == "+256700000123"
    assert row["session_count"] >= 1
    assert row["last_risk_score"] is not None
    assert row["last_session_at"]

    searched = client.get(
        f"{ADMIN_URL}/patients?q=Register%20Person", headers=headers
    ).json()
    assert [item["id"] for item in searched["items"]] == [patient["id"]]

    with_sessions = client.get(
        f"{ADMIN_URL}/patients?hasSessions=true", headers=headers
    ).json()
    assert any(item["id"] == patient["id"] for item in with_sessions["items"])


def test_patient_detail_returns_demographics_sessions_and_audit():
    headers = doctor_headers(client)
    patient = _create_patient(
        full_name="Detail Person",
        age=45,
        address="Kampala",
        next_of_kin_name="Joan",
    )
    session = _submit(
        patient_id=patient["id"],
        patient_code=patient["anonymous_code"],
    )

    payload = client.get(
        f"{ADMIN_URL}/patients/{patient['id']}", headers=headers
    ).json()

    assert payload["full_name"] == "Detail Person"
    assert payload["address"] == "Kampala"
    assert payload["next_of_kin_name"] == "Joan"
    assert any(item["id"] == session["id"] for item in payload["sessions"])
    assert any(
        item["resource_type"] == "patient"
        for item in payload["audit"]
    )
    assert client.get(f"{ADMIN_URL}/patients/999999", headers=headers).status_code == 404


def test_practitioner_detail_returns_full_profile_and_own_activity():
    headers = doctor_headers(client)
    _register_pending()
    account_id = _account_id(PENDING_EMAIL)

    payload = client.get(f"{ADMIN_URL}/users/{account_id}", headers=headers).json()

    assert payload["email"] == PENDING_EMAIL
    assert payload["full_name"] == "Pending Person"
    assert payload["hospital_name"] == "St. Mary's"
    assert payload["is_approved"] is False
    assert payload["audit_count"] >= 0
    assert isinstance(payload["recent_activity"], list)
    assert client.get(f"{ADMIN_URL}/users/999999", headers=headers).status_code == 404


def test_patient_routes_are_admin_only():
    assert client.get(f"{ADMIN_URL}/patients").status_code == 401
    assert client.get(f"{ADMIN_URL}/patients/1").status_code == 401
    practitioner = practitioner_headers(client)
    assert client.get(f"{ADMIN_URL}/patients", headers=practitioner).status_code == 403
    assert client.get(f"{ADMIN_URL}/patients/1", headers=practitioner).status_code == 403
    assert client.get(f"{ADMIN_URL}/users/1", headers=practitioner).status_code == 403


def test_session_list_filters_by_risk_and_status():
    headers = doctor_headers(client)
    high = _submit(region="Chest / Heart", pain_type="Crushing", severity=9)
    low = _submit(region="Left Knee", pain_type="Dull", severity=1)

    high_rows = client.get(
        f"{ADMIN_URL}/sessions?risk_level=high", headers=headers
    ).json()["items"]
    low_rows = client.get(
        f"{ADMIN_URL}/sessions?risk_level=low", headers=headers
    ).json()["items"]

    assert any(row["id"] == high["id"] for row in high_rows)
    assert all(row["id"] != low["id"] for row in high_rows)
    assert any(row["id"] == low["id"] for row in low_rows)

    _submit(region="Left Knee", pain_type="Dull", severity=1, status="closed")
    closed = client.get(
        f"{ADMIN_URL}/sessions?status=closed", headers=headers
    ).json()["items"]
    assert closed
    assert all(row["status"] == "closed" for row in closed)
