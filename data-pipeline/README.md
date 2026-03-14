# Data Engineering Pipeline

This pipeline ingests Amazon products data and generates vector embeddings for semantic search.

## Setup

1. Install PostgreSQL client libraries (required for psycopg2 on macOS):
```bash
brew install libpq
export LDFLAGS="-L$(brew --prefix libpq)/lib"
export CPPFLAGS="-I$(brew --prefix libpq)/include"
export PATH="$(brew --prefix libpq)/bin:$PATH"
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Set environment variables (or create `.env` file):
```bash
export EMBEDDING_SERVICE_URL=http://localhost:8080/embed
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=ecommerce
export DB_USER=postgres
export DB_PASSWORD=postgres
export DATA_FILE=data/amazon_products.json
```

4. Download Amazon products dataset:
   - Visit https://www.kaggle.com/datasets/karkavelrajaj/amazon-products-dataset
   - Or use any Amazon products JSON/CSV file
   - Place it in `data/` directory

5. Ensure embedding service is running:
```bash
cd ../embedding-service
docker build -t embedding-service .
docker run -p 8080:8080 embedding-service
```

6. Run the pipeline:
```bash
python ingest_data.py
```

## Data Format

The pipeline expects JSON or CSV files with the following fields (flexible mapping):
- `product_id` / `asin` / `id`: Unique product identifier
- `title` / `product_name`: Product title
- `description` / `product_description`: Product description
- `category` / `main_cat`: Product category
- `brand`: Product brand
- `price`: Product price
- `rating` / `average_rating`: Product rating
- `review_count` / `num_reviews`: Number of reviews
- `image_url` / `image`: Product image URL
