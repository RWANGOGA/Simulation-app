from datetime import date
from typing import Optional
from pydantic import BaseModel

class DoctorResponse(BaseModel):
    id: int
    email: str
    full_name: str
    role: Optional[str] = None
    license_number: Optional[str] = None
    phone: Optional[str] = None
    hospital_name: Optional[str] = None
    date_of_birth: Optional[date] = None
    is_active: bool

    class Config:
        from_attributes = True

class DoctorUpdate(BaseModel):
    full_name: Optional[str] = None
    role: Optional[str] = None
    license_number: Optional[str] = None
    phone: Optional[str] = None
    hospital_name: Optional[str] = None
    date_of_birth: Optional[date] = None
