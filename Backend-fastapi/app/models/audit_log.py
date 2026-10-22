from datetime import datetime, timezone
from sqlalchemy import Column, DateTime, Index, Integer, String, Text, func
from app.core.database import Base


class AuditLog(Base):
    """Append-only record of every access to patient data.

    Healthcare privacy law (HIPAA §164.312(b), GDPR Art. 30/GDPR Art. 15)
    requires the *system* to be able to answer "who looked at this
    patient's record, when, and from where". Nothing else in this schema
    can: triage_sessions only stores the last edit, and clinical_notes
    only records decisions, never reads.

    Two deliberate design choices:

    1. **No foreign keys.** An audit trail that disappears (or gets
       CASCADE-deleted) when a patient or doctor row is removed is
       worthless exactly when it matters most. actor_id / patient_id are
       plain integers and actor_label is a denormalised snapshot of who
       acted at the time, so the row stays readable forever.
    2. **Metadata only, never clinical content.** We record *that* a
       record was read, not *what* was in it. Copying pain descriptions
       or notes in here would double the number of places PHI lives.

    Written by ``app.services.audit.record_access`` only — endpoints must
    never insert rows here directly, so the shape stays consistent.
    """

    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
        nullable=False,
        index=True,
    )

    # Who acted. actor_type is "doctor" for a JWT-authenticated
    # practitioner, "patient" when the caller proved they hold the
    # patient's anonymous code (X-Patient-Code), and "anonymous" for a
    # bare public lookup.
    actor_type = Column(String, nullable=False, default="anonymous")
    actor_id = Column(Integer, nullable=True, index=True)
    actor_label = Column(String, nullable=True)

    # What happened. action is one of: read, list, aggregate, create,
    # update, delete. outcome is "allowed" or "denied" — a blocked
    # attempt is at least as interesting as a successful one.
    action = Column(String, nullable=False)
    outcome = Column(String, nullable=False, default="allowed")
    resource_type = Column(String, nullable=False)
    resource_id = Column(String, nullable=True)

    # Which patient the accessed data belongs to (searchable axis).
    patient_id = Column(Integer, nullable=True, index=True)
    patient_code = Column(String, nullable=True, index=True)

    # Where the request came from.
    endpoint = Column(String, nullable=True)
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)

    detail = Column(Text, nullable=True)

    __table_args__ = (
        # The two questions auditors actually ask: "everything that
        # happened to this patient" and "everything this practitioner did".
        Index("ix_audit_logs_patient_created_at", "patient_id", "created_at"),
        Index("ix_audit_logs_actor_created_at", "actor_id", "created_at"),
    )
