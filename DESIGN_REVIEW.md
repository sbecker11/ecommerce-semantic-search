# Design Review: ecommerce-semantic-search

---

## Original Problem Statement

Design and implement a Semantic Search capability for an e-commerce application. The problem is broken into two parts — 1) data engineering pipeline and 2) the search engine.

**Data Engineering Pipeline**

- Refer to this open source dataset of Amazon products. Ingest the data to a database of your choice, which should have the vector search capability.
- Choose an LLM (Large Language Model) model of your choice from https://huggingface.co/ and deploy its inference endpoint as a service, preferably in an ECS (Elastic Container Service) Fargate cluster.
- The ingested data should have vector fields which could be generated on certain fields of your choice; they should be relevant to the searchable fields.

**Search Engine**

- Implement a POST API using Java Spring Boot which should take a search string as request body.
- The API should be able to perform a vector search against the database table where the product metadata along with the vector field is already ingested.
- The result should be sorted in order of relevance of the search terms.
- **Bonus** — Fine tune the model to improve the relevancy of retrieval and show the improvement in relevancy using a metric.

---

## Compliance Assessment

Looking at what was implemented against the original problem statement, the project did quite well on the core requirements and addressed the bonus. Here is a breakdown by section.

**Data Engineering Pipeline.** The Amazon products dataset requirement was met — the ingestion pipeline handles multiple field conventions (ASIN (Amazon Standard Identification Number), product_id, etc.) and supports both JSON lines and CSV formats, suggesting it was built specifically around Amazon product data. The choice of pgvector over a standalone vector DB (Database) like Pinecone is a reasonable deviation; it satisfies the "vector search capability" requirement with less operational overhead, though a strict reader might note the problem implied a separate vector service. The HuggingFace model requirement was satisfied with `all-MiniLM-L6-v2`, and deploying it as a separate embedding service with ECS Fargate task definitions directly addresses the "deploy its inference endpoint as a service" requirement. Vector fields on relevant product fields (title, description) were implemented as specified.

**Search Engine.** This is where the project hits every requirement precisely. Spring Boot POST API — check. Vector search against the ingested table — check. Results sorted by cosine similarity relevance — check. Note that the Java Spring Boot constraint was explicitly required by the problem statement, which makes any architectural critique of the polyglot stack somewhat unfair — that decision was not the developer's to make.

**Bonus (Fine-tuning).** The `evaluation/` directory with fine-tuning scripts and NDCG (Normalized Discounted Cumulative Gain)/MRR (Mean Reciprocal Rank)/Precision@Recall metrics shows the intent was there. However, there is no evidence the fine-tuning was actually run, and no before/after metrics are documented anywhere. The bonus was attempted but not demonstrated — a missed opportunity to fully claim credit.

**What exceeded the requirements.** The project went further than asked in several areas: GIN (Generalized Inverted Index) indexes for full-text search, IVFFlat (Inverted File with Flat compression) index configuration, multi-stage Docker builds, CI/CD (Continuous Integration/Continuous Deployment) via GitHub Actions, health check endpoints, and operational scripts for backup/restore. These all signal production thinking that goes well beyond the assignment scope.

**Extra credit: CloudFormation Infrastructure as Code.** The CloudFormation template is for **production (or staging) deployment on AWS only**; local development uses Docker Compose and does not use CloudFormation. The project includes a complete CloudFormation template (`infrastructure/cloudformation/ecs-embedding-service.yaml`) that defines the entire ECS (Elastic Container Service) Fargate deployment stack — ECS cluster, service, Application Load Balancer (ALB), security groups, IAM (Identity and Access Management) roles, CloudWatch logs, and ECR (Elastic Container Registry) repository. This is a significant operational improvement over manual deployment scripts because it provides: (1) **reproducibility** — the same template can deploy identical infrastructure across dev/staging/prod environments; (2) **version control** — infrastructure changes are tracked in git alongside code changes; (3) **complete stack definition** — all AWS (Amazon Web Services) resources (not just the task definition) are defined declaratively, reducing configuration drift and manual setup errors; (4) **team collaboration** — infrastructure changes can be reviewed via pull requests before deployment. For a production system, Infrastructure as Code (IaC) is considered a best practice and demonstrates advanced DevOps (Development Operations) maturity beyond basic containerization.

