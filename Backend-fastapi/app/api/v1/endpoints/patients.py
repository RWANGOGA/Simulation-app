from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.crud import crud_patient
from app.schemas import PatientBase, PatientCreate, PatientResponse
from app.models.doctor import Doctor
from app.api.v1.endpoints.auth import get_current_doctor
from app.services import audit

router = APIRouter(prefix="/patients", tags=["patients"])

# IP-based rate limiting for public patient creation
_patient_rate_limit: dict[str, list[datetime]] = {}
PATIENT_RATE_LIMIT = 5  # requests per window
PATIENT_RATE_WINDOW = timedelta(minutes=5)

def _check_patient_rate_limit(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    now = datetime.now(timezone.utc)
    cutoff = now - PATIENT_RATE_WINDOW
    
    attempts = [t for t in _patient_rate_limit.get(client_ip, []) if t > cutoff]
    _patient_rate_limit[client_ip] = attempts
    
    if len(attempts) >= PATIENT_RATE_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please try again later.",
        )
    
    _patient_rate_limit[client_ip].append(now)

@router.post("/", response_model=PatientResponse, status_code=201)
def create_patient(request: Request, payload: PatientCreate, db: Session = Depends(get_db)):
    _check_patient_rate_limit(request)
    patient = crud_patient.create_patient(db, payload)

    audit.record_access(
        action=audit.ACTION_CREATE,
        resource_type=audit.RESOURCE_PATIENT,
        request=request,
        actor_type=audit.ACTOR_ANONYMOUS,
        patient_id=patient.id,
        patient_code=patient.anonymous_code,
        resource_id=patient.id,
        detail="patient record created at intake",
    )
    return patient

@router.get("/{code}", response_model=PatientResponse)
def get_patient(code: str, request: Request, db: Session = Depends(get_db)):
    patient = crud_patient.get_patient_by_code(db, code)
    if patient is None:
        audit.record_access(
            action=audit.ACTION_READ,
            resource_type=audit.RESOURCE_PATIENT,
            request=request,
            actor_type=audit.ACTOR_ANONYMOUS,
            patient_code=code,
            outcome=audit.OUTCOME_DENIED,
            detail="lookup for an unknown patient code",
        )
        raise HTTPException(status_code=404, detail="Patient not found")

    audit.record_access(
        action=audit.ACTION_READ,
        resource_type=audit.RESOURCE_PATIENT,
        request=request,
        # This route returns the full demographic record including name,
        # phone and address to anyone holding the code — see the note on
        # the route below.
        actor_type=audit.ACTOR_PATIENT,
        patient_id=patient.id,
        patient_code=patient.anonymous_code,
        resource_id=patient.id,
        detail="patient record read by code",
    )
    return patient

# Practitioner-only: corrects demographics entered wrong at intake (or
# never captured for an anonymous walk-in). JWT-guarded since this is a
# clinical data edit, not something the anonymous patient flow ever calls.
@router.patch("/{code}", response_model=PatientResponse)
def update_patient(
    code: str,
    payload: PatientBase,
    request: Request,
    db: Session = Depends(get_db),
    current_doctor: Doctor = Depends(get_current_doctor),
):
    patient = crud_patient.update_patient(db, code, payload)
    if patient is None:
        audit.record_access(
            action=audit.ACTION_UPDATE,
            resource_type=audit.RESOURCE_PATIENT,
            request=request,
            actor=current_doctor,
            patient_code=code,
            outcome=audit.OUTCOME_DENIED,
            detail="demographics update for an unknown patient code",
        )
        raise HTTPException(status_code=404, detail="Patient not found")

    audit.record_access(
        action=audit.ACTION_UPDATE,
        resource_type=audit.RESOURCE_PATIENT,
        request=request,
        actor=current_doctor,
        patient_id=patient.id,
        patient_code=patient.anonymous_code,
        resource_id=patient.id,
        detail="demographics updated: " + ", ".join(sorted(payload.model_dump(exclude_none=True))),
    )
    return patient
