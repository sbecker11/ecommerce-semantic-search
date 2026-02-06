#!/bin/bash
# Start all E-commerce Semantic Search services (PostgreSQL, embedding service, Search API)
# and verify they're running.
#
# Run from project root: ./start_system.sh

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
CURL_TIMEOUT=10
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}E-commerce Semantic Search - Starting System${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}\n"

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}✗ Docker is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo -e "${RED}✗ Docker Compose is required but not installed. Aborting.${NC}" >&2; exit 1; }
if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker Desktop is not running. Starting Docker Desktop...${NC}"
    if [ "$(uname)" = "Darwin" ] && [ -d "/Applications/Docker.app" ]; then
        open -a Docker
        echo "Waiting for Docker Desktop to start (timeout: 60s)..."
        for i in $(seq 1 12); do
            sleep 5
            if docker info >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Docker Desktop is running${NC}"
                break
            fi
            if [ $i -eq 12 ]; then
                echo -e "${RED}✗ Docker Desktop did not start in time. Start it manually and try again. Aborting.${NC}" >&2
                exit 1
            fi
            echo "  Attempt $i/12: waiting..."
        done
    else
        echo -e "${RED}✗ Docker Desktop is not running. Start Docker Desktop and try again. Aborting.${NC}" >&2
        exit 1
    fi
fi

# Java 17+ required for Search API
if ! command -v java >/dev/null 2>&1; then
    echo -e "${RED}✗ Java is required but not installed. Aborting.${NC}" >&2
    exit 1
fi
JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | sed 's/^1\.//' | cut -d'.' -f1)
if [ -z "$JAVA_VERSION" ] || [ "$JAVA_VERSION" -lt 17 ] 2>/dev/null; then
    echo -e "${RED}✗ Java 17+ is required (found: ${JAVA_VERSION:-unknown}). Aborting.${NC}" >&2
    exit 1
fi

# Maven or Maven wrapper required for Search API
if [ ! -f "$SCRIPT_DIR/search-api/mvnw" ] && ! command -v mvn >/dev/null 2>&1; then
    echo -e "${RED}✗ Maven is required (mvnw in search-api/ or mvn in PATH) but not found. Aborting.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}\n"

# Step 1: Start PostgreSQL (idempotent - skip if already running and healthy)
echo -e "${BLUE}Step 1: Starting PostgreSQL...${NC}"
if docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    # Check if we can connect
    if docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT 1" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL already running and healthy${NC}"
    else
        echo "PostgreSQL running but not responding, restarting..."
        docker-compose restart postgres
        sleep 5
    fi
else
    docker-compose up -d postgres
    echo "Waiting for PostgreSQL to be ready..."
    sleep 5
fi

# Initialize database if needed
if ! docker-compose exec -T postgres psql -U postgres -d ecommerce -t -c "SELECT 1 FROM products LIMIT 1;" >/dev/null 2>&1; then
    echo "Initializing database schema..."
    ./infrastructure/init-database.sh
else
    echo -e "${GREEN}✓ Database already initialized${NC}"
fi

# Step 2: Start Embedding Service (idempotent - skip if already running and healthy)
echo -e "\n${BLUE}Step 2: Starting Embedding Service...${NC}"
if docker ps --format '{{.Names}}' | grep -q '^embedding-service$'; then
    # Container is running - check if healthy
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Embedding service already running and healthy${NC}"
    else
        echo "Embedding service running but not healthy, restarting..."
        docker stop embedding-service 2>/dev/null || true
        docker rm embedding-service 2>/dev/null || true
        docker run -d -p 8080:8080 --name embedding-service embedding-service
    fi
elif docker ps -a --format '{{.Names}}' | grep -q '^embedding-service$'; then
    # Container exists but stopped - remove and start fresh
    echo "Embedding container stopped, restarting..."
    docker rm embedding-service 2>/dev/null || true
    docker run -d -p 8080:8080 --name embedding-service embedding-service
elif docker images -q embedding-service 2>/dev/null | grep -q .; then
    # Image exists but no container - start it
    echo "Starting embedding-service from existing image..."
    docker run -d -p 8080:8080 --name embedding-service embedding-service
else
    # No image - build and start
    echo "Building embedding service (this may take 15-25 min on first run)..."
    cd embedding-service
    docker build -t embedding-service .
    cd ..
    docker run -d -p 8080:8080 --name embedding-service embedding-service
fi