**Summary.** The core assignment was implemented thoroughly and faithfully. The primary gaps relative to the problem statement are the unrun fine-tuning experiment (the bonus credit is incomplete) and the absence of a working demo with real data showing the search performing well. For a job application context, those two things are the difference between "I built this" and "I built this and it works."

---

## Executive Summary

This project implements an end-to-end semantic search system for e-commerce products using vector embeddings, pgvector, and a microservices architecture. The overall design is solid and demonstrates good architectural thinking — clean separation of concerns, containerized services, and a sensible technology stack. Below I identify both strengths and areas for improvement across architecture, implementation, operational readiness, and portfolio positioning.

---

## Architecture Assessment

### What Works Well

**Clean microservice boundaries.** The system is decomposed into four logical services (data pipeline, embedding service, search API, database) with clear responsibilities. Each can be developed, tested, and deployed independently.

**Technology choices are well-matched to the problem.** pgvector is the right call for a project of this scale — it avoids the operational overhead of a standalone vector database (Pinecone, Weaviate) while keeping everything in a single Postgres instance. `all-MiniLM-L6-v2` is a sensible default: fast, lightweight (384 dimensions), and well-proven for semantic similarity.

**Production deployment path is credible.** The ECS Fargate task definition, multi-stage Docker builds, and the detailed README table showing where each component runs in production all signal real deployment thinking rather than a toy project.

### Concerns and Recommendations

**1. The polyglot stack (Java + Python) adds complexity without a clear payoff.**

Note: Java Spring Boot was mandated by the original problem statement, so this is a constraint rather than a design choice. That said, the Spring Boot API (Application Programming Interface) as implemented is a thin proxy — it receives a query, calls the embedding service over HTTP (Hypertext Transfer Protocol), runs a native SQL (Structured Query Language) query, and returns results. Any reviewer needs to evaluate two ecosystems. If the README called out that Java was a hard requirement, it would preempt this concern entirely.

**2. The embedding service is a synchronous bottleneck at query time.**

Every search request makes a blocking HTTP call from the search API to the embedding service to vectorize the query. This adds ~50–200ms of network and inference latency per request, and the embedding service becomes a single point of failure.

Recommendations:

- For the search API, consider embedding the model directly (using ONNX (Open Neural Network Exchange) Runtime in Java) to eliminate the network hop at query time. The model is only 80MB.
- If the service boundary is important (e.g., for shared use by both ingestion and search), add retry logic and a circuit breaker. The current `EmbeddingService.java` wraps failures in a bare `RuntimeException` with no retry.
- The embedding service uses only 2 Gunicorn workers. Under concurrent load, this will queue requests. Consider increasing workers or adding async inference.

**3. The IVFFlat index configuration may not match the data scale.**

The index is configured with `lists = 100`, which is appropriate for roughly 10K–1M rows. But the project doesn't specify the expected dataset size, and the `init-db.sql` creates the index at table creation time — before any data exists. IVFFlat requires data to be present for effective clustering; creating the index on an empty table produces a degenerate index.

Recommendations:

- Create the IVFFlat index *after* initial data load, or switch to HNSW (Hierarchical Navigable Small World) (`vector_ip_ops` or `vector_cosine_ops`), which doesn't require training and works well at all scales. pgvector supports HNSW as of v0.5.0.
- Document the expected data scale and index tuning rationale.

**4. No hybrid search (vector + keyword).**

The schema has GIN indexes for full-text search on `title` and `description`, but they are never used. The search API only performs vector similarity search. For e-commerce, hybrid search (combining semantic similarity with keyword/filter matching — brand, category, price range) dramatically improves relevance.

This is a missed opportunity, especially since the infrastructure is already in place. Even a simple `WHERE category = :category AND ...` filter combined with vector search would demonstrate the concept.

