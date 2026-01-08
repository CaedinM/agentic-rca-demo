import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from app.tools.sql_tool import run_sql

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class QueryRequest(BaseModel):
    sql: str
    params: dict | None = None
    timeout_seconds: float | None = None

@app.get("/health/db")
def health_db():
    """Test database connection"""
    try:
        result = run_sql("SELECT 1 as test", {})
        return {
            "ok": True,
            "database": "connected",
            "response_time_ms": result["duration_ms"]
        }
    except Exception as e:
        return {
            "ok": False,
            "database": "disconnected",
            "error": str(e)
        }

@app.post("/query")
def query(req: QueryRequest):
    """Execute a read-only SQL query with connection pooling, timeout, and logging."""
    return run_sql(
        req.sql, 
        req.params or {},
        timeout_seconds=req.timeout_seconds
    )