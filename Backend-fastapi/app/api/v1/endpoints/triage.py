from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, select
from app.core.database import get_db
from app.crud import crud_triage, crud_patient
from app.schemas import TriageCreate, TriageResponse, PatientCreate
from app.services import triage_service
from app.models import Patient, TriageSession

router = APIRouter(prefix="/triage", tags=["triage"])

# ==========================================
# 1. CREATE TRIAGE (Patient submits data)
# ==========================================
@router.post("/", response_model=TriageResponse, status_code=201)
def create_triage(payload: TriageCreate, db: Session = Depends(get_db)):
    risk, contributions = triage_service.compute_risk(payload)

    patient_id = payload.patient_id
    anonymous_code = None

    if patient_id is None:
        new_patient_data = PatientCreate(age=None, gender=None, preferred_language="en")
        new_patient = crud_patient.create_patient(db, new_patient_data)
        patient_id = new_patient.id
        anonymous_code = new_patient.anonymous_code

    session_data = payload.model_dump()
    session_data["patient_id"] = patient_id

    session = crud_triage.create_triage(
        db,
        TriageCreate(**session_data),
        risk_score=risk,
        shap_explanation=triage_service.explain(contributions)
    )

    return {
        "id": session.id, "patient_id": session.patient_id, "anonymous_code": anonymous_code,
        "body_region": session.body_region, "pain_type": session.pain_type, "severity": session.severity,
        "heart_rate": session.heart_rate, "direction": session.direction, "depth": session.depth,
        "risk_score": session.risk_score, "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash, "created_at": session.created_at
    }

# ==========================================
# 2. LIST ALL TRIAGES (Original Route)
# ==========================================
@router.get("/", response_model=List[TriageResponse])
def list_triage(limit: int = 50, patient_id: Optional[int] = None, db: Session = Depends(get_db)):
    return crud_triage.list_triage(db, limit=limit, patient_id=patient_id)

# ==========================================
# 3. GET DASHBOARD STATS
# Must come before /{session_id} — static paths are matched
# top-to-bottom, and a dynamic segment below would otherwise
# swallow "/stats" as if it were a session_id.
# ==========================================
@router.get("/stats")
def get_triage_stats(db: Session = Depends(get_db)):
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
    db: Session = Depends(get_db)
):
    query = db.query(TriageSession, Patient.anonymous_code).join(
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

    sessions = query.offset(offset).limit(limit).all()

    result = []
    for session, anon_code in sessions:
        result.append({
            "id": session.id,
            "anonymous_code": anon_code or "Unknown",
            "body_region": session.body_region,
            "pain_type": session.pain_type,
            "severity": session.severity,
            "risk_score": session.risk_score,
            "created_at": session.created_at.isoformat()
        })
    return result

# ==========================================
# 5. GET LATEST TRIAGE BY PATIENT CODE (QR Scan / Patient views own report)
# Safe relative to /{session_id} since it has two path segments
# ("/patient/...") and can't collide with a single-segment route,
# but keeping it above /{session_id} anyway for readability.
# ==========================================
@router.get("/patient/{patient_code}", response_model=TriageResponse)
def get_triage_by_patient_code(patient_code: str, db: Session = Depends(get_db)):
    patient = crud_patient.get_patient_by_code(db, patient_code)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient ID not found")

    stmt = select(TriageSession).where(
        TriageSession.patient_id == patient.id
    ).order_by(TriageSession.created_at.desc())

    session = db.execute(stmt).scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="No clinical report found for this patient")

    return {
        "id": session.id, "patient_id": session.patient_id, "anonymous_code": patient.anonymous_code,
        "body_region": session.body_region, "pain_type": session.pain_type, "severity": session.severity,
        "heart_rate": session.heart_rate, "direction": session.direction, "depth": session.depth,
        "risk_score": session.risk_score, "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash, "created_at": session.created_at
    }

# ==========================================
# 6. GET SINGLE TRIAGE BY SESSION ID
# MUST BE LAST. Any single dynamic path segment declared here
# will catch every static single-segment route added below it
# (e.g. a future "/export" or "/summary" would break the same way
# "/stats" and "/list" did). Add new static routes ABOVE this one.
# ==========================================
@router.get("/{session_id}", response_model=TriageResponse)
def get_triage(session_id: int, db: Session = Depends(get_db)):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Triage session not found")

    anon_code = None
    if session.patient_id:
        patient = db.query(Patient).filter(Patient.id == session.patient_id).first()
        if patient:
            anon_code = patient.anonymous_code

    return {
        "id": session.id, "patient_id": session.patient_id, "anonymous_code": anon_code,
        "body_region": session.body_region, "pain_type": session.pain_type, "severity": session.severity,
        "heart_rate": session.heart_rate, "direction": session.direction, "depth": session.depth,
        "risk_score": session.risk_score, "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash, "created_at": session.created_at
    }