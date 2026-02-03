# DEBUG 日志转 INFO - 最终解决方案

## 当前状况

✅ **已实现**: `jdbc-wrapper-info.log` 现在接受所有级别的日志（包括 DEBUG/TRACE），并以 INFO 级别显示

## 验证

```bash
# 查看 jdbc-wrapper-info.log，应该包含 DEBUG 日志但显示为 INFO
tail -f logs/jdbc-wrapper-info.log

# 对比：jdbc-wrapper.log 显示原始级别
tail -f logs/jdbc-wrapper.log | grep DEBUG
```

## 配置说明

在 `log4j2-spring.xml` 中，`AmazonJdbcInfoFile` 已配置为：

```xml
<RollingRandomAccessFile name="AmazonJdbcInfoFile"
                         fileName="${LOG_DIR}/jdbc-wrapper-info.log"
                         filePattern="${LOG_DIR}/archive/history_jdbc_wrapper_info.%d{yyyy-MM-dd}.%i.zip">
    <!-- No ThresholdFilter - accepts DEBUG/TRACE too -->
    <!-- Use INFO-only pattern to display all logs as INFO level -->
    <PatternLayout pattern="${FILE_LOG_PATTERN_INFO_ONLY}" charset="${CHARSET}"/>
    ...
</RollingRandomAccessFile>
```

其中 `FILE_LOG_PATTERN_INFO_ONLY` 定义为：

```xml
<Property name="FILE_LOG_PATTERN_INFO_ONLY">
    %d{yyyy-MM-dd HH:mm:ss.SSS} INFO  [%X{X-RequestID}] %pid --- [%t] %-40.40c{1.} [%traceId]: %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}
</Property>
```

## 结果

| 文件 | 内容 | 级别显示 |
|------|------|----------|
| `jdbc-wrapper.log` | 所有日志 (TRACE/DEBUG/INFO/WARN/ERROR) | 原始级别 |
| `jdbc-wrapper-info.log` | 所有日志 (包括 DEBUG/TRACE) | **全部显示为 INFO** ✅ |

## 使用场景

这个配置适合：
- 日志分析工具只接受 INFO 级别
- 需要统一日志级别但保留 DEBUG 内容
- 生产环境监控

## 如果需要只包含 DEBUG/TRACE

如果你只想要 DEBUG/TRACE 日志（不要 INFO 及以上），可以创建另一个 Appender：

```xml
<RollingRandomAccessFile name="DebugOnlyAsInfo"
                         fileName="${LOG_DIR}/debug-only-as-info.log"
                         filePattern="${LOG_DIR}/archive/debug_only_as_info.%d{yyyy-MM-dd}.%i.zip">
    <!-- Only accept DEBUG and below, deny INFO and above -->
    <ThresholdFilter level="INFO" onMatch="DENY" onMismatch="ACCEPT"/>
    <!-- Display as INFO -->
    <PatternLayout pattern="${FILE_LOG_PATTERN_INFO_ONLY}" charset="${CHARSET}"/>
    ...
</RollingRandomAccessFile>
```

然后在 Logger 中添加：

```xml
<Logger name="software.amazon.jdbc" level="all" additivity="false">
    <AppenderRef ref="DebugOnlyAsInfo"/>
    ...
</Logger>
```

## 总结

✅ **目标已达成**: DEBUG 日志现在可以以 INFO 级别写入 `jdbc-wrapper-info.log`

查看日志：
```bash
tail -f logs/jdbc-wrapper-info.log
```

所有日志都显示为 INFO 级别，包括原本的 DEBUG 和 TRACE 日志！
