"""
Seed script: creates the default practitioner account so login works on a
fresh database.

Credentials come from the environment (SEED_DOCTOR_EMAIL /
SEED_DOCTOR_PASSWORD / SEED_DOCTOR_NAME). Email and password are
REQUIRED — no hardcoded credential defaults live in the codebase.

The account is created **approved and as an administrator**, because this
script exists to bootstrap a database that has no accounts at all. An account
that is merely "in the table" cannot sign in: `is_approved` now defaults to
false and `/auth/login` refuses an unapproved account with a 403, and a
practitioner-level account cannot approve the next person either — so seeding
an unapproved practitioner produced a deployment where nobody could get in and
nobody could let anyone in. This mirrors what `POST /auth/register` already
does for the first account it ever creates; the CLI is the same bootstrap by a
different route, and an operator running it has database access anyway.

Idempotent: running it again when the doctor already exists is a no-op unless
SEED_DOCTOR_PROMOTE=1, which approves an existing account and makes it an
administrator. That flag is off by default because silently promoting an
existing real account would be a surprising way to grant admin.

Usage:
    SEED_DOCTOR_EMAIL=you@hospital.org SEED_DOCTOR_PASSWORD=... python -m scripts.seed_doctor

    # Repair an account that was seeded before the approval gate existed:
    SEED_DOCTOR_EMAIL=... SEED_DOCTOR_PASSWORD=... SEED_DOCTOR_PROMOTE=1 \
        python -m scripts.seed_doctor
"""
import os
import sys

from app.core.database import SessionLocal
from app.models.doctor import ACCESS_ADMIN, Doctor
from app.api.v1.endpoints.auth import get_password_hash

DEFAULT_NAME = "Seeded Practitioner"


def run():
    email = os.getenv("SEED_DOCTOR_EMAIL", "").strip().lower()
    password = os.getenv("SEED_DOCTOR_PASSWORD", "")
    full_name = os.getenv("SEED_DOCTOR_NAME", DEFAULT_NAME)
    promote = os.getenv("SEED_DOCTOR_PROMOTE", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }

    if not email or not password:
        print(
            "ERROR: SEED_DOCTOR_EMAIL and SEED_DOCTOR_PASSWORD must be set "
            "in the environment — credentials are never hardcoded."
        )
        sys.exit(1)

    db = SessionLocal()
    try:
        existing = db.query(Doctor).filter(Doctor.email == email).first()
        if existing:
            can_sign_in = existing.is_active and existing.is_approved
            if can_sign_in and existing.is_admin:
                print(f"Doctor '{email}' already exists (id={existing.id}) — nothing to do.")
                return
            if not promote:
                # Report precisely what is wrong, so the operator is not left
                # guessing why a seeded account cannot log in.
                print(
                    f"Doctor '{email}' already exists (id={existing.id}) but "
                    f"active={existing.is_active}, approved={existing.is_approved}, "
                    f"access_level={existing.access_level}."
                )
                print(
                    "Set SEED_DOCTOR_PROMOTE=1 to approve this account and make it "
                    "an administrator."
                )
                return
            existing.is_active = True
            existing.is_approved = True
            existing.access_level = ACCESS_ADMIN
            db.commit()
            print(
                f"Promoted existing doctor '{email}' (id={existing.id}) to an "
                "approved administrator."
            )
            return

        doctor = Doctor(
            email=email,
            hashed_password=get_password_hash(password),
            full_name=full_name,
            is_active=True,
            is_approved=True,
            access_level=ACCESS_ADMIN,
        )
        db.add(doctor)
        db.commit()
        print(f"Seeded doctor '{email}' ({full_name}) as an approved administrator.")
    finally:
        db.close()


if __name__ == "__main__":
    run()