---

## Implementation Details

### Data Pipeline (`ingest_data.py`)

**Strengths:** Handles multiple field name conventions (asin/product_id/id), supports JSON lines and CSV, uses upsert (`ON CONFLICT ... DO UPDATE`).

**Issues:**

- **No batch embedding calls.** The pipeline calls `/embed` once per product, even though the embedding service has a `/embed/batch` endpoint. For 10K products, that's 10K HTTP requests instead of 100 batches of 100. This is a major performance issue.
- **No connection pooling.** A single `psycopg2` connection is used for the entire pipeline. For large datasets, this is fragile — any transient error kills the whole run.
- **Commits per row.** Each `insert_product` call commits individually. Batching commits (e.g., every 100 rows) would be dramatically faster.
- **Error handling swallows failures.** `get_embedding` returns `None` on error and the product is silently skipped. There's no retry, no dead-letter tracking, and no summary of how many products failed.

### Embedding Service (`app.py`)

**Strengths:** Clean, simple Flask app. Normalizes embeddings (`normalize_embeddings=True`), which is important for cosine similarity to work correctly.

**Issues:**

- **No input length validation.** Sentence transformers have a max token limit (256 for MiniLM). Long product descriptions will be silently truncated, potentially losing important information. The service should warn or truncate intelligently (e.g., prioritize title over description).
- **No request size limits.** The batch endpoint accepts unbounded lists. A single large batch request could OOM (Out Of Memory) the service.
- **Model loaded at module level.** If model loading fails, the Flask app fails to start with an unhandled exception. The `try/except` at lines 23–28 catches and re-raises, but Gunicorn workers will crash-loop.

### Search API (Spring Boot)

**Strengths:** Clean controller/service/repository layering. Global exception handler. Configurable limits with max cap.

**Issues:**

- **Manual ORM (Object-Relational Mapping) mapping.** `SearchService.extractProduct()` is a 30+ line method that manually casts `Object[]` indices to Product fields by position. This is brittle — any schema change breaks it silently. Using a JPA (Java Persistence API) `@SqlResultSetMapping` or Spring's `JdbcTemplate.query(RowMapper)` would be safer.
- **Reflection for PGobject.** Lines 73–80 use reflection to call `getValue()` on PGobject (PostgreSQL JDBC driver class for custom types such as vector) to avoid importing the Postgres driver class. This is clever but unnecessary — the Postgres JDBC (Java Database Connectivity) driver is already a compile dependency. A direct cast would be cleaner.
- **`@CrossOrigin(origins = "*")`** is fine for development but should be flagged as something to lock down for production.
- **No pagination.** The API returns up to 100 results but has no offset/cursor support. For production use, this limits client flexibility.

### Database Schema (`init-db.sql`)

**Strengths:** Clean schema, appropriate types, automatic `updated_at` trigger.

**Issues:**

- **`rating DECIMAL(3,2)`** only supports values 0.00–9.99. Since ratings are typically 1–5 with one decimal (e.g., 4.7), this works but `DECIMAL(2,1)` would be more precise about intent.
- **No index on `product_id`** beyond the UNIQUE constraint. The UNIQUE constraint creates an implicit B-tree index, so this is actually fine — but worth noting that `findByProductId` in the repository is covered.

---

## Operational Readiness

### What's Good

- CI pipeline (GitHub Actions) runs Java tests, Python linting, and Docker builds
- Shell scripts for start/stop/status/backup/restore
- Health check endpoints on all services
- Docker Compose for local development
- **CloudFormation IaC template** for complete ECS Fargate deployment (cluster, service, ALB, security groups, IAM roles) — enables reproducible, version-controlled infrastructure deployments (production/staging on AWS; development uses Docker Compose locally)

### Gaps

