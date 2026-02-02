#!/usr/bin/env python3
"""
Fine-tuning script for improving semantic search relevancy
Uses sentence-transformers for fine-tuning on e-commerce data
"""

import os
import json
import pandas as pd
from sentence_transformers import SentenceTransformer, InputExample, losses
from sentence_transformers.evaluation import InformationRetrievalEvaluator
from torch.utils.data import DataLoader
from typing import List, Tuple
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_training_data(file_path: str) -> List[Tuple[str, str, float]]:
    """
    Load training data in format: (query, product_text, relevance_score)
    Relevance score: 0.0 to 1.0 (1.0 = highly relevant)
    """
    logger.info(f"Loading training data from {file_path}")
    
    # Example: Load from JSON with query-product pairs and relevance scores
    with open(file_path, 'r') as f:
        data = json.load(f)
    
    training_examples = []
    for item in data:
        query = item['query']
        product_text = item['product_text']  # Combined title + description
        relevance = item.get('relevance', 1.0)  # Default to 1.0 if not specified
        training_examples.append((query, product_text, relevance))
    
    logger.info(f"Loaded {len(training_examples)} training examples")
    return training_examples


def create_training_examples(training_data: List[Tuple[str, str, float]]) -> List[InputExample]:
    """Convert training data to InputExample format"""
    examples = []
    for query, product_text, score in training_data:
        examples.append(InputExample(texts=[query, product_text], label=float(score)))
    return examples


def prepare_evaluation_data(file_path: str) -> Tuple[dict, dict]:
    """
    Prepare evaluation data for InformationRetrievalEvaluator
    Returns: (queries, corpus, relevant_docs)
    """
    logger.info(f"Loading evaluation data from {file_path}")
    
    with open(file_path, 'r') as f:
        data = json.load(f)
    
    queries = {}
    corpus = {}
    relevant_docs = {}
    
    query_id = 0
    doc_id = 0
    
    for item in data:
        query = item['query']
        query_key = f"q{query_id}"
        queries[query_key] = query
        
        # Get relevant products
        relevant = []
        for product in item.get('relevant_products', []):
            doc_key = f"d{doc_id}"
            corpus[doc_key] = product['text']
            relevant.append(doc_key)
            doc_id += 1
        
        relevant_docs[query_key] = set(relevant)
        query_id += 1
    
    logger.info(f"Prepared {len(queries)} queries, {len(corpus)} documents")
    return queries, corpus, relevant_docs


def fine_tune_model(
    base_model_name: str = 'sentence-transformers/all-MiniLM-L6-v2',
    train_data_path: str = 'data/training_data.json',
    eval_data_path: str = 'data/eval_data.json',
    output_path: str = 'models/fine-tuned-model',
    epochs: int = 3,
    batch_size: int = 16
):
    """Fine-tune the sentence transformer model"""
    
    logger.info(f"Loading base model: {base_model_name}")
    model = SentenceTransformer(base_model_name)
    
    # Load training data
    training_data = load_training_data(train_data_path)
    train_examples = create_training_examples(training_data)
    train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=batch_size)
    
    # Define loss function (CosineSimilarityLoss for semantic similarity)
    train_loss = losses.CosineSimilarityLoss(model)
    
    # Prepare evaluation data if available
    evaluator = None
    if os.path.exists(eval_data_path):
        queries, corpus, relevant_docs = prepare_evaluation_data(eval_data_path)
        evaluator = InformationRetrievalEvaluator(
            queries=queries,
            corpus=corpus,
            relevant_docs=relevant_docs,
            name='ecommerce-search',
            show_progress_bar=True
        )
    
    # Fine-tune the model
    logger.info(f"Starting fine-tuning for {epochs} epochs...")
    model.fit(
        train_objectives=[(train_dataloader, train_loss)],
        epochs=epochs,
        evaluator=evaluator,
        evaluation_steps=500,
        output_path=output_path,
        show_progress_bar=True
    )
    
    logger.info(f"Fine-tuned model saved to {output_path}")
    return model


def evaluate_model(
    model_path: str,
    test_data_path: str,
    base_model_path: str = None
):
    """
    Evaluate fine-tuned model and compare with base model
    Returns evaluation metrics
    """
    logger.info(f"Evaluating model: {model_path}")
    
    fine_tuned_model = SentenceTransformer(model_path)
    queries, corpus, relevant_docs = prepare_evaluation_data(test_data_path)
    
    evaluator = InformationRetrievalEvaluator(
        queries=queries,
        corpus=corpus,
        relevant_docs=relevant_docs,
        name='ecommerce-search-test',
        show_progress_bar=True
    )
    
    # Evaluate fine-tuned model
    fine_tuned_metrics = evaluator(fine_tuned_model)
    
    results = {
        'fine_tuned': fine_tuned_metrics
    }
    
    # Compare with base model if provided
    if base_model_path:
        logger.info(f"Evaluating base model: {base_model_path}")
        base_model = SentenceTransformer(base_model_path)
        base_metrics = evaluator(base_model)
        results['base'] = base_metrics
        
        # Calculate improvement
        for metric in fine_tuned_metrics:
            if metric in base_metrics:
                improvement = fine_tuned_metrics[metric] - base_metrics[metric]
                results[f'improvement_{metric}'] = improvement
                logger.info(f"{metric}: Base={base_metrics[metric]:.4f}, "
                          f"Fine-tuned={fine_tuned_metrics[metric]:.4f}, "
                          f"Improvement={improvement:.4f}")
    
    return results


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Fine-tune sentence transformer for e-commerce search')
    parser.add_argument('--base-model', default='sentence-transformers/all-MiniLM-L6-v2')
    parser.add_argument('--train-data', default='data/training_data.json')
    parser.add_argument('--eval-data', default='data/eval_data.json')
    parser.add_argument('--output', default='models/fine-tuned-model')
    parser.add_argument('--epochs', type=int, default=3)
    parser.add_argument('--batch-size', type=int, default=16)
    parser.add_argument('--evaluate-only', action='store_true')
    
    args = parser.parse_args()
    
    if args.evaluate_only:
        results = evaluate_model(args.output, args.eval_data, args.base_model)
        print("\nEvaluation Results:")
        print(json.dumps(results, indent=2))
    else:
        model = fine_tune_model(
            base_model_name=args.base_model,
            train_data_path=args.train_data,
            eval_data_path=args.eval_data,
            output_path=args.output,
            epochs=args.epochs,
            batch_size=args.batch_size
        )
        
        # Evaluate after training
        if os.path.exists(args.eval_data):
            results = evaluate_model(args.output, args.eval_data, args.base_model)
            print("\nEvaluation Results:")
            print(json.dumps(results, indent=2))
