"""Create the initial AtomyBridge schema.

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-09-15
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0001_initial_schema"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "doctors",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sa.String(), nullable=False),
        sa.Column("hashed_password", sa.String(), nullable=False),
        sa.Column("full_name", sa.String(), nullable=False),
        sa.Column("role", sa.String(), nullable=True),
        sa.Column("license_number", sa.String(), nullable=True),
        sa.Column("phone", sa.String(), nullable=True),
        sa.Column("hospital_name", sa.String(), nullable=True),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email"),
    )
    op.create_index("ix_doctors_email", "doctors", ["email"], unique=False)
    op.create_index("ix_doctors_id", "doctors", ["id"], unique=False)

    op.create_table(
        "patients",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("anonymous_code", sa.String(), nullable=True),
        sa.Column("age", sa.Integer(), nullable=True),
        sa.Column("gender", sa.String(), nullable=True),
        sa.Column("weight", sa.Float(), nullable=True),
        sa.Column("height", sa.Float(), nullable=True),
        sa.Column("full_name", sa.String(), nullable=True),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("phone", sa.String(), nullable=True),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("next_of_kin_name", sa.String(), nullable=True),
        sa.Column("next_of_kin_phone", sa.String(), nullable=True),
        sa.Column("hospital_name", sa.String(), nullable=True),
        sa.Column("preferred_language", sa.String(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("anonymous_code"),
    )
    op.create_index("ix_patients_anonymous_code", "patients", ["anonymous_code"], unique=False)
    op.create_index("ix_patients_id", "patients", ["id"], unique=False)

    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("doctor_id", sa.Integer(), nullable=False),
        sa.Column("token", sa.String(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("revoked", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctors.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token"),
    )
    op.create_index("ix_refresh_tokens_doctor_id", "refresh_tokens", ["doctor_id"], unique=False)
    op.create_index("ix_refresh_tokens_id", "refresh_tokens", ["id"], unique=False)
    op.create_index("ix_refresh_tokens_token", "refresh_tokens", ["token"], unique=False)

    op.create_table(
        "triage_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=True),
        sa.Column("visit_id", sa.String(), nullable=True),
        sa.Column("body_region", sa.String(), nullable=True),
        sa.Column("pain_type", sa.String(), nullable=True),
        sa.Column("severity", sa.Integer(), nullable=True),
        sa.Column("heart_rate", sa.Float(), nullable=True),
        sa.Column("spo2", sa.Float(), nullable=True),
        sa.Column("direction", sa.String(), nullable=True),
        sa.Column("depth", sa.String(), nullable=True),
        sa.Column("risk_score", sa.Float(), nullable=True),
        sa.Column("shap_explanation", sa.Text(), nullable=True),
        sa.Column("qr_payload_hash", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("priority", sa.String(), nullable=True),
        sa.Column("actions_taken", sa.Text(), nullable=True),
        sa.Column("clinical_notes", sa.Text(), nullable=True),
        sa.Column("question_answers", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_triage_sessions_body_region", "triage_sessions", ["body_region"], unique=False)
    op.create_index("ix_triage_sessions_id", "triage_sessions", ["id"], unique=False)
    op.create_index("ix_triage_sessions_status", "triage_sessions", ["status"], unique=False)
    op.create_index("ix_triage_sessions_visit_id", "triage_sessions", ["visit_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_triage_sessions_visit_id", table_name="triage_sessions")
    op.drop_index("ix_triage_sessions_status", table_name="triage_sessions")
    op.drop_index("ix_triage_sessions_id", table_name="triage_sessions")
    op.drop_index("ix_triage_sessions_body_region", table_name="triage_sessions")
    op.drop_table("triage_sessions")
    op.drop_index("ix_refresh_tokens_token", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_id", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_doctor_id", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
    op.drop_index("ix_patients_id", table_name="patients")
    op.drop_index("ix_patients_anonymous_code", table_name="patients")
    op.drop_table("patients")
    op.drop_index("ix_doctors_id", table_name="doctors")
    op.drop_index("ix_doctors_email", table_name="doctors")
    op.drop_table("doctors")
