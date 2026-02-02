#!/bin/bash
# Quick start script for E-commerce Semantic Search

set -e

echo "=== E-commerce Semantic Search Quick Start ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Start PostgreSQL
echo "Starting PostgreSQL with pgvector..."
docker-compose up -d postgres

echo "Waiting for PostgreSQL to be ready..."
sleep 5

# Start embedding service
echo "Building embedding service..."
cd embedding-service
docker build -t embedding-service . > /dev/null 2>&1

echo "Starting embedding service..."
docker run -d -p 8080:8080 --name embedding-service embedding-service || \
  (docker stop embedding-service && docker rm embedding-service && docker run -d -p 8080:8080 --name embedding-service embedding-service)

cd ..

echo "Waiting for embedding service to be ready..."
sleep 10

# Check services
echo ""
echo "Checking services..."
if curl -s http://localhost:8080/health > /dev/null; then
    echo "✓ Embedding service is running"
else
    echo "✗ Embedding service is not responding"
fi

if docker-compose ps postgres | grep -q "Up"; then
    echo "✓ PostgreSQL is running"
else
    echo "✗ PostgreSQL is not running"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Prepare your data file (see data-pipeline/sample_data_template.json)"
echo "2. Run data pipeline:"
echo "   cd data-pipeline"
echo "   pip install -r requirements.txt"
echo "   export EMBEDDING_SERVICE_URL=http://localhost:8080/embed"
echo "   export DATA_FILE=data/your_data.json"
echo "   python ingest_data.py"
echo ""
echo "3. Start search API:"
echo "   cd search-api"
echo "   ./mvnw spring-boot:run"
echo ""
echo "4. Test the API:"
echo "   curl -X POST http://localhost:8081/api/search \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"query\": \"wireless headphones\", \"limit\": 10}'"
echo ""
