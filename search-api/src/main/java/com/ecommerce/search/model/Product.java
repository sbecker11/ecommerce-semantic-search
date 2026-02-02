package com.ecommerce.search.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "products")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Product {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "product_id", unique = true, nullable = false)
    private String productId;
    
    @Column(name = "title", columnDefinition = "TEXT")
    private String title;
    
    @Column(name = "description", columnDefinition = "TEXT")
    private String description;
    
    @Column(name = "category")
    private String category;
    
    @Column(name = "brand")
    private String brand;
    
    @Column(name = "price", precision = 10, scale = 2)
    private BigDecimal price;
    
    @Column(name = "rating", precision = 3, scale = 2)
    private BigDecimal rating;
    
    @Column(name = "review_count")
    private Integer reviewCount;
    
    @Column(name = "image_url", columnDefinition = "TEXT")
    private String imageUrl;
    
    @Column(name = "embedding", columnDefinition = "vector(384)")
    private String embedding; // Stored as string, converted for queries
    
    @Column(name = "created_at")
    private LocalDateTime createdAt;
    
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
}
