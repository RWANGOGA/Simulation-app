from datetime import datetime, timedelta, date, timezone
import re
import secrets
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
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

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = 7

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
    if doctor is None:
        raise credentials_exception
    return doctor

_failed_login_attempts: dict[str, list[datetime]] = {}

def _check_rate_limit(key: str):
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(seconds=settings.LOGIN_LOCKOUT_SECONDS)
    attempts = [t for t in _failed_login_attempts.get(key, []) if t > cutoff]
    _failed_login_attempts[key] = attempts
    if len(attempts) >= settings.MAX_LOGIN_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed login attempts. Please try again later.",
        )

def _record_failed_attempt(key: str):
    now = datetime.now(timezone.utc)
    _failed_login_attempts.setdefault(key, []).append(now)

def _clear_failed_attempts(key: str):
    _failed_login_attempts.pop(key, None)

@router.post("/login", response_model=Token)
def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    email = (form_data.username or "").strip().lower()
    _check_rate_limit(email)

    doctor = db.query(Doctor).filter(Doctor.email == email).first()
    
    if not doctor or not verify_password(form_data.password or "", doctor.hashed_password):
        _record_failed_attempt(email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    _clear_failed_attempts(email)
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(doctor.id)}, expires_delta=access_token_expires
    )
    
    refresh_token_expires = timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    refresh_token_raw = secrets.token_urlsafe(32)
    refresh_token = create_access_token(
        data={"sub": str(doctor.id), "type": "refresh"},
        expires_delta=refresh_token_expires,
    )
    
    db_refresh = RefreshToken(
        doctor_id=doctor.id,
        token=refresh_token_raw,
        expires_at=datetime.now(timezone.utc) + refresh_token_expires,
    )
    db.add(db_refresh)
    db.commit()
    
    return {"access_token": access_token, "refresh_token": refresh_token_raw, "token_type": "bearer"}


@router.post("/refresh", response_model=Token)
def refresh_access_token(refresh_token: str, db: Session = Depends(get_db)):
    stored = db.query(RefreshToken).filter(RefreshToken.token == refresh_token).first()
    if not stored or not stored.is_valid():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )
    
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(stored.doctor_id)}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(refresh_token: Optional[str] = None, db: Session = Depends(get_db)):
    if refresh_token:
        stored = db.query(RefreshToken).filter(RefreshToken.token == refresh_token).first()
        if stored:
            stored.revoked = "true"
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
    if len(password) < 12 or len(password) > 128:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be between 12 and 128 characters",
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
    existing = db.query(Doctor).filter(Doctor.email == email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A doctor with this email already exists",
        )
    doctor = Doctor(
        email=email,
        hashed_password=get_password_hash(password),
        full_name=full_name,
        role=(payload.role or "").strip() or None,
        license_number=(payload.license_number or "").strip() or None,
        phone=(payload.phone or "").strip() or None,
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
        current_doctor.phone = payload.phone.strip() or None
    if payload.hospital_name is not None:
        current_doctor.hospital_name = payload.hospital_name.strip() or None
    if payload.date_of_birth is not None:
        current_doctor.date_of_birth = payload.date_of_birth
    db.commit()
    db.refresh(current_doctor)
    return current_doctor
