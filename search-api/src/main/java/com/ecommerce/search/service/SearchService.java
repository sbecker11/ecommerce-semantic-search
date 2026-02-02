package com.ecommerce.search.service;

import com.ecommerce.search.dto.SearchResponse;
import com.ecommerce.search.model.Product;
import com.ecommerce.search.repository.ProductRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class SearchService {
    private final EmbeddingService embeddingService;
    private final ProductRepository productRepository;
    
    @Value("${search.default.limit:10}")
    private int defaultLimit;
    
    @Value("${search.default.max-limit:100}")
    private int maxLimit;
    
    public SearchService(EmbeddingService embeddingService, ProductRepository productRepository) {
        this.embeddingService = embeddingService;
        this.productRepository = productRepository;
    }
    
    public SearchResponse search(String query, Integer limit) {
        // Validate and set limit
        int searchLimit = limit != null ? Math.min(limit, maxLimit) : defaultLimit;
        
        // Get embedding for query
        List<Double> queryEmbedding = embeddingService.getEmbedding(query);
        String embeddingString = formatEmbeddingForPostgres(queryEmbedding);
        
        // Perform vector search
        List<Object[]> results = productRepository.findSimilarProducts(embeddingString, searchLimit);
        
        // Convert results to response
        List<SearchResponse.ProductResult> productResults = new ArrayList<>();
        Double maxScore = null;
        
        for (Object[] row : results) {
            Product product = extractProduct(row);
            Double similarity = extractSimilarity(row);
            
            if (maxScore == null || similarity > maxScore) {
                maxScore = similarity;
            }
            
            productResults.add(SearchResponse.ProductResult.fromProduct(product, similarity));
        }
        
        return new SearchResponse(productResults, productResults.size(), query, maxScore);
    }
    
    private Product extractProduct(Object[] row) {
        Product product = new Product();
        if (row[0] != null) {
            product.setId(((Number) row[0]).longValue());
        }
        product.setProductId((String) row[1]);
        product.setTitle((String) row[2]);
        product.setDescription((String) row[3]);
        product.setCategory((String) row[4]);
        product.setBrand((String) row[5]);
        if (row[6] != null) {
            product.setPrice(new java.math.BigDecimal(row[6].toString()));
        }
        if (row[7] != null) {
            product.setRating(new java.math.BigDecimal(row[7].toString()));
        }
        if (row[8] != null) {
            product.setReviewCount(((Number) row[8]).intValue());
        }
        product.setImageUrl((String) row[9]);
        // Handle embedding which may be PGobject or String
        if (row[10] != null) {
            // Use reflection to handle PGobject without direct import
            String className = row[10].getClass().getName();
            if (className.equals("org.postgresql.util.PGobject")) {
                try {
                    java.lang.reflect.Method getValueMethod = row[10].getClass().getMethod("getValue");
                    product.setEmbedding((String) getValueMethod.invoke(row[10]));
                } catch (Exception e) {
                    product.setEmbedding(row[10].toString());
                }
            } else {
                product.setEmbedding(row[10].toString());
            }
        }
        return product;
    }
    
    private Double extractSimilarity(Object[] row) {
        // Similarity is the last column
        Object similarityObj = row[row.length - 1];
        if (similarityObj instanceof Number) {
            return ((Number) similarityObj).doubleValue();
        }
        return 0.0;
    }
    
    private String formatEmbeddingForPostgres(List<Double> embedding) {
        return "[" + embedding.stream()
            .map(String::valueOf)
            .collect(Collectors.joining(",")) + "]";
    }
}
