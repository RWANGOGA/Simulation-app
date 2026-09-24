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

@asynccontextmanager
async def lifespan(app: FastAPIOffline):
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
    print("[startup] database connected", flush=True)
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
