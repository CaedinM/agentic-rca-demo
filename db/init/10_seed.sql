-- Load seed data from CSV files
-- Note: CSV files are included in the repository in db/data/ directory
-- These files are generated from the raw "Online Retail Data.csv" using scripts/prepare_seed_data.py
-- The COPY commands will load the data automatically when the database is initialized

-- Load customers (no dependencies)
COPY customers FROM '/db/data/customers.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Load products (no dependencies)
COPY products FROM '/db/data/products.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Load invoices (depends on customers)
COPY invoices FROM '/db/data/invoices.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Load invoice_items (depends on invoices and products)
-- Note: id column is SERIAL, so it will auto-increment
COPY invoice_items(invoice_no, stock_code, quantity) FROM '/db/data/invoice_items.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

