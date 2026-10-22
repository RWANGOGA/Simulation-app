from datetime import datetime, timedelta, date, timezone
import logging
import re
import secrets
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
import bcrypt
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.core.config import settings
from app.core.database import get_db
from app.models.doctor import Doctor
from app.models.refresh_token import RefreshToken
from app.schemas.doctor import DoctorResponse, DoctorUpdate
from app.services import throttle

logger = logging.getLogger(__name__)

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = 7

# A refresh token is single-use: presenting one rotates it. The consumed token
# stays usable for this long afterwards so a client whose response was lost (a
# mobile network dropping mid-refresh) can simply retry instead of being signed
# out mid-shift. Past the window, presenting a consumed token means it leaked.
REFRESH_ROTATION_GRACE_SECONDS = 60

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

router = APIRouter(prefix="/auth", tags=["authentication"])

class Token(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str

class DoctorCreate(BaseModel):
    email: str
    password: str
    full_name: str
    # Professional context — stored for audit/clinical display, self-declared.
    role: Optional[str] = None
    license_number: Optional[str] = None
    phone: Optional[str] = None
    hospital_name: Optional[str] = None
    date_of_birth: Optional[date] = None
    # Required only once settings.INVITE_CODE is set — see register_doctor.
    invite_code: Optional[str] = None

def _is_valid_email(value: str) -> bool:
    if " " in value:
        return False
    local, sep, domain = value.partition("@")
    if not sep or not local or not domain:
        return False
    if "." not in domain:
        return False
    if domain.startswith(".") or domain.endswith(".") or ".." in domain:
        return False
    return True

def verify_password(plain_password: str, hashed_password: str) -> bool:
    password_byte_enc = plain_password.encode('utf-8')
    hashed_password_byte_enc = hashed_password.encode('utf-8')
    return bcrypt.checkpw(password=password_byte_enc, hashed_password=hashed_password_byte_enc)

def get_password_hash(password: str) -> str:
    pwd_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed_password = bcrypt.hashpw(password=pwd_bytes, salt=salt)
    return hashed_password.decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_current_doctor(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> Doctor:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        sub = payload.get("sub")
        if sub is None:
            raise credentials_exception
        doctor_id = int(sub)
    except (JWTError, ValueError):
        raise credentials_exception
        
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if doctor is None or not doctor.is_active:
        raise credentials_exception
    return doctor

# Failed-login lockout. Held in the request_throttle table, not a module-level
# dict: a process-local counter reset on every deploy and was blind to sibling
# workers, so an attacker who could force a restart (or land on a fresh worker)
# got unlimited guesses.
LOGIN_BUCKET_PREFIX = "login"

def _login_bucket(key: str) -> str:
    return f"{LOGIN_BUCKET_PREFIX}:{key}"

def _check_rate_limit(key: str, db: Session):
    attempts = throttle.count(
        db, _login_bucket(key), settings.LOGIN_LOCKOUT_SECONDS
    )
    if attempts >= settings.MAX_LOGIN_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed login attempts. Please try again later.",
            headers={"Retry-After": str(settings.LOGIN_LOCKOUT_SECONDS)},
        )

def _record_failed_attempt(key: str, db: Session):
    throttle.record(db, _login_bucket(key))

def _clear_failed_attempts(key: str, db: Session):
    throttle.clear(db, _login_bucket(key))

@router.post("/login", response_model=Token)
def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    email = (form_data.username or "").strip().lower()
    _check_rate_limit(email, db)

    doctor = db.query(Doctor).filter(Doctor.email == email).first()
    
    if (
        not doctor
        or not doctor.is_active
        or not verify_password(form_data.password or "", doctor.hashed_password)
    ):
        _record_failed_attempt(email, db)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    _clear_failed_attempts(email, db)
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(doctor.id)}, expires_delta=access_token_expires
    )

    # Same helper /refresh uses, so a token minted here and one minted by
    # rotation are indistinguishable in shape and defaults.
    refresh_token_raw = _issue_refresh_token(db, doctor.id)
    db.commit()

    return {"access_token": access_token, "refresh_token": refresh_token_raw, "token_type": "bearer"}


