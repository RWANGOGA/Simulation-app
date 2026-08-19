from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.crud import crud_triage
from app.schemas import TriageCreate, TriageResponse
from app.services import triage_service

router = APIRouter(prefix="/triage", tags=["triage"])

@router.post("/", response_model=TriageResponse, status_code=201)
def create_triage(payload: TriageCreate, db: Session = Depends(get_db)):
    risk, contributions = triage_service.compute_risk(payload)
    session = crud_triage.create_triage(
        db, payload,
        risk_score=risk,
        shap_explanation=triage_service.explain(contributions)
    )
    return session

@router.get("/", response_model=List[TriageResponse])
def list_triage(limit: int = 50, patient_id: Optional[int] = None, db: Session = Depends(get_db)):
    return crud_triage.list_triage(db, limit=limit, patient_id=patient_id)

@router.get("/{session_id}", response_model=TriageResponse)
def get_triage(session_id: int, db: Session = Depends(get_db)):
    session = crud_triage.get_triage(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Triage session not found")
    return session
