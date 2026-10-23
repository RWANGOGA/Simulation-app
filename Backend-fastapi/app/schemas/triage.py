from datetime import datetime, date
from typing import List, Optional, Any
from pydantic import BaseModel, ConfigDict, Field

class TriageBase(BaseModel):
    body_region: str = Field(..., description="e.g., Head, Chest, Left Arm")
    pain_type: str = Field(..., description="e.g., sharp, burning, throbbing")
    severity: int = Field(..., ge=1, le=10)
    heart_rate: Optional[float] = Field(None, description="BPM from camera PPG")
    # No SpO2 field: the camera estimate is a perfusion proxy, not pulse-oximetry,
    # and a number that looks like an oxygen saturation on a triage record invites
    # clinical decisions that the measurement cannot support. The stored column on
    # older visits is left untouched but is read by nothing (see models/triage.py).
    direction: Optional[str] = Field(None, description="e.g., Towards Back, Radiating Down")
    depth: Optional[str] = Field(None, description="e.g., Superficial, Moderate, Deep")
    expansion_behavior: Optional[str] = Field(None, description="e.g., Stays Small, Spreading, Multiplying")
    triggers: Optional[str] = Field(None, description="JSON list or string of aggravating triggers")
    relievers: Optional[str] = Field(None, description="JSON list or string of relieving factors")
    daily_limitations: Optional[str] = Field(None, description="JSON list or string of daily functional limitations")
    visit_id: Optional[str] = Field(None, description="Shared id across all pain points from one visit")
    question_answers: Optional[dict[str, Any]] = Field(None, description="Patient answers to suggested anatomy questions")

class TriageCreate(TriageBase):
    patient_id: Optional[int] = None

class TriageEscalationTrigger(BaseModel):
    """One red flag that fired. `code` is stable for clients to localise or
    count; `detail` is the human-readable English form for logs."""
    code: str
    detail: str


class TriageEscalation(BaseModel):
    """Red-flag outcome for one pain point, computed from the stored clinical
    fields on every read (see triage_service.escalation_for). It sits beside
    `risk_score` rather than replacing it: the score says how concerning the
    picture is overall, this says whether a single finding needs care now."""
    level: str = Field(..., description="emergency | urgent | routine")
    action: str = Field(..., description="seek_emergency_care | seek_urgent_care | routine_review")
    triggers: List[TriageEscalationTrigger] = Field(default_factory=list)


class TriageResponse(TriageBase):
    id: int
    patient_id: Optional[int] = None
    anonymous_code: Optional[str] = None
    risk_score: Optional[float] = None
    escalation: Optional[TriageEscalation] = None
    shap_explanation: Optional[str] = None
    qr_payload_hash: Optional[str] = None
    created_at: datetime
    patient_age: Optional[int] = None
    patient_gender: Optional[str] = None
    patient_weight: Optional[float] = None
    patient_height: Optional[float] = None
    patient_name: Optional[str] = None
    patient_date_of_birth: Optional[date] = None
    patient_phone: Optional[str] = None
    patient_address: Optional[str] = None
    patient_next_of_kin_name: Optional[str] = None
    patient_next_of_kin_phone: Optional[str] = None
    patient_hospital_name: Optional[str] = None
    status: Optional[str] = "open"
    priority: Optional[str] = None
    actions_taken: Optional[str] = None
    clinical_notes: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

class TriageDecisionUpdate(BaseModel):
    """PATCH /triage/{id}/decision — practitioner saves the review outcome."""
    status: Optional[str] = Field(None, pattern="^(open|closed)$")
    priority: Optional[str] = None
    actions_taken: Optional[List[str]] = None
    clinical_notes: Optional[str] = None
