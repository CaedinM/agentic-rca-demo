#!/bin/bash
# Simple wrapper to run the KPI test script from the Docker container

echo "Running KPI test from Docker container..."
echo ""

docker-compose exec api python -c "
import sys
import os
sys.path.insert(0, '/app')

# Import the test script functions
import importlib.util
spec = importlib.util.spec_from_file_location('test_kpi_query', '/app/../scripts/test_kpi_query.py')
test_module = importlib.util.module_from_spec(spec)
sys.modules['test_kpi_query'] = test_module
spec.loader.exec_module(test_module)

# Run the tests
test_module.main()
"

