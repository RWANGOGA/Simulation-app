from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, select
import json
from app.core.database import get_db
from app.crud import crud_triage, crud_patient
from app.schemas import TriageCreate, TriageResponse, TriageDecisionUpdate, PatientCreate
from app.services import triage_service
from app.models import Patient, TriageSession, Doctor
from app.api.v1.endpoints.auth import get_current_doctor

router = APIRouter(prefix="/triage", tags=["triage"])

def _session_payload(session: TriageSession, patient) -> dict:
    """Single source of truth for the triage response shape — every
    endpoint returns this so new fields (spo2, decision workflow, ...)
    only need to be added in one place."""
    return {
        "id": session.id, "patient_id": session.patient_id,
        "anonymous_code": patient.anonymous_code if patient else None,
        "body_region": session.body_region, "pain_type": session.pain_type,
        "severity": session.severity, "heart_rate": session.heart_rate,
        "spo2": session.spo2, "direction": session.direction, "depth": session.depth,
        "visit_id": session.visit_id,
        "risk_score": session.risk_score, "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash, "created_at": session.created_at,
        "status": session.status or "open",
        "priority": session.priority,
        "actions_taken": session.actions_taken,
        "clinical_notes": session.clinical_notes,
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

# ==========================================
# 1. CREATE TRIAGE (Patient submits data)
# Left unauthenticated on purpose: patients submit anonymously from the
# mobile/web app with no account. The doctor-facing READ endpoints below
# are JWT-guarded instead.
# ==========================================
@router.post("/", response_model=TriageResponse, status_code=201)
def create_triage(payload: TriageCreate, db: Session = Depends(get_db)):
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
            # Reject dangling references: previously an unknown patient_id
            # still created a session row pointing at nothing (orphaned
            # record that could never be joined back to a patient).
            raise HTTPException(status_code=404, detail="Patient not found")
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

    return _session_payload(session, patient_obj)

# ==========================================
# 2. LIST ALL TRIAGES (Original Route)
# Doctor-only: exposes every patient's submissions, so it requires a valid
# JWT (issue: data endpoints were previously fully open).
# ==========================================
@router.get("/", response_model=List[TriageResponse])
def list_triage(
    limit: int = 50,
    patient_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    return crud_triage.list_triage(db, limit=limit, patient_id=patient_id)

# ==========================================
# 3. GET DASHBOARD STATS
# Must come before /{session_id} — static paths are matched
# top-to-bottom, and a dynamic segment below would otherwise
# swallow "/stats" as if it were a session_id.
# ==========================================
@router.get("/stats")
def get_triage_stats(
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    total_sessions = db.query(func.count(TriageSession.id)).scalar() or 0
    high_risk_sessions = db.query(func.count(TriageSession.id)).filter(TriageSession.risk_score >= 0.7).scalar() or 0
    medium_risk_sessions = db.query(func.count(TriageSession.id)).filter(
        (TriageSession.risk_score >= 0.4) & (TriageSession.risk_score < 0.7)
    ).scalar() or 0

    return {
        "total": total_sessions,
        "high_risk": high_risk_sessions,
        "medium_risk": medium_risk_sessions,
        "low_risk": total_sessions - high_risk_sessions - medium_risk_sessions
    }

# ==========================================
# 4. GET FILTERED LIST (History / Practitioner Dashboard)
# Also must come before /{session_id} for the same reason.
# ==========================================
@router.get("/list")
def list_triage_sessions(
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
        query = query.filter(Patient.anonymous_code.ilike(f"%{patient_code}%"))

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
# ==========================================
@router.get("/patient/{patient_code}", response_model=List[TriageResponse])
def get_triage_by_patient_code(patient_code: str, db: Session = Depends(get_db)):
    patient = crud_patient.get_patient_by_code(db, patient_code)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient ID not found")

    sessions = crud_triage.get_latest_visit(db, patient.id)
    if not sessions:
        raise HTTPException(status_code=404, detail="No clinical report found for this patient")

    return [_session_payload(s, patient) for s in sessions]

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
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    patient = crud_patient.get_patient_by_code(db, patient_code)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient ID not found")

    sessions = crud_triage.get_patient_history(db, patient.id)
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
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Triage session not found")

    patient = None
    if session.patient_id:
        patient = db.query(Patient).filter(Patient.id == session.patient_id).first()

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
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
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
    return _session_payload(session, patient)
