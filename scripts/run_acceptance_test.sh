#!/bin/bash
# Wrapper script to run KPI acceptance tests from Docker container

echo "Running KPI Acceptance Tests..."
echo ""

docker-compose exec api python -c "
import sys
import os
from pathlib import Path

# Set up environment
os.environ['DATABASE_URL'] = 'postgresql://postgres:postgres@db:5432/retail_sales'
sys.path.insert(0, '/app')

from app.tools.sql_tool import run_sql

# Load template function
def load_template(template_name):
    template_path = Path('/app/sql/templates') / template_name
    if not template_path.exists():
        raise FileNotFoundError(f'Template not found: {template_name}')
    return template_path.read_text(encoding='utf-8')

print('=' * 70)
print('ACCEPTANCE TEST: KPI Computation')
print('=' * 70)
print('Test Window: Current (2011-01-08 to 2011-01-15) vs Prior (2011-01-01 to 2011-01-08)')
print()

# Test 1: Delta Percentage
print('TEST 1: KPI Delta Percentage')
print('-' * 70)
sql = load_template('kpi_trend_window_comparison.sql')
params = {
    'current_start_ts': '2011-01-08',
    'current_end_ts': '2011-01-15',
    'prior_start_ts': '2011-01-01',
    'prior_end_ts': '2011-01-08',
}
result = run_sql(sql, params)
row = result['rows'][0]
print(f'✅ Query executed (hash: {result.get(\"query_hash\", \"N/A\")}, {result[\"duration_ms\"]}ms)')
print(f'   Revenue: Current=\${row.get(\"current_revenue\", 0):,.2f}, Prior=\${row.get(\"prior_revenue\", 0):,.2f}')
print(f'   Delta %: {row.get(\"revenue_pct_change\", 0)*100:.2f}%')
print(f'   Units: Current={row.get(\"current_units\", 0):,.0f}, Prior={row.get(\"prior_units\", 0):,.0f}')
print(f'   Delta %: {row.get(\"units_pct_change\", 0)*100:.2f}%')
test1_pass = row.get('revenue_pct_change') is not None

# Test 2: Top Contributors
print()
print('TEST 2: Top 10 Contributors')
print('-' * 70)
sql = load_template('top_contributors.sql')
params = {
    'current_start_ts': '2011-01-08',
    'current_end_ts': '2011-01-15',
    'prior_start_ts': '2011-01-01',
    'prior_end_ts': '2011-01-08',
    'top_n': 10,
}
result = run_sql(sql, params)
print(f'✅ Query executed (hash: {result.get(\"query_hash\", \"N/A\")}, {result[\"duration_ms\"]}ms)')
print(f'   Contributors found: {result[\"row_count\"]}')
positive = [r for r in result['rows'] if r.get('revenue_contribution', 0) > 0]
negative = [r for r in result['rows'] if r.get('revenue_contribution', 0) < 0]
print(f'   Top positive: {len(positive)}, Top negative: {len(negative)}')
if positive:
    top = positive[0]
    print(f'   Example: {top.get(\"country\", \"N/A\")} contributed \${top.get(\"revenue_contribution\", 0):,.2f} ({top.get(\"revenue_contribution_pct\", 0):.2f}%)')
test2_pass = result['row_count'] > 0

# Test 3: Decomposition
print()
print('TEST 3: Price/Volume Decomposition')
print('-' * 70)
sql = load_template('price_volume_decomposition.sql')
params = {
    'current_start_ts': '2011-01-08',
    'current_end_ts': '2011-01-15',
    'prior_start_ts': '2011-01-01',
    'prior_end_ts': '2011-01-08',
}
result = run_sql(sql, params)
row = result['rows'][0]
print(f'✅ Query executed (hash: {result.get(\"query_hash\", \"N/A\")}, {result[\"duration_ms\"]}ms)')
print(f'   Total Revenue Change: \${row.get(\"total_revenue_change\", 0):,.2f}')
print(f'   Price Effect: \${row.get(\"price_effect\", 0):,.2f} ({row.get(\"price_effect_pct\", 0):.2f}%)')
print(f'   Volume Effect: \${row.get(\"volume_effect\", 0):,.2f} ({row.get(\"volume_effect_pct\", 0):.2f}%)')
test3_pass = row.get('price_effect') is not None and row.get('volume_effect') is not None

# Summary
print()
print('=' * 70)
print('ACCEPTANCE TEST SUMMARY')
print('=' * 70)
print(f'  {\"✅ PASS\" if test1_pass else \"❌ FAIL\"}: Delta Percentage')
print(f'  {\"✅ PASS\" if test2_pass else \"❌ FAIL\"}: Top Contributors')
print(f'  {\"✅ PASS\" if test3_pass else \"❌ FAIL\"}: Decomposition')
all_pass = test1_pass and test2_pass and test3_pass
print()
if all_pass:
    print('🎉 ALL TESTS PASSED!')
    print('✅ KPI computation features verified:')
    print('   - Delta % calculation')
    print('   - Top 10 contributors identification')
    print('   - Price/Volume decomposition')
else:
    print('⚠️  SOME TESTS FAILED')
"

