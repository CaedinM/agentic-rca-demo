-- sql/templates/top_contributors.sql
-- Identify top positive and negative contributors to KPI changes
--
-- Parameters:
--   current_start_ts: Start of current window (TIMESTAMP)
--   current_end_ts: End of current window (TIMESTAMP)
--   prior_start_ts: Start of prior window (TIMESTAMP)
--   prior_end_ts: End of prior window (TIMESTAMP)
--   dimension: 'country', 'stock_code', 'customer_id' (default: 'country')
--   metric: 'revenue' or 'units' (default: 'revenue')
--   top_n: Number of top contributors to return (default: 10)

WITH base AS (
  SELECT
    i.invoice_date,
    ii.quantity,
    p.unit_price,
    (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue,
    c.country,
    p.stock_code,
    p.description,
    i.customer_id
  FROM invoice_items ii
  JOIN invoices i ON i.invoice_no = ii.invoice_no
  JOIN products p ON p.stock_code = ii.stock_code
  LEFT JOIN customers c ON c.customer_id = i.customer_id
  WHERE (i.invoice_date >= %(prior_start_ts)s AND i.invoice_date < %(prior_end_ts)s)
     OR (i.invoice_date >= %(current_start_ts)s AND i.invoice_date < %(current_end_ts)s)
),
dimension_metrics AS (
  SELECT
    -- Return all dimension columns (caller filters by dimension type)
    COALESCE(country, 'Unknown') AS country,
    stock_code,
    customer_id::text AS customer_id,
    MAX(description) AS product_description,
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
contributors AS (
  SELECT
    country,
    stock_code,
    customer_id,
    product_description,
    -- Revenue metrics
    current_revenue,
    prior_revenue,
    (current_revenue - prior_revenue) AS revenue_contribution,
    CASE
      WHEN prior_revenue = 0 THEN NULL
      ELSE (current_revenue - prior_revenue) / prior_revenue
    END AS revenue_pct_change,
    SUM(current_revenue - prior_revenue) OVER () AS total_revenue_change,
    -- Units metrics
    current_units,
    prior_units,
    (current_units - prior_units) AS units_contribution,
    CASE
      WHEN prior_units = 0 THEN NULL
      ELSE (current_units - prior_units) / prior_units
    END AS units_pct_change,
    SUM(current_units - prior_units) OVER () AS total_units_change
  FROM dimension_metrics
  WHERE current_revenue != 0 OR prior_revenue != 0 OR current_units != 0 OR prior_units != 0
),
ranked AS (
  SELECT
    country,
    stock_code,
    customer_id,
    product_description,
    -- Revenue
    ROUND(current_revenue, 2) AS current_revenue,
    ROUND(prior_revenue, 2) AS prior_revenue,
    ROUND(revenue_contribution, 2) AS revenue_contribution,
    ROUND(revenue_pct_change, 6) AS revenue_pct_change,
    CASE
      WHEN total_revenue_change != 0 THEN ROUND((revenue_contribution / total_revenue_change) * 100, 2)
      ELSE NULL
    END AS revenue_contribution_pct,
    ROW_NUMBER() OVER (ORDER BY revenue_contribution DESC) AS revenue_rank_positive,
    ROW_NUMBER() OVER (ORDER BY revenue_contribution ASC) AS revenue_rank_negative,
    -- Units
    ROUND(current_units, 2) AS current_units,
    ROUND(prior_units, 2) AS prior_units,
    ROUND(units_contribution, 2) AS units_contribution,
    ROUND(units_pct_change, 6) AS units_pct_change,
    CASE
      WHEN total_units_change != 0 THEN ROUND((units_contribution / total_units_change) * 100, 2)
      ELSE NULL
    END AS units_contribution_pct,
    ROW_NUMBER() OVER (ORDER BY units_contribution DESC) AS units_rank_positive,
    ROW_NUMBER() OVER (ORDER BY units_contribution ASC) AS units_rank_negative
  FROM contributors
)
SELECT
  country,
  stock_code,
  customer_id,
  product_description,
  -- Revenue metrics
  current_revenue,
  prior_revenue,
  revenue_contribution,
  revenue_pct_change,
  revenue_contribution_pct,
  CASE
    WHEN revenue_contribution > 0 THEN 'positive'
    WHEN revenue_contribution < 0 THEN 'negative'
    ELSE 'neutral'
  END AS revenue_contributor_type,
  CASE
    WHEN revenue_contribution > 0 THEN revenue_rank_positive
    ELSE revenue_rank_negative
  END AS revenue_rank,
  -- Units metrics
  current_units,
  prior_units,
  units_contribution,
  units_pct_change,
  units_contribution_pct,
  CASE
    WHEN units_contribution > 0 THEN 'positive'
    WHEN units_contribution < 0 THEN 'negative'
    ELSE 'neutral'
  END AS units_contributor_type,
  CASE
    WHEN units_contribution > 0 THEN units_rank_positive
    ELSE units_rank_negative
  END AS units_rank
FROM ranked
WHERE (revenue_contribution > 0 AND revenue_rank_positive <= %(top_n)s)
   OR (revenue_contribution < 0 AND revenue_rank_negative <= %(top_n)s)
   OR (units_contribution > 0 AND units_rank_positive <= %(top_n)s)
   OR (units_contribution < 0 AND units_rank_negative <= %(top_n)s)
ORDER BY ABS(revenue_contribution) DESC, ABS(units_contribution) DESC;

