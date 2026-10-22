from datetime import datetime, timezone, timedelta
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, func
from app.core.database import Base

class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id = Column(Integer, primary_key=True, index=True)
    doctor_id = Column(Integer, ForeignKey("doctors.id"), nullable=False, index=True)
    token = Column(String, unique=True, nullable=False, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), server_default=func.now())
    # Holds the literal "false" while the token is live; the ISO-8601 moment
    # it was rotated once consumed; or a hard "revoked:<iso>" stamp when the
    # session was deliberately ended. Keeping the moment (rather than a bare
    # "true") is what lets /auth/refresh tell an accidental retry after a
    # dropped response apart from a replay of a leaked token, with no extra
    # column. Legacy rows written before rotation existed hold "true".
    revoked = Column(String, nullable=False, default="false")

    def is_valid(self) -> bool:
        return self.revoked == "false" and datetime.now(timezone.utc) < self.expires_at
