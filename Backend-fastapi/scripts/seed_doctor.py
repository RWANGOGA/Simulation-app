"""
Seed script: creates the default practitioner account so login works on a
fresh database. Previously there was NO way to create a doctor (no
registration endpoint, no seed), which made the whole auth flow unusable.

Credentials come from the environment (SEED_DOCTOR_EMAIL /
SEED_DOCTOR_PASSWORD / SEED_DOCTOR_NAME). Email and password are
REQUIRED — no hardcoded credential defaults live in the codebase.

Idempotent: running it again when the doctor already exists is a no-op.

Usage:
    SEED_DOCTOR_EMAIL=you@hospital.org SEED_DOCTOR_PASSWORD=... python -m scripts.seed_doctor
"""
import os
import sys

from app.core.database import SessionLocal
from app.models.doctor import Doctor
from app.api.v1.endpoints.auth import get_password_hash

DEFAULT_NAME = "Seeded Practitioner"

def run():
    email = os.getenv("SEED_DOCTOR_EMAIL", "").strip().lower()
    password = os.getenv("SEED_DOCTOR_PASSWORD", "")
    full_name = os.getenv("SEED_DOCTOR_NAME", DEFAULT_NAME)

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
            print(f"Doctor '{email}' already exists (id={existing.id}) — nothing to do.")
            return

        doctor = Doctor(
            email=email,
            hashed_password=get_password_hash(password),
            full_name=full_name,
            is_active=True,
        )
        db.add(doctor)
        db.commit()
        print(f"Seeded doctor '{email}' ({full_name}).")
    finally:
        db.close()

if __name__ == "__main__":
    run()
