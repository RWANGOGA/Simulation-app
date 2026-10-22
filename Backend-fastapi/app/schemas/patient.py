from datetime import datetime, date
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field

class PatientBase(BaseModel):
    age: Optional[int] = Field(None, ge=0, le=120)
    gender: Optional[str] = None
    weight: Optional[float] = Field(None, ge=1, le=500, description="kg")
    height: Optional[float] = Field(None, ge=30, le=272, description="cm")
    # Optional personal demographics — surfaced on the clinical report.
    full_name: Optional[str] = Field(None, max_length=120)
    date_of_birth: Optional[date] = None
    phone: Optional[str] = Field(None, max_length=30)
    address: Optional[str] = Field(None, max_length=500)
    next_of_kin_name: Optional[str] = Field(None, max_length=120)
    next_of_kin_phone: Optional[str] = Field(None, max_length=30)
    hospital_name: Optional[str] = Field(None, max_length=200)
    preferred_language: str = Field("en", description="e.g., en, lug, sign")
    notes: Optional[str] = None

class PatientCreate(PatientBase):
    # Set only by a client that minted the code itself, which happens when the
    # whole intake ran on the device with no network. Supplying it makes create
    # idempotent: a retry after a lost response reuses the same row instead of
    # creating a second patient, and the code printed on the patient's card
    # stays the code this server knows. Left absent by every online caller, so
    # the server keeps minting codes exactly as before.
    anonymous_code: Optional[str] = Field(
        None,
        pattern=r"^P-[A-Z0-9]{12}$",
        description="Code minted offline by the client; acts as an idempotency key.",
    )

class PatientResponse(PatientBase):
    id: int
    anonymous_code: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class PublicPatientResponse(BaseModel):
    """Clinical-only view of a patient record for unauthenticated callers.

    The anonymous code is the patient's only credential and it travels
    inside a screenshot of a QR image that gets printed, shared and shown
    to strangers. Holding the code therefore cannot imply consent to see
    the person's name, phone, address or next of kin — so those fields are
    ABSENT from this schema rather than present-and-null.

    Absent, not null, is deliberate: Pydantic ignores fields a model does
    not declare, so a future column added to ``Patient`` cannot silently
    start leaking through this route. Publishing it has to be a decision.
    Practitioners get the full record through the JWT-guarded triage
    routes (``/triage/patient/{code}/history`` and ``/triage/{session_id}``)
    and through ``PATCH /patients/{code}``.
    """

    id: int
    anonymous_code: str
    age: Optional[int] = None
    gender: Optional[str] = None
    weight: Optional[float] = None
    height: Optional[float] = None
    preferred_language: str = "en"
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
