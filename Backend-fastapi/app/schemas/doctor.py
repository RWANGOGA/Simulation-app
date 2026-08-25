from typing import Optional
from pydantic import BaseModel

class DoctorResponse(BaseModel):
    id: int
    email: str
    full_name: str
    role: Optional[str] = None
    license_number: Optional[str] = None
    is_active: bool

    class Config:
        from_attributes = True
