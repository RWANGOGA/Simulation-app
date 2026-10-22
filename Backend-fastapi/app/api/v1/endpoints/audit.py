"""Read side of the patient-data audit trail.

Recording access (``app/services/audit.py``) is only half of a compliance
control. Auditors, and a patient exercising a right-of-access request, also
need to be able to ask "who looked at this record, and when?" — this module
is that window.

Two rules shape it:

* **The trail is itself sensitive.** It reveals which clinician is treating
  which patient, so every read here is JWT-guarded and is *itself* recorded
  in the trail (``record_access`` on an audit read appends one row; it does
  not recurse, because writing a row never triggers another read).
* **Metadata only.** Nothing here returns clinical content, because the
  table it reads never stores any.
"""
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from app.api.v1.endpoints.auth import get_current_doctor
from app.core.config import settings
from app.core.database import get_db
from app.models import AuditLog, Doctor
from app.services import audit

router = APIRouter(prefix="/audit", tags=["audit"])


def _serialize(entry: AuditLog) -> dict:
    return {
        "id": entry.id,
        "created_at": entry.created_at.isoformat() if entry.created_at else None,
        "action": entry.action,
        "outcome": entry.outcome,
        "actor_type": entry.actor_type,
        "actor_id": entry.actor_id,
        "actor_label": entry.actor_label,
        "resource_type": entry.resource_type,
        "resource_id": entry.resource_id,
        "patient_id": entry.patient_id,
        "patient_code": entry.patient_code,
        "endpoint": entry.endpoint,
        "ip_address": entry.ip_address,
        "user_agent": entry.user_agent,
        "detail": entry.detail,
    }


def _aware(value: Optional[datetime]) -> Optional[datetime]:
    """Treat a naive bound as UTC.

    ``created_at`` is timezone-aware, so comparing it against a naive bound
    would raise on Postgres. A client sending only a date is the common
    case and it should not be a 500.
    """
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _configured_readers() -> set:
    return {e.strip().lower() for e in settings.AUDIT_READER_EMAILS.split(",") if e.strip()}


def get_audit_reader(current_doctor: Doctor = Depends(get_current_doctor)) -> Doctor:
    """Gate the trail behind a named auditor list, when one is configured.

    Leaving ``AUDIT_READER_EMAILS`` empty keeps the trail readable by any
    signed-in practitioner — the right default for a small clinic where the
    only users are the clinicians who generated the trail. Set it in a
    larger deployment so one clinician cannot browse a colleague's access
    history (which would leak who is treating whom).
    """
    allowed = _configured_readers()
    if allowed and (current_doctor.email or "").lower() not in allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is not allowed to read the audit trail",
        )
    return current_doctor


def _record_read(
    *,
    request: Request,
    reader: Doctor,
    detail: str,
    patient_id: Optional[int] = None,
    patient_code: Optional[str] = None,
) -> None:
    audit.record_access(
        action=audit.ACTION_READ,
        resource_type=audit.RESOURCE_AUDIT_LOG,
        request=request,
        actor=reader,
        patient_id=patient_id,
        patient_code=patient_code,
        detail=detail,
    )


@router.get("/logs")
def list_audit_logs(
    request: Request,
    page: int = Query(default=1, ge=1, description="Page number"),
    limit: int = Query(default=50, ge=1, le=200, description="Items per page"),
    patient_code: Optional[str] = Query(default=None, description="Exact anonymous code"),
    patient_id: Optional[int] = Query(default=None),
    actor_id: Optional[int] = Query(default=None, description="Practitioner who acted"),
    action: Optional[str] = Query(
        default=None, pattern="^(read|list|aggregate|create|update|delete)$"
    ),
    outcome: Optional[str] = Query(default=None, pattern="^(allowed|denied)$"),
    resource_type: Optional[str] = Query(default=None),
    since: Optional[datetime] = Query(default=None, description="ISO-8601, inclusive lower bound"),
    until: Optional[datetime] = Query(default=None, description="ISO-8601, inclusive upper bound"),
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_audit_reader),
):
    """Search the trail. Newest first, paginated, every filter optional."""
    query = db.query(AuditLog)

    if patient_code:
        query = query.filter(AuditLog.patient_code == patient_code)
    if patient_id is not None:
        query = query.filter(AuditLog.patient_id == patient_id)
    if actor_id is not None:
        query = query.filter(AuditLog.actor_id == actor_id)
    if action:
        query = query.filter(AuditLog.action == action)
    if outcome:
        query = query.filter(AuditLog.outcome == outcome)
    if resource_type:
        query = query.filter(AuditLog.resource_type == resource_type)
    if since is not None:
        query = query.filter(AuditLog.created_at >= _aware(since))
    if until is not None:
        query = query.filter(AuditLog.created_at <= _aware(until))

    total_records = query.count()
    total_pages = (total_records + limit - 1) // limit if total_records > 0 else 0

    entries = (
        query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    _record_read(
        request=request,
        reader=current_doctor,
        patient_id=patient_id,
        patient_code=patient_code,
        detail=f"audit trail searched, page {page} ({total_records} match(es))",
    )

    return {
        "items": [_serialize(entry) for entry in entries],
        "pagination": {
            "total": total_records,
            "page": page,
            "limit": limit,
            "total_pages": total_pages,
        },
    }


@router.get("/patients/{patient_code}")
def get_patient_audit_trail(
    patient_code: str,
    request: Request,
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_audit_reader),
):
    """Every recorded access to one patient's data, newest first.

    This is the shape a right-of-access request (GDPR Art. 15) or an
    internal review needs: each time the record was touched, by whom, and
    whether it was allowed. Denied attempts are included on purpose — an
    enumeration probe against a patient code shows up here.
    """
    entries = (
        db.query(AuditLog)
        .filter(AuditLog.patient_code == patient_code)
        .order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .limit(limit)
        .all()
    )

    _record_read(
        request=request,
        reader=current_doctor,
        patient_code=patient_code,
        detail=f"per-patient audit trail read ({len(entries)} entrie(s))",
    )

    return {
        "patient_code": patient_code,
        "count": len(entries),
        "items": [_serialize(entry) for entry in entries],
    }