# Step 3: Wait for Embedding Service with timeout
echo -e "\n${BLUE}Step 3: Waiting for Embedding Service (timeout: ${CURL_TIMEOUT}s)...${NC}"
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" http://localhost:8080/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Embedding service is ready${NC}"
        curl -s --max-time "$CURL_TIMEOUT" http://localhost:8080/health | python3 -m json.tool 2>/dev/null || true
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${YELLOW}⚠ Embedding service not responding after 30 attempts. Model may still be downloading.${NC}"
        echo "  Check status: curl -s --max-time $CURL_TIMEOUT http://localhost:8080/health"
        echo "  View logs: docker logs embedding-service"
    else
        echo "  Embedding service - Attempt $i/30: waiting..."
        sleep 5
    fi
done

# Step 4: Status checks
echo -e "\n${BLUE}Step 4: Service Status${NC}"

# PostgreSQL
if docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✓ PostgreSQL: running${NC}"
else
    echo -e "${RED}✗ PostgreSQL: not running${NC}"
fi

# Embedding Service
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" http://localhost:8080/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Embedding Service: healthy (port 8080)${NC}"
else
    echo -e "${YELLOW}⚠ Embedding Service: not responding (HTTP $HTTP_CODE)${NC}"
    echo "  Run: curl -s --max-time $CURL_TIMEOUT http://localhost:8080/health"
fi

# Search API (optional - may not be started)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:8081/api/search/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Search API: healthy (port 8081)${NC}"
else
    echo -e "${YELLOW}○ Search API: not running (start with: cd search-api && ./mvnw spring-boot:run)${NC}"
fi

# Database connection
if docker-compose exec -T postgres psql -U postgres -d ecommerce -c "SELECT 1" >/dev/null 2>&1; then
    COUNT=$(docker-compose exec -T postgres psql -U postgres -d ecommerce -t -c "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d ' ')
    echo -e "${GREEN}✓ Database: connected (products: ${COUNT})${NC}"
else
    echo -e "${RED}✗ Database: connection failed${NC}"
fi

# Step 5: Open Search API in new iTerm2 window (idempotent - skip if already running and healthy)
echo -e "\n${BLUE}Step 5: Starting Search API...${NC}"

# Check if Search API is already running and healthy
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:8081/api/search/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Search API already running and healthy${NC}"
else
    # Need to start Search API in iTerm2 window
    if [ "$(uname)" != "Darwin" ]; then
        echo -e "${RED}✗ Error: macOS is required for Search API iTerm2 window.${NC}" >&2
        exit 1
    fi
    if [ ! -f "/Applications/iTerm2.app/Contents/MacOS/iTerm2" ] && [ ! -d "/Applications/iTerm.app" ] && [ ! -d "/Applications/iTerm 2.app" ]; then
        echo -e "${RED}✗ Error: iTerm2 is required but not installed. Install from https://iterm2.com${NC}" >&2
        exit 1
    fi
    # Use mvnw if present, otherwise mvn (Maven wrapper jar may be missing)
    MVN_CMD="./mvnw"
    [ ! -f "$SCRIPT_DIR/search-api/mvnw" ] && MVN_CMD="mvn"
    if osascript 2>/dev/null <<APPLESCRIPT
tell application "iTerm2"
    set windowExists to false
    activate
    -- Check for existing window with "search-api" in title
    repeat with w in windows
        set winName to name of w
        if winName contains "search-api" then
            set windowExists to true
            set index of w to 1
            exit repeat
        end if
    end repeat
    if not windowExists then
        create window with default profile
        tell current session of current window
            write text " cd \"${SCRIPT_DIR}/search-api\" && ${MVN_CMD} spring-boot:run"
        end tell
    end if
end tell
APPLESCRIPT
    then
        echo -e "${GREEN}✓ Search API window opened${NC}"
    else
        echo -e "${RED}✗ Error: AppleScript failed to open iTerm2. Start manually: cd search-api && ${MVN_CMD} spring-boot:run${NC}" >&2
        exit 1
    fi
fi

# Step 6: Wait for Search API to start (Spring Boot startup)
echo -e "\n${BLUE}Step 6: Waiting for Search API (timeout: 120s)...${NC}"
for i in $(seq 1 40); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" http://localhost:8081/api/search/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Search API is ready (port 8081)${NC}"
        break
    fi
    if [ $i -eq 40 ]; then
        echo -e "${YELLOW}⚠ Search API not responding after 120s. It may still be starting.${NC}"
        echo "  Check the Search API iTerm window or run: curl -s --max-time $CURL_TIMEOUT http://localhost:8081/api/search/health"
    else
        echo "  Search API - Attempt $i/40: waiting..."
        sleep 3
    fi
done

echo -e "\n${BOLD}${GREEN}System startup complete.${NC}\n"
echo "Useful commands:"
echo "  Stop all:         ./stop_system.sh"
echo "  Health check:     curl -s --max-time $CURL_TIMEOUT http://localhost:8080/health"
echo "  Full test:        ./test_system.sh"
echo "  Start Search API: cd search-api && ./mvnw spring-boot:run"
echo ""
