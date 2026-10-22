from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, Date, DateTime, func, text
from app.core.database import Base

# Access levels. Deliberately only two: this app has exactly one privileged
# action (approving accounts) plus reading the audit trail, so a richer role
# hierarchy would be ceremony. A plain string rather than a DB enum keeps the
# migration to an ALTER TABLE instead of a type swap.
ACCESS_PRACTITIONER = "practitioner"
ACCESS_ADMIN = "admin"
ACCESS_LEVELS = (ACCESS_PRACTITIONER, ACCESS_ADMIN)

class Doctor(Base):
    __tablename__ = "doctors"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=False)
    # Professional context captured at signup (self-declared; verified
    # out-of-band for real deployments). `role` is the *job title* a clinician
    # types — "Nurse", "Consultant" — and is display-only. `access_level` is
    # what the server enforces; never let a user-supplied field decide it.
    role = Column(String, nullable=True)
    license_number = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    hospital_name = Column(String, nullable=True)
    date_of_birth = Column(Date, nullable=True)
    is_active = Column(Boolean, default=True)
    # Signing up proves you can receive mail at an address; it proves nothing
    # about whether you should be able to read a patient's clinical record.
    # A new account therefore starts unapproved and cannot obtain a token
    # until an admin approves it. Existing rows are grandfathered by the
    # migration, so shipping this locks nobody out.
    is_approved = Column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    access_level = Column(
        String,
        nullable=False,
        default=ACCESS_PRACTITIONER,
        server_default=text(f"'{ACCESS_PRACTITIONER}'"),
    )
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), server_default=func.now())

    @property
    def is_admin(self) -> bool:
        return self.access_level == ACCESS_ADMIN
