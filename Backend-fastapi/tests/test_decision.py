import json

from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)


def _auth_headers():
    login = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN)
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _create_session():
    response = client.post(
        "/api/v1/triage/",
        json={"body_region": "Chest", "pain_type": "Sharp", "severity": 7},
    )
    assert response.status_code == 201
    return response.json()


def test_new_session_defaults_to_open():
    data = _create_session()
    assert data["status"] == "open"
    assert data["priority"] is None
    assert data["clinical_notes"] is None


def test_decision_requires_jwt():
    session = _create_session()
    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"status": "closed"},
    )
    assert response.status_code == 401


def test_decision_update_roundtrip():
    session = _create_session()
    headers = _auth_headers()

    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={
            "status": "closed",
            "priority": "Review Immediately",
            "actions_taken": ["Physical examination", "Urgent review"],
            "clinical_notes": "Patient reviewed, follow-up booked.",
        },
        headers=headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "closed"
    assert data["priority"] == "Review Immediately"
    assert json.loads(data["actions_taken"]) == ["Physical examination", "Urgent review"]
    assert data["clinical_notes"] == "Patient reviewed, follow-up booked."


def test_decision_rejects_invalid_status():
    session = _create_session()
    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"status": "archived"},
        headers=_auth_headers(),
    )
    assert response.status_code == 422


def test_decision_unknown_session_404():
    response = client.patch(
        "/api/v1/triage/999999/decision",
        json={"status": "closed"},
        headers=_auth_headers(),
    )
    assert response.status_code == 404


def test_list_filters_by_status():
    session = _create_session()
    headers = _auth_headers()

    closed = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"status": "closed"},
        headers=headers,
    )
    assert closed.status_code == 200

    closed_list = client.get("/api/v1/triage/list", params={"status": "closed"}, headers=headers)
    assert closed_list.status_code == 200
    assert any(row["id"] == session["id"] for row in closed_list.json())
    assert all(row["status"] == "closed" for row in closed_list.json())

    open_list = client.get("/api/v1/triage/list", params={"status": "open"}, headers=headers)
    assert open_list.status_code == 200
    assert not any(row["id"] == session["id"] for row in open_list.json())
