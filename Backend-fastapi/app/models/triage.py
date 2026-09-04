from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, Text, ForeignKey, JSON
from app.core.database import Base

class TriageSession(Base):
    __tablename__ = "triage_sessions"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=True)
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
    status = Column(String, nullable=False, default="open", index=True)
    priority = Column(String, nullable=True)
    actions_taken = Column(Text, nullable=True)
    clinical_notes = Column(Text, nullable=True)
    question_answers = Column(JSON, nullable=True)