- **No integration tests.** The CI runs unit tests for the search API and lints Python, but there are no tests that verify the services actually work together (e.g., spin up Docker Compose, ingest sample data, run a search, verify results).
- **No secrets management.** Database credentials are `postgres/postgres` hardcoded in `docker-compose.yml` with env var overrides. The ARCHITECTURE.md mentions "credentials via environment variables" but there's no `.env.example`, no reference to AWS Secrets Manager, and the backup/restore scripts embed credentials in shell commands.
- **No observability.** The ARCHITECTURE.md recommends Prometheus, CloudWatch, and X-Ray but none are implemented. There's no request logging beyond Spring's defaults, no metrics endpoint, and no trace propagation between the search API and embedding service.
- **`backup.sql` is committed to the repo** (81K). This is actual database state checked into version control. It should be in `.gitignore`.

---

## Scaling to Millions of Amazon Products

The current design is well-suited to tens or low hundreds of thousands of products. Scaling to **millions** of Amazon products would require changes across the data pipeline, embedding service, database, and search API. Below is a concise outline of what would need to change.

### Data Pipeline

- **Batch embeddings and batched commits.** The pipeline must use the embedding service’s `/embed/batch` endpoint (e.g., 100–500 texts per request) and commit in batches (e.g., every 1K–10K rows) instead of one request and one commit per product. At millions of rows, per-row HTTP and commits are untenable.
- **Parallelism and throughput.** Run multiple ingestion workers (processes or threads), each handling a shard of the dataset (e.g., by file or by key range). Coordinate with a queue (e.g., SQS) or partitioned input (e.g., S3 prefix per worker) so the embedding service and database are fully utilized.
- **Resilience and observability.** Use connection pooling (e.g., `psycopg2.pool` or SQLAlchemy), retries with backoff for embedding and DB calls, and dead-letter handling for failed products. Emit progress metrics (rows ingested, latency, error counts) and support checkpointing or idempotent runs so ingestion can resume after failures.
- **Incremental updates.** For ongoing catalog updates, only embed and upsert new or changed products (e.g., by `updated_at` or a change-data-capture feed) instead of full re-ingestion.

### Embedding Service

- **Horizontal scaling.** Run multiple ECS tasks (or Kubernetes replicas) behind a load balancer. The stateless design supports this; ensure clients use the batch API and spread load across replicas.
- **Throughput and batching.** Tune worker count (e.g., Gunicorn workers) and batch size so that CPU/GPU is saturated without OOM. Add request size limits and timeouts to avoid one large batch taking down a replica.
- **Optional: dedicated embedding cluster.** For very high throughput, consider a dedicated embedding cluster (e.g., multiple Fargate tasks or GPU instances) used only by the pipeline, separate from the low-latency embedding path used at query time.

### Database and Vector Index

- **Index type and tuning.** For millions of vectors, prefer **HNSW** over IVFFlat for better recall and no training requirement; tune `ef_construction` and `ef_search` for build time vs. query quality. If staying with IVFFlat, increase `lists` (e.g., `sqrt(n)` or more) and create the index only after the table is populated; use `probes` at query time to balance speed and recall.
- **Resources and connection pooling.** Size RDS (or Aurora) for memory (to hold the index and working set) and CPU. Use connection pooling (e.g., PgBouncer, RDS Proxy) so the search API and pipeline do not exhaust connections.
- **Read scaling (optional).** Add read replicas for search traffic and keep writes (ingestion) on the primary. Application must route read-only vector queries to replicas.
- **When to consider a dedicated vector store.** If pgvector becomes a bottleneck (e.g., index size, query latency, or operational limits), consider a vector-native store (e.g., OpenSearch with k-NN, Pinecone, Weaviate) for search, possibly with Postgres remaining as the source of truth for metadata.

### Search API

- **Pagination and limits.** Support cursor- or offset-based pagination so clients can page through large result sets without pulling thousands of rows at once.
- **Caching.** Cache embedding results for repeated or popular queries (e.g., in-process, Redis, or API Gateway cache) to reduce calls to the embedding service and database.
- **Rate limiting and protection.** Add rate limiting and timeouts so that traffic spikes or expensive queries do not overwhelm the embedding service or database.

### IaC (CloudFormation) Template Changes

