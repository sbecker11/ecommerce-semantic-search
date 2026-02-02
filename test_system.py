#!/usr/bin/env python3
"""
Comprehensive test script for E-commerce Semantic Search System
Tests all components: Database, Embedding Service, and Search API
"""

import os
import sys
import json
import requests
import psycopg2
from typing import Dict, List, Optional
from datetime import datetime

# Configuration
EMBEDDING_SERVICE_URL = os.getenv('EMBEDDING_SERVICE_URL', 'http://localhost:8080').rstrip('/')
SEARCH_API_URL = os.getenv('SEARCH_API_URL', 'http://localhost:8081').rstrip('/')
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'ecommerce')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'postgres')

# Test queries
TEST_QUERIES = [
    "wireless headphones",
    "noise cancelling earbuds",
    "Sony audio devices",
    "Apple AirPods",
    "budget wireless earbuds under 150"
]

# ANSI color codes
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'
BOLD = '\033[1m'


def print_header(text: str):
    """Print a formatted header"""
    print(f"\n{BOLD}{BLUE}{'='*60}{RESET}")
    print(f"{BOLD}{BLUE}{text}{RESET}")
    print(f"{BOLD}{BLUE}{'='*60}{RESET}\n")


def print_success(text: str):
    """Print success message"""
    print(f"{GREEN}✓ {text}{RESET}")


def print_error(text: str):
    """Print error message"""
    print(f"{RED}✗ {text}{RESET}")


def print_warning(text: str):
    """Print warning message"""
    print(f"{YELLOW}⚠ {text}{RESET}")


def print_info(text: str):
    """Print info message"""
    print(f"{BLUE}ℹ {text}{RESET}")


