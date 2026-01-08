-- sql/templates/kpi_trend_window_comparison.sql
-- Generic KPI trend comparison between two time windows
-- Supports: Revenue, Units, AOV
-- 
-- Parameters:
--   current_start_ts: Start of current window (TIMESTAMP)
--   current_end_ts: End of current window (TIMESTAMP)
--   prior_start_ts: Start of prior window (TIMESTAMP)
--   prior_end_ts: End of prior window (TIMESTAMP)
--   kpi_type: 'revenue', 'units', or 'aov' (default: 'revenue')
--   Note: For 'aov', calculates Average Order Value (revenue / invoice count)

WITH base AS (
  SELECT
    i.invoice_date,
    i.invoice_no,
    ii.quantity,
    p.unit_price,
    (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue
  FROM invoice_items ii
  JOIN invoices i ON i.invoice_no = ii.invoice_no
  JOIN products p ON p.stock_code = ii.stock_code
  WHERE (i.invoice_date >= %(prior_start_ts)s AND i.invoice_date < %(prior_end_ts)s)
     OR (i.invoice_date >= %(current_start_ts)s AND i.invoice_date < %(current_end_ts)s)
),
period_metrics AS (
  SELECT
    -- Current period
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN line_revenue ELSE 0 END) AS current_revenue,
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN quantity::numeric ELSE 0 END) AS current_units,
    COUNT(DISTINCT CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN invoice_no END) AS current_invoices,
    -- Prior period
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN line_revenue ELSE 0 END) AS prior_revenue,
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN quantity::numeric ELSE 0 END) AS prior_units,
    COUNT(DISTINCT CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN invoice_no END) AS prior_invoices
  FROM base
)
SELECT
  -- Select metric based on kpi_type (caller should use appropriate column)
  ROUND(current_revenue, 2) AS current_revenue,
  ROUND(prior_revenue, 2) AS prior_revenue,
  ROUND((current_revenue - prior_revenue), 2) AS revenue_change,
  CASE
    WHEN prior_revenue = 0 THEN NULL
    ELSE ROUND((current_revenue - prior_revenue) / prior_revenue, 6)
  END AS revenue_pct_change,
  ROUND(current_units, 2) AS current_units,
  ROUND(prior_units, 2) AS prior_units,
  ROUND((current_units - prior_units), 2) AS units_change,
  CASE
    WHEN prior_units = 0 THEN NULL
    ELSE ROUND((current_units - prior_units) / prior_units, 6)
  END AS units_pct_change,
  CASE
    WHEN current_invoices > 0 THEN ROUND(current_revenue / current_invoices, 2)
    ELSE NULL
  END AS current_aov,
  CASE
    WHEN prior_invoices > 0 THEN ROUND(prior_revenue / prior_invoices, 2)
    ELSE NULL
  END AS prior_aov,
  CASE
    WHEN current_invoices > 0 AND prior_invoices > 0 THEN
      ROUND((current_revenue / current_invoices) - (prior_revenue / prior_invoices), 2)
    ELSE NULL
  END AS aov_change,
  current_invoices,
  prior_invoices
FROM period_metrics;

