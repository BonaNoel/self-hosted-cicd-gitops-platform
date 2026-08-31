package com.pipelinepilot.demo.api;

import io.micrometer.core.annotation.Timed;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

@RestController
public class HealthController {

    @Timed(value = "pipeline_pilot_health_seconds", description = "Time spent on /health")
    @GetMapping("/health")
    public Map<String, Object> health() {
        return Map.of(
                "status", "UP",
                "service", "pipeline-pilot",
                "timestamp", Instant.now().toString()
        );
    }
}
