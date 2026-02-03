# Log Level Rewrite Guide

## 概述

本指南介绍如何将 AWS JDBC Wrapper 的 DEBUG/TRACE 级别日志以 INFO 级别写入日志文件。

## 问题场景

当你想要：
1. 在 JDBC URL 中设置 `wrapperLoggerLevel=FINE` (对应 DEBUG)
2. 但希望这些 DEBUG 日志在某些日志文件中显示为 INFO 级别
3. 避免日志分析工具因为 DEBUG 级别而忽略这些重要日志

## 解决方案

### 方案 1: 使用固定 INFO 级别的 Pattern（简单）

**优点**: 简单，无需额外代码  
**缺点**: 只是显示为 INFO，实际日志级别未改变

在 `log4j2-spring.xml` 中添加：

```xml
<Properties>
    <!-- 固定显示 INFO 级别的 Pattern -->
    <Property name="FILE_LOG_PATTERN_INFO_ONLY">
        %d{yyyy-MM-dd HH:mm:ss.SSS} INFO  [%X{X-RequestID}] %pid --- [%t] %-40.40c{1.} [%traceId]: %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}
    </Property>
</Properties>

<Appenders>
    <!-- 接受 DEBUG/TRACE，但显示为 INFO -->
    <RollingRandomAccessFile name="AmazonJdbcDebugAsInfo"
                             fileName="${LOG_DIR}/jdbc-wrapper-debug-as-info.log"
                             filePattern="${LOG_DIR}/archive/history_jdbc_wrapper_debug_as_info.%d{yyyy-MM-dd}.%i.zip">
        <!-- 只接受 DEBUG 和 TRACE 级别 -->
        <Filters>
            <LevelRangeFilter minLevel="DEBUG" maxLevel="DEBUG" onMatch="ACCEPT" onMismatch="NEUTRAL"/>
            <LevelRangeFilter minLevel="TRACE" maxLevel="TRACE" onMatch="ACCEPT" onMismatch="NEUTRAL"/>
            <ThresholdFilter level="INFO" onMatch="DENY" onMismatch="DENY"/>
        </Filters>
        <!-- 使用固定 INFO 的 Pattern -->
        <PatternLayout pattern="${FILE_LOG_PATTERN_INFO_ONLY}" charset="UTF-8"/>
        <Policies>
            <TimeBasedTriggeringPolicy/>
            <SizeBasedTriggeringPolicy size="500 MB"/>
        </Policies>
    </RollingRandomAccessFile>
</Appenders>

<Loggers>
    <Logger name="software.amazon.jdbc" level="all" additivity="false">
        <AppenderRef ref="AmazonJdbcDebugAsInfo"/>
    </Logger>
</Loggers>
```

### 方案 2: 使用 Rewrite Policy（推荐）

**优点**: 真正改变日志级别，更灵活  
**缺点**: 需要自定义 RewritePolicy 类

#### 步骤 1: 创建自定义 RewritePolicy

创建文件 `src/main/java/com/test/logging/LevelRewritePolicy.java`:

```java
package com.test.logging;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.core.LogEvent;
import org.apache.logging.log4j.core.appender.rewrite.RewritePolicy;
import org.apache.logging.log4j.core.config.plugins.Plugin;
import org.apache.logging.log4j.core.config.plugins.PluginAttribute;
import org.apache.logging.log4j.core.config.plugins.PluginFactory;
import org.apache.logging.log4j.core.impl.Log4jLogEvent;

/**
 * Rewrite Policy to convert DEBUG/TRACE logs to INFO level
 */
@Plugin(name = "LevelRewritePolicy", category = "Core", elementType = "rewritePolicy", printObject = true)
public class LevelRewritePolicy implements RewritePolicy {
    
    private final Level targetLevel;
    private final Level minLevel;
    private final Level maxLevel;
    
    private LevelRewritePolicy(Level targetLevel, Level minLevel, Level maxLevel) {
        this.targetLevel = targetLevel;
        this.minLevel = minLevel;
        this.maxLevel = maxLevel;
    }
    
    @Override
    public LogEvent rewrite(LogEvent event) {
        Level eventLevel = event.getLevel();
        
        // Check if event level is within the range to rewrite
        if (eventLevel.isMoreSpecificThan(maxLevel) && eventLevel.isLessSpecificThan(minLevel)) {
            // Rewrite the level
            return new Log4jLogEvent.Builder(event)
                .setLevel(targetLevel)
                .build();
        }
        
        return event;
    }
    
    @PluginFactory
    public static LevelRewritePolicy createPolicy(
            @PluginAttribute("targetLevel") String targetLevel,
            @PluginAttribute("minLevel") String minLevel,
            @PluginAttribute("maxLevel") String maxLevel) {
        
        Level target = Level.toLevel(targetLevel, Level.INFO);
        Level min = Level.toLevel(minLevel, Level.TRACE);
        Level max = Level.toLevel(maxLevel, Level.DEBUG);
        
        return new LevelRewritePolicy(target, min, max);
    }
}
```

