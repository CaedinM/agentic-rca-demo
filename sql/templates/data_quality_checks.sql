-- sql/templates/data_quality_checks.sql
-- Data quality checks: freshness, row counts, null spikes
--
-- Parameters:
--   check_date: Date to check data freshness against (default: current date)
--   expected_daily_rows_min: Minimum expected rows per day (default: 100)
--   null_threshold_pct: Alert if null percentage exceeds this (default: 5.0)

WITH freshness_check AS (
  SELECT
    'freshness' AS check_type,
    MAX(i.invoice_date)::date AS latest_invoice_date,
    %(check_date)s::date AS check_date,
    (%(check_date)s::date - MAX(i.invoice_date)::date) AS days_behind,
    CASE
      WHEN (%(check_date)s::date - MAX(i.invoice_date)::date) <= 1 THEN 'pass'
      WHEN (%(check_date)s::date - MAX(i.invoice_date)::date) <= 3 THEN 'warning'
      ELSE 'fail'
    END AS status
  FROM invoices i
),
row_count_check AS (
  SELECT
    'row_counts' AS check_type,
    COUNT(*) AS total_invoices,
    COUNT(DISTINCT DATE(i.invoice_date)) AS days_with_data,
    COUNT(*)::numeric / NULLIF(COUNT(DISTINCT DATE(i.invoice_date)), 0) AS avg_rows_per_day,
    CASE
      WHEN COUNT(*)::numeric / NULLIF(COUNT(DISTINCT DATE(i.invoice_date)), 0) >= %(expected_daily_rows_min)s THEN 'pass'
      WHEN COUNT(*)::numeric / NULLIF(COUNT(DISTINCT DATE(i.invoice_date)), 0) >= (%(expected_daily_rows_min)s * 0.5) THEN 'warning'
      ELSE 'fail'
    END AS status
  FROM invoices i
),
null_checks AS (
  SELECT
    'null_checks' AS check_type,
    -- Invoice items nulls
    (SELECT COUNT(*) FROM invoice_items) AS total_invoice_items,
    (SELECT COUNT(*) FROM invoice_items WHERE invoice_no IS NULL) AS null_invoice_no,
    (SELECT COUNT(*) FROM invoice_items WHERE stock_code IS NULL) AS null_stock_code,
    (SELECT COUNT(*) FROM invoice_items WHERE quantity IS NULL) AS null_quantity,
    -- Invoices nulls
    (SELECT COUNT(*) FROM invoices WHERE invoice_date IS NULL) AS null_invoice_date,
    (SELECT COUNT(*) FROM invoices WHERE customer_id IS NULL) AS null_customer_id,
    -- Products nulls
    (SELECT COUNT(*) FROM products WHERE unit_price IS NULL) AS null_unit_price,
    -- Customers nulls
    (SELECT COUNT(*) FROM customers WHERE country IS NULL) AS null_country
),
null_percentages AS (
  SELECT
    'null_percentages' AS check_type,
    ROUND((null_invoice_no::numeric / NULLIF(total_invoice_items, 0)) * 100, 2) AS pct_null_invoice_no,
    ROUND((null_stock_code::numeric / NULLIF(total_invoice_items, 0)) * 100, 2) AS pct_null_stock_code,
    ROUND((null_quantity::numeric / NULLIF(total_invoice_items, 0)) * 100, 2) AS pct_null_quantity,
    ROUND((null_invoice_date::numeric / NULLIF((SELECT COUNT(*) FROM invoices), 0)) * 100, 2) AS pct_null_invoice_date,
    ROUND((null_customer_id::numeric / NULLIF((SELECT COUNT(*) FROM invoices), 0)) * 100, 2) AS pct_null_customer_id,
    ROUND((null_unit_price::numeric / NULLIF((SELECT COUNT(*) FROM products), 0)) * 100, 2) AS pct_null_unit_price,
    ROUND((null_country::numeric / NULLIF((SELECT COUNT(*) FROM customers), 0)) * 100, 2) AS pct_null_country,
    CASE
      WHEN GREATEST(
        (null_invoice_no::numeric / NULLIF(total_invoice_items, 0)) * 100,
        (null_stock_code::numeric / NULLIF(total_invoice_items, 0)) * 100,
        (null_quantity::numeric / NULLIF(total_invoice_items, 0)) * 100,
        (null_invoice_date::numeric / NULLIF((SELECT COUNT(*) FROM invoices), 0)) * 100,
        (null_customer_id::numeric / NULLIF((SELECT COUNT(*) FROM invoices), 0)) * 100,
        (null_unit_price::numeric / NULLIF((SELECT COUNT(*) FROM products), 0)) * 100,
        (null_country::numeric / NULLIF((SELECT COUNT(*) FROM customers), 0)) * 100
      ) <= %(null_threshold_pct)s THEN 'pass'
      WHEN GREATEST(
        (null_invoice_no::numeric / NULLIF(total_invoice_items, 0)) * 100,
        (null_stock_code::numeric / NULLIF(total_invoice_items, 0)) * 100,
        (null_quantity::numeric / NULLIF(total_invoice_items, 0)) * 100,
        (null_invoice_date::numeric / NULLIF((SELECT COUNT(*) FROM invoices), 0)) * 100,
        (null_customer_id::numeric / NULLIF((SELECT COUNT(*) FROM invoices), 0)) * 100,
        (null_unit_price::numeric / NULLIF((SELECT COUNT(*) FROM products), 0)) * 100,
        (null_country::numeric / NULLIF((SELECT COUNT(*) FROM customers), 0)) * 100
      ) <= (%(null_threshold_pct)s * 2) THEN 'warning'
      ELSE 'fail'
    END AS status
  FROM null_checks
),
daily_counts AS (
  SELECT
    DATE(i.invoice_date) AS date,
    COUNT(*) AS daily_count
  FROM invoices i
  GROUP BY DATE(i.invoice_date)
),
daily_row_spikes AS (
  SELECT
    'daily_spikes' AS check_type,
    date,
    daily_count,
    AVG(daily_count) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS seven_day_avg,
    CASE
      WHEN daily_count > AVG(daily_count) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) * 2 THEN 'spike'
      WHEN daily_count < AVG(daily_count) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) * 0.5 THEN 'drop'
      ELSE 'normal'
    END AS pattern
  FROM daily_counts
)
SELECT
  'freshness' AS check_type,
  latest_invoice_date::text AS metric_value,
  days_behind::text AS detail,
  status
