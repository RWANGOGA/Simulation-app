"""Request correlation, access logging and the health probes.

Three things are being pinned here:

* every response is traceable back to a log line, including the responses built
  by middleware that never reach a route (a 413 from the size limiter);
* the access log identifies *what* was called without recording *who* it was
  called for — patient codes must not end up in logs; and
* liveness and readiness answer different questions, so a dead database makes
  the instance "not ready" without making it "dead".
"""

import io
import json
import logging
import re
import sys

import pytest
from fastapi.testclient import TestClient

from app.core.logging import configure_logging
from app.main import app

client = TestClient(app)

REQUEST_ID = "X-Request-ID"
PATIENT_CODE = "P-770043"

# /api/v1/health is the cheapest route in the app and has no dependencies.
LIVENESS_URL = "/api/v1/health"
READINESS_URL = "/api/v1/health/ready"


@pytest.fixture
def access_log():
    """Captures our own handler's output, so the assertions see exactly what an
    operator's log pipeline would see."""
    stream = io.StringIO()
    configure_logging(level="INFO", format="json", stream=stream)
    try:
        yield stream
    finally:
        configure_logging(level="INFO", format="plain", stream=sys.stdout)


def _lines(stream: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in stream.getvalue().splitlines() if line.strip()]


def _access_lines(stream: io.StringIO) -> list[dict]:
    return [line for line in _lines(stream) if line["logger"] == "app.access"]


def _access_text(stream: io.StringIO) -> str:
    """Only the trail this application writes.

    httpx logs the full URL of every request it makes, and in these tests it is
    the transport the TestClient itself uses — that line is the harness talking,
    not the server. The same leak in production is uvicorn's own access logger,
    which configure_logging() turns off for exactly this reason.
    """
    return "\n".join(json.dumps(line) for line in _access_lines(stream))


class _UnreachableEngine:
    """Stands in for an engine whose database is gone."""

    def connect(self):  # noqa: D401 - mirrors the SQLAlchemy surface
        raise OSError("connection refused")


# --------------------------------------------------------------------------
# Correlation
# --------------------------------------------------------------------------


def test_every_response_carries_a_request_id():
    response = client.get(LIVENESS_URL)
    assert response.status_code == 200

    request_id = response.headers.get(REQUEST_ID)
    assert request_id and re.fullmatch(r"[0-9a-f]{16}", request_id), request_id


def test_two_requests_get_two_different_ids():
    first = client.get(LIVENESS_URL).headers[REQUEST_ID]
    second = client.get(LIVENESS_URL).headers[REQUEST_ID]
    assert first != second


def test_a_caller_supplied_id_is_echoed_back():
    """A gateway or a retrying client can then quote the id it already knows."""
    response = client.get(LIVENESS_URL, headers={REQUEST_ID: "checkout-abc.123"})
    assert response.headers[REQUEST_ID] == "checkout-abc.123"


@pytest.mark.parametrize(
    "hostile",
    [
        "with space",
        "semi;colon",
        "a" * 200,
        "line\r\nbreak",
        "<script>alert(1)</script>",
        "",
    ],
)
def test_a_hostile_request_id_is_replaced(hostile):
    """The value is echoed in a response header and written to logs, so it is
    validated rather than trusted."""
    response = client.get(LIVENESS_URL, headers={REQUEST_ID: hostile})
    request_id = response.headers[REQUEST_ID]

    assert request_id != hostile
    assert re.fullmatch(r"[0-9a-f]{16}", request_id), request_id


def test_the_response_id_matches_the_access_log_line(access_log):
    response = client.get(LIVENESS_URL)
    request_id = response.headers[REQUEST_ID]

    lines = [line for line in _access_lines(access_log) if line["route"] == LIVENESS_URL]
    assert len(lines) == 1, access_log.getvalue()
    assert lines[0]["request_id"] == request_id


# --------------------------------------------------------------------------
# Access log
# --------------------------------------------------------------------------


def test_the_access_log_line_is_structured(access_log):
    client.get(LIVENESS_URL)

    line = _access_lines(access_log)[-1]
    assert line["level"] == "INFO"
    assert line["message"] == "request"
    assert line["method"] == "GET"
    assert line["status"] == 200
    assert isinstance(line["duration_ms"], (int, float))
    # An aggregate-able timestamp, not a localised string.
    assert line["time"].endswith("Z") or "+00:00" in line["time"]


