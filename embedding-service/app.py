#!/usr/bin/env python3
"""
Embedding Service using HuggingFace Sentence Transformers
Deployed as a Flask service for generating embeddings
"""

import os
import logging
from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer
import torch

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Load model
MODEL_NAME = os.getenv('MODEL_NAME', 'sentence-transformers/all-MiniLM-L6-v2')
logger.info(f"Loading model: {MODEL_NAME}")

try:
    model = SentenceTransformer(MODEL_NAME)
    logger.info("Model loaded successfully")
except Exception as e:
    logger.error(f"Error loading model: {e}")
    raise


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'model': MODEL_NAME}), 200


@app.route('/embed', methods=['POST'])
def embed():
    """
    Generate embedding for input text
    
    Request body:
    {
        "text": "wireless bluetooth headphones"
    }
    
    Response:
    {
        "embedding": [0.123, -0.456, ...],
        "dimension": 384
    }
    """
    try:
        data = request.get_json()
        if not data or 'text' not in data:
            return jsonify({'error': 'Missing "text" field in request body'}), 400
        
        text = data['text']
        if not isinstance(text, str) or not text.strip():
            return jsonify({'error': 'Text must be a non-empty string'}), 400
        
        # Generate embedding
        embedding = model.encode(text, convert_to_numpy=True, normalize_embeddings=True)
        embedding_list = embedding.tolist()
        
        return jsonify({
            'embedding': embedding_list,
            'dimension': len(embedding_list)
        }), 200
    
    except Exception as e:
        logger.error(f"Error generating embedding: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/embed/batch', methods=['POST'])
def embed_batch():
    """
    Generate embeddings for multiple texts
    
    Request body:
    {
        "texts": ["text1", "text2", ...]
    }
    
    Response:
    {
        "embeddings": [[...], [...], ...],
        "count": 2
    }
    """
    try:
        data = request.get_json()
        if not data or 'texts' not in data:
            return jsonify({'error': 'Missing "texts" field in request body'}), 400
        
        texts = data['texts']
        if not isinstance(texts, list) or len(texts) == 0:
            return jsonify({'error': 'Texts must be a non-empty list'}), 400
        
        # Generate embeddings
        embeddings = model.encode(texts, convert_to_numpy=True, normalize_embeddings=True)
        embeddings_list = embeddings.tolist()
        
        return jsonify({
            'embeddings': embeddings_list,
            'count': len(embeddings_list)
        }), 200
    
    except Exception as e:
        logger.error(f"Error generating batch embeddings: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
