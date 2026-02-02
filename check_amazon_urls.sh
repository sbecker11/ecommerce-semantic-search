#!/usr/bin/env bash
# Check each product's Amazon URL and report HTTP status.
# Run from repo root: ./check_amazon_urls.sh
set -e
echo "Fetching product Amazon URLs from database..."
# Tab-separated product_id and url (no title to avoid delimiter issues)
rows=$(docker-compose exec -T postgres psql -U postgres -d ecommerce -t -A -F $'\t' -c \
  "SELECT product_id, amazon_url FROM products WHERE amazon_url IS NOT NULL AND amazon_url != ''")
if [ -z "$rows" ]; then
  echo "No Amazon URLs found in products table."
  exit 0
fi
# Use a browser User-Agent so Amazon is less likely to return 403
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
ok=0
notfound=0
other=0
echo ""
while IFS=$'\t' read -r product_id url; do
  url=$(echo "$url" | tr -d '[:space:]')
  [ -z "$url" ] && continue
  code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 -H "User-Agent: $UA" "$url" 2>/dev/null || echo "ERR")
  case "$code" in
    200) ok=$((ok+1)) ;;
    404) notfound=$((notfound+1)) ;;
    *) other=$((other+1)) ;;
  esac
  printf "  %6s  %s  (%s)\n" "$code" "$url" "$product_id"
done <<< "$rows"
echo "---"
echo "  200 OK: $ok"
echo "  404 Not Found: $notfound"
echo "  Other/Error: $other"
