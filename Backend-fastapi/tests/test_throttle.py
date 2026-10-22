"""Database-backed rate limiting.

Both limits used to live in module-level dicts. That made them per-process
(two uvicorn workers = double the limit), reset on every deploy, and
invisible to an investigator afterwards. These tests pin the properties that
actually follow from moving the state into `request_throttle`:

* the counter is rows in a table, so every worker and every restart agrees;
* a refused attempt does not extend the client's own lockout;
* a successful login forgives the failures that came before it;
* different limits on the same caller do not interfere; and
* a broken table degrades to "no limit", never to a 500.
"""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.database import SessionLocal
from app.main import app
from app.models.patient import Patient
from app.models.request_throttle import RequestThrottle
from app.services import throttle
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)


def _rows_for(bucket: str) -> int:
    """Counts live rows straight from the table, in a fresh session."""
    db = SessionLocal()
    try:
        return (
            db.query(RequestThrottle)
            .filter(RequestThrottle.bucket == bucket)
            .count()
        )
    finally:
        db.close()


def _fail_login(email: str) -> int:
    return client.post(
        "/api/v1/auth/login",
        data={"username": email, "password": "WrongPassword1"},
    ).status_code


def _new_patient() -> dict:
    return client.post(
        "/api/v1/patients/",
        json={"age": 40, "gender": "Male", "weight": 80.0, "height": 180.0},
    ).json()


# --------------------------------------------------------------------------
# Login lockout
# --------------------------------------------------------------------------

def test_login_lockout_is_stored_in_the_database_not_in_memory():
    email = "lockout-state@simtack.com"

    for _ in range(settings.MAX_LOGIN_ATTEMPTS):
        assert _fail_login(email) == 401

    # The count is durable state, which is the whole point: a restarted
    # process and a sibling worker read the same number.
    assert _rows_for(f"login:{email}") == settings.MAX_LOGIN_ATTEMPTS

    # And it is enforced from that state on the next call.
    assert _fail_login(email) == 429


def test_refused_attempts_do_not_extend_the_lockout():
    """A blocked client is not allowed to push its own window forward.

    Record-then-count would make every retry add a row, so an attacker who
    kept hammering would stay locked out forever — and so would a patient
    who hammered the submit button.
    """
    email = "lockout-no-progress@simtack.com"

    for _ in range(settings.MAX_LOGIN_ATTEMPTS):
        assert _fail_login(email) == 401
    bucket = f"login:{email}"
    rows_before = _rows_for(bucket)

    for _ in range(4):
        assert _fail_login(email) == 429

    assert _rows_for(bucket) == rows_before


def test_lockout_response_tells_the_client_when_to_retry():
    email = "lockout-retry-after@simtack.com"

    for _ in range(settings.MAX_LOGIN_ATTEMPTS):
        _fail_login(email)

    blocked = client.post(
        "/api/v1/auth/login",
        data={"username": email, "password": "WrongPassword1"},
    )
    assert blocked.status_code == 429
    assert blocked.headers["Retry-After"] == str(settings.LOGIN_LOCKOUT_SECONDS)


def test_successful_login_forgives_earlier_failures():
    # Failures against the *real* seeded account, so the success below is a
    # genuine login for the bucket that was just filling up.
    email = DOCTOR_LOGIN["username"]
    bucket = f"login:{email}"

    for _ in range(settings.MAX_LOGIN_ATTEMPTS - 1):
        assert _fail_login(email) == 401
    assert _rows_for(bucket) == settings.MAX_LOGIN_ATTEMPTS - 1

    # One attempt of budget left: the correct password must still get through.
    assert client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).status_code == 200

    # ...and it wipes the slate, so the next typo is not attempt number N.
    assert _rows_for(bucket) == 0


# --------------------------------------------------------------------------
# Public intake limits
# --------------------------------------------------------------------------

def test_patient_intake_limit_is_enforced_from_table_state():
    for _ in range(throttle.PATIENT_RATE_LIMIT):
        assert client.post(
            "/api/v1/patients/",
            json={"age": 30, "gender": "Female"},
        ).status_code == 201

    blocked = client.post("/api/v1/patients/", json={"age": 30, "gender": "Female"})
    assert blocked.status_code == 429
    assert blocked.headers["Retry-After"] == str(throttle.PATIENT_RATE_WINDOW_SECONDS)

    # The budget that was spent is six rows in the table, not a counter in
    # the worker's memory: five accepted (the refusal is not recorded).
    assert _rows_for("patient:testclient") == throttle.PATIENT_RATE_LIMIT


