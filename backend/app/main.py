from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import sys
import os

sys.path.append(os.path.join(
    os.path.dirname(__file__),
    "components",
    "self_bias_identification"
))

from app.database import db

from routes.bias_routes import router as bias_router

app = FastAPI(title="Intelligent Diary API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(
    bias_router,
    prefix="/api/bias",
    tags=["Bias Detection"]
)

@app.get("/")
def root():
    return {"status": "Running"}