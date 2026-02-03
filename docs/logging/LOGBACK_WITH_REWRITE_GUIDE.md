# Logback实现日志级别重写指南

## 概述

本文档说明如何在保持Logback作为主日志框架的前提下，实现类似Log4j2 Rewrite功能，将AWS JDBC Wrapper的TRACE/DEBUG日志重写为INFO级别输出。

## 适用场景

- 应用主体使用Logback（Spring Boot默认）
- 需要兼容Apollo等可能与Log4j2冲突的框架
- 希望将AWS JDBC Wrapper的调试日志以INFO级别输出
- 不想切换到Log4j2但需要类似Rewrite功能

## 架构设计

```
AWS JDBC Wrapper (JUL日志)
    ↓
jul-to-slf4j (桥接)
    ↓
SLF4J API
    ↓
Logback (主日志框架)
    ↓
WrapperLevelRewriteAppender (自定义Appender)
    ↓
INFO_FILE (info.log)
```

## 实现步骤

### 1. Maven依赖配置

```xml
<!-- pom.xml -->
<dependencies>
    <!-- Spring Boot Starter (默认包含Logback) -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter</artifactId>
    </dependency>

    <!-- JUL桥接到SLF4J (AWS Wrapper使用JUL) -->
    <dependency>
        <groupId>org.slf4j</groupId>
        <artifactId>jul-to-slf4j</artifactId>
    </dependency>

    <!-- AWS JDBC Wrapper -->
    <dependency>
        <groupId>software.amazon.jdbc</groupId>
        <artifactId>aws-advanced-jdbc-wrapper</artifactId>
        <version>2.6.8</version>
    </dependency>

    <!-- MySQL驱动 -->
    <dependency>
        <groupId>com.mysql</groupId>
        <artifactId>mysql-connector-j</artifactId>
    </dependency>

    <!-- HikariCP连接池 -->
    <dependency>
        <groupId>com.zaxxer</groupId>
        <artifactId>HikariCP</artifactId>
    </dependency>
</dependencies>
```

**关键点**：
- 不引入 `spring-boot-starter-log4j2`
- 使用 `jul-to-slf4j` 桥接JUL日志到SLF4J

---

### 2. 创建自定义Rewrite Appender

创建文件：`src/main/java/com/test/logging/WrapperLevelRewriteAppender.java`

```java
package com.test.logging;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.LoggingEvent;
import ch.qos.logback.core.UnsynchronizedAppenderBase;
import ch.qos.logback.core.spi.AppenderAttachable;
import ch.qos.logback.core.spi.AppenderAttachableImpl;
import ch.qos.logback.core.Appender;

import java.util.Iterator;

/**
 * 自定义Logback Appender：将AWS JDBC Wrapper的TRACE/DEBUG日志重写为INFO级别
 * 
 * 功能：
 * 1. 拦截software.amazon.jdbc包的所有日志
 * 2. 将TRACE/DEBUG级别重写为INFO
 * 3. 其他日志保持原样
 * 4. 输出到配置的目标Appender
 */
public class WrapperLevelRewriteAppender extends UnsynchronizedAppenderBase<ILoggingEvent>
        implements AppenderAttachable<ILoggingEvent> {

    private AppenderAttachableImpl<ILoggingEvent> aai = new AppenderAttachableImpl<>();
    private String loggerPrefix = "software.amazon.jdbc";

    @Override
    protected void append(ILoggingEvent eventObject) {
        // 检查是否是AWS JDBC Wrapper的日志
        if (eventObject.getLoggerName().startsWith(loggerPrefix)) {
            Level originalLevel = eventObject.getLevel();
            
            // 如果是TRACE或DEBUG，重写为INFO
            if (originalLevel.toInt() <= Level.DEBUG.toInt()) {
                ILoggingEvent rewrittenEvent = rewriteLevel(eventObject, Level.INFO);
                aai.appendLoopOnAppenders(rewrittenEvent);
                return;
            }
        }
        
        // 其他日志直接传递
        aai.appendLoopOnAppenders(eventObject);
    }

    /**
     * 创建新的日志事件，使用新的日志级别
     */
    private ILoggingEvent rewriteLevel(ILoggingEvent event, Level newLevel) {
        LoggerContext lc = (LoggerContext) context;
        Logger logger = lc.getLogger(event.getLoggerName());
        
        LoggingEvent newEvent = new LoggingEvent(
            event.getLoggerName(),
            logger,
            newLevel,  // 新的日志级别
            event.getMessage(),
            event.getThrowableProxy(),
            event.getArgumentArray()
        );
        
        // 保留原始时间戳和MDC上下文
        newEvent.setTimeStamp(event.getTimeStamp());
        newEvent.setMDCPropertyMap(event.getMDCPropertyMap());
        
        return newEvent;
    }

    /**
     * 设置要监控的Logger前缀
     */
    public void setLoggerPrefix(String loggerPrefix) {
        this.loggerPrefix = loggerPrefix;
    }

    // ========== AppenderAttachable接口实现 ==========
    
    @Override
    public void addAppender(Appender<ILoggingEvent> newAppender) {
        addInfo("Attaching appender named [" + newAppender.getName() + "] to " + this.getName());
        aai.addAppender(newAppender);
    }

    @Override
    public Iterator<Appender<ILoggingEvent>> iteratorForAppenders() {
        return aai.iteratorForAppenders();
    }

    @Override
    public Appender<ILoggingEvent> getAppender(String name) {
        return aai.getAppender(name);
    }

    @Override
    public boolean isAttached(Appender<ILoggingEvent> appender) {
        return aai.isAttached(appender);
    }

    @Override
    public void detachAndStopAllAppenders() {
        aai.detachAndStopAllAppenders();
    }

    @Override
    public boolean detachAppender(Appender<ILoggingEvent> appender) {
        return aai.detachAppender(appender);
    }

    @Override
    public boolean detachAppender(String name) {
        return aai.detachAppender(name);
    }
}
```

