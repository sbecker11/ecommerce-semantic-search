# E-commerce Semantic Search

A comprehensive semantic search solution for e-commerce applications with data engineering pipeline and search API.

## Architecture

- **Data Pipeline**: Python-based pipeline to ingest Amazon products data and generate embeddings
- **Embedding Service**: HuggingFace model deployed as a service (ECS Fargate ready)
- **Database**: PostgreSQL with pgvector extension for vector search
- **Search API**: Spring Boot REST API for semantic search

## Project Structure

```
ecommerce-semantic-search/
├── data-pipeline/          # Data engineering pipeline
├── embedding-service/      # HuggingFace model inference service
├── search-api/            # Spring Boot search API
├── infrastructure/         # Docker, ECS, and deployment configs
└── evaluation/            # Fine-tuning and evaluation scripts
```

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Java 17+
- Python 3.9+
- PostgreSQL 14+ with pgvector extension

### Setup

For detailed setup instructions, see [SETUP.md](SETUP.md).

**Quick setup:**

1. **Start infrastructure**:
   ```bash
   docker-compose up -d
   ```

2. **Start embedding service**:
   ```bash
   cd embedding-service
   docker build -t embedding-service .
   docker run -d -p 8080:8080 --name embedding-service embedding-service
   ```

3. **Run data pipeline** (after preparing your data):
   ```bash
   cd data-pipeline
   pip install -r requirements.txt
   export EMBEDDING_SERVICE_URL=http://localhost:8080/embed
   export DATA_FILE=data/amazon_products.json
   python ingest_data.py
   ```

4. **Start search API**:
   ```bash
   cd search-api
   ./mvnw spring-boot:run
   # Or use Docker:
   # docker build -t search-api .
   # docker run -d -p 8081:8081 -e DB_HOST=host.docker.internal -e EMBEDDING_SERVICE_URL=http://host.docker.internal:8080/embed search-api
   ```

## API Usage

```bash
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "wireless bluetooth headphones"}'
```

## Sample Data and Amazon URL 404s

If you load the included sample/seed product data, the **Amazon URLs** returned in search results (e.g. `https://www.amazon.com/dp/B08XYZ123`) may return **404 Not Found** when opened in a browser.

**Cause:** The sample data uses placeholder product IDs (e.g. `B08XYZ123`, `B09ABC456`) that are not real Amazon ASINs. The URLs are built correctly as `https://www.amazon.com/dp/{product_id}`, but those IDs do not correspond to real products on Amazon, so the pages do not exist.

**What works:** Semantic search, embeddings, and the Search API all behave correctly; only the destination links are invalid for sample data.

**Options:**

1. **Use real product data**  
   Ingest a dataset that contains real Amazon product IDs (and optionally real `amazon_url` or `url` fields). The data pipeline will store them and the Search API will return valid links.

2. **Check which URLs are valid**  
   From the repo root, run the URL check script to see the HTTP status of each product link:
   ```bash
   ./check_amazon_urls.sh
   ```
   It reports how many URLs return 200 vs 404 (or other errors).

**Summary:** 404s on Amazon links are expected when using the sample product set. Replace or supplement with real product data to get working links.

## Fine-tuning

See `evaluation/` directory for fine-tuning scripts and evaluation metrics.
