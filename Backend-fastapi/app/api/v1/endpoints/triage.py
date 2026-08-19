from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.crud import crud_triage, crud_patient
from app.schemas import TriageCreate, TriageResponse, PatientCreate
from app.services import triage_service
from app.models import Patient, TriageSession 
from app.models import Patient


router = APIRouter(prefix="/triage", tags=["triage"])

@router.post("/", response_model=TriageResponse, status_code=201)
def create_triage(payload: TriageCreate, db: Session = Depends(get_db)):
    """
    Creates a triage session. If no patient_id is provided, 
    automatically creates a new anonymous patient with a secure 12-char Base36 ID.
    """
    # 1. Calculate the risk score
    risk, contributions = triage_service.compute_risk(payload)
    
    # 2. Handle Patient Creation if no patient_id is provided
    patient_id = payload.patient_id
    anonymous_code = None
    
    if patient_id is None:
        # Create a minimal patient record with just the secure ID
        new_patient_data = PatientCreate(
            age=None,
            gender=None,
            preferred_language="en"
        )
        new_patient = crud_patient.create_patient(db, new_patient_data)
        patient_id = new_patient.id
        anonymous_code = new_patient.anonymous_code  # This is the 12-char ID!
    
    # 3. Create the triage session linked to this patient
    # We create a new dict to safely add the patient_id to the payload
    session_data = payload.model_dump()
    session_data["patient_id"] = patient_id
    
    session = crud_triage.create_triage(
        db, 
        TriageCreate(**session_data), 
        risk_score=risk,
        shap_explanation=triage_service.explain(contributions)
    )
    
    # 4. Return the response, explicitly including the anonymous_code for the frontend
    return {
        "id": session.id,
        "patient_id": session.patient_id,
        "anonymous_code": anonymous_code,
        "body_region": session.body_region,
        "pain_type": session.pain_type,
        "severity": session.severity,
        "heart_rate": session.heart_rate,
        "direction": session.direction,
        "depth": session.depth,
        "risk_score": session.risk_score,
        "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash,
        "created_at": session.created_at
    }

@router.get("/", response_model=List[TriageResponse])
def list_triage(limit: int = 50, patient_id: Optional[int] = None, db: Session = Depends(get_db)):
    return crud_triage.list_triage(db, limit=limit, patient_id=patient_id)

@router.get("/{session_id}", response_model=TriageResponse)
def get_triage(session_id: int, db: Session = Depends(get_db)):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Triage session not found")
    
    # Fetch the anonymous code for the single session view
    anon_code = None
    if session.patient_id:
        patient = db.query(Patient).filter(Patient.id == session.patient_id).first()
        if patient:
            anon_code = patient.anonymous_code
            
    return {
        "id": session.id,
        "patient_id": session.patient_id,
        "anonymous_code": anon_code,
        "body_region": session.body_region,
        "pain_type": session.pain_type,
        "severity": session.severity,
        "heart_rate": session.heart_rate,
        "direction": session.direction,
        "depth": session.depth,
        "risk_score": session.risk_score,
        "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash,
        "created_at": session.created_at
    }


from app.models import Patient, TriageSession # Make sure these are imported at the top

@router.get("/patient/{patient_code}", response_model=TriageResponse)
def get_triage_by_patient_code(patient_code: str, db: Session = Depends(get_db)):
    """Fetches the latest triage report for a given anonymous Patient ID."""
    # 1. Find the patient
    patient = crud_patient.get_patient_by_code(db, patient_code)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient ID not found")

    # 2. Find their latest triage session
    stmt = select(TriageSession).where(
        TriageSession.patient_id == patient.id
    ).order_by(TriageSession.created_at.desc())
    
    session = db.execute(stmt).scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="No clinical report found for this patient")

    # 3. Return the formatted data
    return {
        "id": session.id,
        "patient_id": session.patient_id,
        "anonymous_code": patient.anonymous_code,
        "body_region": session.body_region,
        "pain_type": session.pain_type,
        "severity": session.severity,
        "heart_rate": session.heart_rate,
        "direction": session.direction,
        "depth": session.depth,
        "risk_score": session.risk_score,
        "shap_explanation": session.shap_explanation,
        "qr_payload_hash": session.qr_payload_hash,
        "created_at": session.created_at
    }    