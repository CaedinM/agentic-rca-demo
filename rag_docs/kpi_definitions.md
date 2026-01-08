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

## Revenue

**Definition:** Total sales value in the window.

**SQL formula (conceptual):**
`SUM(invoice_items.quantity * products.unit_price)`

**Grain:** invoice_item line-level aggregated to the requested level (day, country, SKU, etc.)

**Assumptions / caveats:**
- No discounts, taxes, shipping, or returns are modeled in this schema.
- `unit_price` is stored on `products`; if historical prices changed over time but the table only stores the latest price, past revenue may be mis-stated.

---

## Units

**Definition:** Total units sold in the window.

**SQL formula (conceptual):**
`SUM(invoice_items.quantity)`

**Assumptions / caveats:**
- If quantity can be negative (returns/corrections), units may net out.

---

## AOV Proxy (Average Order Value)

**Definition:** Revenue per invoice (invoice_no), in the window.

**SQL formula (conceptual):**
`SUM(quantity * unit_price) / COUNT(DISTINCT invoice_no)`

**Assumptions / caveats:**
- `invoice_no` is treated as the order identifier.
- If invoices can represent non-standard “orders” (e.g., adjustments), AOV will be skewed.

---
