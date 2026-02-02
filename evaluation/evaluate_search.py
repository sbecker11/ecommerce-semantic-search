#!/usr/bin/env python3
"""
Evaluation script for semantic search relevancy
Calculates metrics: NDCG, MRR, Precision@K, Recall@K
"""

import json
import requests
import numpy as np
from typing import List, Dict
from collections import defaultdict
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def dcg(relevance_scores: List[float], k: int = None) -> float:
    """Calculate Discounted Cumulative Gain"""
    if k is not None:
        relevance_scores = relevance_scores[:k]
    
    dcg_score = 0.0
    for i, score in enumerate(relevance_scores, 1):
        dcg_score += score / np.log2(i + 1)
    return dcg_score


def ndcg(relevance_scores: List[float], k: int = None) -> float:
    """Calculate Normalized Discounted Cumulative Gain"""
    if not relevance_scores:
        return 0.0
    
    dcg_score = dcg(relevance_scores, k)
    ideal_scores = sorted(relevance_scores, reverse=True)
    idcg_score = dcg(ideal_scores, k)
    
    if idcg_score == 0:
        return 0.0
    
    return dcg_score / idcg_score


def precision_at_k(relevant_items: List[bool], k: int) -> float:
    """Calculate Precision@K"""
    if len(relevant_items) == 0:
        return 0.0
    
    top_k = relevant_items[:k]
    return sum(top_k) / min(k, len(relevant_items))


def recall_at_k(relevant_items: List[bool], total_relevant: int, k: int) -> float:
    """Calculate Recall@K"""
    if total_relevant == 0:
        return 0.0
    
    top_k = relevant_items[:k]
    return sum(top_k) / total_relevant


def mrr(relevance_scores: List[float]) -> float:
    """Calculate Mean Reciprocal Rank"""
    for i, score in enumerate(relevance_scores, 1):
        if score > 0:
            return 1.0 / i
    return 0.0


def evaluate_search(
    search_api_url: str,
    test_queries: List[Dict],
    k_values: List[int] = [5, 10, 20]
) -> Dict:
    """
    Evaluate search API with test queries
    
    test_queries format:
    [
        {
            "query": "wireless headphones",
            "relevant_product_ids": ["prod1", "prod2", ...],
            "relevance_scores": {"prod1": 1.0, "prod2": 0.8, ...}  # Optional
        },
        ...
    ]
    """
    logger.info(f"Evaluating {len(test_queries)} queries against {search_api_url}")
    
    metrics = defaultdict(list)
    
    for query_data in test_queries:
        query = query_data['query']
        relevant_ids = set(query_data.get('relevant_product_ids', []))
        relevance_scores = query_data.get('relevance_scores', {})
        
        # Call search API
        try:
            response = requests.post(
                search_api_url,
                json={'query': query, 'limit': max(k_values)},
                timeout=30
            )
            response.raise_for_status()
            results = response.json()['results']
        except Exception as e:
            logger.error(f"Error querying API for '{query}': {e}")
            continue
        
        # Extract product IDs and similarity scores
        retrieved_ids = [r['productId'] for r in results]
        similarity_scores = [r.get('similarityScore', 0.0) for r in results]
        
        # Create relevance list (1 if relevant, 0 otherwise)
        relevance_list = [1 if pid in relevant_ids else 0 for pid in retrieved_ids]
        
        # Get relevance scores if available
        scored_relevance = [
            relevance_scores.get(pid, 1.0 if pid in relevant_ids else 0.0)
            for pid in retrieved_ids
        ]
        
        # Calculate metrics for different K values
        for k in k_values:
            rel_k = relevance_list[:k]
            scored_k = scored_relevance[:k]
            
            metrics[f'precision@{k}'].append(precision_at_k(rel_k, k))
            metrics[f'recall@{k}'].append(recall_at_k(rel_k, len(relevant_ids), k))
            metrics[f'ndcg@{k}'].append(ndcg(scored_k, k))
        
        metrics['mrr'].append(mrr(relevance_list))
    
    # Calculate average metrics
    avg_metrics = {}
    for metric_name, values in metrics.items():
        avg_metrics[metric_name] = {
            'mean': np.mean(values),
            'std': np.std(values),
            'values': values
        }
    
    return avg_metrics


def compare_models(
    base_api_url: str,
    fine_tuned_api_url: str,
    test_queries: List[Dict],
    k_values: List[int] = [5, 10, 20]
) -> Dict:
    """Compare base model vs fine-tuned model"""
    logger.info("Evaluating base model...")
    base_metrics = evaluate_search(base_api_url, test_queries, k_values)
    
    logger.info("Evaluating fine-tuned model...")
    fine_tuned_metrics = evaluate_search(fine_tuned_api_url, test_queries, k_values)
    
    # Calculate improvements
    improvements = {}
    for metric_name in base_metrics:
        base_mean = base_metrics[metric_name]['mean']
        ft_mean = fine_tuned_metrics[metric_name]['mean']
        improvement = ft_mean - base_mean
        improvement_pct = (improvement / base_mean * 100) if base_mean > 0 else 0
        
        improvements[metric_name] = {
            'base': base_mean,
            'fine_tuned': ft_mean,
            'improvement': improvement,
            'improvement_pct': improvement_pct
        }
    
    return {
        'base': base_metrics,
        'fine_tuned': fine_tuned_metrics,
        'improvements': improvements
    }


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Evaluate semantic search relevancy')
    parser.add_argument('--api-url', required=True, help='Search API URL')
    parser.add_argument('--test-data', required=True, help='Path to test queries JSON file')
    parser.add_argument('--compare', help='Fine-tuned API URL for comparison')
    parser.add_argument('--k-values', nargs='+', type=int, default=[5, 10, 20])
    
    args = parser.parse_args()
    
    # Load test data
    with open(args.test_data, 'r') as f:
        test_queries = json.load(f)
    
    if args.compare:
        results = compare_models(args.api_url, args.compare, test_queries, args.k_values)
        print("\n=== Comparison Results ===")
        print(json.dumps(results['improvements'], indent=2))
    else:
        results = evaluate_search(args.api_url, test_queries, args.k_values)
        print("\n=== Evaluation Results ===")
        for metric, stats in results.items():
            print(f"{metric}: {stats['mean']:.4f} ± {stats['std']:.4f}")
