#!/usr/bin/env bash
set -e

# Provision RDS PostgreSQL and apply init-db.sql
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/cfn-common.sh
source "${SCRIPT_DIR}/lib/cfn-common.sh"

cd "${PROJECT_ROOT}"

STACK_NAME="${RDS_STACK_NAME:-ecommerce-rds}"
DO_CLEANUP=false
SKIP_INIT=false

for arg in "$@"; do
  case "$arg" in
    --cleanup) DO_CLEANUP=true ;;
    --skip-init) SKIP_INIT=true ;;
  esac
done

REGION="$(cfn_region)"
export AWS_REGION="${REGION}"

if [[ "$DO_CLEANUP" == true ]]; then
  echo "=== Deleting RDS stack ${STACK_NAME} ==="
  if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
    aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}" || true
    echo "RDS stack deleted."
  else
    echo "Stack ${STACK_NAME} does not exist."
  fi
  exit 0
fi

cfn_load_deploy_env
cfn_detect_vpc

DB_NAME="${DB_NAME:-ecommerce}"
DB_USER="${DB_USER:-postgres}"
DB_PORT="${DB_PORT:-5432}"

if [[ -z "${DB_PASSWORD}" ]]; then
  DB_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  echo "Generated DB_PASSWORD (saved to ${DEPLOY_ENV_FILE})"
fi

SEARCH_API_SG="${SEARCH_API_SG:-}"
BOOTSTRAP_CIDR="${BOOTSTRAP_CIDR:-$(cfn_public_ip_cidr)}"

if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null; then
  STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" \
    --query 'Stacks[0].StackStatus' --output text)
  echo "Stack ${STACK_NAME} already exists (${STATUS}). Skipping create."
else
  echo "=== Creating RDS stack (10–15 minutes) ==="
  python3 - << PY
import json
params = [
  {"ParameterKey": "VpcId", "ParameterValue": "${VPC_ID}"},
  {"ParameterKey": "SubnetIds", "ParameterValue": "${SUBNET_IDS}"},
  {"ParameterKey": "DBName", "ParameterValue": "${DB_NAME}"},
  {"ParameterKey": "DBUsername", "ParameterValue": "${DB_USER}"},
  {"ParameterKey": "DBPassword", "ParameterValue": "${DB_PASSWORD}"},
  {"ParameterKey": "PubliclyAccessible", "ParameterValue": "true"},
  {"ParameterKey": "BootstrapCidr", "ParameterValue": "${BOOTSTRAP_CIDR}"},
  {"ParameterKey": "SearchApiSecurityGroupId", "ParameterValue": "${SEARCH_API_SG}"},
]
with open("/tmp/cfn-rds-params.json", "w") as f:
    json.dump(params, f)
PY

  aws cloudformation create-stack \
    --stack-name "${STACK_NAME}" \
    --template-body "file://${SCRIPT_DIR}/rds-postgres.yaml" \
    --parameters file:///tmp/cfn-rds-params.json \
    --region "${REGION}"

  cfn_wait_stack_create "${STACK_NAME}"
fi

echo "=== Waiting for RDS instance to be available ==="
aws rds wait db-instance-available --db-instance-identifier ecommerce-postgres --region "${REGION}"

DB_HOST="$(cfn_stack_output "${STACK_NAME}" DBEndpoint)"
DB_PORT_OUT="$(cfn_stack_output "${STACK_NAME}" DBPort)"
DB_PORT="${DB_PORT_OUT:-5432}"

cfn_save_deploy_env "AWS_REGION" "${REGION}"
cfn_save_deploy_env "DB_HOST" "${DB_HOST}"
cfn_save_deploy_env "DB_PORT" "${DB_PORT}"
cfn_save_deploy_env "DB_NAME" "${DB_NAME}"
cfn_save_deploy_env "DB_USER" "${DB_USER}"
cfn_save_deploy_env "DB_PASSWORD" "${DB_PASSWORD}"

export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD

if [[ "$SKIP_INIT" == true ]]; then
  echo "Skipping schema init (--skip-init)."
  exit 0
fi

echo "=== Applying init-db.sql (pgvector + products table) ==="
CONN="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
docker run --rm -i postgres:15-alpine psql "${CONN}" -v ON_ERROR_STOP=1 < "${PROJECT_ROOT}/infrastructure/init-db.sql"

echo ""
echo "=== RDS ready ==="
echo "DB_HOST=${DB_HOST}"
echo "Credentials saved to ${DEPLOY_ENV_FILE}"
aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" \
  --query 'Stacks[0].Outputs' --output table
