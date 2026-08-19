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


class TriageCreate(TriageBase):
    patient_id: Optional[int] = None

class TriageResponse(TriageBase):
    id: int
    patient_id: Optional[int] = None
    risk_score: Optional[float] = None
    shap_explanation: Optional[str] = None
    qr_payload_hash: Optional[str] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
