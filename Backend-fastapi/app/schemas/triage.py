from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field

class TriageBase(BaseModel):
    body_region: str = Field(..., description="e.g., Head, Chest, Left Arm")
    pain_type: str = Field(..., description="e.g., sharp, burning, throbbing")
    severity: int = Field(..., ge=1, le=10)
    heart_rate: Optional[float] = Field(None, description="BPM from camera PPG")
    direction: Optional[str] = Field(None, description="e.g., Towards Back, Radiating Down")
    depth: Optional[str] = Field(None, description="e.g., Superficial, Moderate, Deep")
    # Client-generated id shared by every pain point submitted in the same
    # Review & Submit action, so a multi-region visit can be grouped back
    # together later (e.g. on the QR / patient-code lookup). Optional for
    # backward compatibility with older clients that don't send it yet.
    visit_id: Optional[str] = Field(None, description="Shared id across all pain points from one visit")

class TriageCreate(TriageBase):
    patient_id: Optional[int] = None

class TriageResponse(TriageBase):
    id: int
    patient_id: Optional[int] = None
    anonymous_code: Optional[str] = None  # NEW: The 12-char Base36 ID
    risk_score: Optional[float] = None
    shap_explanation: Optional[str] = None
    qr_payload_hash: Optional[str] = None
    notes: Optional[str] = None
    status: Optional[str] = "Open"
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class TriageDecisionUpdate(BaseModel):
    """Practitioner-authored fields saved from the dashboard's Triage
    Decision panel — distinct from TriageBase, which is patient-submitted
    at triage time."""
    notes: Optional[str] = None
    status: Optional[str] = Field(None, pattern="^(Open|Closed)$")