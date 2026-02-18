#!/usr/bin/env python3
"""
Data Engineering Pipeline for E-commerce Semantic Search
Ingests Amazon products data and generates embeddings
"""

import os
import json
import psycopg2
import requests
import pandas as pd
from typing import List, Dict, Optional
from tqdm import tqdm
from dotenv import load_dotenv

load_dotenv()

# Configuration
EMBEDDING_SERVICE_URL = os.getenv('EMBEDDING_SERVICE_URL', 'http://localhost:8080/embed')
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'ecommerce')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'postgres')
BATCH_SIZE = 100


def get_embedding(text: str, service_url: str) -> Optional[List[float]]:
    """Get embedding vector from embedding service"""
    try:
        response = requests.post(
            service_url,
            json={'text': text},
            timeout=30
        )
        response.raise_for_status()
        return response.json().get('embedding')
    except Exception as e:
        print(f"Error getting embedding: {e}")
        return None


def create_searchable_text(row: Dict) -> str:
    """Create searchable text from product fields"""
    parts = []
    if row.get('title'):
        parts.append(str(row['title']))
    if row.get('description'):
        parts.append(str(row['description']))
    if row.get('brand'):
        parts.append(f"Brand: {row['brand']}")
    if row.get('category'):
        parts.append(f"Category: {row['category']}")
    return ' '.join(parts)


def load_amazon_data(file_path: str) -> pd.DataFrame:
    """Load Amazon products dataset"""
    print(f"Loading data from {file_path}...")

    # Handle different file formats
    if file_path.endswith('.json'):
        with open(file_path, 'r', encoding='utf-8') as f:
            data = []
            for line in f:
                try:
                    data.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        df = pd.DataFrame(data)
    elif file_path.endswith('.csv'):
        df = pd.read_csv(file_path)
    else:
        raise ValueError(f"Unsupported file format: {file_path}")

    print(f"Loaded {len(df)} products")
    return df


def insert_product(conn, product: Dict, embedding: List[float]):
    """Insert product with embedding into database"""
    cursor = conn.cursor()
    try:
        unit_price = product.get('unit_price') or product.get('price')
        ranking = product.get('ranking') or product.get('rank')
        votes = product.get('votes') or product.get('vote_count') or product.get('review_count') or product.get('num_reviews')
        amazon_url = product.get('amazon_url') or product.get('url') or product.get('product_url')
        # Generate Amazon URL from product_id if not provided
        if not amazon_url and product.get('product_id'):
            product_id = product.get('product_id') or product.get('asin') or product.get('id')
            amazon_url = f"https://www.amazon.com/dp/{product_id}"

        cursor.execute("""
            INSERT INTO products (
                product_id, title, description, category, brand,
                price, unit_price, rating, review_count, ranking, votes, image_url, amazon_url, embedding
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (product_id) DO UPDATE SET
                title = EXCLUDED.title,
                description = EXCLUDED.description,
                category = EXCLUDED.category,
                brand = EXCLUDED.brand,
                price = EXCLUDED.price,
                unit_price = EXCLUDED.unit_price,
                rating = EXCLUDED.rating,
                review_count = EXCLUDED.review_count,
                ranking = EXCLUDED.ranking,
                votes = EXCLUDED.votes,
                image_url = EXCLUDED.image_url,
                amazon_url = EXCLUDED.amazon_url,
                embedding = EXCLUDED.embedding,
                updated_at = CURRENT_TIMESTAMP
        """, (
            product.get('product_id') or product.get('asin') or product.get('id'),
            product.get('title') or product.get('product_name'),
            product.get('description') or product.get('product_description'),
            product.get('category') or product.get('main_cat'),
            product.get('brand'),
            product.get('price'),
            unit_price,
            product.get('rating') or product.get('average_rating'),
            product.get('review_count') or product.get('num_reviews'),
            ranking,
            votes,
            product.get('image_url') or product.get('image'),
            amazon_url,
            str(embedding)  # Convert list to string for pgvector
        ))
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"Error inserting product {product.get('product_id')}: {e}")
    finally:
        cursor.close()


def process_batch(conn, batch: List[Dict], service_url: str):
    """Process a batch of products"""
    for product in batch:
        searchable_text = create_searchable_text(product)
        if not searchable_text.strip():
            continue

        embedding = get_embedding(searchable_text, service_url)
        if embedding:
            insert_product(conn, product, embedding)


def main():
    """Main ingestion pipeline"""
    # Get data file path from environment or use default
    data_file = os.getenv('DATA_FILE', 'data/amazon_products.json')

    if not os.path.exists(data_file):
        print(f"Data file not found: {data_file}")
        print("Please download Amazon products dataset and place it in the data/ directory")
        print("Example: wget https://example.com/amazon_products.json -O data/amazon_products.json")
        return

    # Load data
    df = load_amazon_data(data_file)

    # Connect to database
    print(f"Connecting to database {DB_NAME} at {DB_HOST}:{DB_PORT}...")
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

    # Process products in batches
    print(f"Processing {len(df)} products in batches of {BATCH_SIZE}...")
    products = df.to_dict('records')

    for i in tqdm(range(0, len(products), BATCH_SIZE), desc="Processing batches"):
        batch = products[i:i + BATCH_SIZE]
        process_batch(conn, batch, EMBEDDING_SERVICE_URL)

    conn.close()
    print("Data ingestion complete!")


if __name__ == '__main__':
    main()
