# TRACE 日志量过大问题分析

## 问题描述

在客户的 Apollo 环境中观察到：
1. **产生了大量额外的 TRACE 级别日志**
2. **只有 `BlueGreenStatusMonitor`，没有 `BlueGreenStatusProvider`**
3. **TRACE 日志量比 Spring Boot 测试环境多很多**

## 根本原因分析

### 1. BlueGreenStatusProvider vs BlueGreenStatusMonitor

**关系：**
```
BlueGreenStatusProvider (主类)
  └── 包含 BlueGreenStatusMonitor[] monitors (监控线程)
```

**代码证据：**
```java
// BlueGreenStatusProvider.java
public class BlueGreenStatusProvider {
  private static final Logger LOGGER = Logger.getLogger(BlueGreenStatusProvider.class.getName());
  
  protected final BlueGreenStatusMonitor[] monitors = { null, null };  // ⭐ 包含监控线程
  // ...
}
```

**为什么只看到 BlueGreenStatusMonitor：**
- `BlueGreenStatusProvider` 是主类，负责管理状态
- `BlueGreenStatusMonitor` 是后台监控线程，**持续运行**
- 监控线程会**频繁输出 TRACE 日志**来报告状态检查

### 2. JUL 桥接配置的关键差异

#### Spring Boot 配置（当前）

**JulBridgeInitializer.java:**
```java
// ❌ 问题：设置 JUL root logger 为 ALL
Logger rootLogger = Logger.getLogger("");
rootLogger.setLevel(Level.ALL);  // ⚠️ 接受所有级别

// ❌ 问题：设置 AWS JDBC logger 为 ALL
Logger awsJdbcLogger = Logger.getLogger("software.amazon.jdbc");
awsJdbcLogger.setLevel(Level.ALL);  // ⚠️ 接受所有级别
```

**结果：**
- JUL 层面：**接受所有日志**（包括 TRACE）
- 所有 TRACE 日志都被转发到 SLF4J
- 即使 Log4j2 配置了 `level="all"`，也会收到大量 TRACE 日志

#### 原始测试配置（MultiThreadBlueGreenTestWithUnifiedLogging.java）

```java
// ✅ 正确：只设置 root logger 为 ALL，让 JDBC URL 控制
Logger rootLogger = Logger.getLogger("");
rootLogger.setLevel(Level.ALL);

// ✅ 关键：通过 JDBC URL 的 wrapperLoggerLevel 控制
String jdbcUrl = String.format(
    "jdbc:aws-wrapper:mysql://%s/%s?" +
    "wrapperPlugins=%s&" +
    "wrapperLoggerLevel=%s",  // ⭐ 单一控制点
    endpoint, DB_NAME, plugins, jdbcLogLevel  // 例如：FINE
);
```

**结果：**
- JUL root logger：接受所有级别
- AWS JDBC Wrapper：**在源头过滤**，只输出 `wrapperLoggerLevel` 指定的级别
- 如果设置为 `FINE`，则不会产生 TRACE 日志

### 3. 为什么 Spring Boot 产生更多 TRACE 日志

**日志流程对比：**

**原始测试（正确）：**
```
CLI: --jdbc-log-level FINE
  ↓
JDBC URL: wrapperLoggerLevel=FINE  ← ⭐ 在源头过滤
  ↓
AWS JDBC Wrapper (JUL) 只输出 FINE 及以上
  ↓
SLF4JBridgeHandler 转发 FINE 日志
  ↓
Log4j2 输出
```

**Spring Boot（问题）：**
```
JUL: Logger.setLevel(ALL)  ← ❌ 接受所有级别
  ↓
AWS JDBC Wrapper (JUL) 输出所有级别（包括 TRACE）
  ↓
SLF4JBridgeHandler 转发所有日志
  ↓
Log4j2 收到大量 TRACE 日志
```

### 4. BlueGreenStatusMonitor 的 TRACE 日志

**监控线程会产生大量 TRACE 日志：**

```java
// BlueGreenStatusMonitor.java
public void run() {
  while (!stopped) {
    try {
      // ⚠️ 每次循环都可能输出 TRACE 日志
      LOGGER.log(Level.FINEST, "Checking Blue/Green status...");
      
      // 检查状态
      checkStatus();
      
      // ⚠️ 更多 TRACE 日志
      LOGGER.log(Level.FINEST, "Status check completed");
      
      // 等待下一次检查
      Thread.sleep(intervalMs);
    } catch (Exception e) {
      // ...
    }
  }
}
```

**频率：**
- Baseline: 每 60 秒
- Increased: 每 1 秒
- High: 每 100 毫秒

**在蓝绿切换期间：**
- 监控频率提高到 High (100ms)
- **每秒产生 10 次 TRACE 日志**
- 如果有多个连接，日志量成倍增加

## 解决方案

### 方案 1: 修复 JulBridgeInitializer（推荐）

