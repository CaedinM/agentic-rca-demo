-- sql/revenue_by_day.sql
WITH base AS (
  SELECT
    date_trunc('day', i.invoice_date) AS day,
    (ii.quantity::numeric * p.unit_price::numeric) AS line_revenue
  FROM invoice_items ii
  JOIN invoices i ON i.invoice_no = ii.invoice_no
  JOIN products p ON p.stock_code = ii.stock_code
  WHERE i.invoice_date >= %(start_ts)s
    AND i.invoice_date <  %(end_ts)s
)
SELECT
  day::date AS day,
  ROUND(SUM(line_revenue), 2) AS revenue
FROM base
GROUP BY 1
ORDER BY 1;
