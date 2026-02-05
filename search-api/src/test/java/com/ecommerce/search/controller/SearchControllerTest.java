package com.ecommerce.search.controller;

import com.ecommerce.search.dto.SearchRequest;
import com.ecommerce.search.dto.SearchResponse;
import com.ecommerce.search.exception.GlobalExceptionHandler;
import com.ecommerce.search.service.SearchService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Collections;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(SearchController.class)
@Import(GlobalExceptionHandler.class)
class SearchControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private SearchService searchService;

    @Test
    void health_returnsOk() throws Exception {
        mockMvc.perform(get("/api/search/health"))
                .andExpect(status().isOk())
                .andExpect(content().string("OK"));
    }

    @Test
    void search_returnsResults() throws Exception {
        SearchRequest request = new SearchRequest();
        request.setQuery("wireless headphones");
        request.setLimit(10);

        SearchResponse response = new SearchResponse(
                Collections.emptyList(),
                0,
                "wireless headphones",
                0.0
        );

        when(searchService.search(eq("wireless headphones"), eq(10)))
                .thenReturn(response);

        mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.query").value("wireless headphones"))
                .andExpect(jsonPath("$.total").value(0))
                .andExpect(jsonPath("$.results").isArray());
    }

    @Test
    void search_withEmptyQuery_returnsBadRequest() throws Exception {
        SearchRequest request = new SearchRequest();
        request.setQuery("");
        request.setLimit(10);

        mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void search_withInvalidLimit_returnsBadRequest() throws Exception {
        SearchRequest request = new SearchRequest();
        request.setQuery("headphones");
        request.setLimit(0);

        mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void search_whenSearchServiceThrowsRuntimeException_returnsInternalServerError() throws Exception {
        SearchRequest request = new SearchRequest();
        request.setQuery("headphones");
        request.setLimit(10);

        doThrow(new RuntimeException("Embedding service unavailable"))
                .when(searchService).search(eq("headphones"), eq(10));

        mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").value("Embedding service unavailable"));
    }

    @Test
    void search_whenInvalidJson_returnsInternalServerError() throws Exception {
        mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{invalid json"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").exists());
    }
}
