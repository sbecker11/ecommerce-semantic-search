#!/bin/bash
# Initialize database manually (alternative to file mount)

echo "Initializing database..."
docker-compose exec -T postgres psql -U postgres -d ecommerce < infrastructure/init-db.sql
echo "Database initialized successfully!"
