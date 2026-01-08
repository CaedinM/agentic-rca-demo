#!/usr/bin/env python3
"""
Test script to verify read-only database connection and run KPI queries.

Usage Options:

1. Run from Docker container (recommended - DATABASE_URL is already set):
   docker-compose exec api python -c "
   import sys; sys.path.insert(0, '/app');
   exec(open('/app/../scripts/test_kpi_query.py').read())"

2. Run locally with DATABASE_URL:
   export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/retail_sales"
   python scripts/test_kpi_query.py

3. Pass DATABASE_URL as argument:
   python scripts/test_kpi_query.py "postgresql://postgres:postgres@localhost:5432/retail_sales"

Note: If you have a local PostgreSQL on port 5432, you may need to:
- Stop it, or
- Use a different port in docker-compose.yml, or  
- Connect directly to the Docker container's IP
"""

import os
import sys
from pathlib import Path

# Add backend to path so we can import the sql_tool
sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

from app.tools.sql_tool import run_sql


def test_connection():
    """Test basic database connection."""
    print("=" * 60)
    print("Testing Database Connection")
    print("=" * 60)
    
    try:
        result = run_sql("SELECT 1 as test, version() as pg_version", {})
        print(f"✅ Connection successful!")
        print(f"   PostgreSQL version: {result['rows'][0]['pg_version']}")
        print(f"   Query duration: {result['duration_ms']}ms")
        return True
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False


def test_read_only_enforcement():
    """Test that write operations are blocked."""
    print("\n" + "=" * 60)
    print("Testing Read-Only Enforcement")
    print("=" * 60)
    
    # Test 1: Try to INSERT (should fail)
    try:
        run_sql("INSERT INTO customers (customer_id, country) VALUES (999999, 'Test')", {})
        print("❌ INSERT was allowed (should be blocked!)")
        return False
    except ValueError as e:
        print(f"✅ INSERT correctly blocked: {e}")
    
    # Test 2: Try to UPDATE (should fail)
    try:
        run_sql("UPDATE customers SET country = 'Test' WHERE customer_id = 1", {})
        print("❌ UPDATE was allowed (should be blocked!)")
        return False
    except ValueError as e:
        print(f"✅ UPDATE correctly blocked: {e}")
    
    # Test 3: Try to DELETE (should fail)
    try:
        run_sql("DELETE FROM customers WHERE customer_id = 1", {})
        print("❌ DELETE was allowed (should be blocked!)")
        return False
    except ValueError as e:
        print(f"✅ DELETE correctly blocked: {e}")
    
    return True


def test_revenue_kpi():
    """Test Revenue KPI query."""
    print("\n" + "=" * 60)
    print("Testing Revenue KPI Query")
    print("=" * 60)
    
    sql = """
    WITH base AS (
      SELECT
        date_trunc('day', i.invoice_date) AS day,
        (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue
      FROM invoice_items ii
      JOIN invoices i ON i.invoice_no = ii.invoice_no
      JOIN products p ON p.stock_code = ii.stock_code
      WHERE i.invoice_date >= %(start_ts)s
        AND i.invoice_date < %(end_ts)s
    )
    SELECT
      day::date AS day,
      ROUND(SUM(line_revenue), 2) AS revenue
    FROM base
    GROUP BY 1
    ORDER BY 1
    LIMIT 10
    """
    
    params = {
        "start_ts": "2011-01-01",
        "end_ts": "2011-02-01"
    }
    
    try:
        result = run_sql(sql, params)
        print(f"✅ Revenue query successful!")
        print(f"   Rows returned: {result['row_count']}")
        print(f"   Query duration: {result['duration_ms']}ms")
        print(f"\n   Sample results (first 5 days):")
        for row in result['rows'][:5]:
            print(f"     {row['day']}: ${row['revenue']:,.2f}")
        
        if result['row_count'] > 0:
            total_revenue = sum(row['revenue'] for row in result['rows'])
            print(f"\n   Total revenue (sample period): ${total_revenue:,.2f}")
        
        return True
    except Exception as e:
        print(f"❌ Revenue query failed: {e}")
        return False


def test_units_kpi():
    """Test Units KPI query."""
    print("\n" + "=" * 60)
    print("Testing Units KPI Query")
    print("=" * 60)
    
    sql = """
    SELECT
      date_trunc('day', i.invoice_date)::date AS day,
      SUM(ii.quantity) AS units
    FROM invoice_items ii
    JOIN invoices i ON i.invoice_no = ii.invoice_no
    WHERE i.invoice_date >= %(start_ts)s
      AND i.invoice_date < %(end_ts)s
    GROUP BY 1
    ORDER BY 1
    LIMIT 10
    """
    
    params = {
        "start_ts": "2011-01-01",
        "end_ts": "2011-02-01"
    }
    
    try:
        result = run_sql(sql, params)
        print(f"✅ Units query successful!")
        print(f"   Rows returned: {result['row_count']}")
        print(f"   Query duration: {result['duration_ms']}ms")
        print(f"\n   Sample results (first 5 days):")
        for row in result['rows'][:5]:
            print(f"     {row['day']}: {row['units']:,} units")
        
        if result['row_count'] > 0:
            total_units = sum(row['units'] for row in result['rows'])
            print(f"\n   Total units (sample period): {total_units:,}")
        
        return True
    except Exception as e:
        print(f"❌ Units query failed: {e}")
        return False


def test_table_counts():
    """Test basic table row counts."""
    print("\n" + "=" * 60)
    print("Testing Table Row Counts")
    print("=" * 60)
    
    tables = ["customers", "products", "invoices", "invoice_items"]
    
    for table in tables:
        try:
            result = run_sql(f"SELECT COUNT(*) as count FROM {table}", {})
            count = result['rows'][0]['count']
            print(f"   {table:20s}: {count:>10,} rows")
        except Exception as e:
            print(f"   {table:20s}: ERROR - {e}")
    
    return True


def main():
    """Run all tests."""
    # Set DATABASE_URL if provided as argument
    if len(sys.argv) > 1:
        os.environ["DATABASE_URL"] = sys.argv[1]
    
    # Check if DATABASE_URL is set
    if not os.getenv("DATABASE_URL"):
        print("❌ DATABASE_URL environment variable is not set.")
        print("\nUsage:")
        print("  # Make sure Docker containers are running:")
        print("  docker-compose up -d")
        print("\n  # Then run the test:")
        print("  export DATABASE_URL='postgresql://postgres:postgres@localhost:5432/retail_sales'")
        print("  python scripts/test_kpi_query.py")
        print("\n  # Or pass as argument:")
        print("  python scripts/test_kpi_query.py 'postgresql://postgres:postgres@localhost:5432/retail_sales'")
        print("\n  # If you have a local PostgreSQL on port 5432, you may need to:")
        print("  # 1. Stop it, or")
        print("  # 2. Use a different port in docker-compose.yml, or")
        print("  # 3. Connect directly to the Docker container's IP")
        sys.exit(1)
    
    print(f"Database URL: {os.getenv('DATABASE_URL').split('@')[1] if '@' in os.getenv('DATABASE_URL') else 'hidden'}")
    
    results = []
    
    # Run tests
    results.append(("Connection", test_connection()))
    results.append(("Read-Only Enforcement", test_read_only_enforcement()))
    results.append(("Table Counts", test_table_counts()))
    results.append(("Revenue KPI", test_revenue_kpi()))
    results.append(("Units KPI", test_units_kpi()))
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    
    for test_name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {status}: {test_name}")
    
    all_passed = all(result[1] for result in results)
    
    if all_passed:
        print("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        print("\n⚠️  Some tests failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()

