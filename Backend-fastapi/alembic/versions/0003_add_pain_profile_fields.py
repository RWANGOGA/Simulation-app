"""Add pain profile and functional impact columns to triage_sessions.

Revision ID: 0003_add_pain_profile_fields
Revises: 0002_reconcile_existing_schema
Create Date: 2026-09-15
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "0003_add_pain_profile_fields"
down_revision: Union[str, Sequence[str], None] = "0002_reconcile_existing_schema"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("triage_sessions", sa.Column("expansion_behavior", sa.String(), nullable=True))
    op.add_column("triage_sessions", sa.Column("triggers", sa.Text(), nullable=True))
    op.add_column("triage_sessions", sa.Column("relievers", sa.Text(), nullable=True))
    op.add_column("triage_sessions", sa.Column("daily_limitations", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("triage_sessions", "daily_limitations")
    op.drop_column("triage_sessions", "relievers")
    op.drop_column("triage_sessions", "triggers")
    op.drop_column("triage_sessions", "expansion_behavior")
