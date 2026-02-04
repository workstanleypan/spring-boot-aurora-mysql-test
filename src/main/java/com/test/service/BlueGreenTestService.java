package com.test.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Blue/Green Switchover Test Service
 * 
 * Simulates multi-threaded metadata read behavior for testing AWS JDBC Wrapper 
 * during Blue/Green switchover.
 * Reference: MultiThreadBlueGreenTestWithUnifiedLogging.java
 * 
 * Test Scenario:
 * - Multi-threaded continuous metadata reads (high frequency)
 * - Tests connection stability during Blue/Green switchover
 * - Monitors failover events and connection state changes
 */
@Service
public class BlueGreenTestService {
    
    private static final Logger log = LoggerFactory.getLogger(BlueGreenTestService.class);
    private static final Logger bgLog = LoggerFactory.getLogger("BlueGreenTestLogger");
    private static final Logger ipLog = LoggerFactory.getLogger("IPMetadataLogger");
    
    private static final DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");
    
    @Autowired
    private DataSource dataSource;
    
    // Test statistics
    private final AtomicLong totalMetadataReads = new AtomicLong(0);
    private final AtomicLong successfulMetadataReads = new AtomicLong(0);
    private final AtomicLong failedMetadataReads = new AtomicLong(0);
    private final AtomicLong totalWrites = new AtomicLong(0);
    private final AtomicLong successfulWrites = new AtomicLong(0);
    private final AtomicLong failedWrites = new AtomicLong(0);
    private final AtomicLong readOnlyErrors = new AtomicLong(0);
    private final AtomicLong totalReadLatency = new AtomicLong(0);
    private final AtomicLong totalWriteLatency = new AtomicLong(0);
    private final AtomicInteger failoverCount = new AtomicInteger(0);
    private final AtomicBoolean testRunning = new AtomicBoolean(false);
    
    private ExecutorService executor;
    private volatile String lastEndpoint = "unknown";
    private volatile long testStartTime = 0;

    // Continuous mode flag
    private final AtomicBoolean continuousMode = new AtomicBoolean(false);
    private volatile int configuredThreads = 20;
    private volatile int configuredReadsPerSecond = 500;
    private volatile int configuredWritesPerSecond = 10;  // Writes per second per thread
    private volatile int configuredDurationSeconds = 3600;
    private volatile boolean enableWrites = true;  // Enable write operations

    /**
     * Start Blue/Green switchover test with metadata reads and writes
     * 
     * @param numThreads Number of concurrent threads
     * @param readsPerSecond Metadata reads per second per thread
     * @param durationSeconds Test duration in seconds (0 = continuous mode)
     * @return Test ID
     */
    public String startTest(int numThreads, int readsPerSecond, int durationSeconds) {
        return startTest(numThreads, readsPerSecond, 10, durationSeconds, true);
    }
    
