import re
from contextlib import asynccontextmanager
from fastapi_offline import FastAPIOffline
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import text
from sqlalchemy.engine.url import make_url
from app.api.v1.endpoints import auth
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import Base, engine
from app import models  # noqa: F401 registers Patient/TriageSession on Base

# Schema drift fixes. Base.metadata.create_all() never ALTERs existing
# tables and this project has no Alembic, so columns added to models after
# a table was first created must be reconciled here. Every statement is
# guarded by IF NOT EXISTS so it is safe to run on every startup.
_SCHEMA_DRIFT_STATEMENTS = [
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS visit_id VARCHAR",
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS spo2 FLOAT",
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS status VARCHAR DEFAULT 'open'",
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS priority VARCHAR",
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS actions_taken TEXT",
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS clinical_notes TEXT",
    "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS question_answers JSONB",
    "CREATE INDEX IF NOT EXISTS ix_triage_sessions_visit_id "
    "ON triage_sessions (visit_id)",
    "ALTER TABLE doctors ADD COLUMN IF NOT EXISTS role VARCHAR",
    "ALTER TABLE doctors ADD COLUMN IF NOT EXISTS license_number VARCHAR",
    "ALTER TABLE doctors ADD COLUMN IF NOT EXISTS phone VARCHAR",
    "ALTER TABLE doctors ADD COLUMN IF NOT EXISTS hospital_name VARCHAR",
    "ALTER TABLE doctors ADD COLUMN IF NOT EXISTS date_of_birth DATE",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS full_name VARCHAR",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS date_of_birth DATE",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS phone VARCHAR",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS address TEXT",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS next_of_kin_name VARCHAR",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS next_of_kin_phone VARCHAR",
    "ALTER TABLE patients ADD COLUMN IF NOT EXISTS hospital_name VARCHAR",
]

@asynccontextmanager
async def lifespan(app: FastAPIOffline):
    # Which database did we actually connect to? Env-var DATABASE_URL (Render
    # injects the Neon URL) always beats the local .env (Docker Postgres),
    # so this line makes the active environment obvious in the logs.
    _db = make_url(settings.DATABASE_URL)
    print(f"[startup] database connected", flush=True)
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        for stmt in _SCHEMA_DRIFT_STATEMENTS:
            conn.execute(text(stmt))
    yield

app = FastAPIOffline(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    openapi_url=None if settings.ENVIRONMENT == "production" else f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan,
    docs_url=None if settings.ENVIRONMENT == "production" else "/docs",
    redoc_url=None if settings.ENVIRONMENT == "production" else "/redoc",
)

@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response

origins = [o.strip() for o in settings.ALLOWED_ORIGINS.split(",") if o.strip()]
if not origins:
    origins = [
        "http://localhost:3000",
        "http://localhost:8000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8000",
        "https://rwangoga.github.io",
    ]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_func=lambda origin: origin in origins or bool(re.match(r"https://.*\.github\.io", origin)),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Trusted host middleware - only allow known hosts
if settings.ENVIRONMENT == "production":
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=["atomybridge.com", "*.atomybridge.com", "api.atomybridge.com"],
    )

# Request size limiting middleware
@app.middleware("http")
async def limit_request_size(request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > 10 * 1024 * 1024:  # 10MB limit
        raise HTTPException(status_code=413, detail="Request too large")
    return await call_next(request)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/")
def root():
    return {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "docs": "/docs",
        "health": f"{settings.API_V1_STR}/health"
    }