The current template (`infrastructure/cloudformation/ecs-embedding-service.yaml`) deploys only the embedding service (ECS Fargate, ALB, security groups, IAM, ECR, CloudWatch). To support millions of products, the following changes would be needed:

- **Application Auto Scaling.** Add `AWS::ApplicationAutoScaling::ScalableTarget` and `AWS::ApplicationAutoScaling::ScalingPolicy` resources so the ECS service scales on CPU utilization, memory utilization, or (via custom metric) request count. Parameterize min/max task count (e.g. min 2, max 20) so the embedding service can handle concurrent pipeline and search traffic without over-provisioning.
- **Task size and defaults.** For high throughput, allow larger task sizes (e.g. 4096 CPU, 8192 MB memory) via parameters; document recommended values for “millions of products” so operators don’t rely on the current 2 vCPU / 4 GB default under load.
- **ALB and target group tuning.** Increase ALB idle timeout if clients use long-running batch requests; tune target group `deregistration_delay` and health check intervals for faster scaling-in without dropping in-flight requests.
- **Full-stack option.** The template does not define RDS, the search API, or the data pipeline. For a single-stack “production at scale” story, add optional modules or nested stacks for: (1) RDS (or Aurora) with parameter groups for connection limits and (2) RDS Proxy for connection pooling; (3) ECS service(s) for the Spring Boot search API with its own scaling policies; (4) optional queue (e.g. SQS) and Lambda or ECS tasks for the ingestion pipeline. Alternatively, keep embedding-only and document that RDS and search API are deployed separately.
- **Secrets and config.** Move sensitive or environment-specific config (e.g. model name, feature flags) to AWS Secrets Manager or SSM Parameter Store and reference them in the task definition instead of plain `Environment` values where appropriate.
- **Observability.** Template already enables Container Insights. For scale, add optional dashboard (e.g. `AWS::CloudWatch::Dashboard`) and alarms (e.g. `AWS::CloudWatch::Alarm`) for high CPU/memory, error rate, or target response time so operators can react to load.

### Summary Table

| Area              | Current scale assumption | Changes for millions of products                    |
|-------------------|--------------------------|------------------------------------------------------|
| Data pipeline     | Single process, per-row  | Batch embed + batch commit; parallel workers; DLQ    |
| Embedding service | Single task, few workers | Multiple replicas; batch-heavy; optional GPU cluster |
| Database          | Single Postgres, IVFFlat | HNSW or tuned IVFFlat; pooling; read replicas        |
| Search API        | No pagination, no cache  | Pagination; query/embedding cache; rate limits       |
| **IaC (CloudFormation)** | Fixed task count, embedding-only | Auto Scaling; larger task sizes; optional RDS/search API/queue; secrets; alarms/dashboards |

---

## Portfolio Positioning Considerations

Given that this project is likely part of your job search portfolio, a few observations on how it reads to a technical reviewer:

**Strengths for your narrative:** This project directly demonstrates vector embeddings, similarity search, data pipeline engineering, and microservice architecture — all highly relevant for AI/ML (Artificial Intelligence/Machine Learning) engineering roles. The evaluation module with NDCG/MRR/Precision@Recall metrics shows you understand information retrieval theory, not just implementation.

**Areas to strengthen:**

- **Add a working demo.** Seed the database with real (or realistic) data and include a screenshot or GIF of a search query returning ranked results. Reviewers who can't run the project should still see it working.
- **Highlight the fine-tuning story.** The `evaluation/` directory has scripts for fine-tuning and comparison, but there's no evidence they've been run. Adding a `RESULTS.md` showing before/after metrics from an actual fine-tuning experiment would be very compelling.
- **Connect to your patent work.** Your patents are on NLP (Natural Language Processing)-based recommendation systems using vector embeddings and cosine similarity — this project is a direct implementation of those concepts. A brief note in the README connecting the two would add credibility.

---

## Glossary of Key Terms

