import secrets
import string
from typing import Optional
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models import Patient
from app.schemas import PatientCreate

def generate_unique_patient_id(db: Session) -> str:
    """
    Generates a cryptographically secure, 12-character Base36 Patient ID.
    Uses a continuous loop to guarantee zero collisions in the database.
    Format: P-XXXXXXXXXXXX (e.g., P-8X9K2M4Q7W9Z)
    """
    # Base36 alphabet: A-Z (26) + 0-9 (10) = 36 characters
    alphabet = string.ascii_uppercase + string.digits 
    
    # THE CONTINUOUS LOOP
    while True:
        # Generate a random 12-character string
        random_part = ''.join(secrets.choice(alphabet) for _ in range(12))
        patient_id = f"P-{random_part}"
        
        # Check if it already exists in the database (Collision check)
        stmt = select(Patient).where(Patient.anonymous_code == patient_id)
        existing_patient = db.execute(stmt).scalar_one_or_none()
        
        # If it does NOT exist, we break the loop and return the unique ID
        if existing_patient is None:
            return patient_id

def create_patient(db: Session, data: PatientCreate) -> Patient:
    patient = Patient(**data.model_dump())
    
    # Generate the secure ID using our new algorithm
    patient.anonymous_code = generate_unique_patient_id(db)
    
    db.add(patient)
    db.commit()
    db.refresh(patient)
    return patient

def get_patient_by_code(db: Session, code: str) -> Optional[Patient]:
    stmt = select(Patient).where(Patient.anonymous_code == code)
    return db.execute(stmt).scalar_one_or_none()