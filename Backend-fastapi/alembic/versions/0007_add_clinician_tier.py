"""Add clinician_tier to triage_sessions.

The practitioner's own triage category, recorded on the same four SATS categories
the engine derives (app/services/triage_service.py::triage_tier). Until now the
review workflow stored only free-text `priority`, so the system held no reference
standard: no agreement between the tool and a clinician could be computed from
product data, only from a spreadsheet someone kept beside it.

Nullable and never backfilled. A value here is a human's judgement, so inventing
one for historical rows would put words in a clinician's mouth - and would be the
same mistake as recomputing a stored score when a rule changes.

Revision ID: 0007_add_clinician_tier
Revises: b84cd4531bab
Create Date: 2026-11-04
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "0007_add_clinician_tier"
down_revision: Union[str, Sequence[str], None] = "b84cd4531bab"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "triage_sessions",
        sa.Column("clinician_tier", sa.String(), nullable=True),
    )


def downgrade() -> None:
    # Every recorded clinician judgement is deleted by this, which is the point of
    # writing it down in the file: a downgrade is not reversible for the data the
    # evaluation depends on.
    op.drop_column("triage_sessions", "clinician_tier")
