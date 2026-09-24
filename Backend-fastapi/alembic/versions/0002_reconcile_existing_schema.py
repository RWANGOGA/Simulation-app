"""Reconcile databases created before Alembic.

Revision ID: 0002_reconcile_existing_schema
Revises: 0001_initial_schema
Create Date: 2026-09-15
"""
from typing import Sequence, Union

from alembic import op

revision: str = "0002_reconcile_existing_schema"
down_revision: Union[str, Sequence[str], None] = "0001_initial_schema"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS refresh_tokens (
            id SERIAL PRIMARY KEY,
            doctor_id INTEGER NOT NULL REFERENCES doctors(id),
            token VARCHAR NOT NULL UNIQUE,
            expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
            revoked VARCHAR NOT NULL DEFAULT 'false'
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_refresh_tokens_id ON refresh_tokens (id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_refresh_tokens_doctor_id "
        "ON refresh_tokens (doctor_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_refresh_tokens_token ON refresh_tokens (token)"
    )
    op.execute(
        "UPDATE triage_sessions SET status = 'open' WHERE status IS NULL"
    )
    op.execute(
        "ALTER TABLE triage_sessions ALTER COLUMN status SET DEFAULT 'open'"
    )
    op.execute(
        "ALTER TABLE triage_sessions ALTER COLUMN status SET NOT NULL"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_triage_sessions_status "
        "ON triage_sessions (status)"
    )


def downgrade() -> None:
    op.drop_index("ix_triage_sessions_status", table_name="triage_sessions")
    op.execute("ALTER TABLE triage_sessions ALTER COLUMN status DROP NOT NULL")
    op.execute("ALTER TABLE triage_sessions ALTER COLUMN status DROP DEFAULT")
    op.drop_index("ix_refresh_tokens_token", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_doctor_id", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_id", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
