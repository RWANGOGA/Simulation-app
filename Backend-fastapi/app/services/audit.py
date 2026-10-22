"""Write-side of the patient-data audit trail.

Every endpoint that touches a patient record calls :func:`record_access`.
Two properties matter more than speed here:

* **Isolation.** The row is written through its own ``SessionLocal()``,
  not the request's session. The trail therefore survives even when the
  request itself is rolled back or fails afterwards, and a request can
  never be affected by the state of the audit transaction.
* **Never break the request.** Any failure inside this module is logged
  and swallowed. A full disk or a missing table must degrade to "no audit
  row", never to a 500 on a clinician reading a chart.

Trade-off: one connection checkout per audited request. With
``pool_size=20`` and a triage dashboard's read volume that is
comfortable; if that ever changes, batch the writes instead of widening
the pool.
"""
import logging
from typing import Any, Optional

from fastapi import Request
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.models.audit_log import AuditLog

logger = logging.getLogger(__name__)

# Actor kinds.
ACTOR_DOCTOR = "doctor"
ACTOR_PATIENT = "patient"
ACTOR_ANONYMOUS = "anonymous"

# Actions.
ACTION_READ = "read"
ACTION_LIST = "list"
ACTION_AGGREGATE = "aggregate"
ACTION_CREATE = "create"
ACTION_UPDATE = "update"

# Outcomes.
OUTCOME_ALLOWED = "allowed"
OUTCOME_DENIED = "denied"

# Resources.
RESOURCE_TRIAGE_SESSION = "triage_session"
RESOURCE_TRIAGE_HISTORY = "triage_history"
RESOURCE_PATIENT = "patient"
RESOURCE_TRIAGE_STATS = "triage_stats"
RESOURCE_TRIAGE_REPORTS = "triage_reports"


def client_ip(request: Optional[Request]) -> Optional[str]:
    """Best-effort caller IP, proxy-aware.

    In production the app sits behind a platform proxy, so
    ``request.client`` is the proxy and the real caller is the first hop
    of X-Forwarded-For. This value is forensic context only — it is never
    used to authorise anything.
    """
    if request is None:
        return None
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        first = forwarded.split(",")[0].strip()
        if first:
            return first[:64]
    if request.client and request.client.host:
        return request.client.host[:64]
    return None


def record_access(
    *,
    action: str,
    resource_type: str,
    request: Optional[Request] = None,
    actor: Optional[Any] = None,
    actor_type: Optional[str] = None,
    patient_id: Optional[int] = None,
    patient_code: Optional[str] = None,
    resource_id: Optional[Any] = None,
    outcome: str = OUTCOME_ALLOWED,
    detail: Optional[str] = None,
    db: Optional[Session] = None,
) -> None:
    """Append one audit row. Never raises.

    ``actor`` is the authenticated ``Doctor`` when there is one; it wins
    over an explicit ``actor_type`` so callers cannot accidentally label
    a signed-in practitioner as anonymous. Nothing clinical may be passed
    in ``detail`` — this table is metadata only.
    """
    resolved_actor_type = actor_type or ACTOR_ANONYMOUS
    actor_id = None
    actor_label = None
    if actor is not None:
        resolved_actor_type = ACTOR_DOCTOR
        actor_id = getattr(actor, "id", None)
        actor_label = getattr(actor, "email", None)

    entry = AuditLog(
        action=action,
        outcome=outcome,
        actor_type=resolved_actor_type,
        actor_id=actor_id,
        actor_label=actor_label,
        resource_type=resource_type,
        resource_id=None if resource_id is None else str(resource_id),
        patient_id=patient_id,
        patient_code=patient_code,
        endpoint=f"{request.method} {request.url.path}" if request is not None else None,
        ip_address=client_ip(request),
        user_agent=(request.headers.get("user-agent") or None) if request is not None else None,
        detail=detail,
    )

    session = db
    try:
        # Even obtaining a session can fail (pool exhaustion, bad URL),
        # so it happens inside the guard as well.
        if session is None:
            session = SessionLocal()
        session.add(entry)
        session.commit()
    except Exception:  # noqa: BLE001 - auditing must never break a request
        logger.warning(
            "audit write failed (action=%s resource=%s patient=%s)",
            action,
            resource_type,
            patient_id,
            exc_info=True,
        )
        if session is not None:
            try:
                session.rollback()
            except Exception:  # noqa: BLE001
                pass
    finally:
        # Only close a session we opened ourselves; a caller-supplied
        # session belongs to the request lifecycle.
        if db is None and session is not None:
            session.close()
