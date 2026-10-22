import secrets
import string
from typing import Optional
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from app.models import Patient
from app.schemas import PatientCreate, PatientBase


class PatientCodeTaken(Exception):
    """A client-supplied anonymous code is already in use.

    Only reachable through `create_patient` when the payload carried a code,
    which only an offline-first client does. Kept distinct from a generic
    IntegrityError so the route can answer 409 with a body that says nothing
    about the patient already holding that code.
    """

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code

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
    payload = data.model_dump()
    requested_code = payload.pop("anonymous_code", None)

    patient = Patient(**payload)

    if requested_code:
        # The client minted this code while it had no network. Honour it, so the
        # code on the patient's card is the code this server answers on. It also
        # makes the call idempotent: a retry after a response went missing finds
        # the row already there. Raising instead of returning the existing row
        # keeps identity fields (name, phone, next of kin) out of the reply —
        # /patients/{code} withholds them from code-holders deliberately, and
        # this route must not become the way around that.
        if get_patient_by_code(db, requested_code) is not None:
            raise PatientCodeTaken(requested_code)
        patient.anonymous_code = requested_code
    else:
        # Generate the secure ID using our new algorithm
        patient.anonymous_code = generate_unique_patient_id(db)

    db.add(patient)
    try:
        db.commit()
    except IntegrityError:
        # Two requests raced with the same code. The unique index caught it, so
        # report it the same way as the check above rather than a 500.
        db.rollback()
        raise PatientCodeTaken(patient.anonymous_code)
    db.refresh(patient)
    return patient

def get_patient_by_code(db: Session, code: str) -> Optional[Patient]:
    stmt = select(Patient).where(Patient.anonymous_code == code)
    return db.execute(stmt).scalar_one_or_none()

def update_patient(db: Session, code: str, data: PatientBase) -> Optional[Patient]:
    """Applies a practitioner's correction to a patient's demographics.
    exclude_unset means a field the client never included in the request
    body is left untouched — sending just {"phone": "..."} doesn't wipe
    out every other field back to its schema default."""
    patient = get_patient_by_code(db, code)
    if patient is None:
        return None
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(patient, field, value)
    db.commit()
    db.refresh(patient)
    return patient