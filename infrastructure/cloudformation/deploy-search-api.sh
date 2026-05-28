#!/usr/bin/env bash
set -e

# Deploy Search API to ECS Fargate (requires RDS and embedding service).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/cfn-common.sh
source "${SCRIPT_DIR}/lib/cfn-common.sh"

cd "${PROJECT_ROOT}"

STACK_NAME="${SEARCH_API_STACK_NAME:-ecommerce-search-api}"
EMBEDDING_STACK_NAME="${EMBEDDING_STACK_NAME:-ecommerce-embedding-service}"
RDS_STACK_NAME="${RDS_STACK_NAME:-ecommerce-rds}"
DO_CLEANUP=false
SKIP_RDS_LINK=false

for arg in "$@"; do
  case "$arg" in
    --cleanup) DO_CLEANUP=true ;;
    --skip-rds-link) SKIP_RDS_LINK=true ;;
  esac
done

REGION="$(cfn_region)"
export AWS_REGION="${REGION}"

require_env() {
  local name="$1"
  if [[ -z "${!name}" ]]; then
    echo "Error: ${name} is required. Run deploy-rds.sh or deploy-all.sh first." >&2
    exit 1
  fi
}

if [[ "$DO_CLEANUP" == true ]]; then
  echo "=== Cleanup (if stack/ECR exist) ==="
  if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}" 2>/dev/null || true
    echo "Stack deleted."
  else
    echo "Stack ${STACK_NAME} does not exist. Skipping."
  fi
  aws ecr delete-repository --repository-name search-api --region "${REGION}" --force 2>/dev/null || true
  echo "Cleanup done."
  exit 0
fi

cfn_load_deploy_env

if [[ -z "${DB_HOST}" ]]; then
  DB_HOST="$(cfn_stack_output "${RDS_STACK_NAME}" DBEndpoint)"
  [[ -n "${DB_HOST}" && "${DB_HOST}" != "None" ]] && export DB_HOST
fi

cfn_resolve_embedding_url || {
  echo "Error: EMBEDDING_SERVICE_URL not set and stack ${EMBEDDING_STACK_NAME} not found." >&2
  echo "Run ./infrastructure/cloudformation/deploy.sh first." >&2
  exit 1
}
echo "Using EMBEDDING_SERVICE_URL=${EMBEDDING_SERVICE_URL}"

require_env DB_HOST
require_env DB_PASSWORD
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-ecommerce}"
DB_USER="${DB_USER:-postgres}"

echo "=== Setting up ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cfn_detect_vpc
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/search-api:latest"

CREATE_ECS_CLUSTER="false"
if ! aws ecs describe-clusters --clusters ecommerce-cluster --region "${REGION}" \
  --query 'clusters[?status==`ACTIVE`].clusterName' --output text 2>/dev/null | grep -q ecommerce-cluster; then
  CREATE_ECS_CLUSTER="true"
  echo "Cluster ecommerce-cluster not found; stack will create it."
fi

if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
  echo "Stack ${STACK_NAME} already exists. Skipping create (use --cleanup to redeploy)."
else
  echo "=== Creating stack (DesiredCount=0) ==="
  python3 - << PY
import json
params = [
  {"ParameterKey": "ECRImageURI", "ParameterValue": "${ECR_URI}"},
  {"ParameterKey": "VpcId", "ParameterValue": "${VPC_ID}"},
  {"ParameterKey": "SubnetIds", "ParameterValue": "${SUBNET_IDS}"},
  {"ParameterKey": "CreateECRRepository", "ParameterValue": "true"},
  {"ParameterKey": "DesiredCount", "ParameterValue": "0"},
  {"ParameterKey": "CreateECSCluster", "ParameterValue": "${CREATE_ECS_CLUSTER}"},
  {"ParameterKey": "ClusterName", "ParameterValue": "ecommerce-cluster"},
  {"ParameterKey": "DBHost", "ParameterValue": "${DB_HOST}"},
  {"ParameterKey": "DBPort", "ParameterValue": "${DB_PORT}"},
  {"ParameterKey": "DBName", "ParameterValue": "${DB_NAME}"},
  {"ParameterKey": "DBUser", "ParameterValue": "${DB_USER}"},
  {"ParameterKey": "DBPassword", "ParameterValue": "${DB_PASSWORD}"},
  {"ParameterKey": "EmbeddingServiceURL", "ParameterValue": "${EMBEDDING_SERVICE_URL}"},
]
with open("/tmp/cfn-search-api-params.json", "w") as f:
    json.dump(params, f)
PY

  aws cloudformation create-stack \
    --stack-name "${STACK_NAME}" \
    --template-body "file://${SCRIPT_DIR}/ecs-search-api.yaml" \
    --parameters file:///tmp/cfn-search-api-params.json \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}"

  cfn_wait_stack_create "${STACK_NAME}"
fi

echo ""
echo "=== Building and pushing image ==="
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker build -t search-api:latest "${PROJECT_ROOT}/search-api"
docker tag search-api:latest "${ECR_URI}"
docker push "${ECR_URI}"

echo ""
echo "=== Scaling to 2 tasks and deploying ==="
aws ecs update-service \
  --cluster ecommerce-cluster \
  --service search-api \
  --desired-count 2 \
  --force-new-deployment \
  --region "${REGION}" \
  --output text --query 'service.serviceName'

echo ""
echo "=== Deployment complete ==="
aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].Outputs' --output table

SEARCH_URL="$(cfn_stack_output "${STACK_NAME}" LoadBalancerURL)"
ECS_SG="$(cfn_stack_output "${STACK_NAME}" ECSSecurityGroupId)"

cfn_save_deploy_env "EMBEDDING_SERVICE_URL" "${EMBEDDING_SERVICE_URL}"

echo ""
echo "Search API URL: ${SEARCH_URL}"
echo "Health check:   ${SEARCH_URL}/api/search/health"

if [[ "$SKIP_RDS_LINK" == false ]] && aws cloudformation describe-stacks --stack-name "${RDS_STACK_NAME}" --region "${REGION}" &>/dev/null; then
  echo ""
  echo "=== Linking RDS security group to Search API tasks ==="
  "${SCRIPT_DIR}/update-rds-access.sh" "${ECS_SG}"
fi

echo ""
echo "Example search:"
echo "  curl -s -X POST ${SEARCH_URL}/api/search -H 'Content-Type: application/json' \\"
echo "    -d '{\"query\":\"wireless headphones\",\"limit\":5}' | python3 -m json.tool"
