# tools/sql_tool.py
from __future__ import annotations

import os
import re
import time
from typing import Any, Dict, List, Optional, Tuple

import psycopg2
from psycopg2.extras import RealDictCursor


READ_ONLY_FIRST_KEYWORDS = ("select", "with")
DANGEROUS_KEYWORDS = (
    "insert", "update", "delete", "drop", "alter", "truncate",
    "create", "grant", "revoke", "comment", "vacuum", "analyze"
)

_comment_re = re.compile(r"(--[^\n]*\n)|(/\*.*?\*/)", flags=re.S)


def _strip_comments(sql: str) -> str:
    return re.sub(_comment_re, "", sql)


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
) -> Dict[str, Any]:
    """
    Execute a read-only query and return rows as dicts.
    - Blocks non-SELECT queries
    - Blocks multi-statement execution
    - Supports named params: %(name)s
    """
    _is_read_only_sql(sql)

    dsn = os.getenv("DATABASE_URL")
    if not dsn:
        raise RuntimeError("DATABASE_URL env var is not set.")

    t0 = time.time()
    with psycopg2.connect(dsn) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params or {})
            rows = cur.fetchmany(max_rows)
            elapsed_ms = int((time.time() - t0) * 1000)

    return {
        "row_count": len(rows),
        "duration_ms": elapsed_ms,
        "rows": rows,
    }
