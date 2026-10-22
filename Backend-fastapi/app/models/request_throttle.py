from datetime import datetime, timezone
from sqlalchemy import Column, DateTime, Index, Integer, String
from app.core.database import Base


class RequestThrottle(Base):
    """One row per throttled request, pruned by its own window.

    Both limits used to live in process-local dicts, which meant they reset
    on every deploy, were invisible to sibling workers (two uvicorn workers
    doubled the effective limit), and left no trace for an investigator. For
    a login lockout that is the difference between five guesses and
    unlimited ones.

    Rows rather than a counter column, for two reasons:

    * The window slides honestly. A single counter needs a reset timestamp
      and silently over- or under-counts at the boundary.
    * No scheduled cleanup job. Each check deletes only its own bucket's
      expired rows, so the table stays small without a cron.

    ``bucket`` is caller-defined, e.g. ``triage:<ip>``, ``patient:<ip>`` or
    ``login:<email>`` — the prefix keeps unrelated limits from colliding.
    """

    __tablename__ = "request_throttle"

    id = Column(Integer, primary_key=True, index=True)
    bucket = Column(String, nullable=False, index=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    __table_args__ = (
        # Every query is "rows in this bucket newer than the cutoff".
        Index("ix_request_throttle_bucket_created_at", "bucket", "created_at"),
    )
