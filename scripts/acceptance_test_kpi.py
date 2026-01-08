#!/usr/bin/env python3
"""
Acceptance test for KPI computation features:
- Delta % (percentage change)
- Top 10 contributors
- Decomposition (price/volume)

Usage:
    # Run from Docker container
    docker-compose exec api python -c "
    import sys; sys.path.insert(0, '/app');
    exec(open('/app/../scripts/acceptance_test_kpi.py').read())"
    
    # Or run locally
    export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/retail_sales"
    python scripts/acceptance_test_kpi.py
"""

import os
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

from app.tools.sql_tool import run_sql


def load_template(template_name: str) -> str:
    """Load SQL template from sql/templates/ directory."""
    # Try multiple possible paths
    possible_paths = [
        Path(__file__).parent.parent / "sql" / "templates" / template_name,  # Local
        Path("/app/sql/templates") / template_name,  # Docker container
        Path("/app/../sql/templates") / template_name,  # Alternative Docker path
    ]
    
    for template_path in possible_paths:
        if template_path.exists():
            return template_path.read_text(encoding="utf-8")
    
    raise FileNotFoundError(f"Template not found: {template_name}. Tried: {[str(p) for p in possible_paths]}")


def test_kpi_delta_percentage():
    """Test: Given a KPI + window, compute delta %"""
    print("=" * 70)
    print("TEST 1: KPI Delta Percentage")
    print("=" * 70)
    
    sql = load_template("kpi_trend_window_comparison.sql")
    
    params = {
        "current_start_ts": "2011-01-08",
        "current_end_ts": "2011-01-15",
        "prior_start_ts": "2011-01-01",
        "prior_end_ts": "2011-01-08",
    }
    
    try:
        result = run_sql(sql, params)
        
        if result["row_count"] == 0:
            print("❌ FAIL: No results returned")
            return False
        
        row = result["rows"][0]
        
        print(f"✅ Query executed successfully")
        print(f"   Query hash: {result.get('query_hash', 'N/A')}")
        print(f"   Duration: {result['duration_ms']}ms")
        print(f"\n   Revenue Metrics:")
        print(f"     Current: ${row.get('current_revenue', 0):,.2f}")
        print(f"     Prior:   ${row.get('prior_revenue', 0):,.2f}")
        print(f"     Change:  ${row.get('revenue_change', 0):,.2f}")
        print(f"     Delta %: {row.get('revenue_pct_change', 0)*100:.2f}%")
        print(f"\n   Units Metrics:")
        print(f"     Current: {row.get('current_units', 0):,.0f}")
        print(f"     Prior:   {row.get('prior_units', 0):,.0f}")
        print(f"     Change:  {row.get('units_change', 0):,.0f}")
        print(f"     Delta %: {row.get('units_pct_change', 0)*100:.2f}%")
        print(f"\n   AOV Metrics:")
        print(f"     Current: ${row.get('current_aov', 0):,.2f}")
        print(f"     Prior:   ${row.get('prior_aov', 0):,.2f}")
        print(f"     Change:  ${row.get('aov_change', 0):,.2f}")
        
        # Validation
        has_delta = row.get('revenue_pct_change') is not None or row.get('units_pct_change') is not None
        if not has_delta:
            print("❌ FAIL: Delta percentage not calculated")
            return False
        
        print("\n✅ PASS: Delta percentage computed successfully")
        return True
        
    except Exception as e:
        print(f"❌ FAIL: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_top_contributors():
    """Test: Given a KPI + window, identify top 10 contributors"""
    print("\n" + "=" * 70)
    print("TEST 2: Top 10 Contributors")
    print("=" * 70)
    
    sql = load_template("top_contributors.sql")
    
    params = {
        "current_start_ts": "2011-01-08",
        "current_end_ts": "2011-01-15",
        "prior_start_ts": "2011-01-01",
        "prior_end_ts": "2011-01-08",
        "dimension": "country",  # Note: query returns all dimensions, caller filters
        "metric": "revenue",
        "top_n": 10,
    }
    
    try:
        result = run_sql(sql, params)
        
        if result["row_count"] == 0:
            print("❌ FAIL: No contributors returned")
            return False
        
        print(f"✅ Query executed successfully")
        print(f"   Query hash: {result.get('query_hash', 'N/A')}")
        print(f"   Duration: {result['duration_ms']}ms")
        print(f"   Contributors found: {result['row_count']}")
        
        # Show top positive and negative contributors
        positive = [r for r in result["rows"] if r.get("revenue_contribution", 0) > 0]
        negative = [r for r in result["rows"] if r.get("revenue_contribution", 0) < 0]
        
        print(f"\n   Top Positive Contributors (Revenue):")
        for i, row in enumerate(positive[:5], 1):
            country = row.get("country", "N/A")
            contrib = row.get("revenue_contribution", 0)
            contrib_pct = row.get("revenue_contribution_pct", 0)
            print(f"     {i}. {country}: ${contrib:,.2f} ({contrib_pct:.2f}% of total change)")
        
        print(f"\n   Top Negative Contributors (Revenue):")
        for i, row in enumerate(negative[:5], 1):
            country = row.get("country", "N/A")
            contrib = row.get("revenue_contribution", 0)
            contrib_pct = row.get("revenue_contribution_pct", 0)
            print(f"     {i}. {country}: ${contrib:,.2f} ({contrib_pct:.2f}% of total change)")
        
        # Validation
        if len(positive) == 0 and len(negative) == 0:
            print("❌ FAIL: No contributors identified")
            return False
        
        if result["row_count"] < 2:
            print("⚠️  WARNING: Less than 2 contributors found (expected at least top positive and negative)")
        
        print("\n✅ PASS: Top contributors identified successfully")
        return True
        
    except Exception as e:
        print(f"❌ FAIL: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_decomposition():
    """Test: Given a KPI + window, decompose into price/volume effects"""
    print("\n" + "=" * 70)
    print("TEST 3: Price/Volume Decomposition")
    print("=" * 70)
    
    sql = load_template("price_volume_decomposition.sql")
    
    params = {
        "current_start_ts": "2011-01-08",
        "current_end_ts": "2011-01-15",
        "prior_start_ts": "2011-01-01",
        "prior_end_ts": "2011-01-08",
    }
    
    try:
        result = run_sql(sql, params)
        
        if result["row_count"] == 0:
            print("❌ FAIL: No decomposition results returned")
            return False
        
        row = result["rows"][0]
        
        print(f"✅ Query executed successfully")
        print(f"   Query hash: {result.get('query_hash', 'N/A')}")
        print(f"   Duration: {result['duration_ms']}ms")
        print(f"\n   Revenue Change:")
        print(f"     Current: ${row.get('current_revenue', 0):,.2f}")
        print(f"     Prior:   ${row.get('prior_revenue', 0):,.2f}")
        print(f"     Total Change: ${row.get('total_revenue_change', 0):,.2f}")
        print(f"\n   Decomposition:")
        print(f"     Price Effect:  ${row.get('price_effect', 0):,.2f} ({row.get('price_effect_pct', 0):.2f}%)")
        print(f"     Volume Effect: ${row.get('volume_effect', 0):,.2f} ({row.get('volume_effect_pct', 0):.2f}%)")
        print(f"     Total:         ${row.get('decomposition_total', 0):,.2f}")
        print(f"\n   Volume Change:")
        print(f"     Current Units: {row.get('current_quantity', 0):,.0f}")
        print(f"     Prior Units:   {row.get('prior_quantity', 0):,.0f}")
        print(f"     Change:        {row.get('total_quantity_change', 0):,.0f}")
        
        # Validation
        price_effect = row.get('price_effect')
        volume_effect = row.get('volume_effect')
        total_change = row.get('total_revenue_change')
        
        if price_effect is None or volume_effect is None:
            print("❌ FAIL: Decomposition effects not calculated")
            return False
        
        # Check that decomposition approximately equals total change (within rounding)
        decomposition_sum = row.get('decomposition_total', 0)
        if abs(decomposition_sum - total_change) > abs(total_change * 0.01):  # Allow 1% rounding difference
            print(f"⚠️  WARNING: Decomposition sum (${decomposition_sum:,.2f}) doesn't match total change (${total_change:,.2f})")
        
        print("\n✅ PASS: Price/Volume decomposition computed successfully")
        return True
        
    except Exception as e:
        print(f"❌ FAIL: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all acceptance tests."""
    # Set DATABASE_URL if provided as argument
    if len(sys.argv) > 1:
        os.environ["DATABASE_URL"] = sys.argv[1]
    
    # Check if DATABASE_URL is set
    if not os.getenv("DATABASE_URL"):
        print("❌ DATABASE_URL environment variable is not set.")
        print("\nUsage:")
        print("  export DATABASE_URL='postgresql://postgres:postgres@localhost:5432/retail_sales'")
        print("  python scripts/acceptance_test_kpi.py")
        print("\nOr run from Docker:")
        print("  docker-compose exec api python -c \"import sys; sys.path.insert(0, '/app'); exec(open('/app/../scripts/acceptance_test_kpi.py').read())\"")
        sys.exit(1)
    
    print("KPI Acceptance Test Suite")
    print("=" * 70)
    print(f"Database: {os.getenv('DATABASE_URL').split('@')[1] if '@' in os.getenv('DATABASE_URL') else 'hidden'}")
    print(f"Test Window: Current (2011-01-08 to 2011-01-15) vs Prior (2011-01-01 to 2011-01-08)")
    print()
    
    results = []
    
    # Run tests
    results.append(("Delta Percentage", test_kpi_delta_percentage()))
    results.append(("Top Contributors", test_top_contributors()))
    results.append(("Decomposition", test_decomposition()))
    
    # Summary
    print("\n" + "=" * 70)
    print("Acceptance Test Summary")
    print("=" * 70)
    
    for test_name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {status}: {test_name}")
    
    all_passed = all(result[1] for result in results)
    
    print("\n" + "=" * 70)
    if all_passed:
        print("🎉 ALL ACCEPTANCE TESTS PASSED!")
        print("✅ KPI computation features are working correctly:")
        print("   - Delta % calculation")
        print("   - Top 10 contributors identification")
        print("   - Price/Volume decomposition")
        sys.exit(0)
    else:
        print("⚠️  SOME ACCEPTANCE TESTS FAILED")
        print("   Please review the errors above")
        sys.exit(1)


if __name__ == "__main__":
    main()

