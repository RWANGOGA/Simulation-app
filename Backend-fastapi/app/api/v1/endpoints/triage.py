from datetime import datetime, timedelta, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session
from sqlalchemy import func, select
import json
import logging
from app.core.database import get_db
from app.crud import crud_triage, crud_patient
from app.schemas import TriageCreate, TriageResponse, TriageDecisionUpdate, PatientCreate
from app.services import audit, throttle, triage_service
from app.models import Patient, TriageSession, Doctor
from app.api.v1.endpoints.auth import get_current_doctor

router = APIRouter(prefix="/triage", tags=["triage"])
logger = logging.getLogger(__name__)

# Public intake limit. Backed by the request_throttle table rather than a
# module-level dict, so the limit holds across uvicorn workers and survives
# a deploy — a per-process counter let a restart hand an attacker a clean
# slate and multiplied the real limit by the worker count.
def _check_triage_rate_limit(request: Request, db: Session) -> None:
    allowed = throttle.allow(
        db,
        throttle.bucket_for(request, "triage"),
        limit=throttle.TRIAGE_RATE_LIMIT,
        window_seconds=throttle.TRIAGE_RATE_WINDOW_SECONDS,
    )
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please try again later.",
            headers={"Retry-After": str(throttle.TRIAGE_RATE_WINDOW_SECONDS)},
        )

def _session_payload(session: TriageSession, patient) -> dict:
    """Single source of truth for the triage response shape — every
    endpoint returns this so new fields (decision workflow, ...)
    only need to be added in one place.

    `spo2` is deliberately absent. The column still exists on old rows, but the
    camera figure behind it is a perfusion proxy and no response, score or screen
    should present it as an oxygen saturation."""
    return {
        "id": session.id, "patient_id": session.patient_id,
        "anonymous_code": patient.anonymous_code if patient else None,
        "body_region": session.body_region, "pain_type": session.pain_type,
        "severity": session.severity, "heart_rate": session.heart_rate,
        "direction": session.direction, "depth": session.depth,
        "expansion_behavior": session.expansion_behavior, "triggers": session.triggers,
        "relievers": session.relievers, "daily_limitations": session.daily_limitations,
        "visit_id": session.visit_id,
        "risk_score": session.risk_score, "shap_explanation": session.shap_explanation,
        # Red flags sit beside the score, not inside it: the score is a clamped
        # sum, so a single dangerous finding can hide in a medium total. Derived
        # from the stored columns on every read, so every endpoint (create,
        # history, QR lookup, practitioner view) reports the same verdict.
        "escalation": triage_service.escalation_for(session),
        "qr_payload_hash": session.qr_payload_hash, "created_at": session.created_at,
        "status": session.status or "open",
        "priority": session.priority,
        "actions_taken": session.actions_taken,
        "clinical_notes": session.clinical_notes,
        "question_answers": session.question_answers,
        "patient_age": patient.age if patient else None,
        "patient_gender": patient.gender if patient else None,
        "patient_weight": patient.weight if patient else None,
        "patient_height": patient.height if patient else None,
        "patient_name": patient.full_name if patient else None,
        "patient_date_of_birth": patient.date_of_birth if patient else None,
        "patient_phone": patient.phone if patient else None,
        "patient_address": patient.address if patient else None,
        "patient_next_of_kin_name": patient.next_of_kin_name if patient else None,
        "patient_next_of_kin_phone": patient.next_of_kin_phone if patient else None,
        "patient_hospital_name": patient.hospital_name if patient else None,
    }

# Identity and contact fields that must never leave the server on an
# unauthenticated request. The anonymous code travels inside a QR image
# that patients screenshot, print and hand to strangers — so "holds the
# code" cannot be treated as "consented to see this person's name, phone
# number and home address".
_PUBLIC_REDACTED_FIELDS = (
    "patient_name",
    "patient_date_of_birth",
    "patient_phone",
    "patient_address",
    "patient_next_of_kin_name",
    "patient_next_of_kin_phone",
    "patient_hospital_name",
)


