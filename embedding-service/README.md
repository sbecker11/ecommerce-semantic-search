# Embedding Service

A Flask-based service for generating text embeddings using HuggingFace Sentence Transformers models.

**Runtime stack**: Docker → Gunicorn → Flask → Sentence Transformers (PyTorch)

## Features

- Uses `sentence-transformers/all-MiniLM-L6-v2` by default (384-dimensional embeddings)
- Fast inference with optimized models
- Batch embedding support
- Health check endpoint
- Production-ready with Gunicorn

## Local Development

```bash
pip install -r requirements.txt
python app.py
```

## Docker Build

```bash
docker build -t embedding-service .
docker run -p 8080:8080 embedding-service
```

## API Endpoints

### Health Check
```bash
GET /health
```

### Single Embedding
```bash
POST /embed
Content-Type: application/json

{
  "text": "wireless bluetooth headphones"
}
```

### Batch Embeddings
```bash
POST /embed/batch
Content-Type: application/json

{
  "texts": ["text1", "text2", "text3"]
}
```

## Environment Variables

- `MODEL_NAME`: HuggingFace model name (default: `sentence-transformers/all-MiniLM-L6-v2`)
- `PORT`: Service port (default: `8080`)

## ECS Fargate Deployment

See `../infrastructure/ecs-task-definition.json` for ECS Fargate task definition.
