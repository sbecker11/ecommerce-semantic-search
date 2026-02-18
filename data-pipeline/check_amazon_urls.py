#!/usr/bin/env python3
"""
Check each product's Amazon URL and report HTTP status (200, 404, etc.).
Run from repo root with: python data-pipeline/check_amazon_urls.py
Or from data-pipeline with: python check_amazon_urls.py
"""
import os
import requests
from dotenv import load_dotenv

# Load .env from repo root or data-pipeline
load_dotenv()
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'ecommerce')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'postgres')

# Amazon often returns 403 for non-browser User-Agent; use a common one
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
}


def get_urls():
    import psycopg2
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )
    cur = conn.cursor()
    cur.execute("SELECT product_id, title, amazon_url FROM products WHERE amazon_url IS NOT NULL AND amazon_url != ''")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows


def check_url(url, timeout=10):
    try:
        r = requests.head(url, headers=HEADERS, timeout=timeout, allow_redirects=True)
        return r.status_code
    except requests.RequestException as e:
        return str(e)


def main():
    rows = get_urls()
    if not rows:
        print("No product Amazon URLs found in database.")
        return

    print(f"Checking {len(rows)} Amazon URL(s)...\n")
    ok = 0
    not_found = 0
    other = 0

    for product_id, title, url in rows:
        status = check_url(url)
        if status == 200:
            ok += 1
        elif status == 404:
            not_found += 1
        else:
            other += 1
        title_short = (title or "")[:50] + ("..." if (title and len(title) > 50) else "")
        print(f"  {status if isinstance(status, int) else 'ERR':>6}  {url}")
        print(f"         {product_id}  {title_short}\n")

    print("---")
    print(f"  200 OK: {ok}")
    print(f"  404 Not Found: {not_found}")
    print(f"  Other/Error: {other}")


if __name__ == "__main__":
    main()