async def _refresh_token_from_body(request: Request) -> Optional[str]:
    """Reads `refresh_token` from a JSON or urlencoded request body.

    Returns None when the body carries no such field or cannot be parsed —
    the caller turns that into a 401 rather than a 422, so a client that
    forgot the token gets the same "invalid or expired" answer as one that
    sent a bad token.
    """
    try:
        if "application/json" in request.headers.get("content-type", ""):
            payload = await request.json()
            if isinstance(payload, dict):
                value = payload.get("refresh_token")
                return value if isinstance(value, str) else None
        form = await request.form()
        value = form.get("refresh_token")
        return value if isinstance(value, str) else None
    except Exception:
        return None


def _issue_refresh_token(db: Session, doctor_id: int) -> str:
    """Mints and stages a new refresh token for this doctor."""
    raw = secrets.token_urlsafe(32)
    db.add(
        RefreshToken(
            doctor_id=doctor_id,
            token=raw,
            expires_at=datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
            revoked="false",
        )
    )
    return raw


# Prefix marking a revocation that must never be retried. A bare ISO stamp
# means "consumed by rotation" (retryable inside the grace window); this
# prefixed form means "this session was deliberately ended", and it fails
# parsing in _revoked_seconds_ago, which is what makes it immediately fatal.
REVOKED_HARD_PREFIX = "revoked:"


def _revocation_stamp(hard: bool = False) -> str:
    moment = datetime.now(timezone.utc).isoformat()
    return f"{REVOKED_HARD_PREFIX}{moment}" if hard else moment


def _revoked_seconds_ago(stored: RefreshToken) -> float:
    """How long ago this token was consumed.

    ``revoked`` holds either the literal "false", the ISO-8601 moment the
    token was rotated, or a hard ``revoked:<iso>`` stamp — which is what
    gives rotation-decay without adding a column. Anything that is not a
    bare ISO instant (a hard stamp, or a legacy bare "true") is treated as
    infinitely long ago, so it can never be replayed.
    """
    try:
        moment = datetime.fromisoformat(stored.revoked)
    except (TypeError, ValueError):
        return float("inf")
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - moment).total_seconds()


def _revoke_all_tokens_for(db: Session, doctor_id: int) -> int:
    """Kills every live refresh token for a doctor.

    Used when a consumed token is presented long after it was rotated: at
    that point we cannot tell which holder was the legitimate client, so
    both are signed out rather than letting an attacker keep a session.
    Hard stamps, because these revocations must not be retryable.
    """
    live = db.query(RefreshToken).filter(
        RefreshToken.doctor_id == doctor_id, RefreshToken.revoked == "false"
    ).all()
    stamp = _revocation_stamp(hard=True)
    for row in live:
        row.revoked = stamp
    return len(live)


@router.post("/refresh", response_model=Token)
async def refresh_access_token(
    request: Request,
    refresh_token: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """Exchanges a refresh token for a fresh access token and a new refresh token.

    The Flutter client posts the token as a form field (the same urlencoded
    shape /login uses) while curl and the test-suite pass it as a query
    parameter, so both are accepted here. Without the body path the mobile
    app could never actually refresh — its POST carried the token in a body
    this endpoint never looked at, which made every session die silently.

    Rotation: the presented token is consumed and replaced, so a stolen
    token is only useful until the real client next refreshes. Replaying a
    consumed token is treated as a leak and ends the whole session.
    """
    token = refresh_token or await _refresh_token_from_body(request)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A refresh token is required",
        )

    stored = db.query(RefreshToken).filter(RefreshToken.token == token).first()
    if not stored:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    if stored.revoked != "false":
        revoked_ago = _revoked_seconds_ago(stored)
        if revoked_ago > REFRESH_ROTATION_GRACE_SECONDS:
            killed = _revoke_all_tokens_for(db, stored.doctor_id)
            db.commit()
            logger.warning(
                "refresh token reuse detected for doctor %s; revoked %s live token(s)",
                stored.doctor_id,
                killed,
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="This session was ended for security reasons. Please sign in again.",
            )
        # Inside the grace window: almost certainly the client retrying after
        # a lost response, so fall through and rotate again.
    elif datetime.now(timezone.utc) >= stored.expires_at:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    doctor = db.query(Doctor).filter(Doctor.id == stored.doctor_id).first()
    if doctor is None or not doctor.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(stored.doctor_id)}, expires_delta=access_token_expires
    )

    # Consume the presented token and hand back its replacement.
    stored.revoked = _revocation_stamp()
    rotated_token = _issue_refresh_token(db, stored.doctor_id)
    db.commit()

    return {
        "access_token": access_token,
        "refresh_token": rotated_token,
        "token_type": "bearer",
    }


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    request: Request,
    refresh_token: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """Ends the session this refresh token belongs to.

    Accepts the token as a query parameter or in the request body, for the
    same reason /refresh does: without the body path a client that posts it
    urlencoded is silently logged out of nothing, and the endpoint still
    answers 204, which is the worst possible failure mode for logout.

    Idempotent and silent: an unknown or already-revoked token is not an
    error, because a client must be able to log out from a stale session.
    """
    token = refresh_token or await _refresh_token_from_body(request)
    if token:
        stored = db.query(RefreshToken).filter(RefreshToken.token == token).first()
        if stored and stored.revoked == "false":
            # Hard stamp: a logged-out token must be dead immediately, not
            # merely retryable for the rotation grace window.
            stored.revoked = _revocation_stamp(hard=True)
            db.commit()
    return None