def test_the_status_of_a_failed_request_is_recorded(access_log):
    client.get("/api/v1/patients/does-not-exist")  # 401 or 404, never 500

    line = _access_lines(access_log)[-1]
    assert line["status"] >= 400


def test_a_patient_code_never_reaches_the_access_log(access_log):
    """The whole point of logging the template: the trail says a patient record
    was read, not whose."""
    client.get(f"/api/v1/triage/patient/{PATIENT_CODE}")

    logged = _access_text(access_log)
    assert PATIENT_CODE not in logged
    assert "/api/v1/triage/patient/{patient_code}" in logged


def test_an_unmatched_patient_url_is_redacted_too(access_log):
    """No route matched, so there are no path parameters to work from and the
    raw path is all there is. It still must not leak the code."""
    client.get(f"/api/v1/triage/patient/{PATIENT_CODE}/typo")

    logged = _access_text(access_log)
    assert PATIENT_CODE not in logged
    assert "{code}" in logged


def test_a_413_built_by_middleware_still_carries_a_request_id(access_log):
    """The size limiter runs outside the router. If the correlation middleware
    were registered inside it, this response would come back untraceable."""
    response = client.get(
        LIVENESS_URL, headers={"content-length": str(10 * 1024 * 1024 + 1)}
    )

    assert response.status_code == 413
    assert response.headers.get(REQUEST_ID)


# --------------------------------------------------------------------------
# Liveness and readiness
# --------------------------------------------------------------------------


def test_liveness_works_without_a_database(monkeypatch):
    """Restarting a container is the right response to a failing liveness
    probe; restarting it because the *database* is down is a restart loop."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.health.engine", _UnreachableEngine()
    )

    response = client.get(LIVENESS_URL)
    assert response.status_code == 200
    assert response.json()["status"] == "alive"


def test_liveness_reports_what_is_running():
    body = client.get(LIVENESS_URL).json()
    assert body["service"]
    assert body["version"]
    assert body["environment"]


def test_readiness_is_ready_when_the_database_answers():
    response = client.get(READINESS_URL)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["database"] == "ok"
    # The test database is migrated to head by conftest, so this is a real
    # check of the migration-state reporting, not a stub.
    assert body["schema"]["current"] == body["schema"]["expected"]
    assert body["schema"]["up_to_date"] is True


def test_readiness_is_503_when_the_database_is_unreachable(monkeypatch):
    monkeypatch.setattr(
        "app.api.v1.endpoints.health.engine", _UnreachableEngine()
    )

    response = client.get(READINESS_URL)

    assert response.status_code == 503
    body = response.json()
    assert body["status"] == "not_ready"
    assert body["database"] == "unavailable"


def test_readiness_reports_a_schema_behind_the_code(monkeypatch, access_log):
    """A deployment that never ran `alembic upgrade head` is the failure mode
    main.py works around for two tables. It should be visible, but not fatal —
    503 here would take a working instance out of rotation."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.health._database_state",
        lambda: {"reachable": True, "revision": "0001_initial_schema"},
    )

    response = client.get(READINESS_URL)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["schema"]["current"] == "0001_initial_schema"
    assert body["schema"]["up_to_date"] is False
    assert "schema_behind_code" in access_log.getvalue()


def test_the_expected_head_is_found_from_the_migration_scripts():
    """Guards the head-detection parser: if it silently returned None the
    up_to_date check above would always be trivially satisfied."""
    from app.api.v1.endpoints.health import _expected_head

    _expected_head.cache_clear()
    head = _expected_head()
    assert head is not None
    assert head.startswith("0006"), head


# --------------------------------------------------------------------------
# Logging configuration
# --------------------------------------------------------------------------


def test_configure_logging_is_idempotent():
    """Called once at import and again by every test fixture; a second call
    must not stack handlers and duplicate every line."""
    root = logging.getLogger()
    before = list(root.handlers)
    configure_logging(level="INFO", format="plain")
    configure_logging(level="INFO", format="plain")
    assert list(root.handlers) == before


def test_info_level_records_are_actually_emitted(access_log):
    """The bug this replaces: with no configuration, INFO records were dropped
    by the root logger's last-resort handler."""
    logging.getLogger("app.test").info("visible")
    assert "visible" in access_log.getvalue()
