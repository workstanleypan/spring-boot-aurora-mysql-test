# 日志文件说明

## 日志文件列表

应用会生成以下日志文件：

| 文件 | 内容 | 级别过滤 | 用途 |
|------|------|----------|------|
| `info.log` | 所有应用的 INFO+ 日志 | INFO, WARN, ERROR | 查看应用整体运行情况 |
| `jdbc-wrapper.log` | JDBC Wrapper 所有级别日志 | TRACE, DEBUG, INFO, WARN, ERROR | 查看 Wrapper 详细执行流程 |
| `jdbc-wrapper-info.log` | JDBC Wrapper 所有级别日志（副本） | ALL（无过滤） | 包含 DEBUG 级别的完整日志 |
| `error.log` | 所有错误日志 | ERROR | 快速查看错误 |
| `spring-boot.log` | Spring Boot 框架日志 | INFO+ | Spring 框架相关日志 |

## 日志文件详细说明

### 1. info.log

**内容**: 应用的所有 INFO 及以上级别的日志

**包含**:
- Spring Boot 启动信息
- 应用业务日志（INFO+）
- Druid 连接池日志（INFO+）
- 其他组件的 INFO+ 日志

**不包含**:
- DEBUG 级别日志
- TRACE 级别日志
- JDBC Wrapper 的 DEBUG 日志（被过滤）

**适用场景**:
- 查看应用整体运行情况
- 生产环境日志分析
- 快速了解应用状态

**查看命令**:
```bash
# 实时查看
tail -f logs/info.log

# 查看最近 50 行
tail -50 logs/info.log

# 搜索错误
grep -i error logs/info.log
```

### 2. jdbc-wrapper.log

**内容**: JDBC Wrapper 的所有级别日志（TRACE 到 ERROR）

**包含**:
- TRACE 级别：连接打开、属性配置
- DEBUG 级别：Plugin 执行细节
- INFO 级别：基本信息
- WARN 级别：警告信息（如 BG Plugin 不支持）
- ERROR 级别：错误信息

**适用场景**:
- 调试 JDBC Wrapper 问题
- 查看 Plugin 执行流程
- 分析连接问题

**查看命令**:
```bash
# 实时查看
tail -f logs/jdbc-wrapper.log

# 查找 BG Plugin 日志
grep -i "blue.*green\|BlueGreen" logs/jdbc-wrapper.log

# 查找 TRACE 日志
grep "TRACE" logs/jdbc-wrapper.log

# 查找连接相关日志
grep -i "connect" logs/jdbc-wrapper.log
```

### 3. jdbc-wrapper-info.log ⭐ 新增

**内容**: JDBC Wrapper 的所有级别日志（完整副本，无过滤）

**特点**:
- 与 `jdbc-wrapper.log` 内容相同
- 没有 ThresholdFilter，确保所有级别都被记录
- 包含 DEBUG 级别的完整日志

**为什么需要这个文件？**

原来的配置中，`software.amazon.jdbc` Logger 引用了 `InfoFile`，但 `InfoFile` 有 `ThresholdFilter level="INFO"`，会过滤掉 DEBUG 级别的日志。

为了在一个"info"类型的文件中也能看到 DEBUG 级别的 JDBC Wrapper 日志，我们创建了这个专门的文件。

**适用场景**:
- 需要完整的 JDBC Wrapper 日志
- 确保 DEBUG 级别日志不被过滤
- 与其他系统集成时需要完整日志

**查看命令**:
```bash
# 实时查看
tail -f logs/jdbc-wrapper-info.log

# 对比两个文件（应该相同）
diff logs/jdbc-wrapper.log logs/jdbc-wrapper-info.log
```

### 4. error.log

**内容**: 所有组件的 ERROR 级别日志

**包含**:
- 应用错误
- JDBC Wrapper 错误
- Spring Boot 错误
- 其他组件错误

**适用场景**:
- 快速查看所有错误
- 生产环境问题排查
- 错误统计和分析

**查看命令**:
```bash
# 实时查看
tail -f logs/error.log

# 统计错误数量
wc -l logs/error.log

# 查看最近的错误
tail -20 logs/error.log
```

### 5. spring-boot.log

**内容**: Spring Boot 框架相关日志

**包含**:
- Spring 容器启动日志
- Bean 初始化日志
- Web 服务器日志
- Spring 框架内部日志

**适用场景**:
- 调试 Spring 配置问题
- 查看 Bean 加载情况
- 分析 Spring 框架问题

**查看命令**:
```bash
# 实时查看
tail -f logs/spring-boot.log

# 查找 Bean 相关日志
grep -i bean logs/spring-boot.log
```

## 日志级别映射

### JUL (Java Util Logging) → Log4j2

JDBC Wrapper 使用 JUL，通过 SLF4JBridgeHandler 桥接到 Log4j2：

| JUL 级别 | Log4j2 级别 | 说明 |
|----------|-------------|------|
| FINEST | TRACE | 最详细的日志 |
| FINER | TRACE | 非常详细的日志 |
| **FINE** | **DEBUG** | **详细的执行流程（推荐开发环境）** |
| CONFIG | DEBUG | 配置信息 |
| **INFO** | **INFO** | **基本信息（推荐生产环境）** |
| WARNING | WARN | 警告信息 |
| SEVERE | ERROR | 错误信息 |

