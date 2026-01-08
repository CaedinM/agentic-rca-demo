-- sql/revenue_window_vs_last.sql
WITH base AS (
  SELECT
    i.invoice_date,
    (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue
  FROM invoice_items ii
  JOIN invoices i ON i.invoice_no = ii.invoice_no
  JOIN products p ON p.stock_code = ii.stock_code
  WHERE (i.invoice_date >= %(prior_start_ts)s AND i.invoice_date < %(prior_end_ts)s)
     OR (i.invoice_date >= %(current_start_ts)s AND i.invoice_date < %(current_end_ts)s)
),
agg AS (
  SELECT
    SUM(CASE WHEN invoice_date >= %(current_start_ts)s AND invoice_date < %(current_end_ts)s
      THEN line_revenue ELSE 0 END) AS current_revenue,
    SUM(CASE WHEN invoice_date >= %(prior_start_ts)s AND invoice_date < %(prior_end_ts)s
      THEN line_revenue ELSE 0 END) AS prior_revenue
  FROM base
)
SELECT
  ROUND(current_revenue, 2) AS current_revenue,
  ROUND(prior_revenue, 2) AS prior_revenue,
  ROUND((current_revenue - prior_revenue), 2) AS abs_change,
  CASE
    WHEN prior_revenue = 0 THEN NULL
    ELSE ROUND((current_revenue - prior_revenue) / prior_revenue, 6)
  END AS pct_change
FROM agg;
