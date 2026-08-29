package com.pipelinepilot.demo.api;

import com.pipelinepilot.demo.model.LoadSimulationResult;
import com.pipelinepilot.demo.service.LoadSimulationService;
import io.micrometer.core.annotation.Timed;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
public class LoadController {

    private final LoadSimulationService loadSimulationService;

    public LoadController(LoadSimulationService loadSimulationService) {
        this.loadSimulationService = loadSimulationService;
    }

    @Timed(value = "pipeline_pilot_simulate_load_seconds", description = "Time spent on /simulate-load")
    @GetMapping("/simulate-load")
    public LoadSimulationResult simulateLoad(
            @RequestParam(defaultValue = "250") @Min(0) @Max(30000) long cpuMillis,
            @RequestParam(defaultValue = "100") @Min(0) @Max(30000) long ioMillis,
            @RequestParam(defaultValue = "5000") @Min(100) @Max(500000) int complexity
    ) throws InterruptedException {
        return loadSimulationService.simulate(cpuMillis, ioMillis, complexity);
    }
}
