from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, DateTime, Text
from app.core.database import Base

class Patient(Base):
    __tablename__ = "patients"
    id = Column(Integer, primary_key=True, index=True)
    anonymous_code = Column(String, unique=True, index=True, default="P-ANON")
    age = Column(Integer, nullable=True)
    gender = Column(String, nullable=True)
    preferred_language = Column(String, default="en")
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
