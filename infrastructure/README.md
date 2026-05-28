# Infrastructure

Infrastructure configuration for local development and AWS deployment.

## Docker Compose (local)

```bash
docker-compose up -d
```

Starts PostgreSQL with pgvector and the embedding service.

## AWS deployment (recommended)

Full stack from the project root:

```bash
./infrastructure/cloudformation/deploy-all.sh
```

Creates embedding service, RDS PostgreSQL (with `init-db.sql`), and Search API. Credentials go to `cloudformation/.deploy.env` (gitignored).

See [cloudformation/README.md](cloudformation/README.md) for flags, teardown, and troubleshooting.

## Database setup

**Local:** `init-db.sql` runs when the Postgres container starts.

**Production (RDS):** Run `init-db.sql` manually after enabling the pgvector extension. Allow inbound **5432** on the RDS security group from the Search API stack output `ECSSecurityGroupId`.

## Legacy manual ECS push

`infrastructure/deploy.sh` builds and pushes the embedding image to ECR and registers a task definition. It expects an existing ECS cluster and service (or use CloudFormation instead).

```bash
export AWS_REGION=us-west-1
export ECR_REPO=embedding-service
export CLUSTER_NAME=ecommerce-cluster
export SERVICE_NAME=embedding-service
./infrastructure/deploy.sh
```

## Network (production)

- ALB in front of each ECS service (created by CloudFormation)
- RDS in private subnets; Search API tasks need route to RDS (security group rules)
- Embedding ALB is public; Search API calls it via `EMBEDDING_SERVICE_URL`
