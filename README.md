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

## Sample Data and Amazon URLs

The included sample data uses **real Amazon ASINs** for the headphone/earbud products (e.g. Sony WH-1000XM4, Apple AirPods Pro), so `amazon_url` links in search results point to real product pages.

**If your database was seeded with older placeholder IDs** (e.g. `B08XYZ123`, `B09ABC456`) and links return 404, update existing rows to real ASINs with:

```bash
docker-compose exec -T postgres psql -U postgres -d ecommerce < infrastructure/update_product_ids_to_real_asin.sql
```

**Check which URLs are valid** (from repo root):

```bash
./check_amazon_urls.sh
```

## Production: ECS Fargate

The **embedding service** is ECS Fargate ready: it runs in a container and can be deployed to AWS without managing EC2 instances.

**What’s included:**

- **Task definition** — `infrastructure/ecs-task-definition.json` (Fargate, 2 vCPU / 4 GB, health check, CloudWatch logs)
- **Deploy script** — `infrastructure/deploy.sh` builds the image, pushes to ECR, and updates the ECS service

**Deploy the embedding service:**

1. Create an ECS cluster and service (see [infrastructure/README.md](infrastructure/README.md)).
2. From `infrastructure/`, run:
   ```bash
   ./deploy.sh
   ```
   (Set `AWS_REGION`, `ECR_REPO`, `CLUSTER_NAME`, `SERVICE_NAME` if needed.)

The Search API and database are not in the ECS setup; use RDS for Postgres and run the Search API elsewhere (e.g. EC2 or ECS) and point it at the embedding service URL and DB.

## Fine-tuning

See `evaluation/` directory for fine-tuning scripts and evaluation metrics.
