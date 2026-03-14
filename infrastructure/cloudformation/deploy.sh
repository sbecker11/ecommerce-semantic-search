#!/usr/bin/env bash
set -e

# Run from project root; script dir is infrastructure/cloudformation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

REGION="${AWS_REGION:-us-west-1}"
STACK_NAME="ecommerce-embedding-service"
DO_CLEANUP=false

for arg in "$@"; do
  case "$arg" in
    --cleanup) DO_CLEANUP=true ;;
  esac
done

# Step 0: Optional cleanup
if [[ "$DO_CLEANUP" == true ]]; then
  echo "=== Cleanup (if stack/ECR exist) ==="
  if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}" 2>/dev/null || true
    echo "Stack deleted."
  else
    echo "Stack ${STACK_NAME} does not exist. Skipping."
  fi
  aws ecr delete-repository --repository-name embedding-service --region "${REGION}" --force 2>/dev/null || true
  echo "Cleanup done."
  echo ""
fi

# Step 1: Variables
echo "=== Setting up ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/embedding-service:latest"

# Step 2: Deploy stack
echo "=== Creating stack (DesiredCount=0) ==="
CFN_DIR="${SCRIPT_DIR}"
cat > /tmp/cfn-params.json << EOF
[
  {"ParameterKey": "ECRImageURI", "ParameterValue": "${ECR_URI}"},
  {"ParameterKey": "VpcId", "ParameterValue": "${VPC_ID}"},
  {"ParameterKey": "SubnetIds", "ParameterValue": "${SUBNET_IDS}"},
  {"ParameterKey": "CreateECRRepository", "ParameterValue": "true"},
  {"ParameterKey": "DesiredCount", "ParameterValue": "0"}
]
EOF

aws cloudformation create-stack \
  --stack-name "${STACK_NAME}" \
  --template-body "file://${CFN_DIR}/ecs-embedding-service.yaml" \
  --parameters file:///tmp/cfn-params.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}"

# Step 3: Wait for stack (with progress monitor)
echo ""
echo "=== Waiting for stack (may take 10+ minutes) ==="
(
  while true; do
    STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
    echo "$(date +%H:%M:%S) Stack status: ${STATUS:-CREATE_IN_PROGRESS}"
    [[ "$STATUS" == "CREATE_COMPLETE" ]] && echo "Stack creation complete." && exit 0
    [[ "$STATUS" == *"FAILED"* || "$STATUS" == "ROLLBACK"* ]] && exit 1
    sleep 15
  done
) &
MONITOR_PID=$!
aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${REGION}"
kill "${MONITOR_PID}" 2>/dev/null || true

# Step 4: Build and push image
echo ""
echo "=== Building and pushing image ==="
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker build -t embedding-service:latest "${PROJECT_ROOT}/embedding-service"
docker tag embedding-service:latest "${ECR_URI}"
docker push "${ECR_URI}"

# Step 5: Scale up and deploy
echo ""
echo "=== Scaling to 2 tasks and deploying ==="
aws ecs update-service \
  --cluster ecommerce-cluster \
  --service embedding-service \
  --desired-count 2 \
  --force-new-deployment \
  --region "${REGION}" \
  --output text --query 'service.serviceName'

# Step 6: Outputs
echo ""
echo "=== Deployment complete ==="
aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].Outputs' --output table

LOAD_BALANCER_URL=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' --output text)
echo ""
echo "EMBEDDING_SERVICE_URL: ${LOAD_BALANCER_URL}"
echo ""
echo "Wait a few minutes for tasks to become healthy, then:"
echo "  export EMBEDDING_SERVICE_URL=${LOAD_BALANCER_URL}"
