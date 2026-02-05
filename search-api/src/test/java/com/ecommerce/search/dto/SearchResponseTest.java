package com.ecommerce.search.dto;

import com.ecommerce.search.model.Product;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class SearchResponseTest {

    @Test
    void productResult_fromProduct_withAllFields() {
        Product product = new Product();
        product.setProductId("prod-1");
        product.setTitle("Wireless Headphones");
        product.setDescription("Noise cancelling");
        product.setCategory("Electronics");
        product.setBrand("Sony");
        product.setPrice(new BigDecimal("99.99"));
        product.setUnitPrice(new BigDecimal("89.99"));
        product.setRating(new BigDecimal("4.5"));
        product.setReviewCount(100);
        product.setRanking(1);
        product.setVotes(50);
        product.setImageUrl("http://img.com");
        product.setAmazonUrl("http://amazon.com");

        SearchResponse.ProductResult result = SearchResponse.ProductResult.fromProduct(product, 0.92);

        assertEquals("prod-1", result.getProductId());
        assertEquals("Wireless Headphones", result.getTitle());
        assertEquals("Noise cancelling", result.getDescription());
        assertEquals("Electronics", result.getCategory());
        assertEquals("Sony", result.getBrand());
        assertEquals(99.99, result.getPrice());
        assertEquals(89.99, result.getUnitPrice());
        assertEquals(4.5, result.getRating());
        assertEquals(100, result.getReviewCount());
        assertEquals(1, result.getRanking());
        assertEquals(50, result.getVotes());
        assertEquals("http://img.com", result.getImageUrl());
        assertEquals("http://amazon.com", result.getAmazonUrl());
        assertEquals(0.92, result.getSimilarityScore());
    }

    @Test
    void productResult_fromProduct_withNullFields() {
        Product product = new Product();
        product.setProductId("prod-2");
        product.setTitle("Basic Product");
        product.setPrice(null);
        product.setRating(null);

        SearchResponse.ProductResult result = SearchResponse.ProductResult.fromProduct(product, 0.5);

        assertEquals("prod-2", result.getProductId());
        assertNull(result.getPrice());
        assertNull(result.getRating());
        assertEquals(0.5, result.getSimilarityScore());
    }
}
