package com.ecommerce.search.dto;

import com.ecommerce.search.model.Product;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class SearchResponse {
    private List<ProductResult> results;
    private Integer total;
    private String query;
    private Double maxScore;
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ProductResult {
        private String productId;
        private String title;
        private String description;
        private String category;
        private String brand;
        private Double price;
        private Double unitPrice;
        private Double rating;
        private Integer reviewCount;
        private Integer ranking;
        private Integer votes;
        private String imageUrl;
        private String amazonUrl;
        private Double similarityScore;
        
        public static ProductResult fromProduct(Product product, Double similarityScore) {
            return new ProductResult(
                product.getProductId(),
                product.getTitle(),
                product.getDescription(),
                product.getCategory(),
                product.getBrand(),
                product.getPrice() != null ? product.getPrice().doubleValue() : null,
                product.getUnitPrice() != null ? product.getUnitPrice().doubleValue() : null,
                product.getRating() != null ? product.getRating().doubleValue() : null,
                product.getReviewCount(),
                product.getRanking(),
                product.getVotes(),
                product.getImageUrl(),
                product.getAmazonUrl(),
                similarityScore
            );
        }
    }
}