def test_database_connection() -> bool:
    """Test database connectivity and schema"""
    print_header("Testing Database Connection")
    
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        cursor = conn.cursor()
        
        # Test basic connection
        cursor.execute("SELECT version();")
        version = cursor.fetchone()[0]
        print_success(f"Connected to PostgreSQL: {version.split(',')[0]}")
        
        # Check pgvector extension
        cursor.execute("SELECT * FROM pg_extension WHERE extname = 'vector';")
        if cursor.fetchone():
            print_success("pgvector extension is installed")
        else:
            print_error("pgvector extension is NOT installed")
            return False
        
        # Check products table
        cursor.execute("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'products'
            ORDER BY ordinal_position;
        """)
        columns = cursor.fetchall()
        required_columns = {
            'id', 'product_id', 'title', 'description', 'category', 'brand',
            'price', 'unit_price', 'rating', 'review_count', 'ranking', 'votes',
            'image_url', 'embedding', 'created_at', 'updated_at'
        }
        found_columns = {col[0] for col in columns}
        
        print_info(f"Found {len(columns)} columns in products table")
        missing = required_columns - found_columns
        if missing:
            print_warning(f"Missing columns: {', '.join(missing)}")
        else:
            print_success("All required columns present")
        
        # Check product count
        cursor.execute("SELECT COUNT(*) FROM products;")
        count = cursor.fetchone()[0]
        print_info(f"Total products in database: {count}")
        
        # Check products with embeddings
        cursor.execute("SELECT COUNT(*) FROM products WHERE embedding IS NOT NULL;")
        embedding_count = cursor.fetchone()[0]
        print_info(f"Products with embeddings: {embedding_count}")
        
        if count == 0:
            print_warning("No products found in database")
        elif embedding_count < count:
            print_warning(f"{count - embedding_count} products missing embeddings")
        
        cursor.close()
        conn.close()
        return True
        
    except psycopg2.Error as e:
        print_error(f"Database connection failed: {e}")
        return False


def test_embedding_service() -> bool:
    """Test embedding service health and functionality"""
    print_header("Testing Embedding Service")
    
    try:
        # Test health endpoint
        health_url = f"{EMBEDDING_SERVICE_URL}/health"
        response = requests.get(health_url, timeout=5)
        if response.status_code == 200:
            health_data = response.json()
            print_success(f"Embedding service is healthy")
            print_info(f"Model: {health_data.get('model', 'unknown')}")
        else:
            print_error(f"Health check failed: {response.status_code}")
            print_error(f"URL: {health_url}")
            print_error(f"Response: {response.text[:200]}")
            return False
        
        # Test embedding generation
        test_text = "wireless headphones"
        response = requests.post(
            f"{EMBEDDING_SERVICE_URL}/embed",
            json={"text": test_text},
            timeout=10
        )
        
        if response.status_code == 200:
            embedding_data = response.json()
            embedding = embedding_data.get('embedding')
            if embedding and len(embedding) == 384:
                print_success(f"Embedding generated successfully (dimension: {len(embedding)})")
                return True
            else:
                print_error(f"Invalid embedding dimension: {len(embedding) if embedding else 0}")
                return False
        else:
            print_error(f"Embedding generation failed: {response.status_code}")
            print_error(f"Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print_error(f"Embedding service connection failed: {e}")
        return False


def test_search_api() -> bool:
    """Test search API health and functionality"""
    print_header("Testing Search API")
    
    try:
        # Test health endpoint
        response = requests.get(f"{SEARCH_API_URL}/api/search/health", timeout=5)
        if response.status_code == 200:
            print_success("Search API is healthy")
        else:
            print_error(f"Health check failed: {response.status_code}")
            return False
        
        # Test search endpoint with various queries
        all_passed = True
        for query in TEST_QUERIES:
            response = requests.post(
                f"{SEARCH_API_URL}/api/search",
                json={"query": query, "limit": 5},
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                results = data.get('results', [])
                total = data.get('total', 0)
                max_score = data.get('maxScore')
                
                score_str = f"{max_score:.4f}" if max_score else "N/A"
                print_success(f"Query: '{query}' - Found {total} results (max score: {score_str})")
                
                # Validate result structure
                if results:
                    first_result = results[0]
                    required_fields = ['productId', 'title', 'price', 'unitPrice', 'rating', 
                                     'reviewCount', 'ranking', 'votes', 'similarityScore']
                    missing_fields = [f for f in required_fields if f not in first_result]
                    if missing_fields:
                        print_warning(f"Missing fields in result: {', '.join(missing_fields)}")
                        all_passed = False
                    else:
                        print_info(f"  Top result: {first_result.get('title', 'N/A')[:50]}...")
                else:
                    print_warning(f"No results returned for query: '{query}'")
            else:
                print_error(f"Search failed for '{query}': {response.status_code}")
                print_error(f"Response: {response.text[:200]}")
                all_passed = False
        
        return all_passed
        
    except requests.exceptions.RequestException as e:
        print_error(f"Search API connection failed: {e}")
        return False


def test_data_quality() -> bool:
    """Test data quality and completeness"""
    print_header("Testing Data Quality")
    
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        cursor = conn.cursor()
        
        # Check for null values in critical fields
        checks = [
            ("Products with null titles", "SELECT COUNT(*) FROM products WHERE title IS NULL"),
            ("Products with null descriptions", "SELECT COUNT(*) FROM products WHERE description IS NULL"),
            ("Products with null prices", "SELECT COUNT(*) FROM products WHERE price IS NULL"),
            ("Products with null ratings", "SELECT COUNT(*) FROM products WHERE rating IS NULL"),
            ("Products with null embeddings", "SELECT COUNT(*) FROM products WHERE embedding IS NULL"),
        ]
        
        all_passed = True
        for check_name, query in checks:
            cursor.execute(query)
            count = cursor.fetchone()[0]
            if count > 0:
                print_warning(f"{check_name}: {count}")
                all_passed = False
            else:
                print_success(f"{check_name}: 0")
        
        # Check price consistency
        cursor.execute("SELECT COUNT(*) FROM products WHERE unit_price IS NULL;")
        null_unit_price = cursor.fetchone()[0]
        if null_unit_price > 0:
            print_warning(f"Products with null unit_price: {null_unit_price}")
        else:
            print_success("All products have unit_price set")
        
        # Check ranking consistency
        cursor.execute("SELECT COUNT(*) FROM products WHERE ranking IS NULL;")
        null_ranking = cursor.fetchone()[0]
        if null_ranking > 0:
            print_warning(f"Products with null ranking: {null_ranking}")
        else:
            print_success("All products have ranking set")
        
        # Check votes consistency
        cursor.execute("SELECT COUNT(*) FROM products WHERE votes IS NULL;")
        null_votes = cursor.fetchone()[0]
        if null_votes > 0:
            print_warning(f"Products with null votes: {null_votes}")
        else:
            print_success("All products have votes set")
        
        cursor.close()
        conn.close()
        return all_passed
        
    except psycopg2.Error as e:
        print_error(f"Data quality check failed: {e}")
        return False


def test_search_ranking() -> bool:
    """Test that search results are properly ranked by similarity"""
    print_header("Testing Search Ranking")
    
    try:
        response = requests.post(
            f"{SEARCH_API_URL}/api/search",
            json={"query": "wireless noise cancelling headphones", "limit": 10},
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        
        if response.status_code != 200:
            print_error(f"Search request failed: {response.status_code}")
            return False
        
        data = response.json()
        results = data.get('results', [])
        
        if len(results) < 2:
            print_warning("Not enough results to test ranking")
            return True
        
        # Check that results are sorted by similarity (descending)
        scores = [r.get('similarityScore', 0) for r in results]
        is_sorted = all(scores[i] >= scores[i+1] for i in range(len(scores)-1))
        
        if is_sorted:
            print_success("Results are properly sorted by similarity score")
            print_info(f"Score range: {max(scores):.4f} to {min(scores):.4f}")
            return True
        else:
            print_error("Results are NOT properly sorted by similarity")
            print_info(f"Scores: {scores}")
            return False
            
    except requests.exceptions.RequestException as e:
        print_error(f"Ranking test failed: {e}")
        return False


def run_all_tests() -> Dict[str, bool]:
    """Run all tests and return results"""
    print(f"\n{BOLD}{BLUE}{'='*60}{RESET}")
    print(f"{BOLD}{BLUE}E-commerce Semantic Search System - Test Suite{RESET}")
    print(f"{BOLD}{BLUE}{'='*60}{RESET}")
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    results = {
        "Database Connection": test_database_connection(),
        "Embedding Service": test_embedding_service(),
        "Search API": test_search_api(),
        "Data Quality": test_data_quality(),
        "Search Ranking": test_search_ranking(),
    }
    
    return results


def print_summary(results: Dict[str, bool]):
    """Print test summary"""
    print_header("Test Summary")
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    for test_name, result in results.items():
        status = f"{GREEN}PASSED{RESET}" if result else f"{RED}FAILED{RESET}"
        print(f"{test_name}: {status}")
    
    print(f"\n{BOLD}Total: {passed}/{total} tests passed{RESET}")
    
    if passed == total:
        print(f"{GREEN}{BOLD}All tests passed! ✓{RESET}\n")
        return 0
    else:
        print(f"{RED}{BOLD}Some tests failed. Please review the output above.{RESET}\n")
        return 1


def main():
    """Main test runner"""
    try:
        results = run_all_tests()
        exit_code = print_summary(results)
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Tests interrupted by user{RESET}")
        sys.exit(1)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
