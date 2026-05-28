#!/usr/bin/env bash
set -e

# One-command production deploy: embedding → RDS → search API → RDS access
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/cfn-common.sh
source "${SCRIPT_DIR}/lib/cfn-common.sh"

cd "${PROJECT_ROOT}"

SKIP_EMBEDDING=false
SKIP_RDS=false
SKIP_SEARCH=false
RUN_INGEST=false
DO_TEARDOWN=false

for arg in "$@"; do
  case "$arg" in
    --skip-embedding) SKIP_EMBEDDING=true ;;
    --skip-rds) SKIP_RDS=true ;;
    --skip-search) SKIP_SEARCH=true ;;
    --ingest) RUN_INGEST=true ;;
    --teardown) DO_TEARDOWN=true ;;
  esac
done

if [[ "$DO_TEARDOWN" == true ]]; then
  exec "${SCRIPT_DIR}/teardown-all.sh"
fi

export AWS_REGION="$(cfn_region)"

echo "=== E-commerce semantic search — full AWS deploy (${AWS_REGION}) ==="
echo "Credentials will be saved to: ${DEPLOY_ENV_FILE}"
echo ""

if [[ "$SKIP_EMBEDDING" == false ]]; then
  echo ">>> [1/4] Embedding service"
  "${SCRIPT_DIR}/deploy.sh"
  echo ""
fi

if [[ "$SKIP_RDS" == false ]]; then
  echo ">>> [2/4] RDS PostgreSQL"
  "${SCRIPT_DIR}/deploy-rds.sh"
  echo ""
fi

cfn_load_deploy_env

if [[ "$SKIP_SEARCH" == false ]]; then
  echo ">>> [3/4] Search API"
  export DB_HOST DB_PASSWORD DB_NAME DB_USER DB_PORT
  cfn_resolve_embedding_url || {
    echo "Error: could not resolve EMBEDDING_SERVICE_URL" >&2
    exit 1
  }
  export EMBEDDING_SERVICE_URL
  "${SCRIPT_DIR}/deploy-search-api.sh"
  echo ""
fi

if [[ "$RUN_INGEST" == true ]]; then
  echo ">>> Optional: data ingestion"
  cfn_load_deploy_env
  cfn_resolve_embedding_url
  export EMBEDDING_SERVICE_URL DB_HOST DB_PASSWORD DB_NAME DB_USER DB_PORT
  if [[ -f "${PROJECT_ROOT}/data-pipeline/data/amazon_products.json" ]]; then
    export DATA_FILE="${PROJECT_ROOT}/data-pipeline/data/amazon_products.json"
    (cd "${PROJECT_ROOT}/data-pipeline" && pip install -q -r requirements.txt && python ingest_data.py)
  else
    echo "No data-pipeline/data/amazon_products.json — skip ingest or set DATA_FILE."
  fi
fi

SEARCH_URL="$(cfn_stack_output ecommerce-search-api LoadBalancerURL)"
echo "=== Deploy complete ==="
echo "Search API:  ${SEARCH_URL}"
echo "Health:      ${SEARCH_URL}/api/search/health"
echo "Secrets:     ${DEPLOY_ENV_FILE}"
echo ""
echo "Example:"
echo "  source ${DEPLOY_ENV_FILE}"
echo "  curl -s ${SEARCH_URL}/api/search/health"
echo "  curl -s -X POST ${SEARCH_URL}/api/search -H 'Content-Type: application/json' \\"
echo "    -d '{\"query\":\"wireless headphones\",\"limit\":5}'"
