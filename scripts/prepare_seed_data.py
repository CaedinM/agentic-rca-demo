# scripts/prepare_seed_data.py
from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


# ====== EDIT THESE TO MATCH YOUR POSTGRES SCHEMA COLUMN NAMES ======
# Note: The schema (db/init/00_schema.sql) uses INT for invoice_no
# The script defaults to INT (numeric only). Use --invoice-no-as-text if needed.
CUSTOMERS_TABLE = "customers"
PRODUCTS_TABLE = "products"
INVOICES_TABLE = "invoices"
INVOICE_ITEMS_TABLE = "invoice_items"

# Output CSV columns (must match your SQL table definitions / COPY statements)
COLS_CUSTOMERS = ["customer_id", "country"]
COLS_PRODUCTS = ["stock_code", "description", "unit_price"]
COLS_INVOICES = ["invoice_no", "customer_id", "invoice_date"]
COLS_INVOICE_ITEMS = ["invoice_no", "stock_code", "quantity"]
# ===================================================================


def load_raw(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)

    # Normalize raw column names (dataset uses: InvoiceNo, StockCode, ...)
    expected = ["InvoiceNo", "StockCode", "Description", "Quantity", "InvoiceDate", "UnitPrice", "CustomerID", "Country"]
    missing = [c for c in expected if c not in df.columns]
    if missing:
        raise ValueError(f"Missing expected columns in raw CSV: {missing}. Found: {list(df.columns)}")

    # Basic cleanup
    df["StockCode"] = df["StockCode"].astype(str).str.strip()
    df["Description"] = df["Description"].astype(str).str.strip()
    df["Country"] = df["Country"].astype(str).str.strip()

    # Parse datetime (format like 12/1/10 8:26)
    df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"], errors="coerce")

    # Numeric cleanup
    df["UnitPrice"] = pd.to_numeric(df["UnitPrice"], errors="coerce")
    df["Quantity"] = pd.to_numeric(df["Quantity"], errors="coerce").astype("Int64")

    # CustomerID is float in the raw file; convert to nullable integer
    df["CustomerID"] = pd.to_numeric(df["CustomerID"], errors="coerce").astype("Int64")

    return df


