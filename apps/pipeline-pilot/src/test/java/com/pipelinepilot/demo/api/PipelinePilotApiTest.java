package com.pipelinepilot.demo.api;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class PipelinePilotApiTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void healthEndpointReturnsUp() throws Exception {
        mockMvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void usersEndpointReturnsSeedData() throws Exception {
        mockMvc.perform(get("/users"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Ada Lovelace"));
    }

    @Test
    void createOrderReturnsCreated() throws Exception {
        String body = """
                {
                  \"userId\": 1,
                  \"item\": \"coffee\",
                  \"quantity\": 2
                }
                """;

        mockMvc.perform(post("/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.userId").value(1))
                .andExpect(jsonPath("$.item").value("coffee"));
    }

    @Test
    void simulateLoadEndpointRuns() throws Exception {
        mockMvc.perform(get("/simulate-load")
                        .queryParam("cpuMillis", "5")
                        .queryParam("ioMillis", "0")
                        .queryParam("complexity", "200"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.requestedCpuMillis").value(5));
    }
}
