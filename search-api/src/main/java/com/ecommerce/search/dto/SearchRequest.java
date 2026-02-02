package com.ecommerce.search.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Min;
import lombok.Data;

@Data
public class SearchRequest {
    @NotBlank(message = "Query string is required")
    private String query;
    
    @Min(value = 1, message = "Limit must be at least 1")
    private Integer limit = 10;
}
