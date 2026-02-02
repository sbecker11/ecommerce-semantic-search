# Shell Commands Reference

Quick reference for common shell commands to work with the E-commerce Semantic Search system.

## Service Management

### Start Services

```bash
# Start PostgreSQL
docker-compose up -d postgres

# Start embedding service (if not using docker-compose)
docker start embedding-service
# Or if container doesn't exist:
cd embedding-service
docker build -t embedding-service .
docker run -d -p 8080:8080 --name embedding-service embedding-service

# Start search API (in background)
cd search-api
mvn spring-boot:run &
```

### Stop Services

```bash
# Stop PostgreSQL
docker-compose down

# Stop embedding service
docker stop embedding-service

# Stop search API
pkill -f "spring-boot:run"
# Or find and kill specific process:
ps aux | grep "spring-boot:run" | grep -v grep | awk '{print $2}' | xargs kill
```

### Check Service Status

```bash
# Check all Docker containers
docker ps

# Check specific containers
docker ps | grep -E "postgres|embedding"

# Check if ports are in use
lsof -i :8080  # Embedding service
lsof -i :8081  # Search API
lsof -i :5432  # PostgreSQL

# Check service health
curl http://localhost:8080/health
curl http://localhost:8081/api/search/health
```

## Database Operations

### Connect to Database

```bash
# Connect via docker-compose
docker-compose exec postgres psql -U postgres -d ecommerce

# Or directly
docker exec -it ecommerce-postgres psql -U postgres -d ecommerce
```

### View Products

```bash
# Count total products
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products;"

# View all products
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT product_id, title, price, rating FROM products;"

# View products with pagination
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT product_id, title, price FROM products LIMIT 10;"

# View top ranked products
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT product_id, title, rating, ranking, votes FROM products ORDER BY ranking LIMIT 5;"

# Check products with embeddings
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products WHERE embedding IS NOT NULL;"
```

### Database Schema

```bash
# View table structure
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "\d products"

# List all columns
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'products';"

# Check pgvector extension
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "\dx"
```

### Database Maintenance

```bash
# Backup database
docker-compose exec -T postgres pg_dump -U postgres ecommerce > backup.sql

# Restore database
docker-compose exec -T postgres psql -U postgres -d ecommerce < backup.sql

# Clear all products (careful!)
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "TRUNCATE TABLE products;"

# Update rankings
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "WITH ranked AS (SELECT id, ROW_NUMBER() OVER (ORDER BY rating DESC, review_count DESC) as rnk FROM products) UPDATE products SET ranking = ranked.rnk FROM ranked WHERE products.id = ranked.id;"
```

## Search API Testing

### Basic Search

```bash
# Simple search query
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "wireless headphones", "limit": 5}'

# Pretty print JSON response
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "noise cancelling", "limit": 3}' | python3 -m json.tool

# Search with jq (if installed)
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "Sony audio", "limit": 5}' | jq '.results[] | {title, price, similarityScore}'
```

### Multiple Test Queries

```bash
# Test various queries
for query in "wireless headphones" "noise cancelling" "Apple AirPods" "budget earbuds"; do
  echo "Query: $query"
  curl -s -X POST http://localhost:8081/api/search \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$query\", \"limit\": 3}" | python3 -m json.tool | head -20
  echo "---"
done
```

### Extract Specific Fields

```bash
# Get only product titles
curl -s -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "headphones", "limit": 5}' | \
  python3 -c "import sys, json; [print(r['title']) for r in json.load(sys.stdin)['results']]"

# Get titles with prices
curl -s -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "headphones", "limit": 5}' | \
  python3 -c "import sys, json; [print(f\"{r['title']}: \${r['price']}\") for r in json.load(sys.stdin)['results']]"

# Get Amazon URLs
curl -s -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "headphones", "limit": 5}' | \
  python3 -c "import sys, json; [print(r['amazonUrl']) for r in json.load(sys.stdin)['results']]"
```

## Embedding Service

### Test Embedding Service

```bash
# Health check
curl http://localhost:8080/health | python3 -m json.tool

# Generate embedding
curl -X POST http://localhost:8080/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "wireless bluetooth headphones"}' | python3 -m json.tool

# Check embedding dimension
curl -s -X POST http://localhost:8080/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "test"}' | \
  python3 -c "import sys, json; print(f\"Dimension: {len(json.load(sys.stdin)['embedding'])}\")"
```

## Data Ingestion

### Ingest Sample Data

```bash
# Set environment variables
export EMBEDDING_SERVICE_URL=http://localhost:8080/embed
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ecommerce
export DB_USER=postgres
export DB_PASSWORD=postgres
export DATA_FILE=data-pipeline/data/amazon_products.json

# Run ingestion
cd data-pipeline
source venv/bin/activate
python3 ingest_data.py
```

