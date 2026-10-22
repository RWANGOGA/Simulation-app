"""The patient-data audit trail.

Every read of a patient record has to leave a server-side trace that an
auditor can query later: who, what, which patient, and whether it was
allowed. These tests pin the three access modes the app actually uses —
an anonymous lookup, a signed-in practitioner, and a practitioner write —
plus two properties that are easy to regress:

* a blocked attempt is still recorded (denied), and
* a failure to write the audit row must never fail the request.
"""

import uuid

from fastapi.testclient import TestClient

from app.core.database import SessionLocal
from app.main import app
from app.models.audit_log import AuditLog
from app.models.patient import Patient
from app.services import audit
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)


def _doctor_headers() -> dict:
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _new_patient() -> dict:
    response = client.post(
        "/api/v1/patients/",
        json={"age": 33, "gender": "Female", "weight": 60.0, "height": 165.0,
              "full_name": "Brenda Atim"},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _submit(patient_id: int) -> dict:
    db = SessionLocal()
    patient = db.get(Patient, patient_id)
    db.close()
    assert patient is not None
    response = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient_id,
            "body_region": "Abdomen",
            "pain_type": "cramping",
            "severity": 4,
            "visit_id": uuid.uuid4().hex,
        },
        headers={"X-Patient-Code": patient.anonymous_code},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _rows() -> list:
    db = SessionLocal()
    try:
        return db.query(AuditLog).order_by(AuditLog.id.asc()).all()
    finally:
        db.close()


def _clear_audit() -> None:
    """Drop the rows created by the setup calls so an assertion only sees
    what the action under test wrote."""
    db = SessionLocal()
    try:
        db.query(AuditLog).delete()
        db.commit()
    finally:
        db.close()


def test_patient_intake_is_recorded_as_an_anonymous_create():
    patient = _new_patient()

    rows = _rows()
    assert len(rows) == 1
    entry = rows[0]
    assert entry.action == audit.ACTION_CREATE
    assert entry.resource_type == audit.RESOURCE_PATIENT
    assert entry.actor_type == audit.ACTOR_ANONYMOUS
    assert entry.outcome == audit.OUTCOME_ALLOWED
    assert entry.patient_id == patient["id"]
    assert entry.patient_code == patient["anonymous_code"]
    assert entry.created_at is not None


def test_triage_submission_is_recorded_against_the_patient():
    patient = _new_patient()
    _clear_audit()

    session = _submit(patient["id"])

    rows = _rows()
    assert len(rows) == 1
    entry = rows[0]
    assert entry.action == audit.ACTION_CREATE
    assert entry.resource_type == audit.RESOURCE_TRIAGE_SESSION
    # The caller proved possession of the anonymous code.
    assert entry.actor_type == audit.ACTOR_PATIENT
    assert entry.patient_id == patient["id"]
    assert entry.resource_id == str(session["id"])


def test_anonymous_lookup_records_the_read_without_an_identity():
    patient = _new_patient()
    _submit(patient["id"])
    _clear_audit()

    assert client.get(f"/api/v1/triage/patient/{patient['anonymous_code']}").status_code == 200

    rows = _rows()
    assert len(rows) == 1
    entry = rows[0]
    assert entry.action == audit.ACTION_READ
    assert entry.actor_type == audit.ACTOR_PATIENT
    assert entry.patient_id == patient["id"]
    assert entry.patient_code == patient["anonymous_code"]
    # No signed-in user, so no actor identity to attach.
    assert entry.actor_id is None
    assert entry.ip_address is not None


def test_unknown_code_lookup_is_recorded_as_denied():
    """Code enumeration must leave a trail even though nothing was served."""
    _clear_audit()

    assert client.get("/api/v1/triage/patient/P-NOTAREALCODE").status_code == 404

    rows = _rows()
    assert len(rows) == 1
    entry = rows[0]
    assert entry.outcome == audit.OUTCOME_DENIED
    assert entry.patient_code == "P-NOTAREALCODE"
    assert entry.patient_id is None


def test_practitioner_read_attaches_the_doctor_identity():
    patient = _new_patient()
    _submit(patient["id"])
    _clear_audit()

    response = client.get(
        f"/api/v1/triage/patient/{patient['anonymous_code']}/history",
        headers=_doctor_headers(),
    )
    assert response.status_code == 200

    rows = _rows()
    assert len(rows) == 1
    entry = rows[0]
    assert entry.action == audit.ACTION_READ
    assert entry.resource_type == audit.RESOURCE_TRIAGE_HISTORY
    assert entry.actor_type == audit.ACTOR_DOCTOR
    assert entry.actor_id is not None
    # Snapshot, not a join: the label survives account deletion.
    assert entry.actor_label and "@" in entry.actor_label
    assert entry.patient_id == patient["id"]


def test_decision_update_is_recorded_without_copying_clinical_text():
    patient = _new_patient()
    session = _submit(patient["id"])
    _clear_audit()

    response = client.patch(
        f"/api/v1/triage/{session['id']}/decision",
        json={"status": "closed", "clinical_notes": "Referred to surgical OPD."},
        headers=_doctor_headers(),
    )
    assert response.status_code == 200

    rows = _rows()
    assert len(rows) == 1
    entry = rows[0]
    assert entry.action == audit.ACTION_UPDATE
    assert entry.actor_type == audit.ACTOR_DOCTOR
    assert entry.resource_id == str(session["id"])
    # The field names are recorded, the free-text note is not: this table
    # is metadata only, so PHI keeps living in exactly one place.
    assert "clinical_notes" in entry.detail
    assert "Referred to surgical OPD." not in entry.detail


def test_stats_and_reports_reads_are_recorded_as_aggregates():
    patient = _new_patient()
    _submit(patient["id"])
    _clear_audit()
    headers = _doctor_headers()

    assert client.get("/api/v1/triage/stats", headers=headers).status_code == 200
    assert client.get("/api/v1/triage/reports", headers=headers).status_code == 200

    rows = _rows()
    assert [entry.action for entry in rows] == [audit.ACTION_AGGREGATE, audit.ACTION_AGGREGATE]
    assert [entry.resource_type for entry in rows] == [
        audit.RESOURCE_TRIAGE_STATS,
        audit.RESOURCE_TRIAGE_REPORTS,
    ]


def test_audit_failure_never_breaks_the_request(monkeypatch):
    """A broken audit sink must degrade to 'no trail', not to a 500 on a
    clinician reading a chart."""

    def _boom(*args, **kwargs):
        raise RuntimeError("audit store unavailable")

    monkeypatch.setattr(audit, "SessionLocal", _boom)

    patient = _new_patient()
    session = _submit(patient["id"])
    response = client.get(f"/api/v1/triage/{session['id']}", headers=_doctor_headers())

    assert response.status_code == 200
    assert response.json()["body_region"] == "Abdomen"
    assert _rows() == []