#### 步骤 2: 配置 log4j2-spring.xml

```xml
<Appenders>
    <!-- Rewrite Appender: 将 DEBUG/TRACE 改写为 INFO -->
    <Rewrite name="RewriteDebugToInfo">
        <LevelRewritePolicy targetLevel="INFO" minLevel="TRACE" maxLevel="DEBUG"/>
        <AppenderRef ref="AmazonJdbcDebugAsInfoFile"/>
    </Rewrite>
    
    <!-- 实际的文件 Appender -->
    <RollingRandomAccessFile name="AmazonJdbcDebugAsInfoFile"
                             fileName="${LOG_DIR}/jdbc-wrapper-debug-as-info.log"
                             filePattern="${LOG_DIR}/archive/history_jdbc_wrapper_debug_as_info.%d{yyyy-MM-dd}.%i.zip">
        <PatternLayout pattern="${FILE_LOG_PATTERN}" charset="UTF-8"/>
        <Policies>
            <TimeBasedTriggeringPolicy/>
            <SizeBasedTriggeringPolicy size="500 MB"/>
        </Policies>
    </RollingRandomAccessFile>
</Appenders>

<Loggers>
    <Logger name="software.amazon.jdbc" level="all" additivity="false">
        <AppenderRef ref="RewriteDebugToInfo"/>
    </Logger>
</Loggers>
```

### 方案 3: 使用 MapRewritePolicy（内置）

**优点**: 使用 Log4j2 内置功能，无需自定义代码  
**缺点**: 配置稍复杂

```xml
<Appenders>
    <!-- Rewrite Appender using MapRewritePolicy -->
    <Rewrite name="RewriteDebugToInfo">
        <MapRewritePolicy>
            <KeyValuePair key="level" value="INFO"/>
        </MapRewritePolicy>
        <AppenderRef ref="AmazonJdbcDebugAsInfoFile"/>
    </Rewrite>
    
    <RollingRandomAccessFile name="AmazonJdbcDebugAsInfoFile"
                             fileName="${LOG_DIR}/jdbc-wrapper-debug-as-info.log"
                             filePattern="${LOG_DIR}/archive/history_jdbc_wrapper_debug_as_info.%d{yyyy-MM-dd}.%i.zip">
        <!-- 只接受 DEBUG 和 TRACE -->
        <Filters>
            <LevelRangeFilter minLevel="TRACE" maxLevel="DEBUG" onMatch="ACCEPT" onMismatch="DENY"/>
        </Filters>
        <PatternLayout pattern="${FILE_LOG_PATTERN}" charset="UTF-8"/>
        <Policies>
            <TimeBasedTriggeringPolicy/>
            <SizeBasedTriggeringPolicy size="500 MB"/>
        </Policies>
    </RollingRandomAccessFile>
</Appenders>
```

## 使用示例

### 当前配置文件

项目中已提供 `log4j2-spring-with-level-rewrite.xml`，使用方案 1（固定 INFO Pattern）。

### 切换到新配置

```bash
cd spring-boot-mysql-test

# 备份当前配置
cp src/main/resources/log4j2-spring.xml src/main/resources/log4j2-spring.xml.backup

# 使用新配置
cp src/main/resources/log4j2-spring-with-level-rewrite.xml src/main/resources/log4j2-spring.xml

# 重启应用
./restart-app.sh
```

### 验证效果

```bash
# 启动应用（使用 DEBUG 级别）
./run-aurora-bg-debug.sh

# 查看原始 DEBUG 日志
tail -f logs/jdbc-wrapper.log
# 输出: 2026-01-14 08:15:30.123 DEBUG ...

# 查看改写为 INFO 的日志
tail -f logs/jdbc-wrapper-debug-as-info.log
# 输出: 2026-01-14 08:15:30.123 INFO  ...
```

## 日志文件说明