**GIN Index (Generalized Inverted Index).** A PostgreSQL index type designed for columns whose values contain multiple searchable elements, such as text documents containing many words. Rather than mapping each row to a single value (as a B-tree index does), a GIN index inverts the relationship — mapping each token (word) to all rows that contain it. This makes full-text queries like "find products whose description contains 'running shoes'" dramatically faster on large datasets, since PostgreSQL can look up matching tokens instantly rather than scanning every row. In PostgreSQL's full-text search system, text is first converted into a `tsvector` (a normalized token list) and GIN indexes are the standard way to index those columns.

**IVFFlat Index (Inverted File with Flat compression).** An approximate nearest neighbor (ANN (Approximate Nearest Neighbor)) indexing algorithm used by pgvector to accelerate vector similarity searches. Without an index, finding the most similar vector to a query requires comparing against every vector in the table — a brute-force scan that doesn't scale. IVFFlat solves this by running k-means clustering on all vectors at index-build time, grouping them into `lists` number of clusters. At query time, it finds the nearest cluster(s) first, then searches only within those, dramatically reducing comparisons. The tradeoff is that it's *approximate* — results are very accurate but not guaranteed to be perfect. A key requirement is that the index must be built on a populated table, since k-means needs real vectors to cluster; building it on an empty table produces a degenerate, useless index.

**HNSW (Hierarchical Navigable Small World).** A graph-based ANN indexing algorithm and the modern alternative to IVFFlat in pgvector (available since v0.5.0). Rather than clustering vectors into buckets, HNSW builds a layered graph where each vector is connected to its nearest neighbors at multiple levels of granularity. At query time it navigates this graph greedily, converging on the nearest neighbors quickly. Key advantages over IVFFlat: it requires no training step so it works correctly when built on an empty or partially populated table; it generally delivers better recall and query performance; and it doesn't require tuning a `probes` parameter at query time. The tradeoffs are higher memory usage and longer index build times.

**NDCG (Normalized Discounted Cumulative Gain).** An information retrieval metric that measures the quality of a ranked result list, with two important properties: it rewards relevant results appearing higher in the list (discounting), and it accounts for degrees of relevance rather than just binary relevant/not-relevant. "Cumulative Gain" sums up the relevance scores of all returned results. "Discounted" means results lower in the ranking are worth less — a relevant result at position 1 contributes more than the same result at position 10. "Normalized" scales the score against the ideal ranking (if the system had returned results in perfect order), producing a value between 0 and 1. An NDCG of 1.0 means the system returned results in the perfect order; lower values indicate suboptimal ranking.

**MRR (Mean Reciprocal Rank).** A simpler metric that focuses on where the first relevant result appears. For each query, the Reciprocal Rank is 1 divided by the position of the first correct result — so if the right answer is at position 1 the score is 1.0, at position 2 it's 0.5, at position 5 it's 0.2, and so on. MRR averages these scores across all test queries. It's most useful when you care primarily about whether the single best result surfaces near the top, which is common in question-answering and navigational search scenarios.

**Precision@K / Recall@K.** Two complementary metrics for evaluating ranked retrieval at a cutoff of K results. Precision@K asks "of the K results returned, what fraction were actually relevant?" — it penalizes returning irrelevant results. Recall@K asks "of all relevant items that exist, what fraction did the system return within the top K?" — it penalizes missing relevant items. The two are in natural tension: returning more results improves recall but can hurt precision. In practice, both are reported together (sometimes as Precision@Recall curves) to characterize the full accuracy/coverage tradeoff of the search system.

---

## Priority Recommendations (Ranked)

1. **Switch the ingestion pipeline to use batch embeddings** — easiest win, biggest performance improvement
2. **Add hybrid search** (vector + keyword/filters) — differentiates the project from trivial vector search demos
3. **Consider HNSW over IVFFlat** — better out-of-the-box performance, no need to build index after data load
4. **Add an integration test** — even a simple Docker Compose-based smoke test dramatically increases confidence
5. **Remove `backup.sql` from version control** and add a `.env.example`
6. **Add a results showcase** — demo data, search examples, and fine-tuning metrics