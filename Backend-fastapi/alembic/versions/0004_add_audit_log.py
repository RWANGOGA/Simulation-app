"""Add the patient-data access audit trail.

Revision ID: 0004_add_audit_log
Revises: 0003_add_pain_profile_fields
Create Date: 2026-10-22

The table intentionally has no foreign keys: an audit row must outlive the
patient or doctor it refers to, otherwise deleting an account erases the
evidence of who had looked at it.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0004_add_audit_log"
down_revision: Union[str, Sequence[str], None] = "0003_add_pain_profile_fields"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("actor_type", sa.String(), nullable=False),
        sa.Column("actor_id", sa.Integer(), nullable=True),
        sa.Column("actor_label", sa.String(), nullable=True),
        sa.Column("action", sa.String(), nullable=False),
        sa.Column("outcome", sa.String(), nullable=False),
        sa.Column("resource_type", sa.String(), nullable=False),
        sa.Column("resource_id", sa.String(), nullable=True),
        sa.Column("patient_id", sa.Integer(), nullable=True),
        sa.Column("patient_code", sa.String(), nullable=True),
        sa.Column("endpoint", sa.String(), nullable=True),
        sa.Column("ip_address", sa.String(), nullable=True),
        sa.Column("user_agent", sa.String(), nullable=True),
        sa.Column("detail", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_audit_logs_id", "audit_logs", ["id"], unique=False)
    op.create_index("ix_audit_logs_created_at", "audit_logs", ["created_at"], unique=False)
    op.create_index("ix_audit_logs_actor_id", "audit_logs", ["actor_id"], unique=False)
    op.create_index("ix_audit_logs_patient_id", "audit_logs", ["patient_id"], unique=False)
    op.create_index("ix_audit_logs_patient_code", "audit_logs", ["patient_code"], unique=False)
    op.create_index(
        "ix_audit_logs_patient_created_at", "audit_logs", ["patient_id", "created_at"], unique=False
    )
    op.create_index(
        "ix_audit_logs_actor_created_at", "audit_logs", ["actor_id", "created_at"], unique=False
    )


def downgrade() -> None:
    op.drop_index("ix_audit_logs_actor_created_at", table_name="audit_logs")
    op.drop_index("ix_audit_logs_patient_created_at", table_name="audit_logs")
    op.drop_index("ix_audit_logs_patient_code", table_name="audit_logs")
    op.drop_index("ix_audit_logs_patient_id", table_name="audit_logs")
    op.drop_index("ix_audit_logs_actor_id", table_name="audit_logs")
    op.drop_index("ix_audit_logs_created_at", table_name="audit_logs")
    op.drop_index("ix_audit_logs_id", table_name="audit_logs")
    op.drop_table("audit_logs")
