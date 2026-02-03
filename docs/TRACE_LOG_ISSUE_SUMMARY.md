# TRACE 日志问题总结

## 问题发现

在客户的 Apollo 环境中发现：
1. 产生了大量 TRACE 级别日志
2. 只看到 `BlueGreenStatusMonitor`，没有 `BlueGreenStatusProvider`
3. 日志量比 Spring Boot 测试环境多很多

## 根本原因

### 1. BlueGreenStatusProvider vs BlueGreenStatusMonitor

```
BlueGreenStatusProvider (主类)
  └── BlueGreenStatusMonitor[] monitors (监控线程)
```

- `BlueGreenStatusProvider` 是主类，管理蓝绿状态
- `BlueGreenStatusMonitor` 是后台监控线程，**持续运行**
- 监控线程在蓝绿切换期间每 100ms 检查一次状态
- 每次检查都会产生 TRACE 日志

### 2. JUL 桥接配置错误

**问题代码（已修复）：**
```java
// ❌ 错误：显式设置 AWS JDBC logger 为 ALL
Logger awsJdbcLogger = Logger.getLogger("software.amazon.jdbc");
awsJdbcLogger.setLevel(Level.ALL);  // 接受所有 TRACE 日志
```

**正确做法：**
```java
// ✅ 正确：只设置 root logger
Logger rootLogger = Logger.getLogger("");
rootLogger.setLevel(Level.ALL);

// ✅ 不设置 AWS JDBC logger
// 让 wrapperLoggerLevel 在 JDBC URL 中控制
```

### 3. 日志流程对比

**错误流程（修复前）：**
```
JUL: awsJdbcLogger.setLevel(ALL)
  ↓
AWS JDBC Wrapper 输出所有级别（包括 TRACE）
  ↓
SLF4JBridgeHandler 转发所有日志
  ↓
Log4j2 收到大量 TRACE 日志
```

**正确流程（修复后）：**
```
JDBC URL: wrapperLoggerLevel=FINE
  ↓
AWS JDBC Wrapper 只输出 FINE 及以上
  ↓
SLF4JBridgeHandler 转发 FINE 日志
  ↓
Log4j2 收到适量日志
```

## 已实施的修复

### 1. 更新 JulBridgeInitializer.java ✅

**移除了：**
```java
Logger awsJdbcLogger = Logger.getLogger(AWS_JDBC_PACKAGE);
awsJdbcLogger.setLevel(Level.ALL);
```

**添加了说明：**
```java
// ⭐ DO NOT set AWS JDBC logger level here
// Let wrapperLoggerLevel in JDBC URL control it at the source
// This prevents excessive TRACE logs from BlueGreenStatusMonitor
```

### 2. 创建了文档 ✅

- `TRACE_LOG_ISSUE_ANALYSIS.md` - 详细问题分析
- `TRACE_LOG_FIX_GUIDE.md` - 快速修复指南
- `TRACE_LOG_ISSUE_SUMMARY.md` - 本文档

## 验证方法

### 1. 检查配置

```bash
# 确认 JDBC URL 包含 wrapperLoggerLevel
grep "wrapperLoggerLevel" spring-boot-mysql-test/src/main/resources/application.yml
```

### 2. 重新编译

```bash
cd spring-boot-mysql-test
mvn clean compile
```

### 3. 启动测试

```bash
./run-aurora.sh
```

### 4. 验证日志

```bash
# 应该没有 TRACE 日志
grep "TRACE" logs/jdbc-wrapper.log | wc -l

# 应该有适量 FINE 日志
grep "FINE" logs/jdbc-wrapper.log | wc -l
```

## 推荐配置

### 调试蓝绿切换

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://${CLUSTER_ENDPOINT}/${DB_NAME}?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

### 生产环境

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://${CLUSTER_ENDPOINT}/${DB_NAME}?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=INFO
```

## 日志级别说明

| 级别 | JUL | 用途 | 日志量 |
|------|-----|------|--------|
| SEVERE | ERROR | 严重错误 | 最少 |
| WARNING | WARN | 警告 | 少 |
| INFO | INFO | 一般信息 | 适中 |
| FINE | DEBUG | 调试信息 | 较多 ⭐ |
| FINER | DEBUG | 详细调试 | 多 |
| FINEST | TRACE | 完整调试 | 非常多 ⚠️ |

## 关键要点

### ✅ 正确做法

1. **只在 JDBC URL 中设置 `wrapperLoggerLevel`**
2. **不要在 JUL 中显式设置 AWS JDBC logger 级别**
3. **使用 FINE 级别进行蓝绿切换调试**
4. **生产环境使用 INFO 级别**

### ❌ 错误做法

1. **在 JUL 中设置 `awsJdbcLogger.setLevel(Level.ALL)`**
2. **使用 FINEST 级别（除非必要）**
3. **忽略 `wrapperLoggerLevel` 参数**

## 影响

### 修复前

- 日志文件快速增长（GB/小时）
- 大量 TRACE 日志淹没重要信息
- 难以找到关键的 BG Plugin 状态
- 性能影响（日志 I/O）

### 修复后

- 日志量可控（MB/小时）
- 只有重要的 FINE 级别日志
- 清晰的 BG Plugin 状态信息
- 性能正常

## 相关问题

### Q: 为什么原始测试没有这个问题？

**A:** 原始测试通过 CLI 参数和 JDBC URL 控制日志级别，没有在 JUL 中显式设置 logger 级别。

### Q: 为什么 Log4j2 的 level="all" 不够？

**A:** Log4j2 的 `level="all"` 只是接受 SLF4J 转发的日志，但如果 JUL 层面已经接受了所有 TRACE 日志，Log4j2 也会收到。

### Q: 如何在不重启的情况下调整日志级别？

**A:** 目前需要重启应用。未来可以考虑：
- JMX 动态调整
- Spring Boot Actuator 端点
- 配置中心动态刷新

## 总结

**问题：** JUL 桥接配置错误，导致接受所有 TRACE 日志

**修复：** 移除 JUL 中的 AWS JDBC logger 设置，只通过 JDBC URL 控制

**验证：** 重新编译、启动、检查日志量

**推荐：** 使用 `wrapperLoggerLevel=FINE` 进行蓝绿切换调试
