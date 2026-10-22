from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict

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
    # Sent to the client so it can show "awaiting approval" and reveal the
    # admin screens without a second round trip. Server-side enforcement is
    # still require_admin — never trust the client's copy of this.
    is_approved: bool = False
    access_level: str = "practitioner"
    created_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class DoctorAdminUpdate(BaseModel):
    """What an administrator may change about someone else's account.

    Deliberately does not include password or email: those are the account
    holder's own credentials, and an admin silently changing them is account
    takeover rather than administration.
    """

    is_approved: Optional[bool] = None
    is_active: Optional[bool] = None
    access_level: Optional[str] = None

class DoctorUpdate(BaseModel):
    full_name: Optional[str] = None
    role: Optional[str] = None
    license_number: Optional[str] = None
    phone: Optional[str] = None
    hospital_name: Optional[str] = None
    date_of_birth: Optional[date] = None
