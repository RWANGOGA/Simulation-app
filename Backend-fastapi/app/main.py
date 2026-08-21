from contextlib import asynccontextmanager
from fastapi_offline import FastAPIOffline
from fastapi.middleware.cors import CORSMiddleware
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import Base, engine
from app import models  # noqa: F401 registers Patient/TriageSession on Base

@asynccontextmanager
async def lifespan(app: FastAPIOffline):
    Base.metadata.create_all(bind=engine)
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

app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/")
def root():
    return {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "docs": "/docs",
        "health": f"{settings.API_V1_STR}/health"
    }