@router.post("/register", response_model=DoctorResponse, status_code=status.HTTP_201_CREATED)
def register_doctor(payload: DoctorCreate, db: Session = Depends(get_db)):
    """
    Creates a practitioner account. Previously there was no way to create
    a doctor at all (no endpoint, no seed script), so login could never
    succeed on a fresh database.
    NOTE: registration is open by design for this deployment — gate it
    (invite code / admin-only) before any production use.
    """
    if settings.INVITE_CODE and payload.invite_code != settings.INVITE_CODE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid or missing invite code",
        )
    email = payload.email.strip().lower()
    full_name = payload.full_name.strip()
    if not _is_valid_email(email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Enter a valid email address",
        )
    if not full_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Full name is required",
        )
    password = payload.password
    if len(password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 8 characters long",
        )
    if not re.search(r"[A-Z]", password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one uppercase letter",
        )
    if not re.search(r"[a-z]", password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one lowercase letter",
        )
    if not re.search(r"\d", password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one number",
        )
    if not re.search(r"[!@#$%^&*()_+\-=\[\]{};':\"\\|,.<>\/?]", password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one special character (!@#$%^&*()_+-=[]{};':\"|,.<>/? )",
        )
    existing_email = db.query(Doctor).filter(Doctor.email == email).first()
    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A practitioner with this email address already exists. Please use a different email.",
        )
    phone = (payload.phone or "").strip() or None
    if phone:
        existing_phone = db.query(Doctor).filter(Doctor.phone == phone).first()
        if existing_phone:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="A practitioner with this phone number already exists. Please use a different phone number.",
            )
    doctor = Doctor(
        email=email,
        hashed_password=get_password_hash(password),
        full_name=full_name,
        role=(payload.role or "").strip() or None,
        license_number=(payload.license_number or "").strip() or None,
        phone=phone,
        hospital_name=(payload.hospital_name or "").strip() or None,
        date_of_birth=payload.date_of_birth,
        is_active=True,
    )
    db.add(doctor)
    db.commit()
    db.refresh(doctor)
    return doctor

@router.get("/me", response_model=DoctorResponse)
def read_users_me(current_doctor: Doctor = Depends(get_current_doctor)):
    return current_doctor

@router.patch("/me", response_model=DoctorResponse)
def update_users_me(payload: DoctorUpdate, current_doctor: Doctor = Depends(get_current_doctor), db: Session = Depends(get_db)):
    if payload.full_name is not None:
        name = payload.full_name.strip()
        if not name:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Full name is required",
            )
        current_doctor.full_name = name
    if payload.role is not None:
        current_doctor.role = payload.role.strip() or None
    if payload.license_number is not None:
        current_doctor.license_number = payload.license_number.strip() or None
    if payload.phone is not None:
        new_phone = payload.phone.strip() or None
        if new_phone and new_phone != current_doctor.phone:
            existing_phone = db.query(Doctor).filter(Doctor.phone == new_phone, Doctor.id != current_doctor.id).first()
            if existing_phone:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="A practitioner with this phone number already exists. Please use a different phone number.",
                )
        current_doctor.phone = new_phone
    if payload.hospital_name is not None:
        current_doctor.hospital_name = payload.hospital_name.strip() or None
    if payload.date_of_birth is not None:
        current_doctor.date_of_birth = payload.date_of_birth
    db.commit()
    db.refresh(current_doctor)
    return current_doctor
