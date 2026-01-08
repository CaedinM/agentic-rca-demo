# tools/sql_tool.py
from __future__ import annotations

import hashlib
import logging
import os
import re
import time
from typing import Any, Dict, List, Optional, Tuple

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

# Configure logging
logger = logging.getLogger(__name__)

READ_ONLY_FIRST_KEYWORDS = ("select", "with")
DANGEROUS_KEYWORDS = (
    "insert", "update", "delete", "drop", "alter", "truncate",
    "create", "grant", "revoke", "comment", "vacuum", "analyze"
)

_comment_re = re.compile(r"(--[^\n]*\n)|(/\*.*?\*/)", flags=re.S)

# Connection pool (initialized lazily)
_connection_pool: Optional[pool.ThreadedConnectionPool] = None


def _strip_comments(sql: str) -> str:
    return re.sub(_comment_re, "", sql)


def _get_connection_pool() -> pool.ThreadedConnectionPool:
    """Get or create the connection pool."""
    global _connection_pool
    
    if _connection_pool is None:
        dsn = os.getenv("DATABASE_URL")
        if not dsn:
            raise RuntimeError("DATABASE_URL env var is not set.")
        
        # Pool configuration
        min_conn = int(os.getenv("DB_POOL_MIN", "2"))
        max_conn = int(os.getenv("DB_POOL_MAX", "10"))
        
        try:
            _connection_pool = pool.ThreadedConnectionPool(
                minconn=min_conn,
                maxconn=max_conn,
                dsn=dsn,
            )
            logger.info(f"Connection pool created: min={min_conn}, max={max_conn}")
        except Exception as e:
            logger.error(f"Failed to create connection pool: {e}")
            raise
    
    return _connection_pool


def _hash_query(sql: str, params: Optional[Dict[str, Any]] = None) -> str:
    """Generate a hash of the query for logging/tracking."""
    # Normalize SQL (strip whitespace, lowercase)
    normalized_sql = re.sub(r'\s+', ' ', sql.strip().lower())
    
    # Include params in hash if present
    if params:
        # Sort params for consistent hashing
        params_str = str(sorted(params.items()))
        query_str = f"{normalized_sql}|{params_str}"
    else:
        query_str = normalized_sql
    
    return hashlib.sha256(query_str.encode()).hexdigest()[:16]


def _is_read_only_sql(sql: str) -> None:
    s = _strip_comments(sql).strip()
    if not s:
        raise ValueError("Empty SQL is not allowed.")

    # Block multiple statements (simple but effective MVP guardrail)
    # Allow one trailing semicolon
    if ";" in s[:-1]:
        raise ValueError("Multiple SQL statements are not allowed.")

    first = s.split(None, 1)[0].lower()
    if first not in READ_ONLY_FIRST_KEYWORDS:
        raise ValueError("Only SELECT/WITH queries are allowed in run_sql().")

    lowered = s.lower()
    for kw in DANGEROUS_KEYWORDS:
        if re.search(rf"\b{kw}\b", lowered):
            raise ValueError(f"Disallowed keyword detected: {kw}")


def run_sql(
    sql: str,
    params: Optional[Dict[str, Any]] = None,
    *,
    max_rows: int = 5000,
    timeout_seconds: Optional[float] = None,
) -> Dict[str, Any]:
    """
    Execute a read-only query and return rows as dicts.
    
    Features:
    - Connection pooling for performance
    - Read-only enforcement (SELECT/WITH only)
    - Row limit enforcement
    - Query timeout support
    - Query hashing and logging
    
    Args:
        sql: SQL query string (SELECT or WITH statements only)
        params: Optional dictionary of named parameters
        max_rows: Maximum number of rows to return (default: 5000)
        timeout_seconds: Query timeout in seconds (default: None, uses DB_POOL_TIMEOUT env var or 30s)
    
    Returns:
        Dictionary with:
        - row_count: Number of rows returned
        - duration_ms: Query execution time in milliseconds
        - rows: List of row dictionaries
        - query_hash: SHA256 hash of the query (first 16 chars)
    
    Raises:
        ValueError: If query is not read-only or contains dangerous keywords
        RuntimeError: If DATABASE_URL is not set or connection pool fails
        psycopg2.extensions.QueryCanceledError: If query exceeds timeout
    """
    _is_read_only_sql(sql)
    
    # Generate query hash for logging
    query_hash = _hash_query(sql, params)
    
    # Get timeout (from parameter, env var, or default)
    timeout = timeout_seconds
    if timeout is None:
        timeout = float(os.getenv("DB_POOL_TIMEOUT", "30.0"))
    
    # Get connection pool
    connection_pool = _get_connection_pool()
    
    t0 = time.time()
    conn = None
    
    try:
        # Get connection from pool
        conn = connection_pool.getconn()
        if conn is None:
            raise RuntimeError("Failed to get connection from pool")
        
        # Set query timeout
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Set statement timeout (PostgreSQL feature)
            cur.execute(f"SET statement_timeout = {int(timeout * 1000)}")  # Convert to milliseconds
            
            # Execute query
            cur.execute(sql, params or {})
            rows = cur.fetchmany(max_rows)
        
        elapsed_ms = int((time.time() - t0) * 1000)
        
        # Log query execution
        logger.info(
            f"Query executed | hash={query_hash} | "
            f"duration_ms={elapsed_ms} | rows={len(rows)} | "
            f"max_rows={max_rows} | timeout={timeout}s"
        )
        
        return {
            "row_count": len(rows),
            "duration_ms": elapsed_ms,
            "rows": rows,
            "query_hash": query_hash,
        }
    
    except psycopg2.extensions.QueryCanceledError as e:
        elapsed_ms = int((time.time() - t0) * 1000)
        logger.warning(
            f"Query timeout | hash={query_hash} | "
            f"duration_ms={elapsed_ms} | timeout={timeout}s | error={str(e)}"
        )
        raise
    
    except Exception as e:
        elapsed_ms = int((time.time() - t0) * 1000)
        logger.error(
            f"Query failed | hash={query_hash} | "
            f"duration_ms={elapsed_ms} | error={str(e)}"
        )
        raise
    
    finally:
        # Return connection to pool
        if conn is not None:
            connection_pool.putconn(conn)