FROM freshness_check
UNION ALL
SELECT
  'row_counts' AS check_type,
  total_invoices::text AS metric_value,
  format('Days: %s, Avg/day: %.1f', days_with_data, avg_rows_per_day) AS detail,
  status
FROM row_count_check
UNION ALL
SELECT
  'null_percentages' AS check_type,
  format('Max null: %.2f%%', GREATEST(pct_null_invoice_no, pct_null_stock_code, pct_null_quantity, 
         pct_null_invoice_date, pct_null_customer_id, pct_null_unit_price, pct_null_country)) AS metric_value,
  format('Invoice items: %.2f%%, Invoices: %.2f%%, Products: %.2f%%, Customers: %.2f%%',
         GREATEST(pct_null_invoice_no, pct_null_stock_code, pct_null_quantity),
         GREATEST(pct_null_invoice_date, pct_null_customer_id),
         pct_null_unit_price, pct_null_country) AS detail,
  status
FROM null_percentages
UNION ALL
SELECT
  'daily_spikes' AS check_type,
  date::text AS metric_value,
  format('Count: %s, 7-day avg: %.1f', daily_count, seven_day_avg) AS detail,
  pattern AS status
FROM daily_row_spikes
WHERE pattern IN ('spike', 'drop')
ORDER BY check_type, date DESC;

