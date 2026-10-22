from contextlib import asynccontextmanager
from fastapi.responses import JSONResponse
from fastapi_offline import FastAPIOffline
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import text
from app.api.v1.endpoints import auth
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import engine
from app import models  # noqa: F401 registers Patient/TriageSession on Base
from app.models import AuditLog, RequestThrottle


# Tables added after migration 0003. Each is created here with checkfirst so a
# deployment that never runs `alembic upgrade head` still works — neither the
# Dockerfile nor the CI workflow runs it.
#
# Both failures are silent in the worst way, which is why this exists rather
# than a blanket `create_all`:
#   * audit_logs — record_access swallows insert errors by design, so a missing
#     table means "no trail" with nothing in the logs to say so.
#   * request_throttle — the rate limiters treat a broken table as "no rows",
#     so the public intake routes would quietly lose their limit.
#
# Alembic stays the source of truth for everything else; this only ever adds
# these two tables and never alters an existing one.
_RUNTIME_TABLES = (AuditLog, RequestThrottle)


def _ensure_runtime_tables() -> None:
    for model in _RUNTIME_TABLES:
        name = model.__tablename__
        try:
            model.__table__.create(bind=engine, checkfirst=True)
            print(f"[startup] table ready: {name}", flush=True)
        except Exception as exc:  # noqa: BLE001 - never block startup on this
            print(f"[startup] WARNING: table {name} unavailable: {exc}", flush=True)


@asynccontextmanager
async def lifespan(app: FastAPIOffline):
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
    print("[startup] database connected", flush=True)
    _ensure_runtime_tables()
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
        "http://localhost:8003",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8003",
        "https://rwangoga.github.io",
    ]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Trusted host middleware - only allow known hosts
if settings.ENVIRONMENT == "production":
    trusted_hosts = [host.strip() for host in settings.TRUSTED_HOSTS.split(",") if host.strip()]
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=trusted_hosts,
    )

# Request size limiting middleware
@app.middleware("http")
async def limit_request_size(request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > 10 * 1024 * 1024:  # 10MB limit
        return JSONResponse(status_code=413, content={"detail": "Request too large"})
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
