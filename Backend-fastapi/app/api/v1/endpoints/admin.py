"""Administrator console API.

The practitioner routes answer "what is in front of me". This module answers
"what is happening in the system": who is registered, who is waiting for
approval, what the audit trail has recorded, and how triage volume is spread
across risk bands, tiers and regions.

Everything here is read-only except account updates, and every route is guarded
by ``require_admin`` — the role is the single source of truth (see
``auth.require_admin``). Reads that are derived from patient records are
themselves recorded in the audit trail, the same as any other aggregate read.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.api.v1.endpoints.auth import require_admin, update_doctor_account
from app.core.config import settings
from app.core.database import get_db
from app.models import AuditLog, Doctor, Patient, TriageSession
from app.models.doctor import ACCESS_ADMIN, ACCESS_PRACTITIONER
from app.schemas.admin import (
    AdminActivityEntry,
    AdminActivityList,
    AdminActivitySummary,
    AdminOverview,
    AdminPagination,
    AdminPatientCounts,
    AdminSessionItem,
    AdminSessionList,
    AdminTriageOverview,
    AdminUserCounts,
    AdminUserList,
    AdminUserResponse,
)
from app.schemas.doctor import DoctorAdminUpdate
from app.services import audit
from app.services.triage_service import escalation_for, triage_tier

router = APIRouter(prefix="/admin", tags=["admin"])

# Resource label for account-administration reads. The audit table is
# deliberately free-form; adding a constant here keeps the string in one place.
RESOURCE_DOCTOR = "doctor"

_RISK_LEVELS = ("high", "medium", "low")


def _iso(value: Optional[datetime]) -> Optional[str]:
    return value.isoformat() if value is not None else None


def _pagination(total: int, page: int, limit: int) -> AdminPagination:
    return AdminPagination(
        total=total,
        page=page,
        limit=limit,
        total_pages=(total + limit - 1) // limit if total > 0 else 0,
    )


def _risk_level(score: Optional[float]) -> str:
    if score is None:
        return "unknown"
    if score >= 0.7:
        return "high"
    if score >= 0.4:
        return "medium"
    return "low"


def _serialize_audit(entry: AuditLog) -> AdminActivityEntry:
    return AdminActivityEntry(
        id=entry.id,
        created_at=_iso(entry.created_at),
        action=entry.action,
        outcome=entry.outcome,
        actor_type=entry.actor_type,
        actor_id=entry.actor_id,
        actor_label=entry.actor_label,
        resource_type=entry.resource_type,
        resource_id=entry.resource_id,
        patient_id=entry.patient_id,
        patient_code=entry.patient_code,
        endpoint=entry.endpoint,
        ip_address=entry.ip_address,
        user_agent=entry.user_agent,
        detail=entry.detail,
    )


def _serialize_session(
    session: TriageSession, patient_code: Optional[str]
) -> AdminSessionItem:
    tier = triage_tier(session, session.risk_score)
    escalation = escalation_for(session)
    return AdminSessionItem(
        id=session.id,
        patient_code=patient_code,
        visit_id=session.visit_id,
        body_region=session.body_region,
        pain_type=session.pain_type,
        severity=session.severity,
        risk_score=session.risk_score,
        risk_level=_risk_level(session.risk_score),
        tier=tier["tier"],
        escalation=escalation["level"],
        status=session.status or "open",
        created_at=_iso(session.created_at),
    )


def _user_counts(db: Session) -> AdminUserCounts:
    total = db.query(func.count(Doctor.id)).scalar() or 0
    approved = (
        db.query(func.count(Doctor.id))
        .filter(Doctor.is_approved.is_(True))
        .scalar()
        or 0
    )
    active = (
        db.query(func.count(Doctor.id))
        .filter(Doctor.is_active.is_(True))
        .scalar()
        or 0
    )
    admins = (
        db.query(func.count(Doctor.id))
        .filter(Doctor.access_level == ACCESS_ADMIN)
        .scalar()
        or 0
    )
    return AdminUserCounts(
        total=total,
        approved=approved,
        pending=total - approved,
        active=active,
        inactive=total - active,
        admins=admins,
        practitioners=total - admins,
    )


def _triage_overview(
    db: Session,
    now: datetime,
    day_start: datetime,
    week_start: datetime,
) -> AdminTriageOverview:
    total = db.query(func.count(TriageSession.id)).scalar() or 0
    today = (
        db.query(func.count(TriageSession.id))
        .filter(TriageSession.created_at >= day_start)
        .scalar()
        or 0
    )
    last_7_days = (
        db.query(func.count(TriageSession.id))
        .filter(TriageSession.created_at >= week_start)
        .scalar()
        or 0
    )

    high = (
        db.query(func.count(TriageSession.id))
        .filter(TriageSession.risk_score >= 0.7)
        .scalar()
        or 0
    )
    medium = (
        db.query(func.count(TriageSession.id))
        .filter(
            (TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7)
        )
        .scalar()
        or 0
    )

    status_rows = (
        db.query(TriageSession.status, func.count(TriageSession.id))
        .group_by(TriageSession.status)
        .all()
    )
    # Rows created before the decision workflow existed have status=NULL. They
    # are open in every practical sense, so they are counted there rather than
    # dropped from both totals.
    closed = sum(count for status, count in status_rows if status == "closed")
    open_count = total - closed

    by_tier: Dict[str, int] = {"red": 0, "orange": 0, "yellow": 0, "green": 0}
    by_escalation: Dict[str, int] = {
        "emergency": 0,
        "urgent": 0,
        "routine": 0,
    }
    for session in db.query(TriageSession).all():
        tier = triage_tier(session, session.risk_score)["tier"]
        by_tier[tier] = by_tier.get(tier, 0) + 1
        level = escalation_for(session)["level"]
        by_escalation[level] = by_escalation.get(level, 0) + 1

    region_rows = (
        db.query(
            TriageSession.body_region,
            func.count(TriageSession.id).label("n"),
        )
        .group_by(TriageSession.body_region)
        .order_by(func.count(TriageSession.id).desc())
        .limit(10)
        .all()
    )
    avg_severity = db.query(func.avg(TriageSession.severity)).scalar()
    avg_risk = db.query(func.avg(TriageSession.risk_score)).scalar()

    return AdminTriageOverview(
        total=total,
        today=today,
        last_7_days=last_7_days,
        high_risk=high,
        medium_risk=medium,
        low_risk=total - high - medium,
        open=open_count,
        closed=closed,
        by_tier=by_tier,
        by_escalation=by_escalation,
        by_region=[
            {"region": region or "Unknown", "count": count}
            for region, count in region_rows
        ],
        avg_severity=round(avg_severity, 1) if avg_severity is not None else None,
        avg_risk_score=round(avg_risk, 2) if avg_risk is not None else None,
    )


def _activity_summary(db: Session, now: datetime) -> AdminActivitySummary:
    total = db.query(func.count(AuditLog.id)).scalar() or 0
    last_24h = (
        db.query(func.count(AuditLog.id))
        .filter(AuditLog.created_at >= now - timedelta(hours=24))
        .scalar()
        or 0
    )
    denied = (
        db.query(func.count(AuditLog.id))
        .filter(AuditLog.outcome == "denied")
        .scalar()
        or 0
    )
    recent = (
        db.query(AuditLog)
        .order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .limit(10)
        .all()
    )
    return AdminActivitySummary(
        total=total,
        last_24h=last_24h,
        denied=denied,
        recent=[_serialize_audit(entry) for entry in recent],
    )


@router.get("/overview", response_model=AdminOverview)
def get_admin_overview(
    request: Request,
    db: Session = Depends(get_db),
    current_admin: Doctor = Depends(require_admin),
):
    """One call for the console's landing page.

    A single aggregate is cheaper than five round trips on a cold mobile
    connection, and it means every number on the page was computed from the
    same instant.
    """
    now = datetime.now(timezone.utc)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = now - timedelta(days=7)

    overview = AdminOverview(
        generated_at=_iso(now) or "",
        environment=settings.ENVIRONMENT,
        version=settings.VERSION,
        users=_user_counts(db),
        patients=AdminPatientCounts(
            total=db.query(func.count(Patient.id)).scalar() or 0
        ),
        triage=_triage_overview(db, now, day_start, week_start),
        activity=_activity_summary(db, now),
    )

    audit.record_access(
        action=audit.ACTION_AGGREGATE,
        resource_type=audit.RESOURCE_TRIAGE_STATS,
        request=request,
        actor=current_admin,
        detail="administrator overview",
    )
    return overview


@router.get("/users", response_model=AdminUserList)
def list_admin_users(
    request: Request,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=25, ge=1, le=200),
    q: Optional[str] = Query(default=None, max_length=120),
    status_filter: Optional[str] = Query(
        default=None,
        alias="status",
        pattern="^(all|pending|approved|inactive|admin)$",
    ),
    db: Session = Depends(get_db),
    current_admin: Doctor = Depends(require_admin),
):
    """Every account, with the two questions an administrator asks first:
    who is still waiting for approval, and who is no longer active."""
    query = db.query(Doctor)

    if q and q.strip():
        pattern = f"%{q.strip()}%"
        query = query.filter(
            or_(
                Doctor.email.ilike(pattern),
                Doctor.full_name.ilike(pattern),
                Doctor.hospital_name.ilike(pattern),
            )
        )

    if status_filter == "pending":
        query = query.filter(Doctor.is_approved.is_(False))
    elif status_filter == "approved":
        query = query.filter(Doctor.is_approved.is_(True))
    elif status_filter == "inactive":
        query = query.filter(Doctor.is_active.is_(False))
    elif status_filter == "admin":
        query = query.filter(Doctor.access_level == ACCESS_ADMIN)

    total = query.count()
    doctors = (
        query.order_by(Doctor.created_at.asc(), Doctor.id.asc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    audit.record_access(
        action=audit.ACTION_LIST,
        resource_type=RESOURCE_DOCTOR,
        request=request,
        actor=current_admin,
        detail=f"administrator listed {len(doctors)} account(s)",
    )

    return AdminUserList(
        items=[AdminUserResponse.model_validate(doctor) for doctor in doctors],
        pagination=_pagination(total, page, limit),
        counts=_user_counts(db),
    )


@router.patch("/users/{doctor_id}", response_model=AdminUserResponse)
def update_admin_user(
    doctor_id: int,
    payload: DoctorAdminUpdate,
    db: Session = Depends(get_db),
    current_admin: Doctor = Depends(require_admin),
):
    """Approve, deactivate or promote an account.

    The rules live in one place: this delegates to the same handler the
    ``/auth/doctors/{id}`` route uses, including the guard that stops an
    administrator demoting or deactivating themselves.
    """
    doctor = update_doctor_account(
        doctor_id=doctor_id,
        payload=payload,
        db=db,
        current_admin=current_admin,
    )
    return AdminUserResponse.model_validate(doctor)


@router.get("/activity", response_model=AdminActivityList)
def list_admin_activity(
    request: Request,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=50, ge=1, le=200),
    action: Optional[str] = Query(
        default=None, pattern="^(read|list|aggregate|create|update|delete)$"
    ),
    outcome: Optional[str] = Query(default=None, pattern="^(allowed|denied)$"),
    actor_type: Optional[str] = Query(
        default=None, pattern="^(doctor|patient|anonymous)$"
    ),
    resource_type: Optional[str] = Query(default=None, max_length=64),
    db: Session = Depends(get_db),
    current_admin: Doctor = Depends(require_admin),
):
    """The audit trail, newest first. This is the system-wide activity feed."""
    query = db.query(AuditLog)
    if action:
        query = query.filter(AuditLog.action == action)
    if outcome:
        query = query.filter(AuditLog.outcome == outcome)
    if actor_type:
        query = query.filter(AuditLog.actor_type == actor_type)
    if resource_type:
        query = query.filter(AuditLog.resource_type == resource_type)

    total = query.count()
    entries = (
        query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    # Reading the trail is itself an event in it.
    audit.record_access(
        action=audit.ACTION_READ,
        resource_type=audit.RESOURCE_AUDIT_LOG,
        request=request,
        actor=current_admin,
        detail=f"administrator activity page {page} ({total} match(es))",
    )

    return AdminActivityList(
        items=[_serialize_audit(entry) for entry in entries],
        pagination=_pagination(total, page, limit),
    )


@router.get("/sessions", response_model=AdminSessionList)
def list_admin_sessions(
    request: Request,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=25, ge=1, le=200),
    risk_level: Optional[str] = Query(default=None, pattern="^(high|medium|low)$"),
    status_filter: Optional[str] = Query(
        default=None, alias="status", pattern="^(open|closed)$"
    ),
    db: Session = Depends(get_db),
    current_admin: Doctor = Depends(require_admin),
):
    """Recent triage points across the whole system.

    Patient identity is reduced to the anonymous code; the console is for
    operational oversight, not a second clinical chart.
    """
    query = db.query(TriageSession, Patient.anonymous_code).outerjoin(
        Patient, TriageSession.patient_id == Patient.id
    )

    if risk_level == "high":
        query = query.filter(TriageSession.risk_score >= 0.7)
    elif risk_level == "medium":
        query = query.filter(
            (TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7)
        )
    elif risk_level == "low":
        query = query.filter(TriageSession.risk_score < 0.4)

    if status_filter == "closed":
        query = query.filter(TriageSession.status == "closed")
    elif status_filter == "open":
        query = query.filter(
            or_(
                TriageSession.status == "open",
                TriageSession.status.is_(None),
            )
        )

    total = query.count()
    rows = (
        query.order_by(TriageSession.created_at.desc(), TriageSession.id.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    audit.record_access(
        action=audit.ACTION_LIST,
        resource_type=audit.RESOURCE_TRIAGE_HISTORY,
        request=request,
        actor=current_admin,
        detail=f"administrator session list page {page} ({total} match(es))",
    )

    return AdminSessionList(
        items=[_serialize_session(session, code) for session, code in rows],
        pagination=_pagination(total, page, limit),
    )
