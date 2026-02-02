-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create products table with vector field
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    product_id VARCHAR(255) UNIQUE NOT NULL,
    title TEXT,
    description TEXT,
    category VARCHAR(255),
    brand VARCHAR(255),
    price DECIMAL(10, 2),
    unit_price DECIMAL(10, 2),
    rating DECIMAL(3, 2),
    review_count INTEGER,
    ranking INTEGER,
    votes INTEGER,
    image_url TEXT,
    amazon_url TEXT,
    embedding vector(384),  -- Dimension for all-MiniLM-L6-v2
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for vector similarity search
CREATE INDEX IF NOT EXISTS products_embedding_idx ON products 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Create index for text search
CREATE INDEX IF NOT EXISTS products_title_idx ON products USING gin(to_tsvector('english', title));
CREATE INDEX IF NOT EXISTS products_description_idx ON products USING gin(to_tsvector('english', description));

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to auto-update updated_at
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
