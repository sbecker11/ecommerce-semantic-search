package com.ecommerce.search.repository;

import com.ecommerce.search.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {
    
    @Query(value = """
        SELECT 
            p.id, p.product_id, p.title, p.description, p.category, p.brand,
            p.price, p.unit_price, p.rating, p.review_count, p.ranking, p.votes, p.image_url, p.amazon_url, p.embedding,
            1 - (p.embedding <=> CAST(:embedding AS vector)) AS similarity
        FROM products p
        WHERE p.embedding IS NOT NULL
        ORDER BY p.embedding <=> CAST(:embedding AS vector)
        LIMIT :limit
        """, nativeQuery = true)
    List<Object[]> findSimilarProducts(@Param("embedding") String embedding, @Param("limit") int limit);
    
    Product findByProductId(String productId);
}
