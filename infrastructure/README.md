# Infrastructure

Infrastructure configuration files for deploying the semantic search system.

## Docker Compose

For local development:
```bash
docker-compose up -d
```

This starts:
- PostgreSQL with pgvector extension
- Embedding service

## ECS Fargate Deployment

### Prerequisites
- AWS CLI configured
- ECS cluster created
- ECR repository created (or use deploy.sh to create)

### Deploy Embedding Service

1. Make deploy script executable:
```bash
chmod +x deploy.sh
```

2. Set environment variables:
```bash
export AWS_REGION=us-east-1
export ECR_REPO=embedding-service
export CLUSTER_NAME=ecommerce-cluster
export SERVICE_NAME=embedding-service
```

3. Run deployment:
```bash
./deploy.sh
```

### Manual ECS Setup

1. **Create ECS Cluster**:
```bash
aws ecs create-cluster --cluster-name ecommerce-cluster
```

2. **Create Task Definition**:
```bash
# Update ecs-task-definition.json with your ECR URI
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json
```

3. **Create Service**:
```bash
aws ecs create-service \
  --cluster ecommerce-cluster \
  --service-name embedding-service \
  --task-definition embedding-service \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

## Database Setup

The `init-db.sql` script is automatically run when PostgreSQL container starts. It:
- Enables pgvector extension
- Creates products table with vector field
- Creates indexes for efficient vector search

## Network Configuration

For production:
- Use Application Load Balancer (ALB) in front of ECS service
- Configure security groups to allow traffic from ALB
- Use RDS PostgreSQL instead of containerized database
