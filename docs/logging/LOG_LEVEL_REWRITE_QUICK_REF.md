# Log Level Rewrite - 快速参考

## 问题
需要将 AWS JDBC Wrapper 的 DEBUG/TRACE 日志以 INFO 级别写入文件。

## 解决方案对比

| 方案 | 复杂度 | 性能 | 真实级别改变 | 推荐场景 |
|------|--------|------|--------------|----------|
| 方案1: 固定Pattern | ⭐ 简单 | ⭐⭐⭐ 最快 | ❌ 否 | 开发/测试 |
| 方案2: RewritePolicy | ⭐⭐ 中等 | ⭐⭐ 较快 | ✅ 是 | 生产环境 |
| 方案3: MapRewritePolicy | ⭐⭐⭐ 复杂 | ⭐ 较慢 | ✅ 是 | 特殊需求 |

## 快速使用

### 方案1: 固定Pattern（推荐）

```bash
# 1. 使用预配置文件
cd spring-boot-mysql-test
cp src/main/resources/log4j2-spring-with-level-rewrite.xml \
   src/main/resources/log4j2-spring.xml

# 2. 重启应用
./restart-app.sh

# 3. 查看结果
tail -f logs/jdbc-wrapper-debug-as-info.log
# 所有日志都显示为 INFO
```

### 方案2: RewritePolicy（高级）

```bash
# 1. 使用 RewritePolicy 配置
cd spring-boot-mysql-test
cp src/main/resources/log4j2-spring-with-rewrite-policy.xml \
   src/main/resources/log4j2-spring.xml

# 2. 确保 LevelRewritePolicy.java 已编译
mvn clean package -DskipTests

# 3. 重启应用
./restart-app.sh

# 4. 查看结果
tail -f logs/jdbc-wrapper-debug-as-info.log
# 日志级别真正改为 INFO
```

## 配置要点

### 方案1配置片段

```xml
<Properties>
    <!-- 固定显示 INFO 的 Pattern -->
    <Property name="FILE_LOG_PATTERN_INFO_ONLY">
        %d{yyyy-MM-dd HH:mm:ss.SSS} INFO  [%X{X-RequestID}] %pid --- [%t] %-40.40c{1.} [%traceId]: %m%n
    </Property>
</Properties>

<Appenders>
    <RollingRandomAccessFile name="AmazonJdbcDebugAsInfo"
                             fileName="${LOG_DIR}/jdbc-wrapper-debug-as-info.log">
        <!-- 只接受 DEBUG/TRACE -->
        <Filters>
            <LevelRangeFilter minLevel="DEBUG" maxLevel="DEBUG" onMatch="ACCEPT" onMismatch="NEUTRAL"/>
            <LevelRangeFilter minLevel="TRACE" maxLevel="TRACE" onMatch="ACCEPT" onMismatch="NEUTRAL"/>
            <ThresholdFilter level="INFO" onMatch="DENY" onMismatch="DENY"/>
        </Filters>
        <!-- 使用固定 INFO 的 Pattern -->
        <PatternLayout pattern="${FILE_LOG_PATTERN_INFO_ONLY}"/>
    </RollingRandomAccessFile>
</Appenders>
```

### 方案2配置片段

```xml
<!-- 在 Configuration 标签中添加 packages 属性 -->
<Configuration packages="com.test.logging">

<Appenders>
    <!-- Rewrite Appender -->
    <Rewrite name="RewriteDebugToInfo">
        <LevelRewritePolicy targetLevel="INFO" minLevel="TRACE" maxLevel="DEBUG"/>
        <AppenderRef ref="AmazonJdbcDebugAsInfoFile"/>
    </Rewrite>
    
    <RollingRandomAccessFile name="AmazonJdbcDebugAsInfoFile"
                             fileName="${LOG_DIR}/jdbc-wrapper-debug-as-info.log">
        <!-- 只接受 DEBUG/TRACE -->
        <Filters>
            <LevelRangeFilter minLevel="TRACE" maxLevel="DEBUG" onMatch="ACCEPT" onMismatch="DENY"/>
        </Filters>
        <PatternLayout pattern="${FILE_LOG_PATTERN}"/>
    </RollingRandomAccessFile>
</Appenders>

<Loggers>
    <Logger name="software.amazon.jdbc" level="all" additivity="false">
        <AppenderRef ref="RewriteDebugToInfo"/>
    </Logger>
</Loggers>
```

## 测试

```bash
# 自动测试
cd spring-boot-mysql-test
./test-level-rewrite.sh pattern   # 测试方案1
./test-level-rewrite.sh policy    # 测试方案2

# 手动验证
# 1. 启动应用
./run-aurora-bg-debug.sh

# 2. 生成日志
curl http://localhost:8080/api/test

# 3. 对比日志
echo "=== 原始日志 (jdbc-wrapper.log) ==="
grep -E " (DEBUG|TRACE) " logs/jdbc-wrapper.log | head -3

echo "=== 改写后日志 (jdbc-wrapper-debug-as-info.log) ==="
grep " INFO " logs/jdbc-wrapper-debug-as-info.log | head -3
```

## 生成的日志文件

| 文件 | 内容 | 级别 |
|------|------|------|
| `jdbc-wrapper.log` | 所有日志 | 原始级别 (TRACE/DEBUG/INFO/...) |
| `jdbc-wrapper-info.log` | INFO及以上 | 原始级别 (INFO/WARN/ERROR) |
| `jdbc-wrapper-debug-as-info.log` | DEBUG/TRACE | 显示/改写为 INFO |

## 验证成功标准

```bash
# 原始文件应该有 DEBUG/TRACE
grep -c " DEBUG " logs/jdbc-wrapper.log
# 输出: > 0

# 改写文件应该只有 INFO
grep -c " INFO " logs/jdbc-wrapper-debug-as-info.log
# 输出: > 0

grep -c " DEBUG " logs/jdbc-wrapper-debug-as-info.log
# 输出: 0
```

## 常见问题

### Q: 改写文件为空？
```bash
# 检查过滤器配置
grep -A 5 "AmazonJdbcDebugAsInfo" src/main/resources/log4j2-spring.xml

# 确认 JDBC URL 中设置了 DEBUG 级别
grep "wrapperLoggerLevel" src/main/resources/application.yml
# 应该是: FINE 或 FINER
```

### Q: 日志级别没有改变？
```bash
# 方案1: 检查 Pattern
grep "FILE_LOG_PATTERN_INFO_ONLY" src/main/resources/log4j2-spring.xml

# 方案2: 检查 RewritePolicy 是否加载
grep "packages=" src/main/resources/log4j2-spring.xml
# 应该包含: packages="com.test.logging"

# 重新编译
mvn clean package -DskipTests
```

### Q: 性能影响？
- 方案1: 几乎无影响（只改变显示格式）
- 方案2: 轻微影响（需要创建新 LogEvent）
- 建议: 开发用方案1，生产根据需求选择

## 回滚

```bash
# 恢复原始配置
cd spring-boot-mysql-test
cp src/main/resources/log4j2-spring.xml.bak \
   src/main/resources/log4j2-spring.xml

# 重启应用
./restart-app.sh
```

## 相关文档

- 详细指南: `LOG_LEVEL_REWRITE_GUIDE.md`
- 日志说明: `LOG_FILES_EXPLAINED.md`
- 测试脚本: `test-level-rewrite.sh`
