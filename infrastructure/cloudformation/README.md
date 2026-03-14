# CloudFormation Deployment

CloudFormation templates for deploying the embedding service to ECS Fargate on AWS.

**Production deployment only.** These templates are for production (or staging) deployment on AWS. For local development, use Docker Compose; CloudFormation is not required.

## Prerequisites

- AWS CLI configured with appropriate credentials
- AWS account with permissions to create ECS, VPC, IAM, ALB, ECR resources
- VPC and subnets (or use default VPC)
- Docker installed

## Quick Start

From the project root, run:

```bash
./infrastructure/cloudformation/deploy.sh
```

Optionally pass `--cleanup` to remove any existing stack and ECR first:

```bash
./infrastructure/cloudformation/deploy.sh --cleanup
```

The script uses `AWS_REGION` if set (default `us-west-1`), auto-detects VPC and subnets, creates the stack with `DesiredCount=0`, waits for creation, builds and pushes the image, scales to 2 tasks, and prints the embedding service URL. No user input required.

## Manual deployment

If you prefer to run commands yourself:

1. **Cleanup (optional)** – Delete stack and ECR if starting over
2. **Variables** – `ACCOUNT_ID`, `VPC_ID`, `SUBNET_IDS`, `ECR_URI` from AWS CLI
3. **Deploy stack** – `DesiredCount=0` to avoid circuit breaker before image push
4. **Wait** – `aws cloudformation wait stack-create-complete` (use progress monitor from `deploy.sh`)
5. **Build & push** – Docker build, tag, push to ECR
6. **Scale up** – `aws ecs update-service --desired-count 2 --force-new-deployment`

See `deploy.sh` for the exact commands.

## Troubleshooting

**"ECR repository already exists"** – Run `deploy.sh --cleanup`, or delete the stack and ECR manually, then retry.

**"Invalid type for parameter SubnetIds"** – Use the JSON parameters file (`file:///tmp/cfn-params.json`), not inline `--parameters`.

**Stack in ROLLBACK_COMPLETE** – Inspect events, fix the cause, delete the stack, then redeploy:

```bash
aws cloudformation describe-stack-events --stack-name ${STACK_NAME} --region ${REGION} \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' --output table
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}
```

## Updating the Stack

### Update Image

After pushing a new image to ECR, force a new deployment:

```bash
aws ecs update-service \
  --cluster ecommerce-cluster \
  --service embedding-service \
  --force-new-deployment \
  --region ${REGION}
```

### Update Service Configuration

To change desired count, CPU, memory, etc.:

```bash
# Regenerate params (ensure VPC_ID, SUBNET_IDS, ECR_URI are set)
cat > /tmp/cfn-params.json << EOF
[
  {"ParameterKey": "ECRImageURI", "ParameterValue": "${ECR_URI}"},
  {"ParameterKey": "VpcId", "ParameterValue": "${VPC_ID}"},
  {"ParameterKey": "SubnetIds", "ParameterValue": "${SUBNET_IDS}"},
  {"ParameterKey": "CreateECRRepository", "ParameterValue": "true"},
  {"ParameterKey": "DesiredCount", "ParameterValue": "4"},
  {"ParameterKey": "Cpu", "ParameterValue": "4096"},
  {"ParameterKey": "Memory", "ParameterValue": "8192"}
]
EOF

aws cloudformation update-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://ecs-embedding-service.yaml \
  --parameters file:///tmp/cfn-params.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION}
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ClusterName` | `ecommerce-cluster` | ECS cluster name |
| `ServiceName` | `embedding-service` | ECS service name |
| `ECRImageURI` | *required* | Full ECR image URI |
| `DesiredCount` | `2` | Number of tasks to run |
| `Cpu` | `2048` | CPU units (1024 = 1 vCPU) |
| `Memory` | `4096` | Memory in MB |
| `VpcId` | *required* | VPC ID |
| `SubnetIds` | *required* | Comma-separated subnet IDs |
| `AllowedCIDR` | `0.0.0.0/0` | CIDR allowed to access ALB |
| `ModelName` | `sentence-transformers/all-MiniLM-L6-v2` | HuggingFace model |
| `LogRetentionDays` | `7` | CloudWatch log retention |
| `CreateECRRepository` | `true` | Set to true to let CloudFormation create ECR (Quick Start) |

## Resources Created

- **ECS Cluster** - Container orchestration
- **ECS Service** - Manages tasks
- **ECS Task Definition** - Container configuration
- **Application Load Balancer** - Public-facing HTTP load balancer
- **Target Group** - Routes traffic to ECS tasks
- **Security Groups** - ALB and ECS task security
- **IAM Roles** - Task execution and task roles
- **CloudWatch Log Group** - Application logs
- **ECR Repository** - Docker image repository

## Cleanup

To delete all resources:

```bash
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}
```

Note: This will delete the ECR repository and all images if it was created by CloudFormation. Export images first if needed.

## Integration with Search API

After a successful deployment (stack in `CREATE_COMPLETE` or `UPDATE_COMPLETE`), use the `LoadBalancerURL` output as the `EMBEDDING_SERVICE_URL` environment variable for your Search API. Requires `STACK_NAME` and `REGION` to be set (e.g. from Quick Start step 1).

```bash
export EMBEDDING_SERVICE_URL=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text \
  --region ${REGION})
```
