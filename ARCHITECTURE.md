# Architecture Overview

## System Architecture

```
┌─────────────────┐
│   Client App    │
└────────┬────────┘
         │
         │ HTTP POST /api/search
         ▼
┌─────────────────────────────────┐
│   Spring Boot Search API        │
│   (Port 8081)                   │
│                                 │
│  - Receives search queries      │
│  - Calls embedding service      │
│  - Performs vector search       │
│  - Returns ranked results       │
└────────┬────────────────────────┘
         │
         ├─────────────────┬──────────────────┐
         │                 │                  │
         ▼                 ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Embedding   │  │  PostgreSQL  │  │  Embedding   │
│  Service     │  │  + pgvector  │  │  Service     │
│  (Port 8080) │  │  (Port 5432) │  │  (ECS)       │
└──────────────┘  └──────────────┘  └──────────────┘
```

## Components

### 1. Data Engineering Pipeline (`data-pipeline/`)

**Purpose**: Ingest Amazon products data and generate vector embeddings

**Technology**: Python 3.9+

**Process**:
1. Loads product data from JSON/CSV files
2. Creates searchable text from product fields (title, description, brand, category)
3. Calls embedding service to generate vector embeddings
4. Stores products with embeddings in PostgreSQL

**Key Files**:
- `ingest_data.py`: Main ingestion script
- `requirements.txt`: Python dependencies

### 2. Embedding Service (`embedding-service/`)

**Purpose**: Generate text embeddings using HuggingFace models

**Technology**: 
- Flask (Python)
- Sentence Transformers (HuggingFace)
- Docker/ECS Fargate ready

**Features**:
- Single text embedding endpoint
- Batch embedding endpoint
- Health check endpoint
- Configurable model (default: `all-MiniLM-L6-v2`)

**Deployment**:
- Local: Docker container
- Production: ECS Fargate (see `infrastructure/ecs-task-definition.json`)

**API Endpoints**:
- `POST /embed`: Generate embedding for single text
- `POST /embed/batch`: Generate embeddings for multiple texts
- `GET /health`: Health check

### 3. Database (`infrastructure/`)

**Purpose**: Store products with vector embeddings

**Technology**: PostgreSQL 14+ with pgvector extension

**Schema**:
- `products` table with vector field (384 dimensions)
- IVFFlat index for efficient vector similarity search
- Full-text search indexes on title and description

**Vector Operations**:
- Cosine similarity search using `<=>` operator
- Results sorted by similarity (1 - distance)

### 4. Search API (`search-api/`)

**Purpose**: REST API for semantic product search

**Technology**: Spring Boot 3.2, Java 17

**Features**:
- POST endpoint for semantic search
- Vector similarity search using pgvector
- Configurable result limits
- Error handling and validation

**API Endpoints**:
- `POST /api/search`: Search products by query
- `GET /api/search/health`: Health check

**Request Format**:
```json
{
  "query": "wireless bluetooth headphones",
  "limit": 10
}
```

**Response Format**:
```json
{
  "results": [
    {
      "productId": "...",
      "title": "...",
      "similarityScore": 0.92,
      ...
    }
  ],
  "total": 10,
  "query": "...",
  "maxScore": 0.92
}
```

### 5. Fine-tuning & Evaluation (`evaluation/`)

**Purpose**: Improve search relevancy through model fine-tuning

**Technology**: Python, Sentence Transformers

**Components**:
- `fine_tune_model.py`: Fine-tune embedding model on e-commerce data
- `evaluate_search.py`: Evaluate search quality with metrics

**Metrics**:
- NDCG@K (Normalized Discounted Cumulative Gain)
- MRR (Mean Reciprocal Rank)
- Precision@K
- Recall@K

## Data Flow

### Ingestion Flow
```
Amazon Dataset → Data Pipeline → Embedding Service → PostgreSQL
```

1. Data pipeline loads products from file
2. For each product, creates searchable text
3. Calls embedding service to generate vector
4. Stores product + embedding in database

### Search Flow
```
Query → Search API → Embedding Service → Vector Search → Results
```

1. User sends search query to API
2. API calls embedding service to get query embedding
3. API performs vector similarity search in database
4. Results sorted by similarity score
5. API returns ranked product list

## Vector Search

Uses **cosine similarity** for semantic search:

```sql
SELECT *, 1 - (embedding <=> query_embedding) AS similarity
FROM products
ORDER BY embedding <=> query_embedding
LIMIT 10
```

- `<=>` operator: cosine distance
- `1 - distance`: converts to similarity (0-1 scale)
- Higher similarity = more relevant

## Scalability Considerations

### Embedding Service
- Stateless, can be horizontally scaled
- ECS Fargate auto-scaling based on CPU/memory
- Consider using GPU instances for faster inference

### Database
- Vector index (IVFFlat) for fast similarity search
- Consider partitioning for large datasets
- Read replicas for search queries

### Search API
- Stateless, can be horizontally scaled
- Connection pooling for database
- Caching for frequent queries

## Security Considerations

- Database credentials via environment variables
- API authentication/authorization (not implemented, add as needed)
- Network security groups for ECS
- HTTPS/TLS for production APIs

## Monitoring & Observability

Recommended additions:
- Application logs (structured logging)
- Metrics (Prometheus/CloudWatch)
- Distributed tracing (AWS X-Ray)
- Health check endpoints
- Database query performance monitoring
