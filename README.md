# Agentic RCA Demo

A demo application for root cause analysis using an agentic system with FastAPI backend and PostgreSQL database.

## Prerequisites

- Docker and Docker Compose
- (Optional) Python 3.9+ if you need to regenerate seed data

## Quick Start

The project is fully replicable with a single command:

```bash
docker-compose up
```

This will:
- Start a PostgreSQL 15 database with pre-loaded retail sales data
- Start the FastAPI backend on port 8000
- Automatically create schema and load seed data

## API Endpoints

### Health Check
```bash
GET http://localhost:8000/health/db
```
Returns database connection status.

### Query Endpoint
```bash
POST http://localhost:8000/query
Content-Type: application/json

{
  "sql": "SELECT * FROM customers LIMIT 10",
  "params": {}
}
```

**Note:** Only SELECT queries are allowed. The API enforces read-only access for security.

## Project Structure

```
├── backend/          # FastAPI application
│   └── app/
│       ├── api.py    # API endpoints
│       └── tools/
│           └── sql_tool.py  # SQL execution with security checks
├── db/
│   ├── init/         # Database initialization scripts
│   │   ├── 00_schema.sql      # Table definitions
│   │   ├── 01_agent_logging.sql  # Logging tables
│   │   └── 10_seed.sql        # Seed data loading
│   └── data/         # CSV seed data files (included in repo)
├── sql/
│   └── templates/    # SQL query templates
├── scripts/
│   └── prepare_seed_data.py  # Script to regenerate CSV files
└── docker-compose.yml
```

## Database Schema

The database contains normalized retail sales data:
- `customers` - Customer information
- `products` - Product catalog
- `invoices` - Invoice headers
- `invoice_items` - Invoice line items

## Regenerating Seed Data

If you need to regenerate the CSV files from the raw data:

```bash
python scripts/prepare_seed_data.py \
  --input "db/data/Online Retail Data.csv" \
  --outdir db/data
```

**Options:**
- `--include-cancellations` - Keep cancelled invoices (starting with 'C')
- `--include-returns` - Keep negative quantity rows
- `--keep-missing-customers` - Keep rows with NULL CustomerID
- `--invoice-no-as-text` - Keep invoice_no as TEXT instead of INT

## Testing

### Test KPI Queries

Run the test script to verify read-only database connection and KPI queries:

```bash
# Run from Docker container (recommended)
docker-compose exec api python -c "
import sys; sys.path.insert(0, '/app');
exec(open('/app/../scripts/test_kpi_query.py').read())"

# Or run locally (requires DATABASE_URL)
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/retail_sales"
python scripts/test_kpi_query.py
```

The test script verifies:
- Database connection
- Read-only enforcement (blocks INSERT/UPDATE/DELETE)
- Revenue KPI query
- Units KPI query
- Table row counts

## Development

### Rebuilding Services

```bash
docker-compose up --build
```

### Viewing Logs

```bash
docker-compose logs -f api
docker-compose logs -f db
```

### Stopping Services

```bash
docker-compose down
```

To also remove the database volume:
```bash
docker-compose down -v
```

## Notes

- The database persists data in a Docker volume (`pgdata`)
- SQL templates are mounted as a volume for easy access
- The API includes CORS middleware for frontend integration
- All SQL queries are validated to be read-only for security