def _public_session_payload(session: TriageSession, patient) -> dict:
    """Clinical-only view of a session, for the unauthenticated lookup.

    Keeps everything needed to render the report (region, severity, risk
    score, red flags, decision) plus the non-identifying demographics the
    report displays, and drops every field that names or locates the
    person. Practitioners keep the full payload through the JWT-guarded
    routes (/patient/{code}/history and /{session_id}).
    """
    payload = _session_payload(session, patient)
    for field in _PUBLIC_REDACTED_FIELDS:
        payload.pop(field, None)
    return payload

# ==========================================
# 1. CREATE TRIAGE (Patient submits data)
# Left unauthenticated on purpose: patients submit anonymously from the
# mobile/web app with no account. The doctor-facing READ endpoints below
# are JWT-guarded instead.
# ==========================================
@router.post("/", response_model=TriageResponse, status_code=201)
def create_triage(
    request: Request,
    payload: TriageCreate,
    db: Session = Depends(get_db),
):
    _check_triage_rate_limit(request, db)
    # If this pain point belongs to a multi-region visit, score it aware of
    # whatever other regions the patient already reported in the same visit
    # (e.g. chest pain scored alongside already-reported left arm pain).
    sibling_regions = (
        crud_triage.get_regions_in_visit(db, payload.visit_id) if payload.visit_id else None
    )

    patient_id = payload.patient_id
    patient_obj = None

    if patient_id is None:
        new_patient_data = PatientCreate(age=None, gender=None, preferred_language="en")
        new_patient = crud_patient.create_patient(db, new_patient_data)
        patient_id = new_patient.id
        patient_obj = new_patient
    else:
        existing_patient = db.query(Patient).filter(Patient.id == patient_id).first()
        if not existing_patient:
            # Reject dangling references rather than creating an orphaned
            # session row pointing at a nonexistent patient.
            raise HTTPException(status_code=404, detail="Patient not found")
        submitted_code = request.headers.get("X-Patient-Code")
        if submitted_code != existing_patient.anonymous_code:
            # Someone tried to attach a pain point to a patient record whose
            # code they do not hold. The write is blocked, but the attempt
            # itself belongs in the trail.
            audit.record_access(
                action=audit.ACTION_CREATE,
                resource_type=audit.RESOURCE_TRIAGE_SESSION,
                request=request,
                actor_type=audit.ACTOR_PATIENT,
                patient_id=existing_patient.id,
                patient_code=existing_patient.anonymous_code,
                outcome=audit.OUTCOME_DENIED,
                detail="X-Patient-Code did not match the referenced patient",
            )
            raise HTTPException(
                status_code=403,
                detail="Patient code does not match the submitted patient",
            )
        patient_obj = existing_patient

    # Weight/height feed the BMI risk factor; scoring needs the patient
    # resolved first, so risk is computed after the lookup above.
    risk, contributions = triage_service.compute_risk(
        payload,
        sibling_regions=sibling_regions,
        patient_weight=patient_obj.weight if patient_obj else None,
        patient_height=patient_obj.height if patient_obj else None,
    )

    session_data = payload.model_dump()
    session_data["patient_id"] = patient_id

    session = crud_triage.create_triage(
        db,
        TriageCreate(**session_data),
        risk_score=risk,
        shap_explanation=triage_service.explain(contributions)
    )

    audit.record_access(
        action=audit.ACTION_CREATE,
        resource_type=audit.RESOURCE_TRIAGE_SESSION,
        request=request,
        # No patient_id means the caller had no code to prove — the
        # submission is genuinely anonymous.
        actor_type=audit.ACTOR_PATIENT if payload.patient_id is not None else audit.ACTOR_ANONYMOUS,
        patient_id=patient_id,
        patient_code=patient_obj.anonymous_code if patient_obj else None,
        resource_id=session.id,
        detail="triage submitted",
    )

    response_payload = _session_payload(session, patient_obj)

    # A red flag is not a number for someone to notice later in a list view: it
    # is logged the moment the patient submits, so an escalated case is visible
    # to whoever is watching the service even if nobody has the dashboard open.
    escalation = response_payload["escalation"]
    if escalation["level"] != triage_service.ESCALATION_ROUTINE:
        logger.info(
            "triage %s escalated %s (risk=%.2f, %s)",
            session.id,
            escalation["level"],
            risk,
            ", ".join(trigger["code"] for trigger in escalation["triggers"]),
        )

    return response_payload

