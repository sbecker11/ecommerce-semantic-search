#!/bin/bash
# Stop all E-commerce Semantic Search services (Search API, embedding service, PostgreSQL).
# Opposite of start_system.sh.
#
# Run from project root: ./stop_system.sh

set +e  # Don't exit on errors - we want to stop whatever is running

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}E-commerce Semantic Search - Stopping System${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}\n"

# Check Docker Desktop is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✗ Error: Docker Desktop is not running. Start Docker Desktop and try again.${NC}" >&2
    exit 1
fi

# Step 1: Stop Search API - kill process first, then close iTerm2 window
echo -e "${BLUE}Step 1: Stopping Search API...${NC}"

# Kill the process on port 8081 first (avoids iTerm2 confirmation dialog)
PID=$(lsof -ti:8081 2>/dev/null)
PROCESS_KILLED=false
if [ -n "$PID" ]; then
    kill $PID 2>/dev/null || kill -9 $PID 2>/dev/null
    PROCESS_KILLED=true
    sleep 1  # Give process time to terminate
fi

# Close the (now idle) iTerm2 window containing "search-api"
WINDOW_CLOSED=false
if [ "$(uname)" = "Darwin" ]; then
    if [ ! -f "/Applications/iTerm2.app/Contents/MacOS/iTerm2" ] && [ ! -d "/Applications/iTerm.app" ] && [ ! -d "/Applications/iTerm 2.app" ]; then
        echo -e "${RED}✗ Error: iTerm2 is required but not installed. Install from https://iterm2.com${NC}" >&2
        exit 1
    fi
    RESULT=$(osascript 2>/dev/null <<'APPLESCRIPT'
tell application "iTerm2"
    repeat with w in windows
        set winName to name of w
        if winName contains "search-api" then
            close w
            return "closed"
        end if
    end repeat
    return "not_found"
end tell
APPLESCRIPT
    )
    if [ "$RESULT" = "closed" ]; then
        WINDOW_CLOSED=true
    fi
fi

# Report status
if [ "$PROCESS_KILLED" = "true" ] || [ "$WINDOW_CLOSED" = "true" ]; then
    echo -e "${GREEN}✓ Search API stopped${NC}"
else
    echo -e "${YELLOW}○ Search API not running${NC}"
fi

# Step 2: Stop Embedding Service container
echo -e "\n${BLUE}Step 2: Stopping Embedding Service...${NC}"
if docker ps -a --format '{{.Names}}' | grep -q '^embedding-service$'; then
    docker stop embedding-service 2>/dev/null || true
    docker rm embedding-service 2>/dev/null || true
    echo -e "${GREEN}✓ Embedding service stopped and removed${NC}"
else
    echo -e "${YELLOW}○ Embedding service not running${NC}"
fi

# Step 3: Stop PostgreSQL
echo -e "\n${BLUE}Step 3: Stopping PostgreSQL...${NC}"
if docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    docker-compose stop postgres
    echo -e "${GREEN}✓ PostgreSQL stopped${NC}"
else
    echo -e "${YELLOW}○ PostgreSQL not running${NC}"
fi

echo -e "\n${BOLD}${GREEN}System stopped.${NC}\n"
echo "Start again with: ./start_system.sh"
echo ""
