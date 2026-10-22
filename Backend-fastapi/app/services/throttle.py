"""Database-backed request throttling.

Replaces the process-local dicts that used to guard the public intake routes
and the login lockout. Those reset on every deploy and were per-process, so
in production with more than one worker the real limit was multiplied by the
worker count and a restart handed an attacker a clean slate.

**One rule for callers:** run these *before* you write anything else in the
request, which is where a rate-limit check belongs anyway. The helpers commit,
so anything half-built in the session would be flushed along with the throttle
row.

**Fail-open.** Any database failure degrades to "no limit" and a warning in
the log, never to a 500. A patient with a broken `request_throttle` table — a
missing migration on a fresh deployment, an exhausted pool — must still be
able to submit a pain point, and clinicians must still be able to log in. The
resulting exposure (limits off, loudly) is strictly better than an outage. The
table is created at startup for exactly this reason; see `app/main.py`.
"""
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.request_throttle import RequestThrottle

logger = logging.getLogger(__name__)

# Public intake limits (unchanged values, now shared across workers).
TRIAGE_RATE_LIMIT = 10
TRIAGE_RATE_WINDOW_SECONDS = 300
PATIENT_RATE_LIMIT = 5
PATIENT_RATE_WINDOW_SECONDS = 300
# The anatomy assistant is reachable without a token — patients have no
# account — and every uncached call spends real money at the LLM provider.
# Generous for someone tapping around a body map, nowhere near what a script
# needs to run up a bill.
ANATOMY_RATE_LIMIT = 30
ANATOMY_RATE_WINDOW_SECONDS = 300


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _prune(session: Session, bucket: str, window_seconds: int) -> None:
    cutoff = _now() - timedelta(seconds=window_seconds)
    session.query(RequestThrottle).filter(
        RequestThrottle.bucket == bucket,
        RequestThrottle.created_at < cutoff,
    ).delete(synchronize_session=False)


def _spent(session: Session, bucket: str) -> int:
    return (
        session.query(RequestThrottle)
        .filter(RequestThrottle.bucket == bucket)
        .count()
    )


def _recover(session: Session, bucket: str, operation: str) -> None:
    """Logs the failure and drops whatever the session was mid-way through."""
    logger.warning(
        "throttle %s failed for bucket %s — failing open", operation, bucket,
        exc_info=True,
    )
    try:
        session.rollback()
    except Exception:  # noqa: BLE001
        pass


def bucket_for(request, kind: str) -> str:
    """Namespaced caller identity for an inbound HTTP request.

    The prefix is what keeps unrelated limits apart: burning the patient
    intake budget must not block the same IP from submitting a triage.
    """
    host = request.client.host if request is not None and request.client else "unknown"
    return f"{kind}:{host}"


def count(session: Session, bucket: str, window_seconds: int) -> int:
    """Events currently inside the window. Prunes as a side effect, no commit."""
    try:
        _prune(session, bucket, window_seconds)
        return _spent(session, bucket)
    except Exception:  # noqa: BLE001 - throttling must never break a request
        _recover(session, bucket, "count")
        return 0


def record(session: Session, bucket: str) -> None:
    """Marks one event and commits."""
    try:
        session.add(RequestThrottle(bucket=bucket, created_at=_now()))
        session.commit()
    except Exception:  # noqa: BLE001
        _recover(session, bucket, "record")


def allow(session: Session, bucket: str, limit: int, window_seconds: int) -> bool:
    """True when this event fits inside the window, recording it if it does.

    A refused event is deliberately **not** recorded. Otherwise a client that
    keeps retrying after being blocked would push its own window forward on
    every attempt, turning a 5-minute throttle into an indefinite lockout —
    and a patient tapping "submit" twice is not the threat model here.
    """
    try:
        _prune(session, bucket, window_seconds)
        if _spent(session, bucket) >= limit:
            return False
        session.add(RequestThrottle(bucket=bucket, created_at=_now()))
        session.commit()
        return True
    except Exception:  # noqa: BLE001
        _recover(session, bucket, "allow")
        return True


def clear(session: Session, bucket: str) -> None:
    """Forgets a bucket, e.g. after a successful login."""
    try:
        session.query(RequestThrottle).filter(
            RequestThrottle.bucket == bucket
        ).delete(synchronize_session=False)
        session.commit()
    except Exception:  # noqa: BLE001
        _recover(session, bucket, "clear")
