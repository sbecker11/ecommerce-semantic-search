#!/bin/bash
# Deployment script for ECS Fargate

set -e

REGION=${AWS_REGION:-us-east-1}
ECR_REPO=${ECR_REPO:-embedding-service}
CLUSTER_NAME=${CLUSTER_NAME:-ecommerce-cluster}
SERVICE_NAME=${SERVICE_NAME:-embedding-service}

echo "Building and pushing embedding service to ECR..."

# Build Docker image
cd ../embedding-service
docker build -t ${ECR_REPO}:latest .

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Create ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names ${ECR_REPO} --region ${REGION} || \
  aws ecr create-repository --repository-name ${ECR_REPO} --region ${REGION}

# Tag and push image
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:latest"
docker tag ${ECR_REPO}:latest ${ECR_URI}
docker push ${ECR_URI}

echo "Image pushed to ${ECR_URI}"

# Update task definition
echo "Updating ECS task definition..."
TASK_DEF_FILE="ecs-task-definition.json"
sed "s|YOUR_ECR_REPO|${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}|g" ${TASK_DEF_FILE} > ${TASK_DEF_FILE}.tmp
aws ecs register-task-definition --cli-input-json file://${TASK_DEF_FILE}.tmp --region ${REGION}
rm ${TASK_DEF_FILE}.tmp

# Update service
echo "Updating ECS service..."
aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --force-new-deployment \
  --region ${REGION} || echo "Service may not exist yet. Create it manually or use AWS Console."

echo "Deployment complete!"
