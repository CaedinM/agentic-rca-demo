-- sql/templates/mix_shift_by_dimension.sql
-- Analyze mix shift (share changes) by dimension
-- 
-- Parameters:
--   current_start_ts: Start of current window (TIMESTAMP)
--   current_end_ts: End of current window (TIMESTAMP)
--   prior_start_ts: Start of prior window (TIMESTAMP)
--   prior_end_ts: End of prior window (TIMESTAMP)
--   dimension: 'country', 'stock_code', 'customer_id' (default: 'country')
--   metric: 'revenue' or 'units' (default: 'revenue')

WITH base AS (
  SELECT
    i.invoice_date,
    ii.quantity,
    p.unit_price,
    (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue,
    c.country,
    p.stock_code,
    i.customer_id
  FROM invoice_items ii
  JOIN invoices i ON i.invoice_no = ii.invoice_no
  JOIN products p ON p.stock_code = ii.stock_code
  LEFT JOIN customers c ON c.customer_id = i.customer_id
  WHERE (i.invoice_date >= %(prior_start_ts)s AND i.invoice_date < %(prior_end_ts)s)
     OR (i.invoice_date >= %(current_start_ts)s AND i.invoice_date < %(current_end_ts)s)
),
dimension_values AS (
  SELECT
    -- Dimension value (caller should filter by dimension type)
    COALESCE(country, 'Unknown') AS country,
    stock_code,
    customer_id::text AS customer_id,
    -- Current period - both metrics
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN line_revenue ELSE 0 END) AS current_revenue,
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN quantity::numeric ELSE 0 END) AS current_units,
    -- Prior period - both metrics
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN line_revenue ELSE 0 END) AS prior_revenue,
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN quantity::numeric ELSE 0 END) AS prior_units
  FROM base
  GROUP BY country, stock_code, customer_id
),
totals AS (
  SELECT
    SUM(current_revenue) AS current_revenue_total,
    SUM(prior_revenue) AS prior_revenue_total,
    SUM(current_units) AS current_units_total,
    SUM(prior_units) AS prior_units_total
  FROM dimension_values
)
SELECT
  -- Return all dimension columns (caller filters by dimension type)
  dv.country,
  dv.stock_code,
  dv.customer_id,
  -- Revenue metrics
  ROUND(dv.current_revenue, 2) AS current_revenue,
  ROUND(dv.prior_revenue, 2) AS prior_revenue,
  ROUND(dv.current_revenue - dv.prior_revenue, 2) AS revenue_change,
  CASE
    WHEN dv.prior_revenue = 0 THEN NULL
    ELSE ROUND((dv.current_revenue - dv.prior_revenue) / dv.prior_revenue, 6)
  END AS revenue_pct_change,
  CASE
    WHEN t.current_revenue_total > 0 THEN ROUND((dv.current_revenue / t.current_revenue_total) * 100, 2)
    ELSE 0
  END AS current_revenue_share_pct,
  CASE
    WHEN t.prior_revenue_total > 0 THEN ROUND((dv.prior_revenue / t.prior_revenue_total) * 100, 2)
    ELSE 0
  END AS prior_revenue_share_pct,
  CASE
    WHEN t.current_revenue_total > 0 AND t.prior_revenue_total > 0 THEN
      ROUND(((dv.current_revenue / t.current_revenue_total) - (dv.prior_revenue / t.prior_revenue_total)) * 100, 2)
    ELSE NULL
  END AS revenue_mix_shift_pct,
  -- Units metrics
  ROUND(dv.current_units, 2) AS current_units,
  ROUND(dv.prior_units, 2) AS prior_units,
  ROUND(dv.current_units - dv.prior_units, 2) AS units_change,
  CASE
    WHEN dv.prior_units = 0 THEN NULL
    ELSE ROUND((dv.current_units - dv.prior_units) / dv.prior_units, 6)
  END AS units_pct_change,
  CASE
    WHEN t.current_units_total > 0 THEN ROUND((dv.current_units / t.current_units_total) * 100, 2)
    ELSE 0
  END AS current_units_share_pct,
  CASE
    WHEN t.prior_units_total > 0 THEN ROUND((dv.prior_units / t.prior_units_total) * 100, 2)
    ELSE 0
  END AS prior_units_share_pct,
  CASE
    WHEN t.current_units_total > 0 AND t.prior_units_total > 0 THEN
      ROUND(((dv.current_units / t.current_units_total) - (dv.prior_units / t.prior_units_total)) * 100, 2)
    ELSE NULL
  END AS units_mix_shift_pct
FROM dimension_values dv
CROSS JOIN totals t
WHERE dv.current_revenue > 0 OR dv.prior_revenue > 0 OR dv.current_units > 0 OR dv.prior_units > 0
ORDER BY ABS(dv.current_revenue - dv.prior_revenue) DESC;

