# app/services/qr_service.py
import base64
import json
from datetime import datetime
from cryptography.fernet import Fernet
from app.core.config import settings
import hashlib
from app.services.triage_service import risk_level  # Import the risk_level function from triage_service

# settings.QR_SECRET_KEY should be a Fernet key stored in your .env
# generate one with: Fernet.generate_key().decode()
_fernet = Fernet(settings.QR_SECRET_KEY.encode())



def generate_qr_payload(triage_session) -> str:
    """Builds and encrypts the compact passport payload for a triage session."""
    payload = {
        "patient_id": triage_session.patient.anonymous_code,  
        "triage_id": triage_session.id,
        "risk_score": triage_session.risk_score,
        "priority": risk_level(triage_session.risk_score).capitalize(),
        "created_at": triage_session.created_at.isoformat(),
    }
    #generate_qr_payload gives the string to send to the flutter app
    raw = json.dumps(payload, separators=(",", ":")).encode()
    encrypted = _fernet.encrypt(raw)
    return base64.urlsafe_b64encode(encrypted).decode()

def hash_qr_payload(qr_data: str) -> str:
    """SHA-256 fingerprint of the QR string, safe to store in the DB for verification."""
    return hashlib.sha256(qr_data.encode()).hexdigest()
#hash_qr_payload gives what gets written to triage_session.qr_hash in the DB, so we can verify the QR string later without storing the sensitive string.

def decode_qr_payload(qr_string: str) -> dict:
    """Decrypts a scanned QR string back into readable triage data.
    Used by the practitioner web dashboard's scan endpoint."""
    encrypted = base64.urlsafe_b64decode(qr_string.encode())
    raw = _fernet.decrypt(encrypted)
    return json.loads(raw)