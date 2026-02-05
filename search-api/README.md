# Semantic Search API

Spring Boot REST API for semantic product search using vector similarity.

## Features

- POST endpoint for semantic search
- Vector similarity search using PostgreSQL pgvector
- Integration with embedding service
- Configurable search limits
- Health check endpoint

## Build

```bash
./mvnw clean package
```

## Unit Tests & Coverage

Run tests:

```bash
./mvnw test
```

Generate test coverage report (JaCoCo):

```bash
./mvnw test
```

Coverage report is written to `target/site/jacoco/index.html`. Open in a browser to view line-by-line coverage.

## Run Locally

```bash
./mvnw spring-boot:run
```

Or with Docker:
```bash
docker build -t search-api .
docker run -p 8081:8081 \
  -e DB_HOST=localhost \
  -e DB_PORT=5432 \
  -e DB_NAME=ecommerce \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  -e EMBEDDING_SERVICE_URL=http://localhost:8080/embed \
  search-api
```

## API Endpoints

### Search Products
```bash
POST /api/search
Content-Type: application/json

{
  "query": "wireless bluetooth headphones",
  "limit": 10
}
```

Response:
```json
{
  "results": [
    {
      "productId": "B08XYZ123",
      "title": "Sony WH-1000XM4 Wireless Headphones",
      "description": "...",
      "category": "Electronics",
      "brand": "Sony",
      "price": 349.99,
      "rating": 4.8,
      "reviewCount": 12500,
      "imageUrl": "https://...",
      "similarityScore": 0.92
    }
  ],
  "total": 10,
  "query": "wireless bluetooth headphones",
  "maxScore": 0.92
}
```

### Health Check
```bash
GET /api/search/health
```

## Configuration

See `src/main/resources/application.yml` for configuration options:

- Database connection settings
- Embedding service URL
- Search limits
- Server port

## Environment Variables

- `DB_HOST`: PostgreSQL host (default: localhost)
- `DB_PORT`: PostgreSQL port (default: 5432)
- `DB_NAME`: Database name (default: ecommerce)
- `DB_USER`: Database user (default: postgres)
- `DB_PASSWORD`: Database password (default: postgres)
- `EMBEDDING_SERVICE_URL`: Embedding service URL (default: http://localhost:8080/embed)
- `SERVER_PORT`: API server port (default: 8081)
- `SEARCH_LIMIT`: Default search limit (default: 10)
- `SEARCH_MAX_LIMIT`: Maximum search limit (default: 100)
