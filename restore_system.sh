#!/bin/bash
# Restore PostgreSQL tables from a backup file.
# Run from project root: ./restore_system.sh [backup_file]
#
# Usage:
#   ./restore_system.sh                    # Restore from backup.sql (default)
#   ./restore_system.sh backup_20250105.sql
#   RESTORE_FILE=backup.sql ./restore_system.sh

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Input file: argument, RESTORE_FILE env var, or backup.sql default
RESTORE_FILE="${1:-${RESTORE_FILE:-backup.sql}}"

echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}E-commerce Semantic Search - Database Restore${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}\n"

# Check backup file exists
if [ ! -f "$RESTORE_FILE" ]; then
    echo -e "${RED}✗ Backup file not found: ${RESTORE_FILE}${NC}" >&2
    echo "  Usage: ./restore_system.sh [backup_file]" >&2
    exit 1
fi

# Check Docker and PostgreSQL running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✗ Docker Desktop is not running. Start Docker and try again.${NC}" >&2
    exit 1
fi

if ! docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    echo -e "${RED}✗ PostgreSQL is not running. Start with ./start_system.sh first.${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}⚠ This will overwrite existing data in the ecommerce database.${NC}"
echo -e "${BLUE}Restoring from: ${RESTORE_FILE}${NC}\n"

docker-compose exec -T postgres psql -U postgres -d ecommerce < "$RESTORE_FILE"

echo -e "${GREEN}✓ Restore complete${NC}\n"
