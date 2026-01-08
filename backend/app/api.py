from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from app.tools.sql_tool import run_sql

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
    return run_sql(req.sql, req.params or {})