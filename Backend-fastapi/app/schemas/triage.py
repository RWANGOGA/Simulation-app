from datetime import datetime, date
from typing import List, Optional, Any
from pydantic import BaseModel, ConfigDict, Field, field_validator

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


class TriageTier(BaseModel):
    """The pain point mapped onto a published four-category triage scale.

    `tier` is the colour a station acts on, `category` is that colour's name in
    the scale's own vocabulary, and `decided_by` lists the stable rule codes that
    put it there — so the answer is auditable, and a clinician who disagrees can
    say which rule they disagree with rather than which number.

    Derived from stored fields on every read, exactly like `escalation`. Nothing
    here is stored, which is what lets a threshold move without re-triaging
    history, and what keeps this from being presented as a validated model: see
    the honesty boundary in triage_service.triage_tier.
    """
    tier: str = Field(..., description="red | orange | yellow | green")
    scale: str = Field(..., description='The scale these categories come from ("SATS")')
    category: str = Field(
        ...,
        description="emergency | very_urgent | urgent | routine",
    )
    decided_by: List[str] = Field(
        default_factory=list,
        description="Stable codes of the rules that set this tier",
    )


class TriageResponse(TriageBase):
    id: int
    patient_id: Optional[int] = None
    anonymous_code: Optional[str] = None
    risk_score: Optional[float] = None
    escalation: Optional[TriageEscalation] = None
    tier: Optional[TriageTier] = None
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
    clinician_tier: Optional[str] = None
    actions_taken: Optional[str] = None
    clinical_notes: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

class TriageDecisionUpdate(BaseModel):
    """PATCH /triage/{id}/decision — practitioner saves the review outcome."""
    status: Optional[str] = Field(None, pattern="^(open|closed)$")
    priority: Optional[str] = None
    # The reference standard the tool is measured against. `priority` was never
    # it: free text like "Review Immediately" is a worklist instruction, not a
    # triage category, so agreement with a clinician could not be computed from
    # anything the product recorded. Kept writable for the worklist, and this
    # added beside it as a closed set matching the tool's own output.
    clinician_tier: Optional[str] = None
    actions_taken: Optional[List[str]] = None
    clinical_notes: Optional[str] = None

    @field_validator("clinician_tier")
    @classmethod
    def _tier_is_on_the_scale(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return value
        # Imported here rather than at the top: `app.services.triage_service`
        # imports `app.schemas`, so a module-level import is a cycle. The cost is
        # one lookup per validated request; the gain is that the scale's tiers
        # exist in exactly one place, so the API cannot accept a category the
        # engine cannot emit.
        from app.services import triage_service

        if value not in triage_service.TIERS:
            raise ValueError(
                "clinician_tier must be one of "
                + ", ".join(triage_service.TIERS)
            )
        return value
