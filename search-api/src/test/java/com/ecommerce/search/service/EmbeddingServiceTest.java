package com.ecommerce.search.service;

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;

import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static com.github.tomakehurst.wiremock.client.WireMock.*;
import static org.junit.jupiter.api.Assertions.*;

class EmbeddingServiceTest {

    @RegisterExtension
    static WireMockExtension wireMock = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();

    private EmbeddingService embeddingService;

    @BeforeEach
    void setUp() {
        String baseUrl = "http://localhost:" + wireMock.getPort() + "/embed";
        embeddingService = new EmbeddingService(baseUrl);
        ReflectionTestUtils.setField(embeddingService, "timeout", 5000L);
    }

    @Test
    void getEmbedding_returnsEmbeddingVector() {
        wireMock.stubFor(post(urlPathEqualTo("/embed"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"embedding\": [0.1, 0.2, 0.3]}")));

        List<Double> result = embeddingService.getEmbedding("test query");

        assertNotNull(result);
        assertEquals(List.of(0.1, 0.2, 0.3), result);
    }

    @Test
    void getEmbedding_whenServerReturnsError_throwsRuntimeException() {
        wireMock.stubFor(post(urlPathEqualTo("/embed"))
                .willReturn(aResponse().withStatus(500).withBody("Internal Server Error")));

        RuntimeException ex = assertThrows(RuntimeException.class,
                () -> embeddingService.getEmbedding("test"));

        assertTrue(ex.getMessage().contains("Failed to get embedding"));
    }

    @Test
    void getEmbedding_whenServerReturnsInvalidJson_throwsRuntimeException() {
        wireMock.stubFor(post(urlPathEqualTo("/embed"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("not valid json")));

        RuntimeException ex = assertThrows(RuntimeException.class,
                () -> embeddingService.getEmbedding("test"));

        assertTrue(ex.getMessage().contains("Failed to get embedding"));
    }

}
