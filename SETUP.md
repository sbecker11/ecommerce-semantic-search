# Setup Guide

Complete setup instructions for the E-commerce Semantic Search system.

## Prerequisites

- Docker and Docker Compose
- Java 17+ (for Spring Boot API)
- Python 3.9+ (for data pipeline and evaluation)
- Maven 3.6+ (or use Maven wrapper)
- PostgreSQL 14+ with pgvector extension (or use Docker)

## JDK Version Management

This project requires Java 17+. If you need to manage multiple JDK versions, we recommend using **jenv** (available via Homebrew).

### Install jenv

```bash
brew install jenv
```

Add jenv to your shell profile (`~/.zshrc` for zsh or `~/.bash_profile` for bash):

```bash
export PATH="$HOME/.jenv/bin:$PATH"
eval "$(jenv init -)"
```

Reload your shell:
```bash
source ~/.zshrc  # or source ~/.bash_profile
```

### Install Java 17

Install OpenJDK 17 via Homebrew:

```bash
brew install openjdk@17
```

Add it to jenv:

```bash
# For Apple Silicon (M1/M2 Macs)
jenv add /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

# For Intel Macs
jenv add /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

### Set Java Version

Set Java 17 as the global default:

```bash
jenv global 17.0
```

Or set it locally for this project (creates `.java-version` file):

```bash
cd search-api
jenv local 17.0
```

### Verify Installation

Check that Java 17 is active:

```bash
java -version
# Should show: openjdk version "17.x.x"
```

List all installed versions:

```bash
jenv versions
```

### Alternative: SDKMAN!

If you prefer SDKMAN! (installed via curl, not Homebrew):

```bash
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 17.0.9-tem
sdk use java 17.0.9-tem
```

## Step 1: Start Infrastructure

Start PostgreSQL with pgvector:

```bash
docker-compose up -d postgres
```

Wait for PostgreSQL to be ready (check logs):
```bash
docker-compose logs postgres
```

## Step 2: Start Embedding Service

Build and start the embedding service:

```bash
cd embedding-service
docker build -t embedding-service .
docker run -d -p 8080:8080 --name embedding-service embedding-service
```

Or use docker-compose:
```bash
docker-compose up -d embedding-service
```

Verify it's running:
```bash
curl http://localhost:8080/health
```

## Step 3: Prepare Data

Download or prepare your Amazon products dataset. You can use the sample template:

```bash
cd data-pipeline
# Place your data file in data/ directory
# Or use the sample template as reference
```

Example data format (JSON):
```json
[
  {
    "product_id": "B08XYZ123",
    "title": "Product Title",
    "description": "Product description...",
    "category": "Electronics",
    "brand": "Brand Name",
    "price": 99.99,
    "rating": 4.5,
    "review_count": 1000
  }
]
```

## Step 4: Run Data Pipeline

Install Python dependencies and run the ingestion pipeline:

```bash
cd data-pipeline
pip install -r requirements.txt

# Set environment variables
export EMBEDDING_SERVICE_URL=http://localhost:8080/embed
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ecommerce
export DB_USER=postgres
export DB_PASSWORD=postgres
export DATA_FILE=data/amazon_products.json

# Run ingestion
python ingest_data.py
```

The pipeline will:
1. Load products from your data file
2. Generate embeddings using the embedding service
3. Store products with embeddings in PostgreSQL

## Step 5: Start Search API

Build and run the Spring Boot API:

```bash
cd search-api

# Using Maven wrapper (if available)
./mvnw clean package
./mvnw spring-boot:run

# Or using Docker
docker build -t search-api .
docker run -d -p 8081:8081 \
  -e DB_HOST=host.docker.internal \
  -e EMBEDDING_SERVICE_URL=http://host.docker.internal:8080/embed \
  search-api
```

Verify it's running:
```bash
curl http://localhost:8081/api/search/health
```

## Step 6: Test the API

Search for products:

```bash
curl -X POST http://localhost:8081/api/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "wireless bluetooth headphones",
    "limit": 10
  }'
```

## Step 7: Fine-tuning (Optional)

To improve search relevancy:

1. Prepare training data (see `evaluation/sample_training_data.json`)
2. Prepare evaluation data (see `evaluation/sample_eval_data.json`)
3. Run fine-tuning:

```bash
cd evaluation
pip install -r requirements.txt

python fine_tune_model.py \
  --base-model sentence-transformers/all-MiniLM-L6-v2 \
  --train-data sample_training_data.json \
  --eval-data sample_eval_data.json \
  --output ../models/fine-tuned-model \
  --epochs 3
```

4. Update embedding service to use fine-tuned model:
   - Update `MODEL_NAME` environment variable
   - Or rebuild Docker image with fine-tuned model

## Step 8: Evaluate Search Quality (Optional)

Evaluate search relevancy metrics:

```bash
cd evaluation

# Prepare test queries (see sample_test_queries.json)
python evaluate_search.py \
  --api-url http://localhost:8081/api/search \
  --test-data sample_test_queries.json \
  --k-values 5 10 20
```

## Troubleshooting

### Java Version Issues
- Verify Java 17+ is installed: `java -version`
- If using jenv, ensure it's properly initialized: `jenv versions`
- Check JAVA_HOME is set correctly: `echo $JAVA_HOME`
- For Maven issues, ensure Maven uses correct Java version: `mvn -version`
- If you see "Unsupported class file major version" errors, you need Java 17+

### Database Connection Issues
- Ensure PostgreSQL is running: `docker-compose ps`
- Check connection string in environment variables
- Verify pgvector extension is installed: `docker-compose exec postgres psql -U postgres -d ecommerce -c "CREATE EXTENSION IF NOT EXISTS vector;"`

### Embedding Service Issues
- Check service logs: `docker logs embedding-service`
- Verify model download (first run may take time)
- Check port 8080 is available

### Search API Issues
- Check database connection settings
- Verify embedding service URL is accessible
- Check API logs for errors

## Production Deployment

For production deployment on AWS ECS Fargate:

1. Build and push Docker images to ECR
2. Update ECS task definitions
3. Configure RDS PostgreSQL (instead of containerized DB)
4. Set up Application Load Balancer
5. Configure auto-scaling

See `infrastructure/README.md` for detailed ECS deployment instructions.