    /**
     * Start Blue/Green switchover test with custom configuration
     * 
     * @param numThreads Number of concurrent threads
     * @param readsPerSecond Metadata reads per second per thread
     * @param writesPerSecond Writes per second per thread
     * @param durationSeconds Test duration in seconds (0 = continuous mode)
     * @param enableWrites Enable write operations
     * @return Test ID
     */
    public String startTest(int numThreads, int readsPerSecond, int writesPerSecond, 
                           int durationSeconds, boolean enableWrites) {
        if (testRunning.get()) {
            throw new IllegalStateException("Test is already running");
        }
        
        // Save configuration for continuous mode
        this.configuredThreads = numThreads;
        this.configuredReadsPerSecond = readsPerSecond;
        this.configuredWritesPerSecond = writesPerSecond;
        this.configuredDurationSeconds = durationSeconds;
        this.enableWrites = enableWrites;
        
        // Check if continuous mode (duration = 0)
        boolean isContinuous = (durationSeconds == 0);
        continuousMode.set(isContinuous);
        
        // Reset statistics
        resetStatistics();
        testRunning.set(true);
        testStartTime = System.currentTimeMillis();
        
        String testId = "BG-" + testStartTime;
        
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║   Blue/Green Switchover Test - Metadata Reads                 ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("📋 Test Configuration:");
        log.info("   Test ID: {}", testId);
        log.info("   Total Threads: {}", numThreads);
        log.info("   Reads Per Second (per thread): {}", readsPerSecond);
        log.info("   Total Reads Per Second: {}", numThreads * readsPerSecond);
        if (enableWrites) {
            log.info("   Writes Per Second (per thread): {}", writesPerSecond);
            log.info("   Total Writes Per Second: {}", numThreads * writesPerSecond);
        } else {
            log.info("   Writes: DISABLED");
        }
        if (isContinuous) {
            log.info("   Test Duration: ♾️  CONTINUOUS MODE (until manually stopped)");
        } else {
            log.info("   Test Duration: {} seconds", durationSeconds);
        }
        log.info("");
        log.info("🔍 Test Scenario:");
        log.info("   - All {} threads: Continuous metadata reads ({}/sec each)", numThreads, readsPerSecond);
        if (enableWrites) {
            log.info("   - All {} threads: Database writes ({}/sec each)", numThreads, writesPerSecond);
        }
        log.info("   - Monitoring for Blue/Green switchover events");
        log.info("   - Tracking connection state and failover behavior");
        if (isContinuous) {
            log.info("   - ♾️  Running in CONTINUOUS mode - will not stop automatically");
        }
        log.info("");
        
        executor = Executors.newFixedThreadPool(numThreads + 1);
        CountDownLatch startLatch = new CountDownLatch(1);
        
        // Start all metadata read threads
        for (int i = 1; i <= numThreads; i++) {
            final int threadId = i;
            executor.submit(() -> {
                try {
                    startLatch.await();
                    runMetadataReadThread(threadId, readsPerSecond, durationSeconds);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.warn("⚠️  Metadata-Thread-{} interrupted during startup", threadId);
                }
            });
        }
        
        // Start write threads if enabled
        if (enableWrites) {
            for (int i = 1; i <= numThreads; i++) {
                final int threadId = i;
                executor.submit(() -> {
                    try {
                        startLatch.await();
                        runWriteThread(threadId, writesPerSecond, durationSeconds);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        log.warn("⚠️  Write-Thread-{} interrupted during startup", threadId);
                    }
                });
            }
        }
        
        // Start monitoring thread
        executor.submit(() -> {
            try {
                startLatch.await();
                runMonitoringThread(durationSeconds);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
        
        // Start all threads
        log.info("🚀 [{}] Starting {} metadata read threads...", now(), numThreads);
        log.info("");
        startLatch.countDown();
        
        return testId;
    }
    
    /**
     * Stop the running test
     */
    public void stopTest() {
        testRunning.set(false);
        if (executor != null) {
            executor.shutdownNow();
            try {
                executor.awaitTermination(10, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        log.info("🛑 Test stopped");
        printFinalReport();
    }
    
    /**
 * Start simplified continuous write test
 * Each thread holds one connection and writes continuously without releasing
 * 
 * @param numConnections Number of connections (one thread per connection)
 * @param writeIntervalMs Write interval in milliseconds, 0 means as fast as possible
 * @return Test ID
 */
public String startWriteOnlyTest(int numConnections, int writeIntervalMs) {
        if (testRunning.get()) {
            throw new IllegalStateException("Test is already running");
        }
        
        resetStatistics();
        testRunning.set(true);
        testStartTime = System.currentTimeMillis();
        continuousMode.set(true);
        enableWrites = true;
        configuredThreads = numConnections;
        
        String testId = "WRITE-" + testStartTime;
        
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║   Continuous Write Test - Persistent Connection Per Thread    ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("📋 Configuration:");
        log.info("   Test ID: {}", testId);
        log.info("   Connections: {}", numConnections);
        log.info("   Write Interval: {}ms", writeIntervalMs);
        log.info("   Mode: Each thread holds one connection, continuous writes");
        log.info("");
        
        executor = Executors.newFixedThreadPool(numConnections + 1);
        CountDownLatch startLatch = new CountDownLatch(1);
        
        // Start write threads
        for (int i = 1; i <= numConnections; i++) {
            final int threadId = i;
            executor.submit(() -> {
                try {
                    startLatch.await();
                    runPersistentWriteThread(threadId, writeIntervalMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }
        
        // Start monitoring thread
        executor.submit(() -> {
            try {
                startLatch.await();
                runSimpleMonitoringThread();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
        
        log.info("🚀 [{}] Starting {} write threads...", now(), numConnections);
        startLatch.countDown();
        
        return testId;
    }
    
    /**
     * Persistent connection write thread - holds connection without releasing, continuous writes
     */
    private void runPersistentWriteThread(int threadId, int writeIntervalMs) {
        log.info("✍️  [{}] Write-Thread-{}: Starting continuous writes...", now(), threadId);
        
        Connection conn = null;
        String tableName = "bg_write_test";
        
        try {
            // Get and hold connection
            conn = dataSource.getConnection();
            String endpoint = getEndpointInfo(conn);
            lastEndpoint = endpoint;
            
            log.info("✅ [{}] Write-Thread-{} got connection: {}", now(), threadId, endpoint);
            
            // Create test table if not exists
            ensureTestTable(conn, tableName);
            
            long writeCount = 0;
            long lastReportTime = System.currentTimeMillis();
            long lastReportCount = 0;
            
            // Continuous writes until test stops
            while (testRunning.get()) {
                long writeStart = System.nanoTime();
                
                try {
                    // Execute write
                    String sql = "INSERT INTO " + tableName + 
                        " (thread_id, endpoint, write_time, data) VALUES (?, ?, NOW(), ?)";
                    try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
                        pstmt.setInt(1, threadId);
                        pstmt.setString(2, endpoint);
                        pstmt.setString(3, "Thread-" + threadId + " Write #" + writeCount);
                        pstmt.executeUpdate();
                    }
                    
                    successfulWrites.incrementAndGet();
                    
                } catch (SQLException e) {
                    failedWrites.incrementAndGet();
                    
                    String msg = e.getMessage().toLowerCase();
                    if (msg.contains("read-only") || msg.contains("read only")) {
                        readOnlyErrors.incrementAndGet();
                        log.warn("⚠️  [{}] Write-Thread-{}: READ-ONLY error - {}", 
                            now(), threadId, e.getMessage());
                    } else if (msg.contains("failover") || msg.contains("connection")) {
                        failoverCount.incrementAndGet();
                        log.error("🔄 [{}] Write-Thread-{}: FAILOVER detected - {}", 
                            now(), threadId, e.getMessage());
                    } else {
                        log.error("❌ [{}] Write-Thread-{}: Write failed - {}", 
                            now(), threadId, e.getMessage());
                    }
                }
                
                totalWrites.incrementAndGet();
                writeCount++;
                
                long writeLatency = (System.nanoTime() - writeStart) / 1_000_000;
                totalWriteLatency.addAndGet(writeLatency);
                
                // Report every 10 seconds
                long currentTime = System.currentTimeMillis();
                if (currentTime - lastReportTime >= 10000) {
                    long writesInPeriod = writeCount - lastReportCount;
                    double actualRate = writesInPeriod / ((currentTime - lastReportTime) / 1000.0);
                    log.info("📊 [{}] Write-Thread-{}: {} 次写入, 速率: {}/sec, 延迟: {}ms",
                        now(), threadId, writeCount, String.format("%.1f", actualRate), writeLatency);
                    lastReportTime = currentTime;
                    lastReportCount = writeCount;
                }
                
                // Write interval
                if (writeIntervalMs > 0) {
                    try {
                        Thread.sleep(writeIntervalMs);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
            
            log.info("✅ [{}] Write-Thread-{}: Completed {} writes", now(), threadId, writeCount);
            
        } catch (SQLException e) {
            log.error("❌ [{}] Write-Thread-{} connection error: {}", now(), threadId, e.getMessage());
        } finally {
            // Close connection only when test ends
            if (conn != null) {
                try {
                    conn.close();
                    log.info("🔌 [{}] Write-Thread-{} connection closed", now(), threadId);
                } catch (SQLException e) {
                    // Ignore
                }
            }
        }
    }
    
    /**
     * Ensure test table exists
     */
    private void ensureTestTable(Connection conn, String tableName) {
        String sql = "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
            "id BIGINT AUTO_INCREMENT PRIMARY KEY, " +
            "thread_id INT NOT NULL, " +
            "endpoint VARCHAR(255), " +
            "write_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP, " +
            "data TEXT, " +
            "INDEX idx_thread (thread_id), " +
            "INDEX idx_time (write_time)" +
            ") ENGINE=InnoDB";
        
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(sql);
            log.info("✅ Test table {} ready", tableName);
        } catch (SQLException e) {
            log.warn("⚠️  Failed to create table (may already exist): {}", e.getMessage());
        }
    }
    
    /**
     * Simple monitoring thread
     */
    private void runSimpleMonitoringThread() {
        log.info("📊 [{}] Monitoring thread started", now());
        
        while (testRunning.get()) {
            try {
                Thread.sleep(30000); // Report every 30 seconds
                
                long total = totalWrites.get();
                long success = successfulWrites.get();
                long failed = failedWrites.get();
                long readOnly = readOnlyErrors.get();
                long failovers = failoverCount.get();
                double successRate = total > 0 ? (success * 100.0 / total) : 0;
                
                log.info("╔════════════════════════════════════════════════════════════════╗");
                log.info("║  [{}] Write Test Status Report                          ║", now());
                log.info("╠════════════════════════════════════════════════════════════════╣");
                log.info("║  Total Writes: {:,}  Success: {:,}  Failed: {:,}", total, success, failed);
                log.info("║  Success Rate: {:.2f}%", successRate);
                log.info("║  Read-Only Errors: {}  Failover Count: {}", readOnly, failovers);
                log.info("║  Last Connection: {}", lastEndpoint);
                log.info("╚════════════════════════════════════════════════════════════════╝");
                
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
    }
    
    /**
     * Get current test status
     */
    public TestStatus getStatus() {
        long totalReads = totalMetadataReads.get();
        long avgLatency = totalReads > 0 ? totalReadLatency.get() / totalReads : 0;
        long totalWs = totalWrites.get();
        long avgWriteLatency = totalWs > 0 ? totalWriteLatency.get() / totalWs : 0;
        long runningTime = testRunning.get() && testStartTime > 0 
            ? (System.currentTimeMillis() - testStartTime) / 1000 
            : 0;
        
        return new TestStatus(
            testRunning.get(),
            continuousMode.get(),
            enableWrites,
            totalReads,
            successfulMetadataReads.get(),
            failedMetadataReads.get(),
            totalWs,
            successfulWrites.get(),
            failedWrites.get(),
            readOnlyErrors.get(),
            failoverCount.get(),
            lastEndpoint,
            avgLatency,
            avgWriteLatency,
            runningTime
        );
    }

    /**
     * Metadata read thread - continuously reads database metadata
     */
    private void runMetadataReadThread(int threadId, int readsPerSecond, int durationSeconds) {
        int readIntervalMs = 1000 / readsPerSecond;
        boolean isContinuous = continuousMode.get();
        
        if (isContinuous) {
            log.info("📖 [{}] Metadata-Thread-{}: Starting CONTINUOUS metadata reads ({}/sec)...",
                now(), threadId, readsPerSecond);
        } else {
            log.info("📖 [{}] Metadata-Thread-{}: Starting high-frequency metadata reads ({}/sec)...",
                now(), threadId, readsPerSecond);
        }
        
        Connection conn = null;
        
        try {
            // Get connection from pool
            conn = dataSource.getConnection();
            String endpoint = getEndpointInfo(conn);
            lastEndpoint = endpoint;
            
            log.info("✅ [{}] Metadata-Thread-{} got connection from {}",
                now(), threadId, endpoint);
            
            // Get current IP for table name matching
            String currentIP = getCurrentIP(conn);
            ipLog.info("Thread-{}: Current IP: {}, Endpoint: {}", 
                threadId, currentIP, endpoint);
            
            long startTime = System.currentTimeMillis();
            long endTime = isContinuous ? Long.MAX_VALUE : startTime + (durationSeconds * 1000L);
            long readCount = 0;
            long lastReportTime = startTime;
            long lastReportCount = 0;
            
            // Continuous metadata reads until test completes or manually stopped
            while (testRunning.get() && System.currentTimeMillis() < endTime) {
                long readStart = System.nanoTime();
                
                boolean success = readDatabaseMetadata(conn, threadId, readCount, currentIP);
                
                long readLatency = (System.nanoTime() - readStart) / 1_000_000;
                totalReadLatency.addAndGet(readLatency);
                
                if (success) {
                    successfulMetadataReads.incrementAndGet();
                } else {
                    failedMetadataReads.incrementAndGet();
                }
                
                readCount++;
                
                // Report progress every 10 seconds
                long currentTime = System.currentTimeMillis();
                if (currentTime - lastReportTime >= 10000) {
                    long readsInPeriod = readCount - lastReportCount;
                    double actualRate = readsInPeriod / ((currentTime - lastReportTime) / 1000.0);
                    log.info("📊 [{}] Metadata-Thread-{}: {} reads, actual rate: {}/sec",
                        now(), threadId, readCount, String.format("%.1f", actualRate));
                    lastReportTime = currentTime;
                    lastReportCount = readCount;
                }
                
                // Control read frequency
                if (readIntervalMs > 0) {
                    try {
                        Thread.sleep(readIntervalMs);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        log.warn("⚠️  [{}] Metadata-Thread-{}: Interrupted", now(), threadId);
                        break;
                    }
                }
            }
            
            long totalTime = System.currentTimeMillis() - startTime;
            double avgRate = readCount / (totalTime / 1000.0);
            if (isContinuous) {
                log.info("✅ [{}] Metadata-Thread-{}: Stopped after {} metadata reads in {} seconds (avg: {}/sec)",
                    now(), threadId, readCount, String.format("%.1f", totalTime / 1000.0), 
                    String.format("%.1f", avgRate));
            } else {
                log.info("✅ [{}] Metadata-Thread-{}: Completed {} metadata reads in {} seconds (avg: {}/sec)",
                    now(), threadId, readCount, String.format("%.1f", totalTime / 1000.0), 
                    String.format("%.1f", avgRate));
            }
            
        } catch (SQLException e) {
            log.error("❌ [{}] Metadata-Thread-{} connection error: {}",
                now(), threadId, e.getMessage());
            
            // Try to extract wrapper plugin status from exception
            extractWrapperStatusFromException(e, threadId);
            
            // Try to get a new connection to query wrapper status
            tryGetWrapperStatusAfterFailure(threadId);
        } finally {
            if (conn != null) {
                try {
                    conn.close();
                    log.info("🔌 [{}] Metadata-Thread-{} connection returned to pool",
                        now(), threadId);
                } catch (SQLException e) {
                    // Ignore
                }
            }
        }
    }
    
    /**
     * Write thread - continuously writes to database
     */
    private void runWriteThread(int threadId, int writesPerSecond, int durationSeconds) {
        int writeIntervalMs = 1000 / writesPerSecond;
        boolean isContinuous = continuousMode.get();
        
        if (isContinuous) {
            log.info("✍️  [{}] Write-Thread-{}: Starting CONTINUOUS writes ({}/sec)...",
                now(), threadId, writesPerSecond);
        } else {
            log.info("✍️  [{}] Write-Thread-{}: Starting writes ({}/sec)...",
                now(), threadId, writesPerSecond);
        }
        
        Connection conn = null;
        String tableName = "bg_test_thread_" + threadId;
        
        try {
            // Get connection from pool
            conn = dataSource.getConnection();
            String endpoint = getEndpointInfo(conn);
            
            log.info("✅ [{}] Write-Thread-{} got connection from {}",
                now(), threadId, endpoint);
            
            // Create table if not exists
            createTestTable(conn, tableName, threadId);
            
            long startTime = System.currentTimeMillis();
            long endTime = isContinuous ? Long.MAX_VALUE : startTime + (durationSeconds * 1000L);
            long writeCount = 0;
            long lastReportTime = startTime;
            long lastReportCount = 0;
            
            // Continuous writes until test completes or manually stopped
            while (testRunning.get() && System.currentTimeMillis() < endTime) {
                long writeStart = System.nanoTime();
                
                boolean success = executeWrite(conn, threadId, writeCount, tableName, endpoint);
                
                long writeLatency = (System.nanoTime() - writeStart) / 1_000_000;
                totalWriteLatency.addAndGet(writeLatency);
                
                if (success) {
                    successfulWrites.incrementAndGet();
                } else {
                    failedWrites.incrementAndGet();
                }
                
                writeCount++;
                
                // Report progress every 10 seconds
                long currentTime = System.currentTimeMillis();
                if (currentTime - lastReportTime >= 10000) {
                    long writesInPeriod = writeCount - lastReportCount;
                    double actualRate = writesInPeriod / ((currentTime - lastReportTime) / 1000.0);
                    log.info("📊 [{}] Write-Thread-{}: {} writes, actual rate: {}/sec",
                        now(), threadId, writeCount, String.format("%.1f", actualRate));
                    lastReportTime = currentTime;
                    lastReportCount = writeCount;
                }
                
                // Control write frequency
                if (writeIntervalMs > 0) {
                    try {
                        Thread.sleep(writeIntervalMs);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        log.warn("⚠️  [{}] Write-Thread-{}: Interrupted", now(), threadId);
                        break;
                    }
                }
            }
            
            long totalTime = System.currentTimeMillis() - startTime;
            double avgRate = writeCount / (totalTime / 1000.0);
            if (isContinuous) {
                log.info("✅ [{}] Write-Thread-{}: Stopped after {} writes in {} seconds (avg: {}/sec)",
                    now(), threadId, writeCount, String.format("%.1f", totalTime / 1000.0), 
                    String.format("%.1f", avgRate));
            } else {
                log.info("✅ [{}] Write-Thread-{}: Completed {} writes in {} seconds (avg: {}/sec)",
                    now(), threadId, writeCount, String.format("%.1f", totalTime / 1000.0), 
                    String.format("%.1f", avgRate));
            }
            
        } catch (SQLException e) {
            log.error("❌ [{}] Write-Thread-{} connection error: {}",
                now(), threadId, e.getMessage());
            extractWrapperStatusFromException(e, threadId);
            tryGetWrapperStatusAfterFailure(threadId);
        } finally {
            if (conn != null) {
                try {
                    conn.close();
                    log.info("🔌 [{}] Write-Thread-{} connection returned to pool",
                        now(), threadId);
                } catch (SQLException e) {
                    // Ignore
                }
            }
        }
    }
    
    /**
     * Create test table for thread
     */
    private void createTestTable(Connection conn, String tableName, int threadId) {
        String createTableSQL = String.format(
            "CREATE TABLE IF NOT EXISTS %s (" +
            "  id BIGINT AUTO_INCREMENT PRIMARY KEY," +
            "  thread_id INT NOT NULL," +
            "  endpoint VARCHAR(255)," +
            "  phase VARCHAR(50)," +
            "  test_data TEXT," +
            "  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP," +
            "  INDEX idx_thread_id (thread_id)," +
            "  INDEX idx_created_at (created_at)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            tableName
        );
        
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(createTableSQL);
            log.info("✅ [{}] Write-Thread-{}: Table {} created/verified",
                now(), threadId, tableName);
        } catch (SQLException e) {
            log.error("❌ [{}] Write-Thread-{}: Failed to create table {}: {}",
                now(), threadId, tableName, e.getMessage());
        }
    }
    
    /**
     * Execute single write operation
     */
    private boolean executeWrite(Connection conn, int threadId, long writeNumber, 
                                 String tableName, String endpoint) {
        totalWrites.incrementAndGet();
        
        String sql = String.format(
            "INSERT INTO %s (thread_id, endpoint, phase, test_data) VALUES (?, ?, ?, ?)",
            tableName
        );
        
        try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
            pstmt.setInt(1, threadId);
            pstmt.setString(2, endpoint);
            pstmt.setString(3, "CONTINUOUS_TEST");
            pstmt.setString(4, "Thread-" + threadId + " Write #" + writeNumber + " at " + now());
            pstmt.executeUpdate();
            
            return true;
            
        } catch (SQLException e) {
            String errorMsg = e.getMessage();
            
            // Check for read-only error
            if (errorMsg.contains("read-only") || errorMsg.contains("READ_ONLY") || 
                errorMsg.contains("read only") || e.getErrorCode() == 1290) {
                
                readOnlyErrors.incrementAndGet();
                
                log.error("╔════════════════════════════════════════════════════════════════╗");
                log.error("║  🎯 READ-ONLY ERROR DETECTED! 🎯                              ║");
                log.error("╚════════════════════════════════════════════════════════════════╝");
                log.error("[{}] Write-Thread-{} Write #{}", now(), threadId, writeNumber);
                log.error("Error Code: {}", e.getErrorCode());
                log.error("SQL State: {}", e.getSQLState());
                log.error("Message: {}", errorMsg);
                log.error("Current endpoint: {}", endpoint);
                log.error("");
                
            } else {
                // Log errors every 100 failures to avoid log spam
                if (writeNumber % 100 == 0) {
                    log.error("❌ [{}] Write-Thread-{} Write #{} failed: {}",
                        now(), threadId, writeNumber, errorMsg);
                }
            }
            
            return false;
        }
    }
    
    /**
     * Read database metadata - tables containing current IP address
     */
    private boolean readDatabaseMetadata(Connection conn, int threadId, long readNumber, String currentIP) {
        totalMetadataReads.incrementAndGet();
        
        try {
            DatabaseMetaData metaData = conn.getMetaData();
            
            // Read basic metadata info
            String dbProductName = metaData.getDatabaseProductName();
            String dbProductVersion = metaData.getDatabaseProductVersion();
            boolean isReadOnly = metaData.isReadOnly();
            
            // Get current endpoint info
            String endpoint = getEndpointInfo(conn);
            lastEndpoint = endpoint;
            
            // Read tables containing current IP address
            String tablePattern = "%" + currentIP.replace(".", "_") + "%";
            int tableCount = 0;
            
            try (ResultSet tables = metaData.getTables(null, null, tablePattern, new String[]{"TABLE"})) {
                while (tables.next()) {
                    String tableName = tables.getString("TABLE_NAME");
                    tableCount++;
                    
                    // Log table name every 5000 reads
                    if (readNumber % 5000 == 0) {
                        ipLog.info("Thread-{}: Found table matching IP pattern: {}", 
                            threadId, tableName);
                    }
                }
            }
            
            // If no IP-matching tables found, read all tables
            if (tableCount == 0) {
                try (ResultSet tables = metaData.getTables(null, null, "%", new String[]{"TABLE"})) {
                    while (tables.next()) {
                        tableCount++;
                    }
                }
            }
            
            // Log detailed info every 5000 reads
            if (readNumber % 5000 == 0) {
                ipLog.info("Thread-{} Read #{}: Database={} {}, Endpoint={}, ReadOnly={}, IP Pattern={}, Tables={}",
                    threadId, readNumber, dbProductName, dbProductVersion, endpoint, isReadOnly, 
                    currentIP, tableCount);
            }
            
            return true;
            
        } catch (SQLException e) {
            // Log errors every 1000 failures to avoid log spam
            if (readNumber % 1000 == 0) {
                log.error("❌ [{}] Metadata-Thread-{} Read #{} failed: {}",
                    now(), threadId, readNumber, e.getMessage());
            }
            
            // Check for failover-related exceptions
            if (isFailoverException(e)) {
                failoverCount.incrementAndGet();
                log.error("🔄 [{}] Metadata-Thread-{}: FAILOVER DETECTED at read #{}!",
                    now(), threadId, readNumber);
                
                // Log failover to IP log
                ipLog.warn("Thread-{}: FAILOVER DETECTED at read #{} - {}",
                    threadId, readNumber, e.getMessage());
            }
            
            return false;
        }
    }
    
    /**
     * Monitoring thread - periodically reports test status
     */
    private void runMonitoringThread(int durationSeconds) {
        boolean isContinuous = continuousMode.get();
        
        if (isContinuous) {
            log.info("📊 [{}] Monitoring thread started (CONTINUOUS MODE)", now());
        } else {
            log.info("📊 [{}] Monitoring thread started", now());
        }
        
        long startTime = System.currentTimeMillis();
        long endTime = isContinuous ? Long.MAX_VALUE : startTime + (durationSeconds * 1000L);
        long lastReportTime = startTime;
        long lastTotalReads = 0;
        
        while (testRunning.get() && System.currentTimeMillis() < endTime) {
            try {
                Thread.sleep(30000); // Report every 30 seconds
                
                long currentTime = System.currentTimeMillis();
                long totalReads = totalMetadataReads.get();
                long successReads = successfulMetadataReads.get();
                long failedReads = failedMetadataReads.get();
                long failovers = failoverCount.get();
                
                // Calculate rates
                long timeDiff = currentTime - lastReportTime;
                long readsDiff = totalReads - lastTotalReads;
                double currentRate = readsDiff / (timeDiff / 1000.0);
                double successRate = totalReads > 0 ? (successReads * 100.0 / totalReads) : 0;
                
                long runningTime = (currentTime - startTime) / 1000;
                String runningTimeStr = formatDuration(runningTime);
                
                log.info("╔════════════════════════════════════════════════════════════════╗");
                if (isContinuous) {
                    log.info("║  [{}] Test Status Report (CONTINUOUS)                 ║", now());
                } else {
                    log.info("║  [{}] Test Status Report                              ║", now());
                }
                log.info("╠════════════════════════════════════════════════════════════════╣");
                log.info("║  Running Time: {}                                             ", runningTimeStr);
                log.info("║  Total Reads: {}                                              ", String.format("%,d", totalReads));
                log.info("║  Successful: {} ({})                                    ", 
                    String.format("%,d", successReads), String.format("%.2f%%", successRate));
                log.info("║  Failed: {}                                                   ", String.format("%,d", failedReads));
                log.info("║  Current Rate: {} reads/sec                                   ", String.format("%.1f", currentRate));
                log.info("║  Failovers: {}                                                ", failovers);
                log.info("║  Last Endpoint: {}                                            ", lastEndpoint);
                log.info("╚════════════════════════════════════════════════════════════════╝");
                
                lastReportTime = currentTime;
                lastTotalReads = totalReads;
                
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        
        log.info("📊 [{}] Monitoring thread completed", now());
    }
    
    /**
     * Get current connection IP address
     */
    private String getCurrentIP(Connection conn) {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT @@hostname as ip")) {
            if (rs.next()) {
                return rs.getString("ip");
            }
        } catch (SQLException e) {
            log.error("Failed to get current IP: {}", e.getMessage());
        }
        return "unknown";
    }
    
    /**
     * Get current connection endpoint info
     */
    private String getEndpointInfo(Connection conn) {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(
                 "SELECT CONCAT(@@hostname, ':', @@port, ' [', IF(@@read_only=0, 'WRITER', 'READER'), ']') as info")) {
            if (rs.next()) {
                return rs.getString("info");
            }
        } catch (SQLException e) {
            return "unknown (error: " + e.getMessage() + ")";
        }
        return "unknown";
    }
    
    /**
     * Try to get wrapper status after connection failure
     */
    private void tryGetWrapperStatusAfterFailure(int threadId) {
        log.info("🔍 [{}] Metadata-Thread-{}: Attempting to get wrapper status after failure...", 
            now(), threadId);
        
        Connection testConn = null;
        try {
            // Try to get a new connection with short timeout
            testConn = dataSource.getConnection();
            
            log.info("✅ [{}] Metadata-Thread-{}: Got new connection for status check", 
                now(), threadId);
            
            // Get basic connection info
            String endpoint = getEndpointInfo(testConn);
            log.info("   Current endpoint: {}", endpoint);
            
            // Try to get wrapper-specific information
            try {
                DatabaseMetaData metaData = testConn.getMetaData();
                log.info("   Database: {} {}", 
                    metaData.getDatabaseProductName(), 
                    metaData.getDatabaseProductVersion());
                log.info("   Read-only: {}", metaData.isReadOnly());
                log.info("   Connection URL: {}", metaData.getURL());
            } catch (SQLException e) {
                log.warn("   Failed to get metadata: {}", e.getMessage());
            }
            
            // Check if this is an AWS wrapper connection
            String connClassName = testConn.getClass().getName();
            if (connClassName.contains("software.amazon.jdbc")) {
                log.info("   ✅ AWS Wrapper connection detected: {}", connClassName);
            } else {
                log.info("   Connection class: {}", connClassName);
            }
            
        } catch (SQLException e) {
            log.error("❌ [{}] Metadata-Thread-{}: Failed to get status connection: {}", 
                now(), threadId, e.getMessage());
        } finally {
            if (testConn != null) {
                try {
                    testConn.close();
                } catch (SQLException e) {
                    // Ignore
                }
            }
        }
    }
    
    /**
     * Extract wrapper plugin status from exception
     */
    private void extractWrapperStatusFromException(SQLException e, int threadId) {
        log.info("🔍 [{}] Metadata-Thread-{}: Analyzing exception for wrapper status...", 
            now(), threadId);
        
        // Log full exception chain
        SQLException current = e;
        int depth = 0;
        while (current != null && depth < 10) {
            log.info("   Exception[{}]: {} - {}", 
                depth, current.getClass().getSimpleName(), current.getMessage());
            
            // Check for wrapper-specific information in message
            String msg = current.getMessage();
            if (msg != null) {
                // Look for plugin mentions
                if (msg.contains("BlueGreen") || msg.contains("bg plugin") || msg.contains("blue/green")) {
                    log.warn("   ⚠️  BG Plugin mentioned: {}", msg);
                }
                if (msg.contains("failover") || msg.contains("Failover")) {
                    log.warn("   ⚠️  Failover mentioned: {}", msg);
                }
                if (msg.contains("topology") || msg.contains("Topology")) {
                    log.warn("   ⚠️  Topology mentioned: {}", msg);
                }
                if (msg.contains("read-only") || msg.contains("read only")) {
                    log.warn("   ⚠️  Read-only mentioned: {}", msg);
                }
            }
            
            current = current.getNextException();
            depth++;
        }
        
        // Log suppressed exceptions
        Throwable[] suppressed = e.getSuppressed();
        if (suppressed.length > 0) {
            log.info("   Suppressed exceptions: {}", suppressed.length);
            for (int i = 0; i < Math.min(suppressed.length, 5); i++) {
                log.info("   Suppressed[{}]: {} - {}", 
                    i, suppressed[i].getClass().getSimpleName(), suppressed[i].getMessage());
            }
        }
        
        // Log cause chain
        Throwable cause = e.getCause();
        depth = 0;
        while (cause != null && depth < 10) {
            log.info("   Cause[{}]: {} - {}", 
                depth, cause.getClass().getSimpleName(), cause.getMessage());
            cause = cause.getCause();
            depth++;
        }
    }
    
    /**
     * Check if exception is failover-related
     */
    private boolean isFailoverException(SQLException e) {
        String msg = e.getMessage().toLowerCase();
        return msg.contains("failover") || 
               msg.contains("connection") ||
               msg.contains("communications link failure") ||
               msg.contains("lost connection") ||
               e.getErrorCode() == 1047 ||
               e.getErrorCode() == 1053;
    }
    
    /**
     * Print final report
     */
    private void printFinalReport() {
        long totalReads = totalMetadataReads.get();
        long successReads = successfulMetadataReads.get();
        long failedReads = failedMetadataReads.get();
        double successRate = totalReads > 0 ? (successReads * 100.0 / totalReads) : 0;
        long avgReadLatency = totalReads > 0 ? totalReadLatency.get() / totalReads : 0;
        
        long totalWs = totalWrites.get();
        long successWs = successfulWrites.get();
        long failedWs = failedWrites.get();
        double writeSuccessRate = totalWs > 0 ? (successWs * 100.0 / totalWs) : 0;
        long avgWriteLatency = totalWs > 0 ? totalWriteLatency.get() / totalWs : 0;
        long readOnlyErrs = readOnlyErrors.get();
        
        int failovers = failoverCount.get();
        long testDuration = (System.currentTimeMillis() - testStartTime) / 1000;
        
        log.info("");
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║                      FINAL REPORT                              ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("📖 Metadata Read Statistics:");
        log.info("   Total Reads: {}", String.format("%,d", totalReads));
        log.info("   Successful: {}", String.format("%,d", successReads));
        log.info("   Failed: {}", String.format("%,d", failedReads));
        log.info("   Success Rate: {}%", String.format("%.2f", successRate));
        log.info("   Average Read Latency: {}ms", avgReadLatency);
        log.info("");
        
        if (enableWrites) {
            log.info("✍️  Write Statistics:");
            log.info("   Total Writes: {}", String.format("%,d", totalWs));
            log.info("   Successful: {}", String.format("%,d", successWs));
            log.info("   Failed: {}", String.format("%,d", failedWs));
            log.info("   Success Rate: {}%", String.format("%.2f", writeSuccessRate));
            log.info("   Average Write Latency: {}ms", avgWriteLatency);
            log.info("   Read-Only Errors: {}", String.format("%,d", readOnlyErrs));
            log.info("");
        }
        
        log.info("⚡ Performance:");
        log.info("   Test Duration: {} seconds", testDuration);
        if (totalReads > 0 && testDuration > 0) {
            double actualTotalRate = totalReads / (testDuration * 1.0);
            log.info("   Actual Total Read Rate: {} reads/sec", String.format("%.1f", actualTotalRate));
        }
        if (totalWs > 0 && testDuration > 0) {
            double actualWriteRate = totalWs / (testDuration * 1.0);
            log.info("   Actual Total Write Rate: {} writes/sec", String.format("%.1f", actualWriteRate));
        }
        log.info("");
        log.info("🔄 Failover Detection:");
        log.info("   Failovers Detected: {}", failovers);
        log.info("");
        
        if (failovers > 0) {
            log.info("🔄 TEST RESULT: FAILOVER DETECTED");
            log.info("   Failover count: {}", failovers);
            if (successRate > 95.0) {
                log.info("   ✅ High read success rate maintained during failover");
            } else {
                log.info("   ⚠️  Read success rate impacted by failover");
            }
            if (enableWrites && writeSuccessRate > 95.0) {
                log.info("   ✅ High write success rate maintained during failover");
            } else if (enableWrites) {
                log.info("   ⚠️  Write success rate impacted by failover");
            }
            if (readOnlyErrs > 0) {
                log.warn("   ⚠️  {} read-only errors detected during failover", readOnlyErrs);
            }
        } else {
            log.warn("⚠️  TEST RESULT: NO FAILOVER DETECTED");
            log.warn("   Blue/Green switchover may not have occurred during test");
        }
        log.info("");
    }
    
    /**
     * Reset statistics
     */
    private void resetStatistics() {
        totalMetadataReads.set(0);
        successfulMetadataReads.set(0);
        failedMetadataReads.set(0);
        totalWrites.set(0);
        successfulWrites.set(0);
        failedWrites.set(0);
        readOnlyErrors.set(0);
        totalReadLatency.set(0);
        totalWriteLatency.set(0);
        failoverCount.set(0);
        lastEndpoint = "unknown";
        testStartTime = 0;
    }
    
    private String now() {
        return LocalDateTime.now().format(formatter);
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
     * Test Status DTO
     */
    public static class TestStatus {
        private final boolean running;
        private final boolean continuous;
        private final boolean writesEnabled;
        private final long totalReads;
        private final long successfulReads;
        private final long failedReads;
        private final long totalWrites;
        private final long successfulWrites;
        private final long failedWrites;
        private final long readOnlyErrors;
        private final int failoverCount;
        private final String lastEndpoint;
        private final long avgReadLatency;
        private final long avgWriteLatency;
        private final long runningTimeSeconds;
        
        public TestStatus(boolean running, boolean continuous, boolean writesEnabled,
                         long totalReads, long successfulReads, long failedReads,
                         long totalWrites, long successfulWrites, long failedWrites,
                         long readOnlyErrors, int failoverCount, String lastEndpoint, 
                         long avgReadLatency, long avgWriteLatency, long runningTimeSeconds) {
            this.running = running;
            this.continuous = continuous;
            this.writesEnabled = writesEnabled;
            this.totalReads = totalReads;
            this.successfulReads = successfulReads;
            this.failedReads = failedReads;
            this.totalWrites = totalWrites;
            this.successfulWrites = successfulWrites;
            this.failedWrites = failedWrites;
            this.readOnlyErrors = readOnlyErrors;
            this.failoverCount = failoverCount;
            this.lastEndpoint = lastEndpoint;
            this.avgReadLatency = avgReadLatency;
            this.avgWriteLatency = avgWriteLatency;
            this.runningTimeSeconds = runningTimeSeconds;
        }
        
        public boolean isRunning() { return running; }
        public boolean isContinuous() { return continuous; }
        public boolean isWritesEnabled() { return writesEnabled; }
        public long getTotalReads() { return totalReads; }
        public long getSuccessfulReads() { return successfulReads; }
        public long getFailedReads() { return failedReads; }
        public long getTotalWrites() { return totalWrites; }
        public long getSuccessfulWrites() { return successfulWrites; }
        public long getFailedWrites() { return failedWrites; }
        public long getReadOnlyErrors() { return readOnlyErrors; }
        public int getFailoverCount() { return failoverCount; }
        public String getLastEndpoint() { return lastEndpoint; }
        public long getAvgReadLatency() { return avgReadLatency; }
        public long getAvgWriteLatency() { return avgWriteLatency; }
        public long getRunningTimeSeconds() { return runningTimeSeconds; }
        public double getReadSuccessRate() {
            return totalReads > 0 ? (successfulReads * 100.0 / totalReads) : 0;
        }
        public double getWriteSuccessRate() {
            return totalWrites > 0 ? (successfulWrites * 100.0 / totalWrites) : 0;
        }
    }
}
