from .patient import Patient
from .triage import TriageSession  # (or whatever your triage model file is named)
from .doctor import Doctor         # <-- ADD THIS LINE
from .refresh_token import RefreshToken

# This ensures all models are loaded when the app starts
__all__ = ["Patient", "TriageSession", "Doctor", "RefreshToken"]