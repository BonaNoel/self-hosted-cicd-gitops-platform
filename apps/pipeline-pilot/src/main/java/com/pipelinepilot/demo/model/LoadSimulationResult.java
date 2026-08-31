package com.pipelinepilot.demo.model;

public record LoadSimulationResult(long requestedCpuMillis, long requestedIoMillis, int complexity, long durationMillis, long checksum) {
}
