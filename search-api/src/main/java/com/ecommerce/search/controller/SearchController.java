package com.ecommerce.search.controller;

import com.ecommerce.search.dto.SearchRequest;
import com.ecommerce.search.dto.SearchResponse;
import com.ecommerce.search.service.SearchService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/search")
@CrossOrigin(origins = "*")
public class SearchController {
    private final SearchService searchService;
    
    public SearchController(SearchService searchService) {
        this.searchService = searchService;
    }
    
    @PostMapping
    public ResponseEntity<SearchResponse> search(@Valid @RequestBody SearchRequest request) {
        SearchResponse response = searchService.search(request.getQuery(), request.getLimit());
        return ResponseEntity.ok(response);
    }
    
    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("OK");
    }
}