def test_triage_intake_limit_is_enforced():
    patient = _new_patient()
    db = SessionLocal()
    try:
        code = db.get(Patient, patient["id"]).anonymous_code
    finally:
        db.close()

    for _ in range(throttle.TRIAGE_RATE_LIMIT):
        response = client.post(
            "/api/v1/triage/",
            json={
                "patient_id": patient["id"],
                "body_region": "Head",
                "pain_type": "throbbing",
                "severity": 4,
                "visit_id": uuid.uuid4().hex,
            },
            headers={"X-Patient-Code": code},
        )
        assert response.status_code == 201

    blocked = client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Head",
            "pain_type": "throbbing",
            "severity": 4,
            "visit_id": uuid.uuid4().hex,
        },
        headers={"X-Patient-Code": code},
    )
    assert blocked.status_code == 429


def test_the_two_intake_limits_do_not_share_a_bucket():
    """Burning the patient-creation budget must not block triage intake.

    They used to be two dicts, so this was true by construction; now they
    are rows, and only the bucket prefix keeps them apart.
    """
    patient = _new_patient()
    db = SessionLocal()
    try:
        code = db.get(Patient, patient["id"]).anonymous_code
    finally:
        db.close()

    # _new_patient() already spent one of the five slots.
    for _ in range(throttle.PATIENT_RATE_LIMIT - 1):
        client.post("/api/v1/patients/", json={"age": 30, "gender": "Female"})

    assert client.post("/api/v1/patients/", json={"age": 30, "gender": "Female"}).status_code == 429
    # Same IP, different limit — still allowed.
    assert client.post(
        "/api/v1/triage/",
        json={
            "patient_id": patient["id"],
            "body_region": "Chest",
            "pain_type": "sharp",
            "severity": 6,
            "visit_id": uuid.uuid4().hex,
        },
        headers={"X-Patient-Code": code},
    ).status_code == 201


# --------------------------------------------------------------------------
# Window accounting
# --------------------------------------------------------------------------

def test_rows_older_than_the_window_stop_counting():
    db = SessionLocal()
    try:
        bucket = f"triage:window-{uuid.uuid4().hex}"
        stale = datetime.now(timezone.utc) - timedelta(
            seconds=throttle.TRIAGE_RATE_WINDOW_SECONDS + 60
        )
        for _ in range(throttle.TRIAGE_RATE_LIMIT):
            db.add(RequestThrottle(bucket=bucket, created_at=stale))
        db.commit()

        # Full according to the raw row count, empty once expired rows go.
        assert throttle.allow(
            db, bucket, throttle.TRIAGE_RATE_LIMIT, throttle.TRIAGE_RATE_WINDOW_SECONDS
        ) is True
        # The stale rows were pruned, so the bucket holds only this request
        # instead of quietly starting the client halfway to the limit.
        assert throttle.count(db, bucket, throttle.TRIAGE_RATE_WINDOW_SECONDS) == 1
    finally:
        db.close()


def test_allow_refuses_once_the_window_is_full():
    db = SessionLocal()
    try:
        bucket = f"triage:full-{uuid.uuid4().hex}"
        assert throttle.allow(db, bucket, 2, 300) is True
        assert throttle.allow(db, bucket, 2, 300) is True
        assert throttle.allow(db, bucket, 2, 300) is False
        assert throttle.count(db, bucket, 300) == 2
    finally:
        db.close()


def test_a_broken_throttle_table_never_breaks_the_request(monkeypatch):
    """Fail open, loudly.

    A deployment that has not run the migration, or a pool that is out of
    connections, must not turn into an outage on a health app: a patient
    still has to be able to submit, and a clinician still has to be able to
    log in. The limits being off is the lesser failure.
    """
    def missing_table(*args, **kwargs):
        raise RuntimeError('relation "request_throttle" does not exist')

    # Every helper starts by touching the table, so a failing _prune stands in
    # for the table being absent.
    monkeypatch.setattr(throttle, "_prune", missing_table)
    db = SessionLocal()
    try:
        assert throttle.allow(db, "triage:fail-open", 1, 300) is True
        assert throttle.count(db, "triage:fail-open", 300) == 0
    finally:
        db.close()

    class BrokenSession:
        """What the ORM call site sees when the table or pool is unusable."""

        def add(self, *_args, **_kwargs):
            raise RuntimeError("no such table")

        def query(self, *_args, **_kwargs):
            raise RuntimeError("no such table")

        def commit(self):
            raise RuntimeError("no such table")

        def rollback(self):
            raise RuntimeError("rollback is broken too")

    # Neither may raise out into the endpoint.
    throttle.record(BrokenSession(), "triage:fail-open")
    throttle.clear(BrokenSession(), "triage:fail-open")
