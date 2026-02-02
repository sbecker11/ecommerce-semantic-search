# Fine-tuning and Evaluation

This directory contains scripts for fine-tuning the embedding model and evaluating search relevancy.

## Fine-tuning

Fine-tune the sentence transformer model on e-commerce data to improve search relevancy.

### Prepare Training Data

Create `data/training_data.json`:
```json
[
  {
    "query": "wireless bluetooth headphones",
    "product_text": "Sony WH-1000XM4 Wireless Noise Cancelling Headphones",
    "relevance": 1.0
  },
  ...
]
```

### Prepare Evaluation Data

Create `data/eval_data.json`:
```json
[
  {
    "query": "wireless headphones",
    "relevant_products": [
      {"text": "Sony WH-1000XM4 Wireless Headphones"},
      {"text": "Bose QuietComfort 35 II"}
    ]
  },
  ...
]
```

### Run Fine-tuning

```bash
pip install -r requirements.txt
python fine_tune_model.py \
  --base-model sentence-transformers/all-MiniLM-L6-v2 \
  --train-data data/training_data.json \
  --eval-data data/eval_data.json \
  --output models/fine-tuned-model \
  --epochs 3 \
  --batch-size 16
```

## Evaluation

Evaluate search relevancy using metrics: NDCG, MRR, Precision@K, Recall@K.

### Prepare Test Data

Create `data/test_queries.json`:
```json
[
  {
    "query": "wireless headphones",
    "relevant_product_ids": ["prod1", "prod2"],
    "relevance_scores": {
      "prod1": 1.0,
      "prod2": 0.8
    }
  },
  ...
]
```

### Run Evaluation

```bash
python evaluate_search.py \
  --api-url http://localhost:8081/api/search \
  --test-data data/test_queries.json \
  --k-values 5 10 20
```

### Compare Models

```bash
python evaluate_search.py \
  --api-url http://localhost:8081/api/search \
  --compare http://localhost:8082/api/search \
  --test-data data/test_queries.json
```

## Metrics Explained

- **NDCG@K**: Normalized Discounted Cumulative Gain at K - measures ranking quality
- **MRR**: Mean Reciprocal Rank - average of reciprocal ranks of first relevant result
- **Precision@K**: Fraction of top-K results that are relevant
- **Recall@K**: Fraction of relevant items found in top-K results