### Prepare Data File

```bash
# Convert JSON array to JSONL format
python3 -c "import json; data = json.load(open('data-pipeline/sample_data_template.json')); [print(json.dumps(item)) for item in data]" > data-pipeline/data/amazon_products.json

# Validate JSON file
python3 -m json.tool data-pipeline/data/amazon_products.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"

# Count products in file
cat data-pipeline/data/amazon_products.json | wc -l
```

## Testing

### Run Test Scripts

```bash
# Quick test (shell script)
./test_system.sh

# Comprehensive test (Python)
export EMBEDDING_SERVICE_URL=http://localhost:8080
export SEARCH_API_URL=http://localhost:8081
python3 test_system.py

# Test with custom URLs
EMBEDDING_SERVICE_URL=http://localhost:8080 \
SEARCH_API_URL=http://localhost:8081 \
./test_system.sh
```

### Manual Testing

```bash
# Test all services are up
curl -f http://localhost:8080/health && echo "✓ Embedding service OK" || echo "✗ Embedding service DOWN"
curl -f http://localhost:8081/api/search/health && echo "✓ Search API OK" || echo "✗ Search API DOWN"
docker-compose ps postgres | grep -q "Up" && echo "✓ PostgreSQL OK" || echo "✗ PostgreSQL DOWN"

# Test search with timeout
timeout 5 curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "limit": 1}' || echo "Request timed out"
```

## Monitoring & Debugging

### View Logs

```bash
# PostgreSQL logs
docker-compose logs postgres

# Embedding service logs
docker logs embedding-service
docker logs embedding-service --tail 50
docker logs embedding-service -f  # Follow logs

# Search API logs (if running in terminal)
# Check the terminal where mvn spring-boot:run is running
```

### Performance Testing

```bash
# Time a search query
time curl -s -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "headphones", "limit": 10}' > /dev/null

# Multiple concurrent requests
for i in {1..10}; do
  curl -s -X POST http://localhost:8081/api/search \
    -H "Content-Type: application/json" \
    -d '{"query": "test", "limit": 1}' > /dev/null &
done
wait
echo "10 requests completed"
```

### Resource Usage

```bash
# Docker container stats
docker stats --no-stream

# Check memory usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Check disk usage
docker system df
docker volume ls
```

## Common Workflows

### Complete System Restart

```bash
# Stop everything
docker-compose down
docker stop embedding-service 2>/dev/null
pkill -f "spring-boot:run"

# Start everything
docker-compose up -d postgres
docker start embedding-service || (cd embedding-service && docker build -t embedding-service . && docker run -d -p 8080:8080 --name embedding-service embedding-service)
cd search-api && mvn spring-boot:run &

# Wait and verify
sleep 10
curl http://localhost:8080/health
curl http://localhost:8081/api/search/health
```

### Reset and Reingest Data

```bash
# Clear existing data
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "TRUNCATE TABLE products;"

# Reingest
cd data-pipeline
source venv/bin/activate
export EMBEDDING_SERVICE_URL=http://localhost:8080/embed
export DATA_FILE=data/amazon_products.json
python3 ingest_data.py

# Verify
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products;"
```

### Export Search Results

```bash
# Save search results to file
curl -s -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "headphones", "limit": 10}' > search_results.json

# Export as CSV
curl -s -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "headphones", "limit": 10}' | \
  python3 -c "import sys, json, csv; data = json.load(sys.stdin); w = csv.writer(sys.stdout); w.writerow(['Title', 'Price', 'Rating', 'Amazon URL']); [w.writerow([r['title'], r['price'], r['rating'], r['amazonUrl']]) for r in data['results']]" > results.csv
```

## Quick Reference

### Ports
- `5432` - PostgreSQL
- `8080` - Embedding Service
- `8081` - Search API

### Environment Variables
```bash
export EMBEDDING_SERVICE_URL=http://localhost:8080/embed
export SEARCH_API_URL=http://localhost:8081
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ecommerce
export DB_USER=postgres
export DB_PASSWORD=postgres
export DATA_FILE=data-pipeline/data/amazon_products.json
```

### Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# E-commerce search aliases
alias search-test='curl -X POST http://localhost:8081/api/search -H "Content-Type: application/json" -d'
alias search-health='curl http://localhost:8081/api/search/health'
alias embed-health='curl http://localhost:8080/health'
alias db-connect='docker-compose exec postgres psql -U postgres -d ecommerce'
alias db-count='docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products;"'
```

Then use:
```bash
search-test '{"query": "headphones", "limit": 5}' | python3 -m json.tool
search-health
db-count
```
