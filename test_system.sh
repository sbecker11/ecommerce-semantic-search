#!/bin/bash
# Quick test script for E-commerce Semantic Search System
# Tests basic connectivity and functionality

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
EMBEDDING_SERVICE_URL="${EMBEDDING_SERVICE_URL:-http://localhost:8080}"
SEARCH_API_URL="${SEARCH_API_URL:-http://localhost:8081}"

echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}E-commerce Semantic Search - Quick Test${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}\n"

# Test 1: Embedding Service Health
echo -e "${BLUE}Testing Embedding Service...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${EMBEDDING_SERVICE_URL}/health")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Embedding service is healthy${NC}"
    curl -s "${EMBEDDING_SERVICE_URL}/health" | python3 -m json.tool 2>/dev/null || echo "  Response: $(curl -s ${EMBEDDING_SERVICE_URL}/health)"
else
    echo -e "${RED}✗ Embedding service is not responding (HTTP $HTTP_CODE)${NC}"
    exit 1
fi

# Test 2: Search API Health
echo -e "\n${BLUE}Testing Search API...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SEARCH_API_URL}/api/search/health")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Search API is healthy${NC}"
else
    echo -e "${RED}✗ Search API is not responding (HTTP $HTTP_CODE)${NC}"
    exit 1
fi

# Test 3: Database Connection
echo -e "\n${BLUE}Testing Database Connection...${NC}"
if docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM products;" > /dev/null 2>&1; then
    COUNT=$(docker-compose exec -T postgres psql -U postgres -d ecommerce -t -c "SELECT COUNT(*) FROM products;" | tr -d ' ')
    echo -e "${GREEN}✓ Database connection successful${NC}"
    echo -e "  Products in database: ${COUNT}"
else
    echo -e "${RED}✗ Database connection failed${NC}"
    exit 1
fi

# Test 4: Search Functionality
echo -e "\n${BLUE}Testing Search Functionality...${NC}"
QUERY="wireless headphones"
RESPONSE=$(curl -s -X POST "${SEARCH_API_URL}/api/search" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"${QUERY}\", \"limit\": 3}")

if echo "$RESPONSE" | grep -q "results"; then
    TOTAL=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total', 0))" 2>/dev/null || echo "0")
    echo -e "${GREEN}✓ Search query successful${NC}"
    echo -e "  Query: '${QUERY}'"
    echo -e "  Results: ${TOTAL}"
    
    # Show first result
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null | head -20 || echo "$RESPONSE" | head -10
else
    echo -e "${RED}✗ Search query failed${NC}"
    echo "  Response: $RESPONSE"
    exit 1
fi

# Test 5: Multiple Queries
echo -e "\n${BLUE}Testing Multiple Search Queries...${NC}"
QUERIES=("noise cancelling" "Sony audio" "Apple AirPods")
for query in "${QUERIES[@]}"; do
    RESPONSE=$(curl -s -X POST "${SEARCH_API_URL}/api/search" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"${query}\", \"limit\": 1}")
    
    if echo "$RESPONSE" | grep -q "results"; then
        TOTAL=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total', 0))" 2>/dev/null || echo "0")
        echo -e "${GREEN}✓${NC} '${query}': ${TOTAL} result(s)"
    else
        echo -e "${RED}✗${NC} '${query}': Failed"
    fi
done

echo -e "\n${BOLD}${GREEN}All basic tests passed! ✓${NC}\n"
