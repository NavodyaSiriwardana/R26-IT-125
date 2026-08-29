from fastapi import APIRouter
from app.components.temporal_causal_patterns.router import router as temporal_patterns_router

api_router = APIRouter()
api_router.include_router(temporal_patterns_router)