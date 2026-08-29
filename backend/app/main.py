from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import neo4j_conn


from app.routes.task_routes import router as task_router
from app.firebase.firebase_client import initialize_firebase
from app.components.temporal_causal_patterns.graph_builder import graph_builder
from app.routes import api_router

@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_firebase()
    yield


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
    lifespan=lifespan,
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
# ─────────────────────────────────────────────
# STARTUP EVENT
# ─────────────────────────────────────────────

@app.on_event("startup")
async def startup_event():
    # Verify Neo4j connection
    neo4j_conn.verify_connection()

    # Create constraints and indexes
    graph_builder.setup_schema()

    print(f"[App] {settings.APP_NAME} started successfully")


# ─────────────────────────────────────────────
# SHUTDOWN EVENT
# ─────────────────────────────────────────────

@app.on_event("shutdown")
async def shutdown_event():
    neo4j_conn.close()
    print("[App] Neo4j connection closed")


# ─────────────────────────────────────────────
# REGISTER ROUTERS
# ─────────────────────────────────────────────

app.include_router(api_router, prefix="/api/v1")
app.include_router(task_router)


# ─────────────────────────────────────────────
# ROOT
# ─────────────────────────────────────────────

@app.get("/")
def root():
    return {
        "application": "Intelligent Diary API",
        "status": "running",
    }


# ─────────────────────────────────────────────
# HEALTH CHECK
# ─────────────────────────────────────────────

@app.get("/health")
def health_check():
    return {
        "status"  : "running",
        "app"     : settings.APP_NAME,
        "version" : settings.APP_VERSION,
    }
