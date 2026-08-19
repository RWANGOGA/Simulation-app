from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field

class PatientBase(BaseModel):
    age: Optional[int] = Field(None, ge=0, le=120)
    gender: Optional[str] = None
    preferred_language: str = Field("en", description="e.g., en, lug, sign")
    notes: Optional[str] = None

class PatientCreate(PatientBase):
    pass

class PatientResponse(PatientBase):
    id: int
    anonymous_code: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
