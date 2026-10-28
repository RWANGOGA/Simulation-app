import logging
import re
from contextlib import asynccontextmanager
from fastapi.responses import JSONResponse
from fastapi_offline import FastAPIOffline
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import inspect, text
from app.api.v1.endpoints import auth
from app.api.v1.router import api_router
from app.core.config import settings, warn_on_insecure_defaults
from app.core.database import Base, engine
from app.core.logging import configure_logging
from app.core.observability import RequestContextMiddleware
from app import models  # noqa: F401 registers Patient/TriageSession on Base
from app.models import AuditLog, RequestThrottle

# Before anything else logs. Every module calls logging.getLogger(__name__), but
# until this ran there was no handler on the root logger, so INFO lines were
# discarded and the only output was a few print() calls below.
configure_logging(level=settings.LOG_LEVEL, format=settings.LOG_FORMAT)
logger = logging.getLogger(__name__)


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
# Alembic stays the source of truth for everything else. This adds tables only;
# columns are handled separately by `_adopt_missing_columns` below.
_RUNTIME_TABLES = (AuditLog, RequestThrottle)


def _ensure_runtime_tables() -> None:
    for model in _RUNTIME_TABLES:
        name = model.__tablename__
        try:
            model.__table__.create(bind=engine, checkfirst=True)
            logger.info("table_ready", extra={"table": name})
        except Exception as exc:  # noqa: BLE001 - never block startup on this
            logger.warning(
                "table_unavailable", extra={"table": name, "error": str(exc)}
            )


def _adopt_missing_columns() -> None:
    """Add nullable columns the ORM declares that the live table lacks.

    Same reason `_ensure_runtime_tables` exists, one level down. The container
    entrypoint runs `alembic upgrade head`, but a host that starts the app with
    its own command never executes that entrypoint, so a database can sit at an
    old schema forever while the code moves on.

    That gap is not theoretical. `triage_sessions.clinician_tier` (migration
    0007) never reached the deployed database, so every triage INSERT named a
    column that did not exist. The server answered 500, and because Starlette
    builds a 500 outside CORSMiddleware, no CORS header came back with it - the
    browser reported a CORS failure and the real cause stayed invisible.

    A missing *table* can be created from the model directly; a missing *column*
    cannot be fixed by replaying migrations either, because the chain starts
    with a plain `CREATE TABLE` that fails on a database which already has the
    tables. So the schema is reconciled here instead.

    Restricted to nullable columns deliberately: a NOT NULL column cannot be
    added to a populated table without deciding what the existing rows should
    hold, which is a judgement call for a migration rather than for startup.
    """
    inspector = inspect(engine)
    present_tables = set(inspector.get_table_names())
    for table in Base.metadata.sorted_tables:
        if table.name not in present_tables:
            continue
        present_columns = {
            column["name"] for column in inspector.get_columns(table.name)
        }
        for column in table.columns:
            if column.name in present_columns or not column.nullable:
                continue
            column_type = column.type.compile(dialect=engine.dialect)
            with engine.begin() as connection:
                connection.execute(
                    text(
                        f'ALTER TABLE "{table.name}" '
                        f'ADD COLUMN IF NOT EXISTS "{column.name}" {column_type}'
                    )
                )
            # WARNING, not INFO: reaching this line means the deployed schema
            # was behind the code, which is a deployment mistake worth seeing.
            logger.warning(
                "column_adopted",
                extra={"table": table.name, "column": column.name},
            )


@asynccontextmanager
async def lifespan(app: FastAPIOffline):
    warn_on_insecure_defaults()
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
    logger.info(
        "startup",
        extra={"version": settings.VERSION, "environment": settings.ENVIRONMENT},
    )
    _ensure_runtime_tables()
    _adopt_missing_columns()
    yield
    logger.info("shutdown")

app = FastAPIOffline(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    openapi_url=None if settings.ENVIRONMENT == "production" else f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan,
    docs_url=None if settings.ENVIRONMENT == "production" else "/docs",
    redoc_url=None if settings.ENVIRONMENT == "production" else "/redoc",
)

# ── Global exception handler ────────────────────────────────────────────
# When FastAPI raises an unhandled 500, CORSMiddleware never attaches its
# headers — the browser reports "CORS error" and hides the real problem.
# This handler catches everything the route/dependency layer doesn't and
# returns a JSON 500. Starlette keeps ServerErrorMiddleware outside the user
# middleware stack, so CORSMiddleware never sees that response and would leave
# it unreadable from JavaScript - the headers are attached here by hand.
_LOCAL_ORIGIN_PATTERN = r"https?://(localhost|127\.0\.0\.1)(:\d+)?$"
_LOCAL_ORIGIN = re.compile(_LOCAL_ORIGIN_PATTERN)


@app.exception_handler(Exception)
async def _unhandled_exception_handler(request, exc):
    logger.exception("unhandled_error: %s", exc)
    response = JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )
    # Attached by hand for the reason above. Without it the browser reports a
    # CORS failure and the 500 that actually happened stays invisible - which is
    # exactly how a missing column masqueraded as a CORS misconfiguration.
    origin = request.headers.get("origin")
    if origin and (origin in origins or _LOCAL_ORIGIN.match(origin)):
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["Vary"] = "Origin"
    return response

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

# ── Middleware registration order ────────────────────────────────────────
# Starlette inserts each add_middleware() at the FRONT of the stack, so
# the LAST call becomes the outermost layer.
#
# Desired execution order (outermost → innermost):
#   RequestContextMiddleware → CORSMiddleware → TrustedHostMiddleware → app
#
# CORS must wrap TrustedHost: a browser preflight (OPTIONS) that hits
# TrustedHost first would be rejected without CORS headers, making the
# real error invisible to JavaScript.

# Trusted host middleware - only allow known hosts (innermost of the three)
if settings.ENVIRONMENT == "production":
    trusted_hosts = [host.strip() for host in settings.TRUSTED_HOSTS.split(",") if host.strip()]
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=trusted_hosts,
    )

# CORS middleware (wraps TrustedHost so errors from it still carry CORS headers)
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=_LOCAL_ORIGIN_PATTERN,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request size limiting middleware
@app.middleware("http")
async def limit_request_size(request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > 10 * 1024 * 1024:  # 10MB limit
        return JSONResponse(status_code=413, content={"detail": "Request too large"})
    return await call_next(request)

# Registered last on purpose: Starlette inserts each new middleware at the front
# of the stack, so this becomes the outermost one. That matters — a 413 from the
# size limiter above still has to carry X-Request-ID, and the id has to exist
# before any other middleware logs.
app.add_middleware(RequestContextMiddleware)

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
