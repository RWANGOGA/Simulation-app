"""
Seed script: creates the default practitioner account so login works on a
fresh database. Previously there was NO way to create a doctor (no
registration endpoint, no seed), which made the whole auth flow unusable.

Credentials come from the environment (SEED_DOCTOR_EMAIL /
SEED_DOCTOR_PASSWORD / SEED_DOCTOR_NAME) with safe-ish local defaults.

Idempotent: running it again when the doctor already exists is a no-op.

Usage:
    python -m scripts.seed_doctor
"""
import os

from app.core.database import SessionLocal
from app.models.doctor import Doctor
from app.api.v1.endpoints.auth import get_password_hash

DEFAULT_EMAIL = "doctor@atomybridge.care"
DEFAULT_PASSWORD = "ChangeMe123!"
DEFAULT_NAME = "Dr. AtomyBridge"

def run():
    email = os.getenv("SEED_DOCTOR_EMAIL", DEFAULT_EMAIL).strip().lower()
    password = os.getenv("SEED_DOCTOR_PASSWORD", DEFAULT_PASSWORD)
    full_name = os.getenv("SEED_DOCTOR_NAME", DEFAULT_NAME)

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
        if email == DEFAULT_EMAIL and password == DEFAULT_PASSWORD:
            print("WARNING: default credentials used — set SEED_DOCTOR_EMAIL / "
                  "SEED_DOCTOR_PASSWORD for anything beyond local development.")
    finally:
        db.close()

if __name__ == "__main__":
    run()
