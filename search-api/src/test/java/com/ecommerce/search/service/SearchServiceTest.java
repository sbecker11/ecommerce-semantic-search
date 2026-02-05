package com.ecommerce.search.service;

import com.ecommerce.search.dto.SearchResponse;
import com.ecommerce.search.model.Product;
import com.ecommerce.search.repository.ProductRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SearchServiceTest {

    @Mock
    private EmbeddingService embeddingService;

    @Mock
    private ProductRepository productRepository;

    private SearchService searchService;

    @BeforeEach
    void setUp() {
        searchService = new SearchService(embeddingService, productRepository);
        ReflectionTestUtils.setField(searchService, "defaultLimit", 10);
        ReflectionTestUtils.setField(searchService, "maxLimit", 100);
    }

    @Test
    void search_returnsResults() {
        List<Double> embedding = List.of(0.1, 0.2, 0.3);
        when(embeddingService.getEmbedding("headphones")).thenReturn(embedding);

        Object[] row = createProductRow(1L, "prod-1", "Headphones", "Description",
                "Electronics", "Brand", new BigDecimal("99.99"), new BigDecimal("89.99"),
                new BigDecimal("4.5"), 100, 1, 50, "http://img.com", "http://amazon.com", "[0.1,0.2,0.3]", 0.95);
        List<Object[]> rows = new ArrayList<>();
        rows.add(row);
        when(productRepository.findSimilarProducts(anyString(), eq(10)))
                .thenReturn(rows);

        SearchResponse response = searchService.search("headphones", 10);

        assertNotNull(response);
        assertEquals("headphones", response.getQuery());
        assertEquals(1, response.getTotal());
        assertEquals(0.95, response.getMaxScore());
        assertEquals(1, response.getResults().size());
        assertEquals("prod-1", response.getResults().get(0).getProductId());
        assertEquals("Headphones", response.getResults().get(0).getTitle());
        assertEquals(0.95, response.getResults().get(0).getSimilarityScore());
    }

    @Test
    void search_withNullLimit_usesDefaultLimit() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        when(productRepository.findSimilarProducts(anyString(), eq(10)))
                .thenReturn(Collections.emptyList());

        SearchResponse response = searchService.search("query", null);

        assertNotNull(response);
        assertEquals("query", response.getQuery());
        assertEquals(0, response.getTotal());
        assertEquals(0, response.getResults().size());
    }

    @Test
    void search_withLimitExceedingMax_capsAtMaxLimit() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        when(productRepository.findSimilarProducts(anyString(), eq(100)))
                .thenReturn(Collections.emptyList());

        SearchResponse response = searchService.search("query", 500);

        assertNotNull(response);
    }

    @Test
    void search_withNullFieldsInRow_extractsProductCorrectly() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        // Row with nulls: id, price, unitPrice, rating, reviewCount, ranking, votes, embedding
        Object[] row = new Object[]{null, "prod-2", "Title", "Desc", "Cat", "Brand",
                null, null, null, null, null, null, "http://img.com", "http://amazon.com", null, 0.85};
        List<Object[]> rows = Collections.singletonList(row);
        when(productRepository.findSimilarProducts(anyString(), eq(10))).thenReturn(rows);

        SearchResponse response = searchService.search("query", 10);

        assertNotNull(response);
        assertEquals(1, response.getTotal());
        assertEquals(0.85, response.getMaxScore());
        assertEquals("prod-2", response.getResults().get(0).getProductId());
        assertEquals("Title", response.getResults().get(0).getTitle());
        assertNull(response.getResults().get(0).getPrice());
        assertNull(response.getResults().get(0).getRating());
    }

    @Test
    void search_withStringEmbedding_extractsCorrectly() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        Object[] row = createProductRow(1L, "prod-3", "Product", "Desc", "Cat", "Brand",
                new BigDecimal("10.00"), new BigDecimal("10.00"), new BigDecimal("4.0"),
                10, 1, 10, "http://img.com", "http://amazon.com", "[0.1,0.2]", 0.75);
        List<Object[]> rows = Collections.singletonList(row);
        when(productRepository.findSimilarProducts(anyString(), eq(10))).thenReturn(rows);

        SearchResponse response = searchService.search("query", 10);

        assertNotNull(response);
        assertEquals(1, response.getTotal());
        assertEquals(0.75, response.getMaxScore());
    }

    @Test
    void search_withNonNumberSimilarity_returnsZero() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        Object[] row = new Object[]{1L, "prod-4", "Product", "Desc", "Cat", "Brand",
                new BigDecimal("10.00"), new BigDecimal("10.00"), new BigDecimal("4.0"),
                10, 1, 10, "http://img.com", "http://amazon.com", "[0.1]", "invalid"};
        List<Object[]> rows = Collections.singletonList(row);
        when(productRepository.findSimilarProducts(anyString(), eq(10))).thenReturn(rows);

        SearchResponse response = searchService.search("query", 10);

        assertNotNull(response);
        assertEquals(1, response.getTotal());
        assertEquals(0.0, response.getResults().get(0).getSimilarityScore());
        assertEquals(0.0, response.getMaxScore());
    }

    @Test
    void search_withNullSimilarity_returnsZero() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        Object[] row = new Object[]{1L, "prod-5", "Product", "Desc", "Cat", "Brand",
                new BigDecimal("10.00"), new BigDecimal("10.00"), new BigDecimal("4.0"),
                10, 1, 10, "http://img.com", "http://amazon.com", "[0.1]", null};
        List<Object[]> rows = Collections.singletonList(row);
        when(productRepository.findSimilarProducts(anyString(), eq(10))).thenReturn(rows);

        SearchResponse response = searchService.search("query", 10);

        assertNotNull(response);
        assertEquals(0.0, response.getResults().get(0).getSimilarityScore());
    }

    @Test
    void search_withEmptyResults_returnsNullMaxScore() {
        when(embeddingService.getEmbedding("query")).thenReturn(List.of(0.1));
        when(productRepository.findSimilarProducts(anyString(), eq(10)))
                .thenReturn(Collections.emptyList());

        SearchResponse response = searchService.search("query", 10);

        assertNotNull(response);
        assertEquals(0, response.getTotal());
        assertNull(response.getMaxScore());
    }

    private Object[] createProductRow(Long id, String productId, String title, String description,
                                      String category, String brand, BigDecimal price, BigDecimal unitPrice,
                                      BigDecimal rating, Integer reviewCount, Integer ranking, Integer votes,
                                      String imageUrl, String amazonUrl, String embedding, Double similarity) {
        return new Object[]{id, productId, title, description, category, brand,
                price, unitPrice, rating, reviewCount, ranking, votes, imageUrl, amazonUrl, embedding, similarity};
    }
}
