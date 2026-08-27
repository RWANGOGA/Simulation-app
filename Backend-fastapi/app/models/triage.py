from datetime import datetime, timezone
from sqlalchemy.orm import relationship
from sqlalchemy import Column, Integer, String, Float, DateTime, Text, ForeignKey
from app.core.database import Base

class TriageSession(Base):
    __tablename__ = "triage_sessions"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=True)
    # Groups multiple pain-point submissions from the same patient visit
    # together (a patient can mark several body regions in one Review &
    # Submit action; each becomes its own TriageSession row, tied together
    # by a shared visit_id generated client-side). Nullable so existing
    # rows created before this field existed keep working unchanged —
    # they're just treated as a "visit" of one.
    visit_id = Column(String, nullable=True, index=True)
    body_region = Column(String, index=True)
    pain_type = Column(String)
    severity = Column(Integer)
    heart_rate = Column(Float, nullable=True)
    spo2 = Column(Float, nullable=True)
    direction = Column(String, nullable=True)
    depth = Column(String, nullable=True)
    risk_score = Column(Float, nullable=True)
    shap_explanation = Column(Text, nullable=True)
    qr_payload_hash = Column(String, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    patient = relationship("Patient", back_populates="triage_sessions")
    # ---- Practitioner decision workflow ----
    # Lifecycle of a session: stays "open" until a practitioner reviews and
    # closes it. DB-level default so old rows and patient-side inserts
    # always carry a value.
    status = Column(String, nullable=False, default="open", index=True)
    # Confirmed priority label, e.g. "Review Immediately".
    priority = Column(String, nullable=True)
    # JSON array of the actions the practitioner ticked off.
    actions_taken = Column(Text, nullable=True)
    clinical_notes = Column(Text, nullable=True)
