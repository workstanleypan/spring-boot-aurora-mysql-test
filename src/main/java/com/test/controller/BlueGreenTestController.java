package com.test.controller;

import com.test.service.BlueGreenTestService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * Blue/Green Switchover Test Controller
 * 
 * Provides REST API to control and monitor Blue/Green switchover tests
 */
@RestController
@RequestMapping("/api/bluegreen")
public class BlueGreenTestController {
    
    private static final Logger log = LoggerFactory.getLogger(BlueGreenTestController.class);
    
    private final BlueGreenTestService testService;
    
    public BlueGreenTestController(BlueGreenTestService testService) {
        this.testService = testService;
    }
    
    /**
     * Start Blue/Green switchover test
     * 
     * @param request Request body containing test parameters
     *                - numThreads: Number of threads (default: 20)
     *                - readsPerSecond: Reads per second per thread (default: 500)
     *                - writesPerSecond: Writes per second per thread (default: 10)
     *                - durationSeconds: Test duration in seconds (default: 3600, 0 = continuous mode)
     *                - enableWrites: Enable write operations (default: true)
     * @return Test ID and configuration info
     */
    @PostMapping("/start")
    public ResponseEntity<Map<String, Object>> startTest(@RequestBody(required = false) Map<String, Object> request) {
        log.info("POST /api/bluegreen/start");
        
        // Parse parameters with defaults
        int numThreads = 20;
        int readsPerSecond = 500;
        int writesPerSecond = 10;
        int durationSeconds = 3600;
        boolean enableWrites = true;
        
        if (request != null) {
            numThreads = (int) request.getOrDefault("numThreads", numThreads);
            readsPerSecond = (int) request.getOrDefault("readsPerSecond", readsPerSecond);
            writesPerSecond = (int) request.getOrDefault("writesPerSecond", writesPerSecond);
            durationSeconds = (int) request.getOrDefault("durationSeconds", durationSeconds);
            enableWrites = (boolean) request.getOrDefault("enableWrites", enableWrites);
        }
        
        // Validate parameters
        if (numThreads < 1 || numThreads > 100) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "numThreads must be between 1 and 100"
            ));
        }
        if (readsPerSecond < 1 || readsPerSecond > 10000) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "readsPerSecond must be between 1 and 10000"
            ));
        }
        if (durationSeconds < 0 || durationSeconds > 86400) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "durationSeconds must be between 0 (continuous) and 86400 (24 hours)"
            ));
        }
        
        try {
            String testId = testService.startTest(numThreads, readsPerSecond, writesPerSecond, durationSeconds, enableWrites);
            
            boolean isContinuous = (durationSeconds == 0);
            
            Map<String, Object> config = new HashMap<>();
            config.put("numThreads", numThreads);
            config.put("readsPerSecond", readsPerSecond);
            config.put("totalReadsPerSecond", numThreads * readsPerSecond);
            config.put("enableWrites", enableWrites);
            if (enableWrites) {
                config.put("writesPerSecond", writesPerSecond);
                config.put("totalWritesPerSecond", numThreads * writesPerSecond);
            }
            if (isContinuous) {
                config.put("mode", "continuous");
                config.put("durationSeconds", "∞ (until manually stopped)");
            } else {
                config.put("mode", "timed");
                config.put("durationSeconds", durationSeconds);
            }
            
            Map<String, Object> response = new HashMap<>();
            response.put("status", "started");
            response.put("testId", testId);
            response.put("configuration", config);
            response.put("message", isContinuous 
                ? "Blue/Green switchover test started in CONTINUOUS mode"
                : "Blue/Green switchover test started successfully");
            
            log.info("✅ Test started: {} ({})", testId, isContinuous ? "CONTINUOUS" : "TIMED");
            return ResponseEntity.ok(response);
            
        } catch (IllegalStateException e) {
            log.warn("⚠️  Test already running");
            return ResponseEntity.status(409).body(Map.of(
                "error", e.getMessage(),
                "status", "already_running"
            ));
        } catch (Exception e) {
            log.error("❌ Failed to start test", e);
            return ResponseEntity.status(500).body(Map.of(
                "error", "Failed to start test: " + e.getMessage()
            ));
        }
    }
    
    /**
     * Stop the currently running test
     */
    @PostMapping("/stop")
    public ResponseEntity<Map<String, Object>> stopTest() {
        log.info("POST /api/bluegreen/stop");
        
        try {
            testService.stopTest();
            
            Map<String, Object> response = new HashMap<>();
            response.put("status", "stopped");
            response.put("message", "Test stopped successfully");
            
            log.info("✅ Test stopped");
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("❌ Failed to stop test", e);
            return ResponseEntity.status(500).body(Map.of(
                "error", "Failed to stop test: " + e.getMessage()
            ));
        }
    }
    
    /**
     * Get current test status
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getStatus() {
        log.debug("GET /api/bluegreen/status");
        
        try {
            BlueGreenTestService.TestStatus status = testService.getStatus();
            
            Map<String, Object> response = new HashMap<>();
            response.put("running", status.isRunning());
            response.put("mode", status.isContinuous() ? "continuous" : "timed");
            
            Map<String, Object> stats = new HashMap<>();
            stats.put("totalReads", status.getTotalReads());
            stats.put("successfulReads", status.getSuccessfulReads());
            stats.put("failedReads", status.getFailedReads());
            stats.put("readSuccessRate", String.format("%.2f%%", status.getReadSuccessRate()));
            stats.put("avgReadLatency", status.getAvgReadLatency() + "ms");
            
            if (status.isWritesEnabled()) {
                stats.put("totalWrites", status.getTotalWrites());
                stats.put("successfulWrites", status.getSuccessfulWrites());
                stats.put("failedWrites", status.getFailedWrites());
                stats.put("writeSuccessRate", String.format("%.2f%%", status.getWriteSuccessRate()));
                stats.put("avgWriteLatency", status.getAvgWriteLatency() + "ms");
                stats.put("readOnlyErrors", status.getReadOnlyErrors());
            }
            
            stats.put("failoverCount", status.getFailoverCount());
            stats.put("runningTimeSeconds", status.getRunningTimeSeconds());
            stats.put("runningTime", formatDuration(status.getRunningTimeSeconds()));
            response.put("statistics", stats);
            
            response.put("connection", Map.of(
                "lastEndpoint", status.getLastEndpoint()
            ));
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("❌ Failed to get status", e);
            return ResponseEntity.status(500).body(Map.of(
                "error", "Failed to get status: " + e.getMessage()
            ));
        }
    }
    
    /**
     * Format duration in seconds to human-readable format
     */
    private String formatDuration(long seconds) {
        long hours = seconds / 3600;
        long minutes = (seconds % 3600) / 60;
        long secs = seconds % 60;
        
        if (hours > 0) {
            return String.format("%dh %dm %ds", hours, minutes, secs);
        } else if (minutes > 0) {
            return String.format("%dm %ds", minutes, secs);
        } else {
            return String.format("%ds", secs);
        }
    }
    
    /**
     * Quick start test - uses default parameters
     */
    @PostMapping("/quick-start")
    public ResponseEntity<Map<String, Object>> quickStart() {
        log.info("POST /api/bluegreen/quick-start");
        return startTest(null);
    }
    
    /**
     * Start short test - for quick verification
     */
    @PostMapping("/quick-test")
    public ResponseEntity<Map<String, Object>> quickTest() {
        log.info("POST /api/bluegreen/quick-test");
        
        Map<String, Object> params = new HashMap<>();
        params.put("numThreads", 5);
        params.put("readsPerSecond", 100);
        params.put("durationSeconds", 60);
        
        return startTest(params);
    }
    
    /**
     * Start continuous test - runs indefinitely until manually stopped
     */
    @PostMapping("/start-continuous")
    public ResponseEntity<Map<String, Object>> startContinuous(@RequestBody(required = false) Map<String, Object> request) {
        log.info("POST /api/bluegreen/start-continuous");
        
        // Parse parameters with defaults
        int numThreads = 20;
        int readsPerSecond = 500;
        
        if (request != null) {
            numThreads = (int) request.getOrDefault("numThreads", numThreads);
            readsPerSecond = (int) request.getOrDefault("readsPerSecond", readsPerSecond);
        }
        
        // Set duration to 0 for continuous mode
        Map<String, Object> params = new HashMap<>();
        params.put("numThreads", numThreads);
        params.put("readsPerSecond", readsPerSecond);
        params.put("durationSeconds", 0);
        
        return startTest(params);
    }
    
    /**
     * Start continuous write test - each thread holds one connection, continuous writes
     * 
     * @param numConnections Number of connections (default: 10)
     * @param writeIntervalMs Write interval in milliseconds (default: 100, i.e., 10 writes/sec)
     */
    @PostMapping("/start-write")
    public ResponseEntity<Map<String, Object>> startWriteTest(
            @RequestParam(defaultValue = "10") int numConnections,
            @RequestParam(defaultValue = "100") int writeIntervalMs) {
        
        log.info("POST /api/bluegreen/start-write?numConnections={}&writeIntervalMs={}", 
            numConnections, writeIntervalMs);
        
        // Validate parameters
        if (numConnections < 1 || numConnections > 100) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "numConnections must be between 1 and 100"
            ));
        }
        if (writeIntervalMs < 0 || writeIntervalMs > 10000) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", "writeIntervalMs must be between 0 and 10000"
            ));
        }
        
        try {
            String testId = testService.startWriteOnlyTest(numConnections, writeIntervalMs);
            
            Map<String, Object> response = new HashMap<>();
            response.put("status", "started");
            response.put("testId", testId);
            response.put("configuration", Map.of(
                "numConnections", numConnections,
                "writeIntervalMs", writeIntervalMs,
                "writesPerSecondPerThread", writeIntervalMs > 0 ? 1000 / writeIntervalMs : "max",
                "mode", "persistent_connection_write"
            ));
            response.put("message", "Continuous write test started - each thread holds one connection");
            
            log.info("✅ Write test started: {}", testId);
            return ResponseEntity.ok(response);
            
        } catch (IllegalStateException e) {
            return ResponseEntity.status(409).body(Map.of(
                "error", e.getMessage(),
                "status", "already_running"
            ));
        } catch (Exception e) {
            log.error("❌ Failed to start write test", e);
            return ResponseEntity.status(500).body(Map.of(
                "error", "Failed to start test: " + e.getMessage()
            ));
        }
    }
    
    /**
     * Get test help information
     */
    @GetMapping("/help")
    public ResponseEntity<Map<String, Object>> getHelp() {
        Map<String, Object> help = new HashMap<>();
        
        help.put("description", "Blue/Green Switchover Test API - Tests AWS JDBC Wrapper behavior during Blue/Green switchover");
        
        help.put("endpoints", Map.of(
            "POST /api/bluegreen/start", "Start test (customizable parameters)",
            "POST /api/bluegreen/start-continuous", "Start continuous test (runs indefinitely)",
            "POST /api/bluegreen/stop", "Stop test",
            "GET /api/bluegreen/status", "Get test status",
            "POST /api/bluegreen/quick-start", "Quick start (default parameters)",
            "POST /api/bluegreen/quick-test", "Quick test (5 threads, 60 seconds)",
            "GET /api/bluegreen/help", "Get help information"
        ));
        
        help.put("parameters", Map.of(
            "numThreads", "Number of threads (1-100, default: 20)",
            "readsPerSecond", "Reads per second per thread (1-10000, default: 500)",
            "durationSeconds", "Test duration in seconds (0=continuous mode, 10-86400, default: 3600)"
        ));
        
        help.put("examples", Map.of(
            "start_default", "curl -X POST http://localhost:8080/api/bluegreen/start",
            "start_custom", "curl -X POST http://localhost:8080/api/bluegreen/start -H 'Content-Type: application/json' -d '{\"numThreads\":10,\"readsPerSecond\":200,\"durationSeconds\":1800}'",
            "start_continuous", "curl -X POST http://localhost:8080/api/bluegreen/start-continuous",
            "start_continuous_custom", "curl -X POST http://localhost:8080/api/bluegreen/start-continuous -H 'Content-Type: application/json' -d '{\"numThreads\":10,\"readsPerSecond\":200}'",
            "quick_test", "curl -X POST http://localhost:8080/api/bluegreen/quick-test",
            "status", "curl http://localhost:8080/api/bluegreen/status",
            "stop", "curl -X POST http://localhost:8080/api/bluegreen/stop"
        ));
        
        help.put("testScenario", Map.of(
            "description", "Multi-threaded continuous metadata reads, simulating high-frequency database access",
            "monitoring", "Monitors failover events and connection state changes",
            "logging", "Detailed logs in logs/jdbc-wrapper.log and logs/spring-boot.log"
        ));
        
        return ResponseEntity.ok(help);
    }
}
