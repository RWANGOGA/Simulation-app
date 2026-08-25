from contextlib import asynccontextmanager
from fastapi_offline import FastAPIOffline
from fastapi.middleware.cors import CORSMiddleware
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
    "CREATE INDEX IF NOT EXISTS ix_triage_sessions_visit_id "
    "ON triage_sessions (visit_id)",
]

@asynccontextmanager
async def lifespan(app: FastAPIOffline):
    # Which database did we actually connect to? Env-var DATABASE_URL (Render
    # injects the Neon URL) always beats the local .env (Docker Postgres),
    # so this line makes the active environment obvious in the logs.
    _db = make_url(settings.DATABASE_URL)
    print(f"[startup] database host={_db.host} db={_db.database}", flush=True)
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        for stmt in _SCHEMA_DRIFT_STATEMENTS:
            conn.execute(text(stmt))
    yield

app = FastAPIOffline(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
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