**移除显式设置 AWS JDBC logger 级别：**

```java
@Component
public class JulBridgeInitializer implements BeanFactoryPostProcessor {
    
    @Override
    public void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
        cleanupAndInstallBridge();
        configureLoggers();
    }
    
    private void configureLoggers() {
        // ✅ 只设置 root logger 为 ALL
        Logger rootLogger = Logger.getLogger("");
        rootLogger.setLevel(Level.ALL);
        
        // ✅ 不要显式设置 AWS JDBC logger
        // 让 wrapperLoggerLevel 在源头控制
        
        // ❌ 移除这行
        // Logger awsJdbcLogger = Logger.getLogger("software.amazon.jdbc");
        // awsJdbcLogger.setLevel(Level.ALL);
    }
}
```

### 方案 2: 在 application.yml 中控制日志级别

**确保 JDBC URL 包含 wrapperLoggerLevel：**

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://${CLUSTER_ENDPOINT}/${DB_NAME}?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
    #                                                                                                                                                                    ↑
    #                                                                                                                                                    ⭐ 单一控制点
```

**级别说明：**
- `INFO`: 最少日志，只有重要事件
- `FINE`: 推荐级别，包含 BG Plugin 状态
- `FINER`: 详细日志，包含插件执行流程
- `FINEST`: 最详细（TRACE），包含所有调试信息

### 方案 3: 使用环境变量动态控制

```bash
# 设置日志级别
export JDBC_LOG_LEVEL=FINE

# 在 application.yml 中引用
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://${CLUSTER_ENDPOINT}/${DB_NAME}?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=${JDBC_LOG_LEVEL:FINE}
```

## 验证方法

### 1. 检查当前配置

```bash
# 查看 JDBC URL
grep "wrapperLoggerLevel" spring-boot-mysql-test/src/main/resources/application.yml

# 查看 JUL 桥接配置
grep -A 5 "awsJdbcLogger" spring-boot-mysql-test/src/main/java/com/test/config/JulBridgeInitializer.java
```

### 2. 测试日志输出

```bash
# 启动应用
./run-aurora.sh

# 查看日志级别
grep "TRACE" logs/jdbc-wrapper.log | wc -l
grep "DEBUG" logs/jdbc-wrapper.log | wc -l
grep "FINE" logs/jdbc-wrapper.log | wc -l
```

### 3. 对比日志量

**预期结果（修复后）：**
- TRACE 日志：0 行
- DEBUG 日志：少量
- FINE 日志：适量（BG Plugin 状态）

**问题状态（修复前）：**
- TRACE 日志：数千行
- DEBUG 日志：数千行
- FINE 日志：被淹没

## 最佳实践

### 1. 日志级别选择

**生产环境：**
```yaml
wrapperLoggerLevel=INFO  # 最少日志
```

**调试蓝绿切换：**
```yaml
wrapperLoggerLevel=FINE  # 包含 BG Plugin 状态
```

**深度调试：**
```yaml
wrapperLoggerLevel=FINER  # 详细插件执行流程
```

**问题诊断：**
```yaml
wrapperLoggerLevel=FINEST  # 所有调试信息（慎用）
```

### 2. JUL 桥接配置

**正确配置：**
```java
// ✅ 只设置 root logger
Logger rootLogger = Logger.getLogger("");
rootLogger.setLevel(Level.ALL);

// ✅ 不要设置特定 logger 的级别
// 让 wrapperLoggerLevel 控制
```

**错误配置：**
```java
// ❌ 不要这样做
Logger awsJdbcLogger = Logger.getLogger("software.amazon.jdbc");
awsJdbcLogger.setLevel(Level.ALL);  // 会接受所有 TRACE 日志
```

### 3. Log4j2 配置

**保持 level="all"：**
```xml
<!-- ✅ 正确：接受 JUL 转发的日志，但 JUL 已在源头过滤 -->
<Logger name="software.amazon.jdbc" level="all" additivity="false">
    <AppenderRef ref="Console"/>
    <AppenderRef ref="AmazonJdbcRewrite"/>
    <AppenderRef ref="ErrorFile"/>
</Logger>
```

## 总结

### 问题根源
1. **JulBridgeInitializer 设置了 AWS JDBC logger 为 ALL**
2. **导致所有 TRACE 日志都被转发到 SLF4J**
3. **BlueGreenStatusMonitor 监控线程产生大量 TRACE 日志**

### 解决方案
1. **移除 JulBridgeInitializer 中的 AWS JDBC logger 设置**
2. **只通过 JDBC URL 的 wrapperLoggerLevel 控制**
3. **推荐使用 FINE 级别进行蓝绿切换调试**

### 验证标准
- ✅ 没有 TRACE 日志输出
- ✅ 只有 wrapperLoggerLevel 指定级别的日志
- ✅ 日志量可控，不会淹没重要信息
