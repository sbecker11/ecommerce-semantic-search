#!/bin/bash
# Report the current status of all E-commerce Semantic Search services.
# Run from project root: ./status_system.sh
#
# After ./stop_system.sh, all services should report "not running".

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
EMBEDDING_SERVICE_URL="${EMBEDDING_SERVICE_URL:-http://localhost:8080}"
SEARCH_API_URL="${SEARCH_API_URL:-http://localhost:8081}"
CURL_TIMEOUT="${CURL_TIMEOUT:-5}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}E-commerce Semantic Search - Service Status${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}\n"

# PostgreSQL
printf "%-30s" "PostgreSQL (port 5432):"
if docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}running${NC}"
else
    echo -e "${RED}not running${NC}"
fi

# Embedding Service
printf "%-30s" "Embedding Service (port 8080):"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" "${EMBEDDING_SERVICE_URL}/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}running${NC}"
else
    echo -e "${RED}not running${NC}"
fi

# Search API
printf "%-30s" "Search API (port 8081):"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" "${SEARCH_API_URL}/api/search/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}running${NC}"
else
    echo -e "${RED}not running${NC}"
fi

echo ""
