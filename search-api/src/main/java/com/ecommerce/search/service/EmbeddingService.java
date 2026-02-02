package com.ecommerce.search.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.List;

@Service
public class EmbeddingService {
    private final WebClient webClient;
    private final ObjectMapper objectMapper;
    
    @Value("${embedding.service.timeout:30000}")
    private long timeout;
    
    public EmbeddingService(@Value("${embedding.service.url}") String embeddingServiceUrl) {
        this.webClient = WebClient.builder()
            .baseUrl(embeddingServiceUrl)
            .build();
        this.objectMapper = new ObjectMapper();
    }
    
    public List<Double> getEmbedding(String text) {
        try {
            String response = webClient.post()
                .uri("")
                .bodyValue(new EmbeddingRequest(text))
                .retrieve()
                .bodyToMono(String.class)
                .timeout(Duration.ofMillis(timeout))
                .block();
            
            JsonNode jsonNode = objectMapper.readTree(response);
            JsonNode embeddingNode = jsonNode.get("embedding");
            
            return objectMapper.convertValue(embeddingNode, 
                objectMapper.getTypeFactory().constructCollectionType(List.class, Double.class));
        } catch (Exception e) {
            throw new RuntimeException("Failed to get embedding: " + e.getMessage(), e);
        }
    }
    
    private record EmbeddingRequest(String text) {}
}