---

### 3. Logback配置文件

创建或修改：`src/main/resources/logback-spring.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    
    <!-- ========== 控制台输出 ========== -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- ========== INFO级别日志文件 ========== -->
    <appender name="INFO_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>logs/info.log</file>
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>logs/info-%d{yyyy-MM-dd}-%i.log.gz</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>30</maxHistory>
            <totalSizeCap>10GB</totalSizeCap>
        </rollingPolicy>
    </appender>

    <!-- ========== ERROR级别日志文件 ========== -->
    <appender name="ERROR_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>logs/error.log</file>
        <filter class="ch.qos.logback.classic.filter.ThresholdFilter">
            <level>ERROR</level>
        </filter>
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>logs/error-%d{yyyy-MM-dd}-%i.log.gz</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>30</maxHistory>
        </rollingPolicy>
    </appender>

    <!-- ========== AWS JDBC Wrapper专用配置 ========== -->
    
    <!-- 自定义Rewrite Appender -->
    <appender name="WRAPPER_REWRITE" class="com.test.logging.WrapperLevelRewriteAppender">
        <!-- 配置要监控的Logger前缀 -->
        <loggerPrefix>software.amazon.jdbc</loggerPrefix>
        <!-- 将重写后的日志输出到INFO_FILE -->
        <appender-ref ref="INFO_FILE"/>
    </appender>

    <!-- AWS JDBC Wrapper Logger配置 -->
    <!-- level设为TRACE以捕获所有日志，由Rewrite Appender处理级别转换 -->
    <logger name="software.amazon.jdbc" level="TRACE" additivity="false">
        <appender-ref ref="WRAPPER_REWRITE"/>
    </logger>

    <!-- ========== 其他组件日志配置 ========== -->
    
    <!-- HikariCP连接池 -->
    <logger name="com.zaxxer.hikari" level="INFO"/>
    
    <!-- Spring框架 -->
    <logger name="org.springframework" level="INFO"/>
    
    <!-- 应用自身日志 -->
    <logger name="com.test" level="DEBUG"/>

    <!-- ========== Root Logger ========== -->
    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="INFO_FILE"/>
        <appender-ref ref="ERROR_FILE"/>
    </root>

</configuration>
```

**配置说明**：
- `WRAPPER_REWRITE`：自定义Appender，负责级别重写
- `software.amazon.jdbc` Logger设为TRACE级别，确保捕获所有日志
- `additivity="false"`：防止日志重复输出到Root Logger
- 重写后的日志输出到 `INFO_FILE`，与应用其他日志混合

---

### 4. JUL桥接初始化

创建或确认存在：`src/main/java/com/test/config/JulBridgeInitializer.java`

