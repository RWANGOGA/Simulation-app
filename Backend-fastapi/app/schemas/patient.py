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
    pass

class PatientResponse(PatientBase):
    id: int
    anonymous_code: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
