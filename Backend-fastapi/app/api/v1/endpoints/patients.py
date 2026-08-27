from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.crud import crud_patient
from app.schemas import PatientCreate, PatientResponse
from app.models import Doctor
from app.api.v1.endpoints.auth import get_current_doctor

router = APIRouter(prefix="/patients", tags=["patients"])

#left unauthenticated on purpose because patients register anonymously
@router.post("/", response_model=PatientResponse, status_code=201)
def create_patient(payload: PatientCreate, db: Session = Depends(get_db)):
    return crud_patient.create_patient(db, payload)

#the doctor only exposes a patient's record so it requres a valid JWT token
@router.get("/{code}", response_model=PatientResponse)
def get_patient(code: str, 
                db: Session = Depends(get_db),
                current_doctor: Doctor = Depends(get_current_doctor)):
    patient = crud_patient.get_patient_by_code(db, code)
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")
    return patient
