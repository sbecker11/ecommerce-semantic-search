#!/usr/bin/env bash
set -e

# Delete all CloudFormation stacks (reverse dependency order)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/cfn-common.sh"

REGION="$(cfn_region)"

echo "=== Tearing down AWS stacks in ${REGION} ==="

"${SCRIPT_DIR}/deploy-search-api.sh" --cleanup 2>/dev/null || true
"${SCRIPT_DIR}/deploy-rds.sh" --cleanup 2>/dev/null || true
"${SCRIPT_DIR}/deploy.sh" --cleanup 2>/dev/null || true

if [[ -f "${DEPLOY_ENV_FILE}" ]]; then
  rm -f "${DEPLOY_ENV_FILE}"
  echo "Removed ${DEPLOY_ENV_FILE}"
fi

echo "Teardown initiated. RDS deletion may take several minutes."
