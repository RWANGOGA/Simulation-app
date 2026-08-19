import secrets
from typing import Optional
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models import Patient
from app.schemas import PatientCreate

def create_patient(db: Session, data: PatientCreate) -> Patient:
    patient = Patient(**data.model_dump())
    patient.anonymous_code = f"P-{secrets.token_hex(3).upper()}"
    db.add(patient)
    db.commit()
    db.refresh(patient)
    return patient

def get_patient_by_code(db: Session, code: str) -> Optional[Patient]:
    stmt = select(Patient).where(Patient.anonymous_code == code)
    return db.execute(stmt).scalar_one_or_none()
