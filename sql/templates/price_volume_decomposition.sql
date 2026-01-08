-- sql/templates/price_volume_decomposition.sql
-- Decompose revenue change into price effect vs volume effect
-- Uses Laspeyres decomposition: ΔRevenue = Price Effect + Volume Effect
--
-- Parameters:
--   current_start_ts: Start of current window (TIMESTAMP)
--   current_end_ts: End of current window (TIMESTAMP)
--   prior_start_ts: Start of prior window (TIMESTAMP)
--   prior_end_ts: End of prior window (TIMESTAMP)

WITH base AS (
  SELECT
    p.stock_code,
    i.invoice_date,
    ii.quantity,
    p.unit_price,
    (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue
  FROM invoice_items ii
  JOIN invoices i ON i.invoice_no = ii.invoice_no
  JOIN products p ON p.stock_code = ii.stock_code
  WHERE (i.invoice_date >= %(prior_start_ts)s AND i.invoice_date < %(prior_end_ts)s)
     OR (i.invoice_date >= %(current_start_ts)s AND i.invoice_date < %(current_end_ts)s)
),
product_metrics AS (
  SELECT
    stock_code,
    -- Current period
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN quantity ELSE 0 END) AS current_quantity,
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN line_revenue ELSE 0 END) AS current_revenue,
    -- Prior period
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN quantity ELSE 0 END) AS prior_quantity,
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN line_revenue ELSE 0 END) AS prior_revenue,
    -- Average prices
    CASE 
      WHEN SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s THEN quantity ELSE 0 END) > 0
      THEN SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s THEN line_revenue ELSE 0 END) /
           SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s THEN quantity ELSE 0 END)
      ELSE NULL
    END AS current_avg_price,
    CASE 
      WHEN SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s THEN quantity ELSE 0 END) > 0
      THEN SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s THEN line_revenue ELSE 0 END) /
           SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s THEN quantity ELSE 0 END)
      ELSE NULL
    END AS prior_avg_price
  FROM base
  GROUP BY stock_code
),
decomposition AS (
  SELECT
    -- Total changes
    SUM(current_revenue) AS current_revenue,
    SUM(prior_revenue) AS prior_revenue,
    SUM(current_revenue - prior_revenue) AS total_revenue_change,
    SUM(current_quantity) AS current_quantity,
    SUM(prior_quantity) AS prior_quantity,
    SUM(current_quantity - prior_quantity) AS total_quantity_change,
    -- Price effect: (current_price - prior_price) * prior_quantity
    SUM((COALESCE(current_avg_price, 0) - COALESCE(prior_avg_price, 0)) * prior_quantity) AS price_effect,
    -- Volume effect: prior_price * (current_quantity - prior_quantity)
    SUM(COALESCE(prior_avg_price, 0) * (current_quantity - prior_quantity)) AS volume_effect
  FROM product_metrics
)
SELECT
  ROUND(current_revenue, 2) AS current_revenue,
  ROUND(prior_revenue, 2) AS prior_revenue,
  ROUND(total_revenue_change, 2) AS total_revenue_change,
  ROUND(price_effect, 2) AS price_effect,
  ROUND(volume_effect, 2) AS volume_effect,
  ROUND(price_effect + volume_effect, 2) AS decomposition_total,
  CASE
    WHEN total_revenue_change != 0 THEN
      ROUND((price_effect / total_revenue_change) * 100, 2)
    ELSE NULL
  END AS price_effect_pct,
  CASE
    WHEN total_revenue_change != 0 THEN
      ROUND((volume_effect / total_revenue_change) * 100, 2)
    ELSE NULL
  END AS volume_effect_pct,
  current_quantity,
  prior_quantity,
  total_quantity_change
FROM decomposition;

