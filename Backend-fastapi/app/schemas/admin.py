"""Contracts for the administrator console.

The console is a read-mostly view over the same tables the practitioner routes
use. These models exist so the response shapes are explicit and documented,
not so the admin API can grow a second interpretation of a doctor or a session.
"""

from datetime import datetime
from typing import Dict, List, Optional

from pydantic import BaseModel

from app.schemas.doctor import DoctorResponse


class AdminPagination(BaseModel):
    total: int
    page: int
    limit: int
    total_pages: int


class AdminUserResponse(DoctorResponse):
    # Derived from access_level, surfaced because every admin list row needs
    # to show who is privileged without the client re-implementing the rule.
    is_admin: bool = False


class AdminUserCounts(BaseModel):
    total: int
    approved: int
    pending: int
    active: int
    inactive: int
    admins: int
    practitioners: int


class AdminUserList(BaseModel):
    items: List[AdminUserResponse]
    pagination: AdminPagination
    counts: AdminUserCounts


class AdminPatientCounts(BaseModel):
    total: int


class AdminTriageOverview(BaseModel):
    total: int
    today: int
    last_7_days: int
    high_risk: int
    medium_risk: int
    low_risk: int
    open: int
    closed: int
    # Derived on read from the same rules the practitioner sees, so the
    # console cannot report a distribution the report screen disagrees with.
    by_tier: Dict[str, int]
    by_escalation: Dict[str, int]
    by_region: List[Dict[str, object]]
    # Real daily volume for the last 14 days, oldest first. Computed from the
    # sessions table on every request so the chart cannot drift from the rest
    # of the console.
    trend: List[Dict[str, object]] = []
    avg_severity: Optional[float] = None
    avg_risk_score: Optional[float] = None


class AdminActivityEntry(BaseModel):
    id: int
    created_at: Optional[str] = None
    action: str
    outcome: str
    actor_type: str
    actor_id: Optional[int] = None
    actor_label: Optional[str] = None
    resource_type: str
    resource_id: Optional[str] = None
    patient_id: Optional[int] = None
    patient_code: Optional[str] = None
    endpoint: Optional[str] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    detail: Optional[str] = None


class AdminActivitySummary(BaseModel):
    total: int
    last_24h: int
    denied: int
    recent: List[AdminActivityEntry]
    by_action: Dict[str, int] = {}
    by_outcome: Dict[str, int] = {}
    by_actor_type: Dict[str, int] = {}


class AdminActivityList(BaseModel):
    items: List[AdminActivityEntry]
    pagination: AdminPagination


class AdminOverview(BaseModel):
    generated_at: str
    environment: str
    version: str
    users: AdminUserCounts
    patients: AdminPatientCounts
    triage: AdminTriageOverview
    activity: AdminActivitySummary


class AdminSessionItem(BaseModel):
    id: int
    patient_code: Optional[str] = None
    visit_id: Optional[str] = None
    body_region: str
    pain_type: str
    severity: int
    risk_score: Optional[float] = None
    risk_level: str
    tier: str
    escalation: str
    status: str
    created_at: Optional[str] = None


class AdminSessionList(BaseModel):
    items: List[AdminSessionItem]
    pagination: AdminPagination


class AdminPatientItem(BaseModel):
    """One row of the system-wide patient register."""
    id: int
    anonymous_code: str
    full_name: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    phone: Optional[str] = None
    hospital_name: Optional[str] = None
    preferred_language: str = "en"
    created_at: Optional[str] = None
    session_count: int = 0
    last_session_at: Optional[str] = None
    last_risk_score: Optional[float] = None


class AdminPatientList(BaseModel):
    items: List[AdminPatientItem]
    pagination: AdminPagination


class AdminPatientDetail(AdminPatientItem):
    weight: Optional[float] = None
    height: Optional[float] = None
    date_of_birth: Optional[str] = None
    address: Optional[str] = None
    next_of_kin_name: Optional[str] = None
    next_of_kin_phone: Optional[str] = None
    notes: Optional[str] = None
    sessions: List[AdminSessionItem] = []
    audit: List[AdminActivityEntry] = []


class AdminUserDetail(AdminUserResponse):
    """Everything the console knows about one practitioner account."""
    role: Optional[str] = None
    license_number: Optional[str] = None
    phone: Optional[str] = None
    hospital_name: Optional[str] = None
    date_of_birth: Optional[str] = None
    created_at: Optional[str] = None
    audit_count: int = 0
    denied_count: int = 0
    recent_activity: List[AdminActivityEntry] = []
