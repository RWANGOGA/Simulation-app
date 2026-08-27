from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, DateTime, Date, Text, Float
from app.core.database import Base
from sqlalchemy.orm import relationship 

class Patient(Base):
    __tablename__ = "patients"
    id = Column(Integer, primary_key=True, index=True)
    anonymous_code = Column(String, unique=True, index=True, default="P-ANON")
    age = Column(Integer, nullable=True)
    gender = Column(String, nullable=True)
    weight = Column(Float, nullable=True)  # kg
    height = Column(Float, nullable=True)  # cm
    # Personal demographics — all optional so the flow stays fast for
    # anonymous walk-ins, but carried through to the clinical report
    # and the QR-scan lookup when provided.
    full_name = Column(String, nullable=True)
    date_of_birth = Column(Date, nullable=True)
    phone = Column(String, nullable=True)
    address = Column(Text, nullable=True)
    next_of_kin_name = Column(String, nullable=True)
    next_of_kin_phone = Column(String, nullable=True)
    hospital_name = Column(String, nullable=True)
    preferred_language = Column(String, default="en")
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    triage_sessions = relationship("TriageSession", back_populates="patient")
