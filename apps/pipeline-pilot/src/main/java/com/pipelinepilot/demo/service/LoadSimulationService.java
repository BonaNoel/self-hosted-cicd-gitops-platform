package com.pipelinepilot.demo.service;

import com.pipelinepilot.demo.model.LoadSimulationResult;
import org.springframework.stereotype.Service;

@Service
public class LoadSimulationService {

    public LoadSimulationResult simulate(long cpuMillis, long ioMillis, int complexity) throws InterruptedException {
        long start = System.currentTimeMillis();
        long checksum = burnCpu(cpuMillis, complexity);

        if (ioMillis > 0) {
            Thread.sleep(ioMillis);
        }

        long duration = System.currentTimeMillis() - start;
        return new LoadSimulationResult(cpuMillis, ioMillis, complexity, duration, checksum);
    }

    private long burnCpu(long cpuMillis, int complexity) {
        long end = System.currentTimeMillis() + cpuMillis;
        long result = 1;
        long i = 1;

        while (System.currentTimeMillis() < end) {
            // Keep arithmetic unpredictable enough so JIT cannot optimize it away completely.
            result = (result * 31 + (i * i) + complexity) % 1_000_000_007L;
            i++;
            if (i > complexity) {
                i = 1;
            }
        }

        return result;
    }
}
