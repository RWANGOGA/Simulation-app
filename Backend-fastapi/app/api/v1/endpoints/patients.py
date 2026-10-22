from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.crud import crud_patient
from app.schemas import PatientBase, PatientCreate, PatientResponse, PublicPatientResponse
from app.models.doctor import Doctor
from app.api.v1.endpoints.auth import get_current_doctor
from app.services import audit, throttle

router = APIRouter(prefix="/patients", tags=["patients"])

# Public intake limit, held in the request_throttle table so it is shared by
# every worker and survives a restart (see app/services/throttle).
def _check_patient_rate_limit(request: Request, db: Session) -> None:
    allowed = throttle.allow(
        db,
        throttle.bucket_for(request, "patient"),
        limit=throttle.PATIENT_RATE_LIMIT,
        window_seconds=throttle.PATIENT_RATE_WINDOW_SECONDS,
    )
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please try again later.",
            headers={"Retry-After": str(throttle.PATIENT_RATE_WINDOW_SECONDS)},
        )

@router.post("/", response_model=PatientResponse, status_code=201)
def create_patient(request: Request, payload: PatientCreate, db: Session = Depends(get_db)):
    _check_patient_rate_limit(request, db)

    try:
        patient = crud_patient.create_patient(db, payload)
    except crud_patient.PatientCodeTaken:
        # Only reachable when the payload carried a code the client minted
        # offline. Answered without any patient fields on purpose: the code
        # travels inside a printed QR image, so holding one must not become a
        # way to read the name and next of kin that /patients/{code} withholds.
        audit.record_access(
            action=audit.ACTION_CREATE,
            resource_type=audit.RESOURCE_PATIENT,
            request=request,
            actor_type=audit.ACTOR_ANONYMOUS,
            patient_code=payload.anonymous_code,
            outcome=audit.OUTCOME_DENIED,
            detail="create attempted with a patient code that already exists",
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A patient with this code already exists.",
        )

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

# Unauthenticated on purpose: the anonymous code IS the patient's
# credential, and the intake flow reaches this route with no account.
# It therefore returns PublicPatientResponse — clinical demographics only,
# with every identity field absent. Practitioners read the full record
# through the JWT-guarded triage routes.
@router.get("/{code}", response_model=PublicPatientResponse)
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
        actor_type=audit.ACTOR_PATIENT,
        patient_id=patient.id,
        patient_code=patient.anonymous_code,
        resource_id=patient.id,
        detail="patient record read by code (clinical fields only)",
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