def transform(
    df: pd.DataFrame,
    include_cancellations: bool,
    include_returns: bool,
    drop_missing_customers: bool,
    invoice_no_as_text: bool,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    # Cancellations are invoices starting with "C" in this dataset
    is_cancel = df["InvoiceNo"].astype(str).str.startswith("C", na=False)
    if not include_cancellations:
        df = df[~is_cancel].copy()

    # Returns often have negative quantities
    if not include_returns:
        df = df[df["Quantity"].fillna(0) > 0].copy()

    # Missing customer IDs
    if drop_missing_customers:
        df = df[df["CustomerID"].notna()].copy()

    # Drop rows with broken essentials
    df = df.dropna(subset=["InvoiceNo", "StockCode", "InvoiceDate", "UnitPrice", "Quantity"])

    # InvoiceNo: either keep text (safer) or convert to int (if your PK is INT)
    if invoice_no_as_text:
        df["_invoice_no"] = df["InvoiceNo"].astype(str).str.strip()
    else:
        # Keep only numeric invoice numbers
        inv = df["InvoiceNo"].astype(str).str.strip()
        is_numeric = inv.str.fullmatch(r"\d+")
        df = df[is_numeric].copy()
        df["_invoice_no"] = inv[is_numeric].astype(int)

    # CustomerID -> int
    df["_customer_id"] = df["CustomerID"].astype("Int64")
    df["_stock_code"] = df["StockCode"].astype(str).str.strip()

    # ---- customers ----
    customers = (
        df[["_customer_id", "Country"]]
        .dropna(subset=["_customer_id"])
        .drop_duplicates(subset=["_customer_id"], keep="last")
        .rename(columns={"_customer_id": "customer_id", "Country": "country"})
        .sort_values("customer_id")
        .reset_index(drop=True)
    )

    # ---- products ----
    # UnitPrice can vary. We'll use the most common (mode) per StockCode, fallback to median.
    def pick_price(s: pd.Series) -> float:
        s2 = s.dropna()
        if s2.empty:
            return float("nan")
        mode = s2.mode()
        if not mode.empty:
            return float(mode.iloc[0])
        return float(s2.median())

    products = (
        df.groupby("_stock_code", as_index=False)
        .agg(
            description=("Description", lambda x: x.dropna().iloc[0] if len(x.dropna()) else ""),
            unit_price=("UnitPrice", pick_price),
        )
        .rename(columns={"_stock_code": "stock_code"})
        .sort_values("stock_code")
        .reset_index(drop=True)
    )

    # ---- invoices ----
    invoices = (
        df[["_invoice_no", "_customer_id", "InvoiceDate"]]
        .dropna(subset=["_invoice_no"])
        .drop_duplicates(subset=["_invoice_no"], keep="first")
        .rename(columns={"_invoice_no": "invoice_no", "_customer_id": "customer_id", "InvoiceDate": "invoice_date"})
        .sort_values("invoice_no")
        .reset_index(drop=True)
    )

    # ---- invoice_items ----
    invoice_items = (
        df[["_invoice_no", "_stock_code", "Quantity"]]
        .rename(
            columns={
                "_invoice_no": "invoice_no",
                "_stock_code": "stock_code",
                "Quantity": "quantity",
            }
        )
        .sort_values(["invoice_no", "stock_code"])
        .reset_index(drop=True)
    )

    # Align to schema column lists
    customers = customers[COLS_CUSTOMERS]
    products = products[COLS_PRODUCTS]
    invoices = invoices[COLS_INVOICES]
    invoice_items = invoice_items[COLS_INVOICE_ITEMS]

    return customers, products, invoices, invoice_items


def write_csv(df: pd.DataFrame, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_path, index=False)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, help="Path to raw Online Retail CSV")
    p.add_argument("--outdir", default="db/data", help="Output folder for generated CSVs")
    p.add_argument("--include-cancellations", action="store_true", help="Keep invoices starting with 'C'")
    p.add_argument("--include-returns", action="store_true", help="Keep negative-quantity rows")
    p.add_argument("--keep-missing-customers", action="store_true", help="Keep rows with NULL CustomerID (not recommended)")
    p.add_argument("--invoice-no-as-text", action="store_true", help="Keep invoice_no as TEXT instead of INT")
    args = p.parse_args()

    raw_path = Path(args.input).expanduser().resolve()
    outdir = Path(args.outdir).expanduser().resolve()

    df = load_raw(raw_path)
    customers, products, invoices, invoice_items = transform(
        df=df,
        include_cancellations=args.include_cancellations,
        include_returns=args.include_returns,
        drop_missing_customers=not args.keep_missing_customers,
        invoice_no_as_text=args.invoice_no_as_text,
    )

    write_csv(customers, outdir / f"{CUSTOMERS_TABLE}.csv")
    write_csv(products, outdir / f"{PRODUCTS_TABLE}.csv")
    write_csv(invoices, outdir / f"{INVOICES_TABLE}.csv")
    write_csv(invoice_items, outdir / f"{INVOICE_ITEMS_TABLE}.csv")

    print("Wrote:")
    print(f"  {outdir / f'{CUSTOMERS_TABLE}.csv'}  rows={len(customers):,}")
    print(f"  {outdir / f'{PRODUCTS_TABLE}.csv'}   rows={len(products):,}")
    print(f"  {outdir / f'{INVOICES_TABLE}.csv'}   rows={len(invoices):,}")
    print(f"  {outdir / f'{INVOICE_ITEMS_TABLE}.csv'} rows={len(invoice_items):,}")


if __name__ == "__main__":
    main()
