#!/usr/bin/env bash
set -e

# Grant Search API ECS tasks access to RDS; remove bootstrap CIDR when done.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cfn-common.sh
source "${SCRIPT_DIR}/lib/cfn-common.sh"

RDS_STACK="${RDS_STACK_NAME:-ecommerce-rds}"
SEARCH_STACK="${SEARCH_API_STACK_NAME:-ecommerce-search-api}"
REGION="$(cfn_region)"

SEARCH_API_SG="${1:-}"
if [[ -z "${SEARCH_API_SG}" ]]; then
  SEARCH_API_SG="$(cfn_stack_output "${SEARCH_STACK}" ECSSecurityGroupId)"
fi

if [[ -z "${SEARCH_API_SG}" || "${SEARCH_API_SG}" == "None" ]]; then
  echo "Error: Search API ECS security group not found. Deploy search-api first." >&2
  exit 1
fi

if ! aws cloudformation describe-stacks --stack-name "${RDS_STACK}" --region "${REGION}" &>/dev/null; then
  echo "Error: RDS stack ${RDS_STACK} not found." >&2
  exit 1
fi

cfn_load_deploy_env
cfn_detect_vpc

DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD required in .deploy.env}"
DB_NAME="${DB_NAME:-ecommerce}"
DB_USER="${DB_USER:-postgres}"

echo "=== Updating RDS stack: allow Search API SG ${SEARCH_API_SG}, remove bootstrap CIDR ==="
python3 - << PY
import json
params = [
  {"ParameterKey": "VpcId", "ParameterValue": "${VPC_ID}"},
  {"ParameterKey": "SubnetIds", "ParameterValue": "${SUBNET_IDS}"},
  {"ParameterKey": "DBName", "ParameterValue": "${DB_NAME}"},
  {"ParameterKey": "DBUsername", "ParameterValue": "${DB_USER}"},
  {"ParameterKey": "DBPassword", "ParameterValue": "${DB_PASSWORD}"},
  {"ParameterKey": "PubliclyAccessible", "ParameterValue": "true"},
  {"ParameterKey": "BootstrapCidr", "ParameterValue": ""},
  {"ParameterKey": "SearchApiSecurityGroupId", "ParameterValue": "${SEARCH_API_SG}"},
]
with open("/tmp/cfn-rds-params.json", "w") as f:
    json.dump(params, f)
PY

aws cloudformation update-stack \
  --stack-name "${RDS_STACK}" \
  --template-body "file://${SCRIPT_DIR}/rds-postgres.yaml" \
  --parameters file:///tmp/cfn-rds-params.json \
  --region "${REGION}"

aws cloudformation wait stack-update-complete --stack-name "${RDS_STACK}" --region "${REGION}"
echo "RDS security groups updated."
