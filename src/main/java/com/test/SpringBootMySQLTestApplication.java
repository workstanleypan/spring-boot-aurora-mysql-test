package com.test;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.bridge.SLF4JBridgeHandler;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;

import java.util.logging.Level;

/**
 * Spring Boot MySQL Test Application
 * 
 * Tests Spring Boot integration with AWS JDBC Wrapper
 * 
 * Logging Architecture:
 * AWS JDBC Wrapper (JUL) → SLF4JBridgeHandler → SLF4J → Log4j2
 */
@SpringBootApplication
public class SpringBootMySQLTestApplication {
    
    private static final Logger log = LoggerFactory.getLogger(SpringBootMySQLTestApplication.class);
    
    static {
        // Initialize JUL to SLF4J bridge
        SLF4JBridgeHandler.removeHandlersForRootLogger();
        SLF4JBridgeHandler.install();
        
        // Set JUL root logger level to ALL to allow all logs through the bridge
        java.util.logging.Logger rootLogger = java.util.logging.Logger.getLogger("");
        rootLogger.setLevel(Level.ALL);
        
        // Set AWS JDBC Wrapper log level
        String wrapperLogLevel = System.getenv("WRAPPER_LOG_LEVEL");
        if (wrapperLogLevel != null && !wrapperLogLevel.isEmpty()) {
            try {
                Level level = Level.parse(wrapperLogLevel);
                java.util.logging.Logger.getLogger("software.amazon.jdbc").setLevel(level);
                java.util.logging.Logger.getLogger("software.amazon").setLevel(level);
                System.out.println("[JUL] Set software.amazon.jdbc level to: " + level);
            } catch (IllegalArgumentException e) {
                System.err.println("[JUL] Invalid log level: " + wrapperLogLevel);
            }
        }
    }
    
    public static void main(String[] args) {
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║   Spring Boot Aurora MySQL Test Application                   ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("📋 Logging Architecture:");
        log.info("   AWS JDBC Wrapper (JUL) → SLF4JBridgeHandler → SLF4J → Log4j2");
        log.info("   WRAPPER_LOG_LEVEL (env): {}", System.getenv("WRAPPER_LOG_LEVEL"));
        log.info("");
        
        SpringApplication.run(SpringBootMySQLTestApplication.class, args);
    }
    
    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady(ApplicationReadyEvent event) {
        String port = event.getApplicationContext().getEnvironment().getProperty("local.server.port", "8080");
        log.info("");
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║              Application Ready                                 ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("✅ Application is ready!");
        log.info("📋 Access endpoints:");
        log.info("   - Health: http://localhost:{}/actuator/health", port);
        log.info("   - Blue/Green Status: http://localhost:{}/api/bluegreen/status", port);
        log.info("   - Start Write Test: http://localhost:{}/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500", port);
        log.info("");
    }
}
