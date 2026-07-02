#!/usr/bin/env bash
# Tear down the ecommerce embedding stack and related out-of-stack resources.
# Does NOT touch linkage-engine or other non-ecommerce resources.
#
# Usage:
#   ./infrastructure/cloudformation/teardown-embedding.sh           # dry-run (default)
#   ./infrastructure/cloudformation/teardown-embedding.sh --execute # run teardown

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cfn-common.sh
source "${SCRIPT_DIR}/lib/cfn-common.sh"

REGION="$(cfn_region)"
REQUIRED_ACCOUNT_ID="286103606369"
STACK_NAME="${EMBEDDING_STACK_NAME:-ecommerce-embedding-service}"
CLUSTER_NAME="${CLUSTER_NAME:-ecommerce-cluster}"
SERVICE_NAME="${SERVICE_NAME:-embedding-service}"
ECR_REPO="${ECR_REPO:-embedding-service}"
ALB_NAME="embedding-service-alb"

LOG_GROUPS=(
  "/ecs/${SERVICE_NAME}"
  "/aws/ecs/containerinsights/${CLUSTER_NAME}/performance"
)

DO_EXECUTE=false
for arg in "$@"; do
  case "$arg" in
    --execute) DO_EXECUTE=true ;;
    --dry-run) DO_EXECUTE=false ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg} (use --dry-run or --execute)" >&2
      exit 1
      ;;
  esac
done

require_account() {
  local account
  account="$(aws sts get-caller-identity --query Account --output text)"
  if [[ "${account}" != "${REQUIRED_ACCOUNT_ID}" ]]; then
    echo "ERROR: Expected AWS account ${REQUIRED_ACCOUNT_ID}, got ${account}. Aborting." >&2
    exit 1
  fi
  echo "Account: ${account} (${REQUIRED_ACCOUNT_ID})"
}

stack_exists() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" &>/dev/null
}

print_plan() {
  echo "=== Teardown plan (embedding only) ==="
  echo "Region:      ${REGION}"
  echo "Stack:       ${STACK_NAME}"
  echo "ECS cluster: ${CLUSTER_NAME}"
  echo "ECS service: ${SERVICE_NAME}"
  echo "ECR repo:    ${ECR_REPO}"
  echo "ALB:         ${ALB_NAME}"
  echo ""
  echo "Will NOT touch linkage-engine or other non-ecommerce resources."
  echo ""

  if stack_exists; then
    local status
    status="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" \
      --query 'Stacks[0].StackStatus' --output text)"
    echo "CloudFormation stack: ${STACK_NAME} (${status})"
  else
    echo "CloudFormation stack: ${STACK_NAME} (not found)"
  fi

  if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'clusters[0].status' --output text 2>/dev/null | grep -q ACTIVE; then
    aws ecs describe-services --cluster "${CLUSTER_NAME}" --services "${SERVICE_NAME}" --region "${REGION}" \
      --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,status:status}' \
      --output table 2>/dev/null || echo "ECS service ${SERVICE_NAME}: not found"
  else
    echo "ECS cluster ${CLUSTER_NAME}: not active"
  fi

  aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "LoadBalancers[?LoadBalancerName==\`${ALB_NAME}\`].{Name:LoadBalancerName,State:State.Code}" \
    --output table 2>/dev/null || true

  aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${REGION}" \
    --query 'repositories[].repositoryName' --output text 2>/dev/null \
    && echo "(ECR repo ${ECR_REPO} exists)" || echo "ECR repo ${ECR_REPO}: not found"

  echo "Log groups to clean (if still present):"
  for lg in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "${lg}" --region "${REGION}" \
      --query 'logGroups[?logGroupName==`'"${lg}"'`].logGroupName' --output text 2>/dev/null | grep -q .; then
      echo "  - ${lg}"
    else
      echo "  - ${lg} (not found)"
    fi
  done
  echo ""
}

scale_service_to_zero() {
  if ! aws ecs describe-services --cluster "${CLUSTER_NAME}" --services "${SERVICE_NAME}" --region "${REGION}" \
    --query 'services[0].serviceName' --output text 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    echo "ECS service ${SERVICE_NAME} not found; skipping scale-to-zero."
    return 0
  fi

  echo "=== Step 1: Scale ${SERVICE_NAME} to desired-count 0 ==="
  aws ecs update-service \
    --cluster "${CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --desired-count 0 \
    --region "${REGION}" \
    --output text --query 'service.{desired:desiredCount,running:runningCount}'

  echo "Waiting for service to stabilize (tasks drained)..."
  aws ecs wait services-stable \
    --cluster "${CLUSTER_NAME}" \
    --services "${SERVICE_NAME}" \
    --region "${REGION}" 2>/dev/null || true
  echo "Scale-to-zero complete."
}

