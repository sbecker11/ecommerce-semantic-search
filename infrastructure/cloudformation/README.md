# CloudFormation Deployment

Deploy the full semantic search stack to **ECS Fargate** and **RDS PostgreSQL** on AWS.

**Local development** uses Docker Compose only; CloudFormation is for AWS.

## One-command deploy (recommended)

From the project root (requires AWS CLI, Docker, ~30–45 minutes first run):

```bash
./infrastructure/cloudformation/deploy-all.sh
```

This runs, in order:

1. **Embedding service** — ECS cluster, ALB, ECR (`ecommerce-embedding-service`)
2. **RDS PostgreSQL 15** — pgvector schema via `init-db.sql` (`ecommerce-rds`)
3. **Search API** — ECS service, ALB, RDS security group link (`ecommerce-search-api`)

Credentials and endpoints are saved to `infrastructure/cloudformation/.deploy.env` (gitignored).

Optional flags:

| Flag | Effect |
| ------ | -------- |
| `--ingest` | Run data pipeline if `data-pipeline/data/amazon_products.json` exists |
| `--skip-embedding` | Skip step 1 (stack already up) |
| `--skip-rds` | Skip step 2 |
| `--skip-search` | Skip step 3 |
| `--teardown` | Delete all stacks (runs `teardown-all.sh`) |

Teardown only:

```bash
./infrastructure/cloudformation/teardown-all.sh
```

## Step-by-step

```bash
./infrastructure/cloudformation/deploy.sh              # embedding
./infrastructure/cloudformation/deploy-rds.sh          # RDS + schema
source infrastructure/cloudformation/.deploy.env       # DB_HOST, DB_PASSWORD, etc.
./infrastructure/cloudformation/deploy-search-api.sh   # search API + RDS SG link
```

## Stacks

| Stack | Template | Script |
| ------- | ---------- | -------- |
| `ecommerce-embedding-service` | `ecs-embedding-service.yaml` | `deploy.sh` |
| `ecommerce-rds` | `rds-postgres.yaml` | `deploy-rds.sh` |
| `ecommerce-search-api` | `ecs-search-api.yaml` | `deploy-search-api.sh` |

Shared helpers: `lib/cfn-common.sh`

## Prerequisites

- AWS CLI with credentials (ECS, VPC, IAM, ALB, ECR, RDS)
- Docker
- Default VPC in your region (`AWS_REGION`, default `us-west-1`)
- Outbound HTTPS from your machine (schema init uses `docker run postgres:15-alpine psql`)

## Environment variables

| Variable | When |
| ---------- | ------ |
| `AWS_REGION` | All scripts (default `us-west-1`) |
| `DB_PASSWORD` | Optional; auto-generated on first RDS deploy |
| `DB_HOST` | Auto from RDS stack or `.deploy.env` |
| `EMBEDDING_SERVICE_URL` | Auto from embedding stack; **must end with `/embed`** |

See `.deploy.env.example` for the saved file format.

### Embedding URL outputs

| Output | Use |
|--------|-----|
| `LoadBalancerURL` | Base ALB; health at `/health` |
| `EmbeddingServiceURL` | Search API / pipeline: `…/embed` |

Do **not** set `EMBEDDING_SERVICE_URL` to `LoadBalancerURL` alone — Spring expects the `/embed` path.

## RDS notes

- Instance: `ecommerce-postgres`, PostgreSQL **15**, `db.t3.micro`, 20 GB
- **Publicly accessible** for solo-dev schema init from your laptop
- Temporary **bootstrap** ingress: your public IP `/32` during `deploy-rds.sh`
- After Search API deploy, `update-rds-access.sh` allows ECS tasks and removes bootstrap CIDR

## Data ingestion

```bash
source infrastructure/cloudformation/.deploy.env
export DATA_FILE=data-pipeline/data/amazon_products.json   # your dataset
cd data-pipeline && pip install -r requirements.txt && python ingest_data.py
```

Or: `./infrastructure/cloudformation/deploy-all.sh --ingest`

## Test

```bash
source infrastructure/cloudformation/.deploy.env
SEARCH_URL=$(aws cloudformation describe-stacks --stack-name ecommerce-search-api \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' --output text \
  --region "${AWS_REGION}")

curl -s "${SEARCH_URL}/api/search/health"
curl -s -X POST "${SEARCH_URL}/api/search" -H 'Content-Type: application/json' \
  -d '{"query":"wireless headphones","limit":5}'
```

## Troubleshooting

**RDS create slow** — Normal 10–15 minutes. `aws rds describe-db-instances --db-instance-identifier ecommerce-postgres`.

**init-db fails** — Ensure bootstrap CIDR matches your IP; re-run `deploy-rds.sh` or check RDS is `available`.

**Search API unhealthy** — CloudWatch `/ecs/search-api`; verify RDS SG allows Search API ECS SG.

**Stack ROLLBACK_COMPLETE** — `describe-stack-events`, `delete-stack`, redeploy.

**ECR already exists** — `deploy.sh --cleanup` or `teardown-embedding.sh` / `teardown-all.sh`.

**Stack delete stuck** — Fargate tasks still running. Run `teardown-embedding.sh` (scales service to 0
first) or manually:

```bash
aws ecs update-service --cluster ecommerce-cluster --service embedding-service \
  --desired-count 0 --region us-west-1
```

**Stack DELETE_FAILED on ECR** — Repository still had images. `teardown-embedding.sh` force-deletes ECR
and retries stack delete automatically; or:

```bash
aws ecr delete-repository --repository-name embedding-service --force
aws cloudformation delete-stack --stack-name ecommerce-embedding-service
```

## Updating images

```bash
aws ecs update-service --cluster ecommerce-cluster --service embedding-service --force-new-deployment --region $AWS_REGION
aws ecs update-service --cluster ecommerce-cluster --service search-api --force-new-deployment --region $AWS_REGION
```

## Cleanup

Tear down AWS resources when you no longer need the deployed stack. Everything is recreatable from
this repo via `deploy-all.sh` or the step-by-step deploy scripts.

| Script | Scope |
| -------- | -------- |
| `teardown-embedding.sh` | Embedding stack only (`ecommerce-embedding-service`) |
| `teardown-all.sh` | All project stacks: search-api → RDS → embedding |

Both default to **account `286103606369`** and **region `us-west-1`** (via `AWS_REGION`). The embedding
script aborts if `aws sts get-caller-identity` shows a different account. Neither script touches
`linkage-engine` resources.

### Embedding stack only

Scales `embedding-service` to 0 (avoids stuck CloudFormation deletes), deletes stack
`ecommerce-embedding-service`, then cleans leftover ECR repo, log groups, and orphan ECS cluster.

```bash
./infrastructure/cloudformation/teardown-embedding.sh           # dry-run (no changes)
./infrastructure/cloudformation/teardown-embedding.sh --execute # destructive
```

### All stacks

```bash
./infrastructure/cloudformation/teardown-all.sh
```

Deletes stacks in reverse dependency order and removes `.deploy.env` when present. For a stuck
embedding delete, prefer `teardown-embedding.sh --execute` first.

After any teardown, recheck **AWS Cost Explorer in 24–48h**; ALB and Fargate charges can lag a day or two.
