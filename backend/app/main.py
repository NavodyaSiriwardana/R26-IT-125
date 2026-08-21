from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.task_routes import router as task_router


app = FastAPI(
    title="Intelligent Diary API",
    version="1.0.0",
)


# Development configuration for Flutter Web and mobile testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {
        "application": "Intelligent Diary API",
        "status": "running",
    }


@app.get("/health")
def health():
    return {"status": "healthy"}


app.include_router(task_router)