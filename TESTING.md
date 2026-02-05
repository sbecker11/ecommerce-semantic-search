./# Testing Guide

This guide explains how to test the E-commerce Semantic Search system.

## Quick Test (Shell Script)

For a quick connectivity and basic functionality test:

```bash
# With default URLs (localhost:8080 and localhost:8081)
./test_system.sh

# Or with custom URLs
EMBEDDING_SERVICE_URL=http://localhost:8080 \
SEARCH_API_URL=http://localhost:8081 \
./test_system.sh
```

This script tests:
- Embedding service health
- Search API health
- Database connectivity
- Basic search functionality
- Multiple search queries

## Comprehensive Test (Python Script)

For detailed testing of all system components:

```bash
# Install dependencies (if not already installed)
cd data-pipeline
python3 -m venv venv
source venv/bin/activate
pip install psycopg2-binary requests

# Run comprehensive tests (recommended: set environment variables)
cd ..
export EMBEDDING_SERVICE_URL=http://localhost:8080
export SEARCH_API_URL=http://localhost:8081
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ecommerce
export DB_USER=postgres
export DB_PASSWORD=postgres

python3 test_system.py
```

Or with inline environment variables:

```bash
export EMBEDDING_SERVICE_URL=http://localhost:8080
export SEARCH_API_URL=http://localhost:8081
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ecommerce
export DB_USER=postgres
export DB_PASSWORD=postgres

python3 test_system.py
```

### Test Coverage

The comprehensive test script (`test_system.py`) covers:

1. **Database Connection**
   - PostgreSQL connectivity
   - pgvector extension verification
   - Table schema validation
   - Product count and embedding coverage

2. **Embedding Service**
   - Health check
   - Model information
   - Embedding generation (dimension validation)

3. **Search API**
   - Health check
   - Multiple search queries
   - Response structure validation
   - Field completeness check

4. **Data Quality**
   - Null value checks for critical fields
   - Price consistency (unit_price)
   - Ranking and votes validation

5. **Search Ranking**
   - Similarity score ordering
   - Result sorting validation

## Manual Testing

### Test Search API Directly

```bash
# Health check
curl http://localhost:8081/api/search/health

# Search query
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "wireless headphones", "limit": 5}'

# Pretty print results
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "noise cancelling", "limit": 3}' | python3 -m json.tool
```

### Test Embedding Service

```bash
# Health check
curl http://localhost:8080/health

# Generate embedding
curl -X POST http://localhost:8080/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "wireless headphones"}' | python3 -m json.tool
```

### Test Database

```bash
# Check product count
docker-compose exec postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products;"

# Check products with embeddings
docker-compose exec postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products WHERE embedding IS NOT NULL;"

# View sample products
docker-compose exec postgres psql -U postgres -d ecommerce -c "SELECT product_id, title, price, rating, ranking, votes FROM products LIMIT 5;"
```

## Test Queries

The test scripts use these sample queries:

- "wireless headphones"
- "noise cancelling earbuds"
- "Sony audio devices"
- "Apple AirPods"
- "budget wireless earbuds under 150"

## Expected Results

### Successful Test Output

- All services should respond with HTTP 200
- Database should have products with embeddings
- Search queries should return results with similarity scores
- Results should be sorted by similarity (descending)
- All required fields should be present in responses

### Common Issues

1. **Service not responding**
   - Check if services are running: `docker ps` and `ps aux | grep spring-boot`
   - Verify ports: 8080 (embedding), 8081 (search API), 5432 (PostgreSQL)

2. **No search results**
   - Verify products exist: `docker-compose exec postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products;"`
   - Check embeddings: `docker-compose exec postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products WHERE embedding IS NOT NULL;"`

3. **Database connection errors**
   - Ensure PostgreSQL is running: `docker-compose ps`
   - Check connection string in environment variables

## Continuous Testing

For CI/CD pipelines, use the Python test script:

```bash
python3 test_system.py
```

Exit code 0 = all tests passed
Exit code 1 = one or more tests failed