```java
package com.test.config;

import org.slf4j.bridge.SLF4JBridgeHandler;
import org.springframework.context.ApplicationListener;
import org.springframework.context.event.ContextRefreshedEvent;
import org.springframework.stereotype.Component;

import java.util.logging.LogManager;

/**
 * JUL到SLF4J桥接初始化器
 * 
 * AWS JDBC Wrapper使用JUL (java.util.logging)，需要桥接到SLF4J
 */
@Component
public class JulBridgeInitializer implements ApplicationListener<ContextRefreshedEvent> {

    private static boolean initialized = false;

    @Override
    public void onApplicationEvent(ContextRefreshedEvent event) {
        if (!initialized) {
            // 移除JUL默认处理器
            LogManager.getLogManager().reset();
            
            // 安装SLF4J桥接处理器
            SLF4JBridgeHandler.removeHandlersForRootLogger();
            SLF4JBridgeHandler.install();
            
            initialized = true;
            
            System.out.println("JUL to SLF4J bridge initialized successfully");
        }
    }
}
```

**关键点**：
- 在Spring容器启动后初始化JUL桥接
- 移除JUL默认处理器，避免日志重复
- 使用单例模式防止重复初始化

---

### 5. application.yml配置

```yaml
spring:
  application:
    name: spring-boot-mysql-test

# 指定使用logback配置文件
logging:
  config: classpath:logback-spring.xml

# 数据源配置
spring:
  datasource:
    driver-class-name: software.amazon.jdbc.Driver
    url: jdbc:aws-wrapper:mysql://your-cluster.cluster-xxx.us-east-1.rds.amazonaws.com:3306/testdb
    username: admin
    password: ${DB_PASSWORD}
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
```

---

## 工作流程

### 日志流转过程

```
1. AWS JDBC Wrapper产生TRACE/DEBUG日志
   Logger: software.amazon.jdbc.plugin.bluegreen.BlueGreenPlugin
   Level: DEBUG
   Message: "Checking cluster status..."
   
2. JUL日志通过jul-to-slf4j桥接到SLF4J
   
3. Logback接收日志事件
   
4. WrapperLevelRewriteAppender拦截
   - 检测到logger名称以"software.amazon.jdbc"开头
   - 检测到级别为DEBUG (≤ DEBUG)
   
5. 创建新的日志事件
   Logger: software.amazon.jdbc.plugin.bluegreen.BlueGreenPlugin
   Level: INFO (重写后)
   Message: "Checking cluster status..."
   
6. 输出到INFO_FILE
   2026-01-19 10:30:15.123 [main] INFO  software.amazon.jdbc.plugin.bluegreen.BlueGreenPlugin - Checking cluster status...
```

### 级别转换规则

| 原始级别 | 转换后级别 | 是否输出 |
|---------|-----------|---------|
| TRACE   | INFO      | ✅ 输出 |
| DEBUG   | INFO      | ✅ 输出 |
| INFO    | INFO      | ✅ 输出 |
| WARN    | WARN      | ✅ 输出 |
| ERROR   | ERROR     | ✅ 输出 |

---

## 验证测试

### 1. 编译项目

```bash
cd spring-boot-mysql-test
mvn clean package
```

### 2. 启动应用

```bash
./run-aurora.sh
```

### 3. 查看日志输出

```bash
# 实时查看info.log
tail -f logs/info.log

# 应该看到类似输出：
# 2026-01-19 10:30:15.123 [main] INFO  software.amazon.jdbc.plugin.bluegreen.BlueGreenPlugin - Initializing Blue/Green Plugin
# 2026-01-19 10:30:15.456 [main] INFO  software.amazon.jdbc.plugin.bluegreen.BlueGreenStatusMonitor - Starting status monitor
```

### 4. 验证级别重写

```bash
# 搜索AWS Wrapper日志
grep "software.amazon.jdbc" logs/info.log

# 所有日志应该显示为INFO级别，即使原始级别是TRACE/DEBUG
```

### 5. 测试API

```bash
# 触发数据库操作
curl http://localhost:8080/api/users

# 查看日志中的Wrapper调试信息
tail -20 logs/info.log
```

---

## 与Log4j2 Rewrite对比

### Log4j2 Rewrite配置

```xml
<Rewrite name="AmazonJdbcRewrite">
    <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
        <KeyValuePair key="TRACE" value="INFO"/>
        <KeyValuePair key="DEBUG" value="INFO"/>
    </LoggerNameLevelRewritePolicy>
    <AppenderRef ref="InfoFile"/>
</Rewrite>
```

### Logback等价配置

```xml
<appender name="WRAPPER_REWRITE" class="com.test.logging.WrapperLevelRewriteAppender">
    <loggerPrefix>software.amazon.jdbc</loggerPrefix>
    <appender-ref ref="INFO_FILE"/>
</appender>
```

### 功能对比

