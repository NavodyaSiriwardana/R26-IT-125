from fastapi import FastAPI
from app.config import settings
from app.database import neo4j_conn
from app.components.temporal_causal_patterns.graph_builder import graph_builder
from app.routes import api_router

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
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