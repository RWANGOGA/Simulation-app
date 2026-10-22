"""Add doctor access levels and the account-approval gate.

Revision ID: 0006_add_doctor_roles
Revises: 0005_add_request_throttle
Create Date: 2026-10-22

Registration was open and unconditional: anyone who could reach the endpoint
became a doctor with `is_active = true`, and a doctor could read every
patient's clinical record and full identity. Signing up proves you own an
email address, not that you should see somebody's chart.

Two columns fix that:

* ``is_approved`` — new accounts start false and cannot obtain a token until
  an admin approves them. **Existing rows are set to true**, because they
  already have access; shipping a security fix must not lock out the people
  currently using the system.
* ``access_level`` — 'practitioner' or 'admin'. Only admins approve accounts
  and read the audit trail.

The promotion of one existing account to admin is a bootstrap: without it the
deployment would have nobody able to approve anyone, which is a worse outcome
than the hole being closed. It targets the earliest-created account, on the
assumption that it is the one the team set up first. If that is the wrong
account, change it directly:

    UPDATE doctors SET access_level = 'admin' WHERE email = '...';
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0006_add_doctor_roles"
down_revision: Union[str, Sequence[str], None] = "0005_add_request_throttle"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "doctors",
        sa.Column(
            "is_approved",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column(
        "doctors",
        sa.Column(
            "access_level",
            sa.String(),
            nullable=False,
            server_default=sa.text("'practitioner'"),
        ),
    )
    op.create_index(
        "ix_doctors_access_level", "doctors", ["access_level"], unique=False
    )

    # Grandfather every account that exists today.
    op.execute("UPDATE doctors SET is_approved = true")

    # Bootstrap exactly one approver, so the deployment is not deadlocked.
    op.execute(
        """
        UPDATE doctors
           SET access_level = 'admin'
         WHERE id = (SELECT id FROM doctors ORDER BY created_at ASC NULLS LAST, id ASC LIMIT 1)
        """
    )


def downgrade() -> None:
    op.drop_index("ix_doctors_access_level", table_name="doctors")
    op.drop_column("doctors", "access_level")
    op.drop_column("doctors", "is_approved")
