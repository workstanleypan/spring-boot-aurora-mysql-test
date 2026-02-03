package com.test.config;

import lombok.extern.slf4j.Slf4j;
import org.slf4j.bridge.SLF4JBridgeHandler;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.beans.factory.config.ConfigurableListableBeanFactory;
import org.springframework.stereotype.Component;

import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogManager;
import java.util.logging.Logger;

/**
 * Initialize JUL -> SLF4J bridge during Spring bootstrap
 * 
 * This ensures:
 * 1. JUL logs from AWS JDBC Wrapper are captured
 * 2. Bridge is installed before any database connections
 * 3. Log4j2 is already configured when bridge forwards logs
 * 
 * Architecture:
 * AWS JDBC Wrapper (JUL) → SLF4JBridgeHandler → SLF4J → Log4j2
 */
@Slf4j
@Component
public class JulBridgeInitializer implements BeanFactoryPostProcessor {
    
    private static final String AWS_JDBC_PACKAGE = "software.amazon.jdbc";
    
    @Override
    public void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║  Initializing JUL -> SLF4J Bridge                              ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        
        cleanupAndInstallBridge();
        configureLoggers();
        
        log.info("✅ JUL Bridge initialization completed");
        log.info("");
    }
    
    /**
     * Cleanup existing JUL handlers and install SLF4J bridge
     */
    private void cleanupAndInstallBridge() {
        // Reset JUL configuration
        LogManager.getLogManager().reset();
        
        // Remove all handlers from root logger
        Logger rootLogger = Logger.getLogger("");
        Handler[] handlers = rootLogger.getHandlers();
        for (Handler handler : handlers) {
            rootLogger.removeHandler(handler);
            log.debug("Removed JUL handler: {}", handler.getClass().getName());
        }
        
        // Install SLF4J bridge
        SLF4JBridgeHandler.removeHandlersForRootLogger();
        SLF4JBridgeHandler.install();
        
        log.info("✅ SLF4JBridgeHandler installed");
    }
    
    /**
     * Configure JUL loggers
     * 
     * IMPORTANT: Only set root logger to ALL
     * DO NOT set AWS JDBC logger level here!
     * 
     * The AWS JDBC Wrapper's log level should be controlled by:
     * - wrapperLoggerLevel parameter in JDBC URL (single control point)
     * 
     * If we set AWS JDBC logger to ALL here, it will accept all TRACE logs
     * from BlueGreenStatusMonitor, causing excessive logging.
     */
    private void configureLoggers() {
        // Set root logger to ALL - accept everything from JUL
        Logger rootLogger = Logger.getLogger("");
        rootLogger.setLevel(Level.ALL);
        
        // Set all handlers to ALL
        for (Handler handler : rootLogger.getHandlers()) {
            handler.setLevel(Level.ALL);
        }
        
        // ⭐ DO NOT set AWS JDBC logger level here
        // Let wrapperLoggerLevel in JDBC URL control it at the source
        // This prevents excessive TRACE logs from BlueGreenStatusMonitor
        
        log.info("✅ JUL loggers configured:");
        log.info("   - Root logger: {}", rootLogger.getLevel());
        log.info("   - AWS JDBC logger: controlled by wrapperLoggerLevel in JDBC URL");
        log.info("   - Handler count: {}", rootLogger.getHandlers().length);
        log.info("");
        log.info("📋 Log Level Control:");
        log.info("   - Set wrapperLoggerLevel in JDBC URL to control AWS JDBC Wrapper logs");
        log.info("   - Recommended: wrapperLoggerLevel=FINE (for BG plugin debugging)");
        log.info("   - Production: wrapperLoggerLevel=INFO (minimal logging)");
    }
}
