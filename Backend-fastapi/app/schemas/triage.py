from datetime import datetime, date
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

class TriageBase(BaseModel):
    body_region: str = Field(..., description="e.g., Head, Chest, Left Arm")
    pain_type: str = Field(..., description="e.g., sharp, burning, throbbing")
    severity: int = Field(..., ge=1, le=10)
    heart_rate: Optional[float] = Field(None, description="BPM from camera PPG")
    spo2: Optional[float] = Field(None, description="SpO2 estimate (%) from camera PPG — perfusion-based proxy, not clinical pulse-oximetry")
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
    qr_data : Optional[str] = None  #going to add this to the endpoint
    created_at: datetime
    # Patient demographics joined from the patients table so the clinical
    # report / dashboard can show who a reading belongs to. Collected at
    # intake and stored, but previously never returned by any endpoint.
    patient_age: Optional[int] = None
    patient_gender: Optional[str] = None
    patient_weight: Optional[float] = None
    patient_height: Optional[float] = None
    # Personal demographics (optional at intake) — carried through so the
    # practitioner sees name/contact/next-of-kin when scanning the QR code.
    patient_name: Optional[str] = None
    patient_date_of_birth: Optional[date] = None
    patient_phone: Optional[str] = None
    patient_address: Optional[str] = None
    patient_next_of_kin_name: Optional[str] = None
    patient_next_of_kin_phone: Optional[str] = None
    patient_hospital_name: Optional[str] = None
    # Practitioner decision workflow fields.
    status: Optional[str] = "open"
    priority: Optional[str] = None
    actions_taken: Optional[str] = None  # JSON array string of ticked actions
    clinical_notes: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

class TriageDecisionUpdate(BaseModel):
    """PATCH /triage/{id}/decision — practitioner saves the review outcome."""
    status: Optional[str] = Field(None, pattern="^(open|closed)$")
    priority: Optional[str] = None
    actions_taken: Optional[List[str]] = None
    clinical_notes: Optional[str] = None
