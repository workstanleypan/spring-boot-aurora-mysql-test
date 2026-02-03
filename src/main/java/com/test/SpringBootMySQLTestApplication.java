package com.test;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;

/**
 * Spring Boot MySQL Test Application
 * 
 * 测试 Spring Boot 与 AWS JDBC Wrapper 的集成
 * 
 * 日志架构：
 * AWS JDBC Wrapper (JUL) → SLF4JBridgeHandler → SLF4J → Log4j2
 * 
 * 注意：JUL Bridge 由 JulBridgeInitializer 自动初始化
 */
@SpringBootApplication
public class SpringBootMySQLTestApplication {
    
    private static final Logger log = LoggerFactory.getLogger(SpringBootMySQLTestApplication.class);
    
    public static void main(String[] args) {
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║   Spring Boot MySQL Test Application                          ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("📋 Logging Architecture:");
        log.info("   AWS JDBC Wrapper (JUL)");
        log.info("   ↓");
        log.info("   SLF4JBridgeHandler (auto-initialized by JulBridgeInitializer)");
        log.info("   ↓");
        log.info("   SLF4J API");
        log.info("   ↓");
        log.info("   Log4j2 (Console + RollingFile)");
        log.info("");
        
        SpringApplication.run(SpringBootMySQLTestApplication.class, args);
    }
    
    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        log.info("");
        log.info("╔════════════════════════════════════════════════════════════════╗");
        log.info("║              Application Ready                                 ║");
        log.info("╚════════════════════════════════════════════════════════════════╝");
        log.info("");
        log.info("✅ Application is ready!");
        log.info("📋 Access endpoints:");
        log.info("   - Health: http://localhost:8080/actuator/health");
        log.info("   - Test: http://localhost:8080/api/test");
        log.info("   - Users: http://localhost:8080/api/users");
        log.info("");
        log.info("📝 Log files:");
        log.info("   - Info: logs/info.log");
        log.info("   - Error: logs/error.log");
        log.info("   - Spring Boot: logs/spring-boot.log");
        log.info("");
    }
}
