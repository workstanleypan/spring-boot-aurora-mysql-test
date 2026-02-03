# 为什么需要 Rewrite Policy？

## 🎯 核心问题

InfoFile 必须设置 `ThresholdFilter level="INFO"` 来过滤低级别日志，但这会导致 AWS JDBC Wrapper 的 TRACE/DEBUG 日志被过滤掉。

## 📊 Log4j2 处理流程

### 错误的理解（不使用 Rewrite）
```
AWS JDBC Wrapper 产生 DEBUG 日志
    ↓
Logger (software.amazon.jdbc)
    ↓
直接发送到 InfoFile
    ↓
ThresholdFilter level="INFO" ❌ 拒绝 DEBUG
    ↓
日志丢失
```

### 正确的方案（使用 Rewrite）
```
AWS JDBC Wrapper 产生 DEBUG 日志
    ↓
Logger (software.amazon.jdbc)
    ↓
发送到 Rewrite Appender
    ↓
LoggerNameLevelRewritePolicy 重写：DEBUG → INFO
    ↓
转发到 InfoFile
    ↓
ThresholdFilter level="INFO" ✅ 接受 INFO
    ↓
日志成功写入
```

## 🔑 关键点

1. **Filter 在 Appender 级别执行**
   - ThresholdFilter 检查的是日志事件的原始级别
   - 如果不重写，DEBUG 日志会被 INFO filter 拒绝

2. **Rewrite 在 Filter 之前执行**
   - Rewrite Appender 先修改日志级别
   - 然后转发到目标 Appender（InfoFile）
   - InfoFile 的 Filter 看到的是重写后的 INFO 级别

3. **必须保持 InfoFile 的 Filter**
   - 其他 logger 的 DEBUG 日志不应该进入 InfoFile
   - 只有 AWS JDBC Wrapper 的日志需要特殊处理


## 📝 完整配置示例

```xml
<Appenders>
    <!-- InfoFile with INFO ThresholdFilter -->
    <RollingRandomAccessFile name="InfoFile" fileName="${LOG_DIR}/info.log">
        <ThresholdFilter level="INFO" onMatch="ACCEPT" onMismatch="DENY" />
        <PatternLayout pattern="${FILE_LOG_PATTERN}"/>
    </RollingRandomAccessFile>

    <!-- Rewrite Appender for AWS JDBC Wrapper -->
    <Rewrite name="AmazonJdbcRewrite">
        <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
            <KeyValuePair key="TRACE" value="INFO"/>
            <KeyValuePair key="DEBUG" value="INFO"/>
        </LoggerNameLevelRewritePolicy>
        <AppenderRef ref="InfoFile"/>
    </Rewrite>
</Appenders>

<Loggers>
    <!-- AWS JDBC Wrapper Logger -->
    <Logger name="software.amazon.jdbc" level="all" additivity="false">
        <AppenderRef ref="Console"/>
        <AppenderRef ref="AmazonJdbcRewrite"/>  <!-- 通过 Rewrite 发送到 InfoFile -->
        <AppenderRef ref="ErrorFile"/>
    </Logger>
</Loggers>
```

## ✅ 验证方法

启动应用后检查日志：

```bash
# 查看 info.log 中的 AWS JDBC Wrapper 日志
grep "software.amazon.jdbc" logs/info.log

# 应该看到日志显示为 INFO 级别
# 例如：
# 2026-01-16 04:43:10.123 INFO  [12345] --- [main] software.amazon.jdbc.plugin.bg : ...
```

## 🎓 总结

**Rewrite Policy 是必需的**，因为：
- ✅ InfoFile 必须保持 INFO ThresholdFilter（过滤其他 logger 的 DEBUG）
- ✅ AWS JDBC Wrapper 的 DEBUG 需要被记录
- ✅ Rewrite 在 Filter 之前执行，将 DEBUG 重写为 INFO
- ✅ 重写后的日志可以通过 InfoFile 的 Filter

**构建时间**：2026-01-16 04:43:08 UTC  
**状态**：✅ 配置正确