## 日志配置对比

### software.amazon.jdbc Logger 配置

```xml
<Logger name="software.amazon.jdbc" level="all" additivity="false">
    <AppenderRef ref="AmazonJdbcConsole"/>      <!-- 控制台：所有级别 -->
    <AppenderRef ref="AmazonJdbcFile"/>         <!-- jdbc-wrapper.log：TRACE+ -->
    <AppenderRef ref="AmazonJdbcInfoFile"/>     <!-- jdbc-wrapper-info.log：所有级别（无过滤） -->
    <AppenderRef ref="ErrorFile"/>              <!-- error.log：ERROR -->
</Logger>
```

### 各 Appender 的过滤规则

| Appender | ThresholdFilter | 接受的级别 |
|----------|----------------|-----------|
| AmazonJdbcConsole | 无 | ALL |
| AmazonJdbcFile | TRACE | TRACE, DEBUG, INFO, WARN, ERROR |
| **AmazonJdbcInfoFile** | **无** | **ALL（包括 DEBUG）** |
| ErrorFile | ERROR | ERROR |
| InfoFile | INFO | INFO, WARN, ERROR |

## 日志文件大小和归档

### 配置

```xml
<Policies>
    <TimeBasedTriggeringPolicy/>              <!-- 每天滚动 -->
    <SizeBasedTriggeringPolicy size="500 MB"/> <!-- 超过 500MB 滚动 -->
</Policies>
<DefaultRolloverStrategy max="7">             <!-- 保留 7 个归档文件 -->
    <Delete basePath="${LOG_DIR}/archive" maxDepth="2">
        <IfFileName glob="history_*"/>
        <IfLastModified age="1d"/>            <!-- 删除 1 天前的文件 -->
    </Delete>
</DefaultRolloverStrategy>
```

### 归档文件位置

```
logs/archive/
├── history_info.2026-01-13.1.zip
├── history_jdbc_wrapper.2026-01-13.1.zip
├── history_jdbc_wrapper_info.2026-01-13.1.zip
├── history_error.2026-01-13.1.zip
└── spring-boot-2026-01-13.1.zip
```

## 常用日志查看命令

### 实时监控

```bash
# 监控所有日志
tail -f logs/info.log

# 监控 JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# 监控错误日志
tail -f logs/error.log

# 同时监控多个文件
tail -f logs/info.log logs/jdbc-wrapper.log logs/error.log
```

### 搜索和过滤

```bash
# 搜索 BG Plugin 相关日志
grep -i "blue.*green\|BlueGreen" logs/jdbc-wrapper.log

# 搜索错误
grep -i error logs/info.log

# 搜索特定时间段的日志
grep "2026-01-14 03:" logs/info.log

# 统计日志行数
wc -l logs/*.log
```

### 日志分析

```bash
# 查看最近 100 行
tail -100 logs/info.log

# 查看前 100 行
head -100 logs/info.log

# 查看特定行范围
sed -n '100,200p' logs/info.log

# 统计错误数量
grep -c ERROR logs/info.log
```

## 日志级别选择建议

### 生产环境

```yaml
# application.yml
wrapperLoggerLevel: INFO
```

**原因**:
- 减少日志量
- 提高性能
- 只记录重要信息

**日志文件**:
- `info.log`: 应用整体日志
- `jdbc-wrapper-info.log`: JDBC Wrapper INFO+ 日志
- `error.log`: 错误日志

### 开发环境

```yaml
# application.yml
wrapperLoggerLevel: FINE
```

**原因**:
- 详细的执行流程
- 便于调试问题
- 可以看到 Plugin 执行细节

**日志文件**:
- `jdbc-wrapper.log`: 包含 DEBUG 级别的详细日志
- `jdbc-wrapper-info.log`: 完整的 JDBC Wrapper 日志

### 问题排查

```yaml
# application.yml
wrapperLoggerLevel: FINEST
```

**原因**:
- 最详细的日志
- 可以看到所有内部细节
- 用于复杂问题排查

**注意**: 日志量会非常大，只在必要时使用

## 总结

### 关键点

1. ✅ `jdbc-wrapper-info.log` 是新增的文件，包含所有级别的 JDBC Wrapper 日志
2. ✅ 没有 ThresholdFilter，确保 DEBUG 级别不被过滤
3. ✅ 与 `jdbc-wrapper.log` 内容相同，但配置更明确
4. ✅ 所有日志文件都会自动归档和清理

### 推荐使用

- **日常开发**: 查看 `jdbc-wrapper.log` 或 `jdbc-wrapper-info.log`
- **生产监控**: 查看 `info.log` 和 `error.log`
- **问题排查**: 查看 `jdbc-wrapper.log` 和 `error.log`
- **BG Plugin 调试**: 在 `jdbc-wrapper.log` 中搜索 "BlueGreen"

### 相关文档

- [log4j2-spring.xml](src/main/resources/log4j2-spring.xml) - 日志配置文件
- [查看BG_Plugin日志.md](查看BG_Plugin日志.md) - BG Plugin 日志查看指南
- [README.md](README.md) - 项目主文档