使用新配置后，会生成以下日志文件：

| 文件 | 内容 | 级别显示 |
|------|------|----------|
| `jdbc-wrapper.log` | 所有 Wrapper 日志（TRACE/DEBUG/INFO/WARN/ERROR） | 原始级别 |
| `jdbc-wrapper-info.log` | INFO 及以上的 Wrapper 日志 | 原始级别 |
| `jdbc-wrapper-debug-as-info.log` | DEBUG/TRACE 日志 | 显示为 INFO |

## 使用场景

### 场景 1: 日志分析工具只接受 INFO 级别

```bash
# 使用 jdbc-wrapper-debug-as-info.log
# 所有 DEBUG 日志都显示为 INFO，可以被工具正常处理
```

### 场景 2: 需要区分不同级别的日志

```bash
# 使用 jdbc-wrapper.log - 查看原始级别
tail -f logs/jdbc-wrapper.log | grep DEBUG

# 使用 jdbc-wrapper-debug-as-info.log - 统一为 INFO
tail -f logs/jdbc-wrapper-debug-as-info.log
```

### 场景 3: 生产环境监控

```bash
# 开发环境: 使用原始级别
tail -f logs/jdbc-wrapper.log

# 生产环境: 使用改写后的 INFO 级别
tail -f logs/jdbc-wrapper-debug-as-info.log
```

## 性能考虑

1. **方案 1（固定 Pattern）**: 性能影响最小，只是改变显示格式
2. **方案 2（自定义 RewritePolicy）**: 轻微性能影响，需要创建新的 LogEvent
3. **方案 3（MapRewritePolicy）**: 性能影响较大，会修改 LogEvent 的 Map

**推荐**: 
- 开发环境: 使用方案 1
- 生产环境: 如果需要真正改变级别，使用方案 2

## 过滤器组合

### 只接受 DEBUG 级别（不包括 TRACE）

```xml
<Filters>
    <LevelRangeFilter minLevel="DEBUG" maxLevel="DEBUG" onMatch="ACCEPT" onMismatch="DENY"/>
</Filters>
```

### 接受 DEBUG 和 TRACE，排除 INFO 及以上

```xml
<Filters>
    <LevelRangeFilter minLevel="DEBUG" maxLevel="DEBUG" onMatch="ACCEPT" onMismatch="NEUTRAL"/>
    <LevelRangeFilter minLevel="TRACE" maxLevel="TRACE" onMatch="ACCEPT" onMismatch="NEUTRAL"/>
    <ThresholdFilter level="INFO" onMatch="DENY" onMismatch="DENY"/>
</Filters>
```

### 接受 TRACE 到 INFO（不包括 WARN/ERROR）

```xml
<Filters>
    <LevelRangeFilter minLevel="TRACE" maxLevel="INFO" onMatch="ACCEPT" onMismatch="DENY"/>
</Filters>
```

## 故障排查

### 日志文件为空

```bash
# 检查过滤器配置
grep -A 5 "AmazonJdbcDebugAsInfo" src/main/resources/log4j2-spring.xml

# 检查 Logger 级别
grep -A 3 "software.amazon.jdbc" src/main/resources/log4j2-spring.xml

# 确认 JDBC URL 中的日志级别
grep "wrapperLoggerLevel" src/main/resources/application.yml
```

### 级别未改变

```bash
# 确认使用了正确的配置文件
ls -la src/main/resources/log4j2-spring.xml

# 检查 Pattern 配置
grep "FILE_LOG_PATTERN_INFO_ONLY" src/main/resources/log4j2-spring.xml

# 重启应用
./restart-app.sh
```

### 性能问题

```bash
# 如果日志量很大，考虑：
# 1. 增加缓冲区大小
# 2. 使用异步 Appender
# 3. 调整滚动策略
```

## 最佳实践

1. **开发环境**: 保留原始日志级别，便于调试
2. **测试环境**: 使用改写后的 INFO 级别，模拟生产环境
3. **生产环境**: 根据监控工具要求选择合适的方案
4. **日志归档**: 定期清理旧日志，避免磁盘空间不足
5. **性能监控**: 监控日志写入性能，必要时使用异步 Appender

## 相关文档

- `LOG_FILES_EXPLAINED.md` - 日志文件说明
- `UNIFIED_LOGGING_GUIDE.md` - 统一日志系统指南
- `PLUGIN_CONFIGURATION.md` - 插件配置说明