# ==========================================
# 4b. PAGINATED SESSION HISTORY (Practitioner History Screen)
# Returns the FULL rich payload (via _session_payload) and pagination 
# metadata. Must come before dynamic routes like /patient/{code}.
# ==========================================
@router.get("/history")
def get_triage_history(
    request: Request,
    page: int = Query(default=1, ge=1, description="Page number"),
    limit: int = Query(default=20, ge=1, le=100, description="Items per page"),
    risk_level: Optional[str] = Query(default=None, description="HIGH, MEDIUM, or LOW"),
    status: Optional[str] = Query(default=None, pattern="^(open|closed)$"),
    body_region: Optional[str] = Query(default=None),
    patient_code: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    offset = (page - 1) * limit
    
    # 1. Base query joining Patient to get demographics and anonymous_code
    base_query = db.query(TriageSession).join(
        Patient, TriageSession.patient_id == Patient.id, isouter=True
    )
    
    # 2. Apply Filters dynamically
    if patient_code:
        base_query = base_query.filter(Patient.anonymous_code.ilike(func.concat('%', patient_code, '%')))
    if body_region:
        base_query = base_query.filter(TriageSession.body_region.ilike(func.concat('%', body_region, '%')))
    if risk_level == "HIGH":
        base_query = base_query.filter(TriageSession.risk_score >= 0.7)
    elif risk_level == "MEDIUM":
        base_query = base_query.filter((TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7))
    elif risk_level == "LOW":
        base_query = base_query.filter(TriageSession.risk_score < 0.4)
    if status:
        base_query = base_query.filter(TriageSession.status == status)
        
    # 3. Get total count of records matching the filters (for pagination math)
    total_records = base_query.count()
    total_pages = (total_records + limit - 1) // limit if total_records > 0 else 0
    
    # 4. Execute the query with offset, limit, and ordering (newest first)
    sessions = base_query.order_by(TriageSession.created_at.desc()).offset(offset).limit(limit).all()
    
    # 5. Build the rich payload using your existing helper!
    items = []
    for session in sessions:
        # Fetch the patient object for the payload helper
        patient = db.query(Patient).filter(Patient.id == session.patient_id).first() if session.patient_id else None
        items.append(_session_payload(session, patient))

    audit.record_access(
        action=audit.ACTION_LIST,
        resource_type=audit.RESOURCE_TRIAGE_HISTORY,
        request=request,
        actor=current_doctor,
        patient_code=patient_code,
        detail=f"practitioner history page {page} ({total_records} match(es))",
    )

    # 6. Return the structured JSON response
    return {
        "items": items,
        "pagination": {
            "total": total_records,
            "page": page,
            "limit": limit,
            "total_pages": total_pages,
        }
    }    

# ==========================================
# 2. LIST ALL TRIAGES (Original Route)
# Doctor-only: exposes every patient's submissions, so it requires a valid JWT.
# ==========================================
@router.get("/", response_model=List[TriageResponse])
def list_triage(
    request: Request,
    limit: int = 50,
    patient_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    sessions = crud_triage.list_triage(db, limit=limit, patient_id=patient_id)
    audit.record_access(
        action=audit.ACTION_LIST,
        resource_type=audit.RESOURCE_TRIAGE_SESSION,
        request=request,
        actor=current_doctor,
        patient_id=patient_id,
        detail=f"listed {len(sessions)} session(s)",
    )
    return sessions

# ==========================================
# 3. GET DASHBOARD STATS
# Must come before /{session_id} — static paths are matched
# top-to-bottom, and a dynamic segment below would otherwise
# swallow "/stats" as if it were a session_id.
# ==========================================
@router.get("/stats")
def get_triage_stats(
    request: Request,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    total_sessions = db.query(func.count(TriageSession.id)).scalar() or 0
    high_risk_sessions = db.query(func.count(TriageSession.id)).filter(TriageSession.risk_score >= 0.7).scalar() or 0
    medium_risk_sessions = db.query(func.count(TriageSession.id)).filter(
        (TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7)
    ).scalar() or 0

    # Aggregates carry no identifiers, but they are still derived from
    # patient records — auditors expect the read to be visible.
    audit.record_access(
        action=audit.ACTION_AGGREGATE,
        resource_type=audit.RESOURCE_TRIAGE_STATS,
        request=request,
        actor=current_doctor,
        detail=f"dashboard stats over {total_sessions} session(s)",
    )

    return {
        "total": total_sessions,
        "high_risk": high_risk_sessions,
        "medium_risk": medium_risk_sessions,
        "low_risk": total_sessions - high_risk_sessions - medium_risk_sessions
    }

# ==========================================
# 3b. GET PRACTITIONER REPORTS (aggregate breakdowns for the Reports page)
# Separate from /stats above so nothing that already depends on that
# endpoint's shape is affected. Also must come before /{session_id}.
# ==========================================
@router.get("/reports")
def get_triage_reports(
    request: Request,
    period: str = Query(default="all", pattern="^(week|month|all)$"),
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    query = db.query(TriageSession)
    period_start = None
    if period == "week":
        period_start = datetime.now(timezone.utc) - timedelta(days=7)
    elif period == "month":
        period_start = datetime.now(timezone.utc) - timedelta(days=30)
    if period_start is not None:
        query = query.filter(TriageSession.created_at >= period_start)

    session_ids = [row.id for row in query.with_entities(TriageSession.id).all()]
    total_sessions = len(session_ids)

    def _scoped(q):
        return q.filter(TriageSession.id.in_(session_ids)) if period_start is not None else q

    high_risk_count = _scoped(
        db.query(func.count(TriageSession.id)).filter(TriageSession.risk_score >= 0.7)
    ).scalar() or 0
    medium_risk_count = _scoped(
        db.query(func.count(TriageSession.id)).filter(
            (TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7)
        )
    ).scalar() or 0

    status_rows = (
        _scoped(db.query(TriageSession.status, func.count(TriageSession.id)))
        .group_by(TriageSession.status)
        .all()
    )
    # Rows created before the decision workflow existed have status=NULL —
    # they're "open" in every practical sense (never reviewed/closed).
    open_count = sum(count for status, count in status_rows if status != "closed")
    closed_count = sum(count for status, count in status_rows if status == "closed")

    region_rows = (
        _scoped(db.query(TriageSession.body_region, func.count(TriageSession.id).label("n")))
        .group_by(TriageSession.body_region)
        .order_by(func.count(TriageSession.id).desc())
        .all()
    )
    pain_type_rows = (
        _scoped(db.query(TriageSession.pain_type, func.count(TriageSession.id).label("n")))
        .group_by(TriageSession.pain_type)
        .order_by(func.count(TriageSession.id).desc())
        .all()
    )

    avg_severity = _scoped(db.query(func.avg(TriageSession.severity))).scalar()
    avg_risk_score = _scoped(db.query(func.avg(TriageSession.risk_score))).scalar()

    audit.record_access(
        action=audit.ACTION_AGGREGATE,
        resource_type=audit.RESOURCE_TRIAGE_REPORTS,
        request=request,
        actor=current_doctor,
        detail=f"reports period={period} over {total_sessions} session(s)",
    )

    return {
        "period": period,
        "total": total_sessions,
        "high_risk_count": high_risk_count,
        "medium_risk_count": medium_risk_count,
        "low_risk_count": total_sessions - high_risk_count - medium_risk_count,
        "open_count": open_count,
        "closed_count": closed_count,
        "by_region": [{"region": region, "count": n} for region, n in region_rows],
        "by_pain_type": [{"pain_type": pt, "count": n} for pt, n in pain_type_rows],
        "avg_severity": round(avg_severity, 1) if avg_severity is not None else None,
        "avg_risk_score": round(avg_risk_score, 2) if avg_risk_score is not None else None,
    }

# ==========================================
# 4. GET FILTERED LIST (History / Practitioner Dashboard)
# Also must come before /{session_id} for the same reason.
# ==========================================
@router.get("/list")
def list_triage_sessions(
    request: Request,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    patient_code: Optional[str] = Query(default=None),
    risk_level: Optional[str] = Query(default=None),
    status: Optional[str] = Query(default=None, pattern="^(open|closed)$"),
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    query = db.query(
        TriageSession,
        Patient.anonymous_code,
        Patient.age,
        Patient.gender,
    ).join(
        Patient, TriageSession.patient_id == Patient.id, isouter=True
    ).order_by(TriageSession.created_at.desc())

    if patient_code:
        query = query.filter(Patient.anonymous_code.ilike(func.concat('%', patient_code, '%')))

    if risk_level == "HIGH":
        query = query.filter(TriageSession.risk_score >= 0.7)
    elif risk_level == "MEDIUM":
        query = query.filter((TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7))
    elif risk_level == "LOW":
        query = query.filter(TriageSession.risk_score < 0.4)

    if status:
        query = query.filter(TriageSession.status == status)

    sessions = query.offset(offset).limit(limit).all()

    result = []
    for session, anon_code, age, gender in sessions:
        result.append({
            "id": session.id,
            "anonymous_code": anon_code or "Unknown",
            "body_region": session.body_region,
            "pain_type": session.pain_type,
            "severity": session.severity,
            "risk_score": session.risk_score,
            "shap_explanation": session.shap_explanation,
            "patient_age": age,
            "patient_gender": gender,
            "status": session.status or "open",
            "created_at": session.created_at.isoformat()
        })

    audit.record_access(
        action=audit.ACTION_LIST,
        resource_type=audit.RESOURCE_TRIAGE_SESSION,
        request=request,
        actor=current_doctor,
        patient_code=patient_code,
        detail=f"filtered list returned {len(result)} row(s)",
    )
    return result

# ==========================================
# 5. GET LATEST VISIT BY PATIENT CODE (QR Scan / Patient views own report)
# Now returns EVERY pain point submitted in the patient's most recent
# visit (grouped by visit_id), not just the single most recent row.
# Response shape changed: was a single TriageResponse object, now a JSON
# array of TriageResponse objects — the Flutter client needs to switch
# from decoding one object to decoding a list.
# Safe relative to /{session_id} since it has two path segments
# ("/patient/...") and can't collide with a single-segment route,
# but keeping it above /{session_id} anyway for readability.
# Kept unauthenticated on purpose: the 12-char anonymous code IS the
# patient's credential — they reach this via QR scan with no account.
# Because of that, the response is REDACTED: clinical data only, no name,
# no date of birth, no phone, no address, no next of kin. Practitioners
# read the full record through the JWT-guarded /history route below.
# ==========================================
@router.get("/patient/{patient_code}", response_model=List[TriageResponse])
def get_triage_by_patient_code(
    patient_code: str,
    request: Request,
    db: Session = Depends(get_db),
):
    patient = crud_patient.get_patient_by_code(db, patient_code)
    if not patient:
        # A wrong code is indistinguishable from a probe, so record it:
        # code enumeration is exactly what this trail is for.
        audit.record_access(
            action=audit.ACTION_READ,
            resource_type=audit.RESOURCE_TRIAGE_SESSION,
            request=request,
            actor_type=audit.ACTOR_ANONYMOUS,
            patient_code=patient_code,
            outcome=audit.OUTCOME_DENIED,
            detail="anonymous lookup for an unknown patient code",
        )
        raise HTTPException(status_code=404, detail="Patient ID not found")

    sessions = crud_triage.get_latest_visit(db, patient.id)
    if not sessions:
        audit.record_access(
            action=audit.ACTION_READ,
            resource_type=audit.RESOURCE_TRIAGE_SESSION,
            request=request,
            actor_type=audit.ACTOR_PATIENT,
            patient_id=patient.id,
            patient_code=patient_code,
            outcome=audit.OUTCOME_DENIED,
            detail="no clinical report for this patient yet",
        )
        raise HTTPException(status_code=404, detail="No clinical report found for this patient")

    audit.record_access(
        action=audit.ACTION_READ,
        resource_type=audit.RESOURCE_TRIAGE_SESSION,
        request=request,
        # Holding the anonymous code is the patient's only credential and
        # the response is redacted to clinical fields, so this is a
        # patient-scoped read rather than a public one.
        actor_type=audit.ACTOR_PATIENT,
        patient_id=patient.id,
        patient_code=patient_code,
        detail=f"latest visit read ({len(sessions)} pain point(s))",
    )

    return [_public_session_payload(s, patient) for s in sessions]

# ==========================================
# 5b. FULL PATIENT HISTORY (Visit timeline)
# Practitioner-only: every session the patient ever submitted, newest
# first, so the report can render a timeline across visits. Patients
# keep using the unauthenticated latest-visit route above.
# Two path segments — safe relative to /{session_id}.
# ==========================================
@router.get("/patient/{patient_code}/history", response_model=List[TriageResponse])
def get_patient_history(
    patient_code: str,
    request: Request,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    patient = crud_patient.get_patient_by_code(db, patient_code)
    if not patient:
        audit.record_access(
            action=audit.ACTION_READ,
            resource_type=audit.RESOURCE_TRIAGE_HISTORY,
            request=request,
            actor=current_doctor,
            patient_code=patient_code,
            outcome=audit.OUTCOME_DENIED,
            detail="practitioner history lookup for an unknown patient code",
        )
        raise HTTPException(status_code=404, detail="Patient ID not found")

    sessions = crud_triage.get_patient_history(db, patient.id)

    # This is the full, unredacted record — the most sensitive read in the
    # API, so it is audited with the acting practitioner attached.
    audit.record_access(
        action=audit.ACTION_READ,
        resource_type=audit.RESOURCE_TRIAGE_HISTORY,
        request=request,
        actor=current_doctor,
        patient_id=patient.id,
        patient_code=patient_code,
        detail=f"full history read ({len(sessions)} session(s))",
    )
    return [_session_payload(s, patient) for s in sessions]

# ==========================================
# 6. GET SINGLE TRIAGE BY SESSION ID
# MUST BE LAST. Any single dynamic path segment declared here
# will catch every static single-segment route added below it
# (e.g. a future "/export" or "/summary" would break the same way
# "/stats" and "/list" did). Add new static routes ABOVE this one.
# ==========================================
@router.get("/{session_id}", response_model=TriageResponse)
def get_triage(
    session_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
        audit.record_access(
            action=audit.ACTION_READ,
            resource_type=audit.RESOURCE_TRIAGE_SESSION,
            request=request,
            actor=current_doctor,
            resource_id=session_id,
            outcome=audit.OUTCOME_DENIED,
            detail="unknown session id",
        )
        raise HTTPException(status_code=404, detail="Triage session not found")

    patient = None
    if session.patient_id:
        patient = db.query(Patient).filter(Patient.id == session.patient_id).first()

    audit.record_access(
        action=audit.ACTION_READ,
        resource_type=audit.RESOURCE_TRIAGE_SESSION,
        request=request,
        actor=current_doctor,
        patient_id=session.patient_id,
        patient_code=patient.anonymous_code if patient else None,
        resource_id=session.id,
        detail="single session read",
    )

    return _session_payload(session, patient)

# ==========================================
# 7. UPDATE TRIAGE DECISION (Practitioner review workflow)
# Two path segments, so it can't collide with the single-segment
# /{session_id} route below. JWT-guarded: only a signed-in practitioner
# may record a decision on a session.
# ==========================================
@router.patch("/{session_id}/decision", response_model=TriageResponse)
def update_triage_decision(
    session_id: int,
    payload: TriageDecisionUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
        audit.record_access(
            action=audit.ACTION_UPDATE,
            resource_type=audit.RESOURCE_TRIAGE_SESSION,
            request=request,
            actor=current_doctor,
            resource_id=session_id,
            outcome=audit.OUTCOME_DENIED,
            detail="decision attempted on an unknown session id",
        )
        raise HTTPException(status_code=404, detail="Triage session not found")

    if payload.status is not None:
        session.status = payload.status
    if payload.priority is not None:
        session.priority = payload.priority
    if payload.actions_taken is not None:
        session.actions_taken = json.dumps(payload.actions_taken)
    if payload.clinical_notes is not None:
        session.clinical_notes = payload.clinical_notes
    db.commit()
    db.refresh(session)

    patient = db.query(Patient).filter(Patient.id == session.patient_id).first() if session.patient_id else None

    audit.record_access(
        action=audit.ACTION_UPDATE,
        resource_type=audit.RESOURCE_TRIAGE_SESSION,
        request=request,
        actor=current_doctor,
        patient_id=session.patient_id,
        patient_code=patient.anonymous_code if patient else None,
        resource_id=session.id,
        # Which fields changed, never their values — notes are PHI.
        detail="decision updated: " + ", ".join(sorted(payload.model_dump(exclude_none=True))),
    )
    return _session_payload(session, patient)
