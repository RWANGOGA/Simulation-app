"""Add the database-backed request throttle.

Revision ID: 0005_add_request_throttle
Revises: 0004_add_audit_log
Create Date: 2026-10-22

Replaces the in-process rate-limit dicts. Those were per-worker and reset on
every deploy, so the effective limit scaled with the worker count and a
restart cleared an attacker's history.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0005_add_request_throttle"
down_revision: Union[str, Sequence[str], None] = "0004_add_audit_log"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "request_throttle",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("bucket", sa.String(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_request_throttle_id", "request_throttle", ["id"], unique=False)
    op.create_index(
        "ix_request_throttle_bucket", "request_throttle", ["bucket"], unique=False
    )
    op.create_index(
        "ix_request_throttle_created_at", "request_throttle", ["created_at"], unique=False
    )
    op.create_index(
        "ix_request_throttle_bucket_created_at",
        "request_throttle",
        ["bucket", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_request_throttle_bucket_created_at", table_name="request_throttle")
    op.drop_index("ix_request_throttle_created_at", table_name="request_throttle")
    op.drop_index("ix_request_throttle_bucket", table_name="request_throttle")
    op.drop_index("ix_request_throttle_id", table_name="request_throttle")
    op.drop_table("request_throttle")
