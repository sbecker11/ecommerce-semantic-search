#!/bin/bash
# Backup all PostgreSQL tables in the ecommerce database.
# Run from project root: ./backup_system.sh
#
# Output: backup.sql (or BACKUP_FILE if set)

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output file: BACKUP_FILE env var, or timestamped default
BACKUP_FILE="${BACKUP_FILE:-backup.sql}"

echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}E-commerce Semantic Search - Database Backup${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}\n"

# Check Docker and PostgreSQL running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✗ Docker Desktop is not running. Start Docker and try again.${NC}" >&2
    exit 1
fi

if ! docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    echo -e "${RED}✗ PostgreSQL is not running. Start with ./start_system.sh first.${NC}" >&2
    exit 1
fi

echo -e "${BLUE}Backing up ecommerce database...${NC}"
docker-compose exec -T postgres pg_dump -U postgres -d ecommerce --clean --if-exists > "$BACKUP_FILE"

if [ -s "$BACKUP_FILE" ]; then
    SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    echo -e "${GREEN}✓ Backup complete: ${BACKUP_FILE} (${SIZE})${NC}\n"
else
    echo -e "${RED}✗ Backup failed or produced empty file.${NC}" >&2
    rm -f "$BACKUP_FILE"
    exit 1
fi