| 特性 | Log4j2 Rewrite | Logback自定义Appender |
|-----|---------------|---------------------|
| 级别重写 | ✅ 原生支持 | ✅ 自定义实现 |
| 配置复杂度 | 简单（XML配置） | 中等（需Java类） |
| 性能 | 高 | 高 |
| 灵活性 | 中等 | 高（可自定义逻辑） |
| 依赖冲突风险 | 可能与Apollo冲突 | 无冲突 |

---

## 优势与限制

### 优势

✅ **兼容性好**：不引入Log4j2，避免与Apollo等框架冲突  
✅ **功能完整**：实现了Log4j2 Rewrite的核心功能  
✅ **统一输出**：所有日志输出到同一个文件  
✅ **不影响现有配置**：其他应用日志继续使用Logback原有配置  
✅ **灵活扩展**：可以自定义更复杂的重写逻辑

### 限制

⚠️ **需要Java代码**：需要编写自定义Appender类  
⚠️ **配置稍复杂**：相比Log4j2需要额外的Java类  
⚠️ **维护成本**：需要维护自定义Appender代码

---

## 故障排查

### 问题1：看不到AWS Wrapper日志

**检查项**：
```bash
# 1. 确认JUL桥接已初始化
grep "JUL to SLF4J bridge initialized" logs/info.log

# 2. 确认Logger级别设置
# logback-spring.xml中应该有：
# <logger name="software.amazon.jdbc" level="TRACE" additivity="false">

# 3. 检查依赖
mvn dependency:tree | grep jul-to-slf4j
```

### 问题2：日志级别没有被重写

**检查项**：
```bash
# 1. 确认自定义Appender类存在
ls -la src/main/java/com/test/logging/WrapperLevelRewriteAppender.java

# 2. 确认配置正确
grep "WRAPPER_REWRITE" src/main/resources/logback-spring.xml

# 3. 查看启动日志
grep "Attaching appender" logs/info.log
```

### 问题3：日志重复输出

**原因**：`additivity="false"` 未设置

**解决**：
```xml
<logger name="software.amazon.jdbc" level="TRACE" additivity="false">
    <appender-ref ref="WRAPPER_REWRITE"/>
</logger>
```

---

## 生产环境优化

### 1. 性能优化

```xml
<!-- 使用异步Appender -->
<appender name="ASYNC_INFO" class="ch.qos.logback.classic.AsyncAppender">
    <queueSize>512</queueSize>
    <discardingThreshold>0</discardingThreshold>
    <appender-ref ref="INFO_FILE"/>
</appender>

<appender name="WRAPPER_REWRITE" class="com.test.logging.WrapperLevelRewriteAppender">
    <loggerPrefix>software.amazon.jdbc</loggerPrefix>
    <appender-ref ref="ASYNC_INFO"/>
</appender>
```

### 2. 条件化日志级别

```xml
<!-- 开发环境：输出所有Wrapper日志 -->
<springProfile name="dev">
    <logger name="software.amazon.jdbc" level="TRACE" additivity="false">
        <appender-ref ref="WRAPPER_REWRITE"/>
    </logger>
</springProfile>

<!-- 生产环境：只输出INFO及以上 -->
<springProfile name="prod">
    <logger name="software.amazon.jdbc" level="INFO" additivity="false">
        <appender-ref ref="INFO_FILE"/>
    </logger>
</springProfile>
```

### 3. 监控日志大小

```bash
# 定期检查日志文件大小
du -sh logs/

# 配置日志轮转
# logback-spring.xml中已配置：
# <maxFileSize>100MB</maxFileSize>
# <maxHistory>30</maxHistory>
# <totalSizeCap>10GB</totalSizeCap>
```

---

## 总结

本方案通过自定义Logback Appender实现了Log4j2 Rewrite功能，在保持Logback作为主日志框架的同时，解决了与Apollo等框架的兼容性问题。

**适用场景**：
- 需要兼容特定版本的第三方框架（如Apollo 2.4.0）
- 希望保持Spring Boot默认的Logback配置
- 需要将AWS JDBC Wrapper的调试日志以INFO级别输出

**核心文件**：
1. `pom.xml` - 依赖配置
2. `WrapperLevelRewriteAppender.java` - 自定义Appender
3. `logback-spring.xml` - Logback配置
4. `JulBridgeInitializer.java` - JUL桥接初始化

**关键技术**：
- JUL到SLF4J桥接
- Logback自定义Appender
- 日志事件级别重写
- AppenderAttachable接口实现
