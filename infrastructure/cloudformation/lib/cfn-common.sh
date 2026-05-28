# Shared helpers for CloudFormation deploy scripts. Source from deploy scripts:
#   source "${SCRIPT_DIR}/lib/cfn-common.sh"

DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-${SCRIPT_DIR}/.deploy.env}"

cfn_region() {
  echo "${AWS_REGION:-us-west-1}"
}

cfn_load_deploy_env() {
  if [[ -f "${DEPLOY_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${DEPLOY_ENV_FILE}"
    set +a
  fi
}

cfn_save_deploy_env() {
  local key="$1"
  local value="$2"
  touch "${DEPLOY_ENV_FILE}"
  if grep -q "^${key}=" "${DEPLOY_ENV_FILE}" 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "${DEPLOY_ENV_FILE}"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "${DEPLOY_ENV_FILE}"
    fi
  else
    echo "${key}=${value}" >> "${DEPLOY_ENV_FILE}"
  fi
  chmod 600 "${DEPLOY_ENV_FILE}" 2>/dev/null || true
}

cfn_detect_vpc() {
  REGION="$(cfn_region)"
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --region "${REGION}" \
    --query 'Vpcs[0].VpcId' --output text)
  if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
    echo "Error: no default VPC found in ${REGION}. Set VPC_ID and SUBNET_IDS manually." >&2
    exit 1
  fi
  SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --region "${REGION}" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
  VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" --region "${REGION}" \
    --query 'Vpcs[0].CidrBlock' --output text)
  export VPC_ID SUBNET_IDS VPC_CIDR REGION
}

cfn_stack_output() {
  local stack="$1"
  local key="$2"
  aws cloudformation describe-stacks --stack-name "${stack}" --region "$(cfn_region)" \
    --query "Stacks[0].Outputs[?OutputKey==\`${key}\`].OutputValue" --output text 2>/dev/null || true
}

cfn_resolve_embedding_url() {
  local embed_stack="${EMBEDDING_STACK_NAME:-ecommerce-embedding-service}"
  if [[ -n "${EMBEDDING_SERVICE_URL}" ]]; then
    if [[ "${EMBEDDING_SERVICE_URL}" != */embed ]]; then
      EMBEDDING_SERVICE_URL="${EMBEDDING_SERVICE_URL%/}/embed"
    fi
    export EMBEDDING_SERVICE_URL
    return 0
  fi
  if aws cloudformation describe-stacks --stack-name "${embed_stack}" --region "$(cfn_region)" &>/dev/null; then
    EMBEDDING_SERVICE_URL="$(cfn_stack_output "${embed_stack}" EmbeddingServiceURL)"
    if [[ -z "${EMBEDDING_SERVICE_URL}" || "${EMBEDDING_SERVICE_URL}" == "None" ]]; then
      local base
      base="$(cfn_stack_output "${embed_stack}" LoadBalancerURL)"
      EMBEDDING_SERVICE_URL="${base%/}/embed"
    fi
    export EMBEDDING_SERVICE_URL
    return 0
  fi
  return 1
}

cfn_wait_stack_create() {
  local stack="$1"
  local region
  region="$(cfn_region)"
  (
    while true; do
      STATUS=$(aws cloudformation describe-stacks --stack-name "${stack}" --region "${region}" \
        --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
      echo "$(date +%H:%M:%S) ${stack}: ${STATUS:-CREATE_IN_PROGRESS}"
      [[ "$STATUS" == "CREATE_COMPLETE" ]] && exit 0
      [[ "$STATUS" == *"FAILED"* || "$STATUS" == "ROLLBACK"* ]] && exit 1
      sleep 15
    done
  ) &
  local pid=$!
  aws cloudformation wait stack-create-complete --stack-name "${stack}" --region "${region}"
  kill "${pid}" 2>/dev/null || true
}

cfn_public_ip_cidr() {
  local ip
  ip="$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')"
  if [[ -z "${ip}" ]]; then
    echo "0.0.0.0/0"
  else
    echo "${ip}/32"
  fi
}
