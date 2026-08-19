from fastapi import APIRouter
from app.api.v1.endpoints import health, patients, triage

api_router = APIRouter()
api_router.include_router(health.router, tags=["health"])
api_router.include_router(patients.router)
api_router.include_router(triage.router)