delete_stack() {
  if ! stack_exists; then
    echo "Stack ${STACK_NAME} does not exist; skipping delete."
    return 0
  fi

  echo "=== Step 2: Delete CloudFormation stack ${STACK_NAME} ==="
  aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
  echo "Waiting for stack-delete-complete..."
  if ! aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}"; then
    echo "=== Step 3: Stack delete failed — DELETE_FAILED events ==="
    aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "${REGION}" \
      --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[Timestamp,LogicalResourceId,ResourceType,ResourceStatusReason]' \
      --output table 2>/dev/null || true
    return 1
  fi
  echo "Stack deleted."
}

cleanup_leftovers() {
  echo "=== Step 4: Delete ECR repo ${ECR_REPO} (if present) ==="
  aws ecr delete-repository --repository-name "${ECR_REPO}" --force --region "${REGION}" 2>/dev/null \
    && echo "ECR repo deleted." || echo "ECR repo not found (ok)."

  echo "=== Step 5: Delete log groups (if present) ==="
  for lg in "${LOG_GROUPS[@]}"; do
    aws logs delete-log-group --log-group-name "${lg}" --region "${REGION}" 2>/dev/null \
      && echo "Deleted ${lg}" || echo "${lg} not found (ok)."
  done

  echo "=== Step 6: Delete orphan ECS cluster (if still ACTIVE) ==="
  local cluster_status
  cluster_status="$(aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'clusters[0].status' --output text 2>/dev/null || echo "MISSING")"
  if [[ "${cluster_status}" == "ACTIVE" ]]; then
    aws ecs delete-cluster --cluster "${CLUSTER_NAME}" --region "${REGION}"
    echo "Cluster ${CLUSTER_NAME} deleted."
  else
    echo "Cluster ${CLUSTER_NAME} status: ${cluster_status} (ok)."
  fi
}

retry_stack_delete_if_needed() {
  if ! stack_exists; then
    return 0
  fi
  local status
  status="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" \
    --query 'Stacks[0].StackStatus' --output text)"
  if [[ "${status}" != "DELETE_FAILED" && "${status}" != "DELETE_IN_PROGRESS" ]]; then
    return 0
  fi
  echo "=== Step 6b: Retry stack delete (after ECR/images cleanup) ==="
  aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
  if aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}"; then
    echo "Stack deleted on retry."
  else
    echo "Stack delete retry failed — DELETE_FAILED events:"
    aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "${REGION}" \
      --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[Timestamp,LogicalResourceId,ResourceType,ResourceStatusReason]' \
      --output table 2>/dev/null || true
    return 1
  fi
}

verify() {
  echo "=== Step 7: Verification ==="
  local issues=0

  if stack_exists; then
    local status
    status="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" \
      --query 'Stacks[0].StackStatus' --output text)"
    echo "STILL ALIVE: CloudFormation stack ${STACK_NAME} (${status})"
    issues=$((issues + 1))
  else
    echo "OK: CloudFormation stack ${STACK_NAME} gone."
  fi

  local cluster_status
  cluster_status="$(aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'clusters[0].status' --output text 2>/dev/null || echo "MISSING")"
  if [[ "${cluster_status}" == "ACTIVE" ]]; then
    echo "STILL ALIVE: ECS cluster ${CLUSTER_NAME}"
    issues=$((issues + 1))
  else
    echo "OK: ECS cluster ${CLUSTER_NAME} not active (${cluster_status})."
  fi

  local alb_count
  alb_count="$(aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "length(LoadBalancers[?LoadBalancerName==\`${ALB_NAME}\`])" --output text)"
  if [[ "${alb_count}" != "0" ]]; then
    echo "STILL ALIVE: ALB ${ALB_NAME}"
    issues=$((issues + 1))
  else
    echo "OK: ALB ${ALB_NAME} gone."
  fi

  if aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${REGION}" &>/dev/null; then
    echo "STILL ALIVE: ECR repo ${ECR_REPO}"
    issues=$((issues + 1))
  else
    echo "OK: ECR repo ${ECR_REPO} gone."
  fi

  echo ""
  if [[ "${issues}" -eq 0 ]]; then
    echo "Teardown verification passed."
  else
    echo "Teardown verification found ${issues} remaining resource(s)."
  fi
  echo "Recheck AWS Cost Explorer in 24-48h; some charges settle over a day or two."
}

main() {
  require_account
  print_plan

  if [[ "${DO_EXECUTE}" == false ]]; then
    echo "DRY RUN — no changes made."
    echo "Re-run with --execute to perform teardown:"
    echo "  ./infrastructure/cloudformation/teardown-embedding.sh --execute"
    exit 0
  fi

  echo ""
  echo "=== EXECUTING TEARDOWN ==="
  scale_service_to_zero
  delete_stack || true
  cleanup_leftovers
  retry_stack_delete_if_needed || true
  verify
}

main "$@"
