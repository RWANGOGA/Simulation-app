from sqlalchemy import Column, Integer, String, Boolean, DateTime, func
from app.core.database import Base

class Doctor(Base):
    __tablename__ = "doctors"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=False)
    # Professional context captured at signup (self-declared; verified
    # out-of-band for real deployments).
    role = Column(String, nullable=True)
    license_number = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
