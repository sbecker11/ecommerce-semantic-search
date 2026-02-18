# CloudFormation Deployment

CloudFormation templates for deploying the embedding service to ECS Fargate on AWS.

**Production deployment only.** These templates are for production (or staging) deployment on AWS. For local development, use Docker Compose; CloudFormation is not required.

## Prerequisites

- AWS CLI configured with appropriate credentials
- AWS account with permissions to create ECS, VPC, IAM, ALB resources
- VPC and subnets (or use default VPC)
- Docker image built and pushed to ECR (or use the ECR repository created by this template)

## Quick Start

### 1. Build and Push Docker Image

```bash
cd ../embedding-service
docker build -t embedding-service:latest .

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-us-east-1}

# Login to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Create ECR repository (or use the one created by CloudFormation)
aws ecr create-repository --repository-name embedding-service --region ${REGION} || true

# Tag and push
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/embedding-service:latest"
docker tag embedding-service:latest ${ECR_URI}
docker push ${ECR_URI}
```

### 2. Get VPC and Subnet IDs

```bash
# Option 1: Use default VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

# Option 2: Use specific VPC
# VPC_ID=vpc-xxxxx
# SUBNET_IDS=subnet-xxxxx,subnet-yyyyy
```

### 3. Deploy CloudFormation Stack

```bash
cd cloudformation

# Set parameters
STACK_NAME=ecommerce-embedding-service
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/embedding-service:latest"

aws cloudformation create-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://ecs-embedding-service.yaml \
  --parameters \
    ParameterKey=ECRImageURI,ParameterValue=${ECR_URI} \
    ParameterKey=VpcId,ParameterValue=${VPC_ID} \
    ParameterKey=SubnetIds,ParameterValue=${SUBNET_IDS} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION}
```

### 4. Wait for Stack Creation

```bash
aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME} --region ${REGION}
```

### 5. Get Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs' \
  --region ${REGION} \
  --output table
```

The `LoadBalancerURL` output gives you the URL to access the embedding service (e.g., `http://embedding-service-alb-xxx.us-east-1.elb.amazonaws.com`).

## Updating the Stack

### Update Image

After pushing a new image to ECR:

```bash
aws cloudformation update-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://ecs-embedding-service.yaml \
  --parameters \
    ParameterKey=ECRImageURI,ParameterValue=${NEW_ECR_URI} \
    ParameterKey=VpcId,ParameterValue=${VPC_ID} \
    ParameterKey=SubnetIds,ParameterValue=${SUBNET_IDS} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${REGION}
```

### Update Service Configuration

To change desired count, CPU, memory, etc.:

```bash
aws cloudformation update-stack \
  --stack-name ${STACK_NAME} \
  --template-body file://ecs-embedding-service.yaml \
  --parameters \
    ParameterKey=ECRImageURI,ParameterValue=${ECR_URI} \
    ParameterKey=VpcId,ParameterValue=${VPC_ID} \
    ParameterKey=SubnetIds,ParameterValue=${SUBNET_IDS} \
    ParameterKey=DesiredCount,ParameterValue=4 \
    ParameterKey=Cpu,ParameterValue=4096 \
    ParameterKey=Memory,ParameterValue=8192 \
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

## Resources Created

- **ECS Cluster** - Container orchestration
- **ECS Service** - Manages tasks
- **ECS Task Definition** - Container configuration
- **Application Load Balancer** - Public-facing HTTP load balancer
- **Target Group** - Routes traffic to ECS tasks
- **Security Groups** - ALB and ECS task security
- **IAM Roles** - Task execution and task roles
- **CloudWatch Log Group** - Application logs
- **ECR Repository** - Docker image repository (optional)

## Cleanup

To delete all resources:

```bash
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}
```

Note: This will delete the ECR repository and all images if it was created by CloudFormation. Export images first if needed.

## Integration with Search API

After deployment, use the `LoadBalancerURL` output as the `EMBEDDING_SERVICE_URL` environment variable for your Search API:

```bash
export EMBEDDING_SERVICE_URL=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text \
  --region ${REGION})
```
