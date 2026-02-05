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

1. **Start all services** (PostgreSQL + embedding service + status checks):
   ```bash
   ./start_system.sh
   ```

   **Stop all services**: `./stop_system.sh`

2. **Or start individually**:
   ```bash
   docker-compose up -d postgres
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

**Verify services** (with timeouts to avoid hanging):
```bash
./test_system.sh
# Or check embedding health: curl -s --max-time 10 http://localhost:8080/health
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

**Where to run the rest:**

| Component      | Where to run | Notes |
|----------------|--------------|--------|
| **Database**   | **Amazon RDS** (PostgreSQL) | Use RDS with the pgvector extension (Postgres 14+). Create a DB subnet group, enable the extension in your schema, and run `init-db.sql` (or equivalent) to create the `products` table and indexes. Point the Search API and data pipeline at the RDS endpoint. |
| **Search API** | **ECS Fargate**, **EC2**, or **App Runner** | Run the Spring Boot app in a container. ECS Fargate: add a task definition and service for the search-api image (like the embedding service), put an ALB in front, and set env vars `DB_HOST` (RDS endpoint), `EMBEDDING_SERVICE_URL` (embedding service URL, e.g. ALB or service discovery). EC2: run the JAR or container on an instance. App Runner: deploy the container and configure the same env vars. |
| **Data pipeline** | **Your machine**, **EC2**, or **scheduled job** | Run the ingestion script when you have new data. Optionally run it on a cron (e.g. EC2 or Lambda + Step Functions) or from a CI/CD pipeline. It needs network access to RDS, the embedding service, and (if used) S3 or other data sources. |

In all cases, the Search API needs `DB_HOST`, `DB_*` credentials, and `EMBEDDING_SERVICE_URL` pointing at the deployed embedding service (e.g. `https://embedding-alb-xxx.us-east-1.elb.amazonaws.com`).

## Ingestion Pipeline

The `data-pipeline/` script (run locally or on a schedule) is sufficient for small or batch loads. For a more sophisticated, partner-driven pipeline on AWS you can use:

1. **Data partners** write new product data to **designated S3 buckets** (e.g. a landing bucket per partner or per feed).
2. **S3 event notifications** (e.g. `s3:ObjectCreated:*`) invoke a **Lambda** when new objects arrive.
3. **Lambda** starts **Glue crawler(s)** (e.g. `glue.start_crawler`) so the new data is discovered and cataloged.
4. **Glue crawlers** run against the bucket(s), infer schema, and update the **Glue Data Catalog**.

Once the catalog is updated, the step that **loads data into semantic search** (read from S3 or the catalog → call the embedding service → write vectors to Postgres/RDS) can be implemented as:

- A **Glue ETL job** that reads from the Glue Data Catalog (or S3), calls your embedding service API, and writes to your database, or  
- A **Lambda**, **Step Functions** workflow, or **scheduled job** that runs the same read → embed → load logic (e.g. the existing `ingest_data.py` logic invoked from a job).

This keeps raw data cataloged and queryable in the Data Catalog while the embedding + load step feeds the search system.

## Fine-tuning

See `evaluation/` directory for fine-tuning scripts and evaluation metrics.
