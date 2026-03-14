package com.pipelinepilot.demo.model;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record OrderRequest(
        @NotNull Long userId,
        @NotBlank String item,
        @Min(1) int quantity
) {
}
