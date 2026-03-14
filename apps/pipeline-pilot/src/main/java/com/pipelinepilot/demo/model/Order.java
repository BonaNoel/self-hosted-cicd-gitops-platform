package com.pipelinepilot.demo.model;

import java.time.Instant;

public record Order(Long id, Long userId, String item, int quantity, Instant createdAt) {
}
