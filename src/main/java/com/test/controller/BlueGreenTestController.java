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
 * 提供 REST API 来控制和监控蓝绿切换测试
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
     * 启动蓝绿切换测试
     * 
     * @param request 包含测试参数的请求体
     *                - numThreads: 线程数 (默认: 20)
     *                - readsPerSecond: 每线程每秒读取次数 (默认: 500)
     *                - durationSeconds: 测试持续时间(秒) (默认: 3600, 0 = 持续模式)
     * @return 测试ID和配置信息
     */
    @PostMapping("/start")
    public ResponseEntity<Map<String, Object>> startTest(@RequestBody(required = false) Map<String, Integer> request) {
        log.info("POST /api/bluegreen/start");
        
        // Parse parameters with defaults
        int numThreads = 20;
        int readsPerSecond = 500;
        int durationSeconds = 3600;
        
        if (request != null) {
            numThreads = request.getOrDefault("numThreads", numThreads);
            readsPerSecond = request.getOrDefault("readsPerSecond", readsPerSecond);
            durationSeconds = request.getOrDefault("durationSeconds", durationSeconds);
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
            String testId = testService.startTest(numThreads, readsPerSecond, durationSeconds);
            
            boolean isContinuous = (durationSeconds == 0);
            
            Map<String, Object> config = new HashMap<>();
            config.put("numThreads", numThreads);
            config.put("readsPerSecond", readsPerSecond);
            config.put("totalReadsPerSecond", numThreads * readsPerSecond);
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
     * 停止当前运行的测试
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
     * 获取当前测试状态
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
     * 快速启动测试 - 使用默认参数
     */
    @PostMapping("/quick-start")
    public ResponseEntity<Map<String, Object>> quickStart() {
        log.info("POST /api/bluegreen/quick-start");
        return startTest(null);
    }
    
    /**
     * 启动短时测试 - 用于快速验证
     */
    @PostMapping("/quick-test")
    public ResponseEntity<Map<String, Object>> quickTest() {
        log.info("POST /api/bluegreen/quick-test");
        
        Map<String, Integer> params = new HashMap<>();
        params.put("numThreads", 5);
        params.put("readsPerSecond", 100);
        params.put("durationSeconds", 60);
        
        return startTest(params);
    }
    
    /**
     * 启动持续测试 - 无限期运行直到手动停止
     */
    @PostMapping("/start-continuous")
    public ResponseEntity<Map<String, Object>> startContinuous(@RequestBody(required = false) Map<String, Integer> request) {
        log.info("POST /api/bluegreen/start-continuous");
        
        // Parse parameters with defaults
        int numThreads = 20;
        int readsPerSecond = 500;
        
        if (request != null) {
            numThreads = request.getOrDefault("numThreads", numThreads);
            readsPerSecond = request.getOrDefault("readsPerSecond", readsPerSecond);
        }
        
        // Set duration to 0 for continuous mode
        Map<String, Integer> params = new HashMap<>();
        params.put("numThreads", numThreads);
        params.put("readsPerSecond", readsPerSecond);
        params.put("durationSeconds", 0);
        
        return startTest(params);
    }
    
    /**
     * 获取测试帮助信息
     */
    @GetMapping("/help")
    public ResponseEntity<Map<String, Object>> getHelp() {
        Map<String, Object> help = new HashMap<>();
        
        help.put("description", "Blue/Green Switchover Test API - 用于测试 AWS JDBC Wrapper 在蓝绿切换时的表现");
        
        help.put("endpoints", Map.of(
            "POST /api/bluegreen/start", "启动测试 (可自定义参数)",
            "POST /api/bluegreen/start-continuous", "启动持续测试 (无限期运行)",
            "POST /api/bluegreen/stop", "停止测试",
            "GET /api/bluegreen/status", "获取测试状态",
            "POST /api/bluegreen/quick-start", "快速启动 (默认参数)",
            "POST /api/bluegreen/quick-test", "快速测试 (5线程, 60秒)",
            "GET /api/bluegreen/help", "获取帮助信息"
        ));
        
        help.put("parameters", Map.of(
            "numThreads", "线程数 (1-100, 默认: 20)",
            "readsPerSecond", "每线程每秒读取次数 (1-10000, 默认: 500)",
            "durationSeconds", "测试持续时间(秒) (0=持续模式, 10-86400, 默认: 3600)"
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
            "description", "多线程持续元数据读取，模拟高频数据库访问",
            "monitoring", "监控 failover 事件和连接状态变化",
            "logging", "详细日志记录在 logs/jdbc-wrapper.log 和 logs/spring-boot.log"
        ));
        
        return ResponseEntity.ok(help);
    }
}
