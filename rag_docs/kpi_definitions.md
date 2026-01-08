# KPI Definitions (Retail Sales BI)

This project computes KPIs from the normalized schema:

- `invoices(invoice_no, invoice_date)`
- `invoice_items(id, invoice_no, stock_code, customer_id, quantity)`
- `products(stock_code, description, unit_price)`
- `customers(customer_id, country)`

All KPI computations use joins:
`invoice_items -> invoices` on `invoice_no`
`invoice_items -> products` on `stock_code`
`invoice_items -> customers` on `customer_id`

---

## Time Column

**Primary time column:** `invoices.invoice_date` (TIMESTAMP)

All KPI calculations should filter by `invoice_date` to define the time window. The time column is located on the `invoices` table and must be joined through `invoice_items` to access it.

**Example filter:**
```sql
WHERE i.invoice_date >= %(start_ts)s 
  AND i.invoice_date < %(end_ts)s
```

---

## Key Dimensions

KPIs can be aggregated by the following dimensions:

- **Time:** `invoice_date` (can be truncated to day, week, month, etc.)
- **Geography:** `customers.country`
- **Product:** `products.stock_code` (SKU), `products.description`
- **Customer:** `customers.customer_id`
- **Invoice:** `invoices.invoice_no` (for order-level metrics)

**Grain:** The base grain is `invoice_items` (line-item level). All KPIs are aggregated from this grain.

---

## Revenue

**Definition:** Total sales value in the window.

**SQL formula (conceptual):**
`SUM(invoice_items.quantity * products.unit_price)`

**Time column:** `invoices.invoice_date`

**Key dimensions:** Can be aggregated by day, country, stock_code (SKU), customer_id, or invoice_no

**Grain:** invoice_item line-level aggregated to the requested level (day, country, SKU, etc.)

**Filters:**
- Filter by `invoice_date` to define time window
- Optional filters: `country`, `stock_code`, `customer_id`

**Assumptions / caveats:**
- No discounts, taxes, shipping, or returns are modeled in this schema.
- `unit_price` is stored on `products`; if historical prices changed over time but the table only stores the latest price, past revenue may be mis-stated.

---

## Units

**Definition:** Total units sold in the window.

**SQL formula (conceptual):**
`SUM(invoice_items.quantity)`

**Time column:** `invoices.invoice_date`

**Key dimensions:** Can be aggregated by day, country, stock_code (SKU), customer_id, or invoice_no

**Grain:** invoice_item line-level aggregated to the requested level

**Filters:**
- Filter by `invoice_date` to define time window
- Optional filters: `country`, `stock_code`, `customer_id`

**Assumptions / caveats:**
- If quantity can be negative (returns/corrections), units may net out.

---

## AOV Proxy (Average Order Value)

**Definition:** Revenue per invoice (invoice_no), in the window.

**SQL formula (conceptual):**
`SUM(quantity * unit_price) / COUNT(DISTINCT invoice_no)`

**Time column:** `invoices.invoice_date`

**Key dimensions:** Can be aggregated by day, country, or customer_id (invoice-level metric)

**Grain:** Aggregated to invoice level (invoice_no)

**Filters:**
- Filter by `invoice_date` to define time window
- Optional filters: `country`, `customer_id`

**Assumptions / caveats:**
- `invoice_no` is treated as the order identifier.
- If invoices can represent non-standard "orders" (e.g., adjustments), AOV will be skewed.

---
