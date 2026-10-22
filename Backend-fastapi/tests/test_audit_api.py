"""The read side of the audit trail.

Writing the trail is only useful if it can be reviewed, so these tests
cover the query surface: filters an investigator actually uses, pagination,
the per-patient view a right-of-access request needs, and the fact that
reading the trail is itself an audited act.

They also pin the gate: the trail reveals who is treating whom, so it is
JWT-only and can be narrowed to a named auditor list.
"""

import uuid

from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.database import SessionLocal
from app.main import app
from app.models.audit_log import AuditLog
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)

AUDIT_URL = "/api/v1/audit/logs"


def _doctor_headers() -> dict:
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _new_patient(name: str = "Brenda Atim") -> dict:
    response = client.post(
        "/api/v1/patients/",
        json={"age": 33, "gender": "Female", "weight": 60.0, "height": 165.0,
              "full_name": name, "phone": "+256700111222"},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _submit(patient: dict) -> dict:
    response = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Abdomen",
            "pain_type": "cramping",
            "severity": 4,
            "visit_id": uuid.uuid4().hex,
        },
        headers={"X-Patient-Code": patient["anonymous_code"]},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _clear_audit() -> None:
    db = SessionLocal()
    try:
        db.query(AuditLog).delete()
        db.commit()
    finally:
        db.close()


def test_audit_trail_requires_jwt():
    assert client.get(AUDIT_URL).status_code == 401


def test_audit_trail_lists_the_access_that_just_happened():
    patient = _new_patient()
    _submit(patient)
    _clear_audit()
    assert client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}").status_code == 200

    first = client.get(AUDIT_URL, headers=_doctor_headers()).json()
    # Exactly the lookup so far. The row for *this* read is written after
    # the query, so reading the trail cannot report itself — the trail
    # stays append-only and a reader never sees a partial version of their
    # own access.
    assert first["pagination"]["total"] == 1
    entry = first["items"][0]
    assert entry["action"] == "read"
    assert entry["resource_type"] == "triage_session"
    assert entry["patient_code"] == patient["anonymous_code"]
    assert entry["ip_address"]

    second = client.get(AUDIT_URL, headers=_doctor_headers()).json()
    assert second["pagination"]["total"] == 2
    assert second["items"][0]["resource_type"] == "audit_log"
    assert second["items"][0]["actor_type"] == "doctor"


def test_audit_trail_filters_by_patient_code():
    first = _new_patient("First Patient")
    second = _new_patient("Second Patient")
    _submit(first)
    _submit(second)
    client.get(f"/api/v1/triage/patient/{first['anonymous_code']}")

    response = client.get(
        AUDIT_URL,
        params={"patient_code": first["anonymous_code"]},
        headers=_doctor_headers(),
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert items
    assert {item["patient_code"] for item in items} == {first["anonymous_code"]}


def test_audit_trail_can_isolate_denied_attempts():
    """Enumeration probes are the reason the denied rows exist."""
    _clear_audit()
    client.get("/api/v1/triage/patient/P-GUESSONE")
    client.get("/api/v1/triage/patient/P-GUESSTWO")

    response = client.get(
        AUDIT_URL,
        params={"outcome": "denied", "resource_type": "triage_session"},
        headers=_doctor_headers(),
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert len(items) == 2
    assert {item["patient_code"] for item in items} == {"P-GUESSONE", "P-GUESSTWO"}
    assert all(item["outcome"] == "denied" for item in items)


def test_audit_trail_paginates():
    patient = _new_patient()
    _submit(patient)
    _clear_audit()
    for _ in range(3):
        client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}")

    # Scoping to triage_session keeps the reviewed set stable across the two
    # requests. Auditing an audit read appends to the same table, so an
    # unscoped page-2 request would legitimately see a shifted window.
    params = {"resource_type": "triage_session", "limit": 2}
    first_page = client.get(
        AUDIT_URL, params={**params, "page": 1}, headers=_doctor_headers()
    ).json()
    second_page = client.get(
        AUDIT_URL, params={**params, "page": 2}, headers=_doctor_headers()
    ).json()

    assert first_page["pagination"]["total"] == 3
    assert first_page["pagination"]["total_pages"] == 2
    assert len(first_page["items"]) == 2
    assert len(second_page["items"]) == 1

    first_ids = {item["id"] for item in first_page["items"]}
    second_ids = {item["id"] for item in second_page["items"]}
    assert first_ids.isdisjoint(second_ids)
    # Newest first, continued across the page boundary.
    assert min(first_ids) > max(second_ids)


def test_reading_the_trail_is_itself_recorded():
    patient = _new_patient()
    _submit(patient)
    _clear_audit()

    client.get(
        AUDIT_URL,
        params={"patient_code": patient["anonymous_code"]},
        headers=_doctor_headers(),
    )

    db = SessionLocal()
    try:
        rows = (
            db.query(AuditLog)
            .filter(AuditLog.resource_type == "audit_log")
            .all()
        )
    finally:
        db.close()
    assert len(rows) == 1
    assert rows[0].action == "read"
    assert rows[0].actor_type == "doctor"
    # The query being reviewed is captured, so a review cannot be silent.
    assert patient["anonymous_code"] in (rows[0].detail + str(rows[0].patient_code))


def test_per_patient_trail_shows_the_full_access_history():
    patient = _new_patient()
    _submit(patient)
    client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}")

    response = client.get(
        f"/api/v1/audit/patients/{patient['anonymous_code']}",
        headers=_doctor_headers(),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["patient_code"] == patient["anonymous_code"]
    assert body["count"] == len(body["items"])
    # Intake created the record, the submission created a session, the
    # lookup read it — all three carry the same patient code.
    actions = [item["action"] for item in body["items"]]
    assert "create" in actions
    assert "read" in actions


def test_per_patient_trail_requires_jwt():
    assert client.get("/api/v1/audit/patients/P-ANY").status_code == 401


def test_auditor_allowlist_keeps_other_practitioners_out(monkeypatch):
    monkeypatch.setattr(settings, "AUDIT_READER_EMAILS", "auditor@elsewhere.example")

    response = client.get(AUDIT_URL, headers=_doctor_headers())
    assert response.status_code == 403


def test_auditor_allowlist_admits_the_named_reader(monkeypatch):
    from tests.conftest import DOCTOR_EMAIL

    monkeypatch.setattr(settings, "AUDIT_READER_EMAILS", f"someone@x.example, {DOCTOR_EMAIL}")

    assert client.get(AUDIT_URL, headers=_doctor_headers()).status_code == 200


def test_trail_never_contains_clinical_free_text():
    """Detail is metadata only — a note typed by a clinician must not be
    copied into the audit table, and therefore must not come back out."""
    patient = _new_patient()
    session = _submit(patient)
    client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"status": "closed", "clinical_notes": "Suspected appendicitis."},
        headers=_doctor_headers(),
    )

    body = client.get(
        AUDIT_URL, params={"patient_code": patient["anonymous_code"]}, headers=_doctor_headers()
    ).text
    assert "Suspected appendicitis." not in body
    assert "Brenda Atim" not in body
    assert "+256700111222" not in body
