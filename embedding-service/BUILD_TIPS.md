# Embedding Service Build Tips

## Why the build is slow

The embedding service build takes time because it installs:
- **PyTorch** (~2-3 GB) - Deep learning framework
- **Transformers** (~500 MB) - HuggingFace library
- **Sentence Transformers** - Additional dependencies

**First build**: 10-20 minutes (downloads everything)
**Subsequent builds**: 5-10 minutes (uses Docker cache)

## Speed up builds

### Option 1: Use build cache (recommended)
```bash
# First build (slow)
docker build -t embedding-service .

# Subsequent builds (faster - uses cache)
docker build -t embedding-service .
```

### Option 2: Use faster Dockerfile (for development)
```bash
# Use Dockerfile.fast which keeps pip cache
docker build -f Dockerfile.fast -t embedding-service .
```

### Option 3: Build in background
```bash
# Build in background and check progress
docker build -t embedding-service . > build.log 2>&1 &
tail -f build.log
```

### Option 4: Use pre-built base image
Consider using a pre-built Python image with ML libraries:
```dockerfile
FROM python:3.9-slim
# Or use: FROM huggingface/transformers-pytorch-cpu:latest
```

## Monitor build progress

```bash
# Watch build progress
docker build --progress=plain -t embedding-service .

# Check Docker build cache
docker system df
```

## Expected build times

- **First build**: 15-25 minutes (depends on internet speed)
- **Cached build**: 2-5 minutes
- **Model download** (first run): Additional 2-3 minutes when container starts

## Tips

1. **Don't cancel** - The first build is always slow, but subsequent builds are much faster
2. **Use Docker cache** - Don't change requirements.txt unnecessarily
3. **Build once, use many times** - The image can be reused
4. **Check your internet** - Slow connection = slower downloads

## After build completes

The model will download on **first container start**, not during build:
```bash
docker run -p 8080:8080 embedding-service
# First start: Downloads model (~100-200 MB) - takes 1-2 minutes
# Subsequent starts: Uses cached model - instant
```
