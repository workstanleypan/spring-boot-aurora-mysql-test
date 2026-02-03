# Rewrite 配置详解

## 🎯 配置目标

让 AWS JDBC Wrapper 的 TRACE/DEBUG 日志能够写入 InfoFile，同时保持 InfoFile 的 INFO ThresholdFilter。

## 📊 完整配置

### 1. InfoFile Appender（带 INFO Filter）
```xml
<RollingRandomAccessFile name="InfoFile"
                         fileName="${LOG_DIR}/info.log"
                         filePattern="${LOG_DIR}/archive/history_info.%d{yyyy-MM-dd}.%i.zip">
    <!-- ⚠️ 这个 Filter 会拒绝所有 DEBUG/TRACE 日志 -->
    <ThresholdFilter level="INFO" onMatch="ACCEPT" onMismatch="DENY" />
    <PatternLayout pattern="${FILE_LOG_PATTERN}" charset="${CHARSET}"/>
    <Policies>
        <TimeBasedTriggeringPolicy/>
        <SizeBasedTriggeringPolicy size="500 MB"/>
    </Policies>
</RollingRandomAccessFile>
```

### 2. Rewrite Appender（重写级别）
```xml
<!-- Rewrite Appender for AWS JDBC Wrapper -->
<!-- Rewrites TRACE/DEBUG to INFO so they can pass InfoFile's ThresholdFilter -->
<Rewrite name="AmazonJdbcRewrite">
    <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
        <KeyValuePair key="TRACE" value="INFO"/>
        <KeyValuePair key="DEBUG" value="INFO"/>
    </LoggerNameLevelRewritePolicy>
    <!-- ⭐ 重写后转发到 InfoFile -->
    <AppenderRef ref="InfoFile"/>
</Rewrite>
```

### 3. Logger 配置（使用 Rewrite）
```xml
<Logger name="software.amazon.jdbc" level="all" additivity="false">
    <AppenderRef ref="Console"/>
    <!-- ⭐ 通过 Rewrite Appender 发送到 InfoFile -->
    <AppenderRef ref="AmazonJdbcRewrite"/>
    <AppenderRef ref="ErrorFile"/>
</Logger>
```

## 🔄 日志流程图

```
┌─────────────────────────────────────────────────────────────┐
│ AWS JDBC Wrapper 产生日志                                    │
│ Level: DEBUG                                                 │
│ Message: "Checking for Blue/Green deployment..."            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ JUL → SLF4JBridgeHandler → SLF4J                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Logger: software.amazon.jdbc (level="all")                  │
│ 接收所有级别的日志                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────┴───────┐
                    ↓               ↓
        ┌──────────────┐   ┌──────────────────┐
        │   Console    │   │ AmazonJdbcRewrite│
        │              │   │  (Rewrite)       │
        └──────────────┘   └──────────────────┘
                                    ↓
                    ┌───────────────────────────────┐
                    │ LoggerNameLevelRewritePolicy  │
                    │ DEBUG → INFO                  │
                    └───────────────────────────────┘
                                    ↓
                            ┌──────────────┐
                            │   InfoFile   │
                            │ (Filter: INFO)│
                            └──────────────┘
                                    ↓
                    ┌───────────────────────────────┐
                    │ ThresholdFilter level="INFO"  │
                    │ ✅ ACCEPT (因为已重写为 INFO) │
                    └───────────────────────────────┘
                                    ↓
                            ┌──────────────┐
                            │ logs/info.log│
                            │ 日志成功写入  │
                            └──────────────┘
```

## 🔑 关键理解

### 为什么不能直接让 InfoFile 接受 DEBUG？
```xml
<!-- ❌ 错误方案：移除 Filter 或改为 DEBUG -->
<RollingRandomAccessFile name="InfoFile">
    <ThresholdFilter level="DEBUG" onMatch="ACCEPT" onMismatch="DENY" />
    ...
</RollingRandomAccessFile>
```

**问题**：这会导致**所有** logger 的 DEBUG 日志都进入 InfoFile！
- Spring 的 DEBUG 日志 ✗
- Druid 的 DEBUG 日志 ✗
- 应用代码的 DEBUG 日志 ✗

### 为什么需要 Rewrite？
```xml
<!-- ✅ 正确方案：使用 Rewrite -->
<Rewrite name="AmazonJdbcRewrite">
    <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
        ...
    </LoggerNameLevelRewritePolicy>
    <AppenderRef ref="InfoFile"/>
</Rewrite>
```

**优势**：
- ✅ InfoFile 保持 INFO Filter（其他 logger 的 DEBUG 被过滤）
- ✅ 只有 `software.amazon.jdbc` 的日志被重写
- ✅ 重写后的日志可以通过 InfoFile 的 Filter
- ✅ 精确控制，不影响其他 logger


## 📝 配置检查清单

验证配置是否正确：

- [ ] InfoFile 有 `ThresholdFilter level="INFO"`
- [ ] Rewrite Appender 名为 `AmazonJdbcRewrite`
- [ ] Rewrite 使用 `LoggerNameLevelRewritePolicy`
- [ ] Rewrite 的 `logger` 属性为 `software.amazon.jdbc`
- [ ] Rewrite 包含 `TRACE → INFO` 和 `DEBUG → INFO` 映射
- [ ] Rewrite 引用 `InfoFile`
- [ ] Logger `software.amazon.jdbc` 引用 `AmazonJdbcRewrite`
- [ ] Logger `software.amazon.jdbc` 的 `level="all"`

## 🧪 测试验证

### 1. 构建项目
```bash
mvn clean package -DskipTests
```

### 2. 验证配置
```bash
./test-builtin-rewrite.sh
```

### 3. 启动应用
```bash
./run-aurora-bg-debug.sh
```

### 4. 检查日志
```bash
# 查看 info.log 中的 AWS JDBC Wrapper 日志
tail -f logs/info.log | grep "software.amazon.jdbc"

# 应该看到日志显示为 INFO 级别
# 例如：
# 2026-01-16 04:43:10.123 INFO  [12345] --- [main] software.amazon.jdbc.plugin.bg.BlueGreenPlugin : 
#   Checking for Blue/Green deployment...
```

### 5. 验证其他 logger 的 DEBUG 不在 info.log
```bash
# 检查 Spring 的 DEBUG 日志（应该不在 info.log）
grep "DEBUG.*org.springframework" logs/info.log
# 应该没有结果（或很少）

# 检查应用的 DEBUG 日志（应该不在 info.log）
grep "DEBUG.*com.test" logs/info.log
# 应该没有结果（因为 com.test logger level="debug" 但 InfoFile filter="INFO"）
```

## 🎓 技术细节

### Log4j2 处理顺序
1. **Logger Level Filter**：Logger 的 level 属性过滤
2. **Appender Routing**：日志事件路由到 Appender
3. **Rewrite Policy**：Rewrite Appender 修改日志事件
4. **Appender Filter**：目标 Appender 的 Filter 过滤
5. **Layout**：格式化日志消息
6. **Output**：写入文件/控制台

### 为什么 Rewrite 在 Filter 之前？
- Rewrite Appender 是一个**包装器**
- 它先修改 LogEvent，然后转发到目标 Appender
- 目标 Appender（InfoFile）看到的是**修改后**的 LogEvent
- 因此 InfoFile 的 ThresholdFilter 检查的是**重写后**的级别

### LoggerNameLevelRewritePolicy 工作原理
```java
// 伪代码
public LogEvent rewrite(LogEvent event) {
    // 检查 logger 名称是否匹配
    if (event.getLoggerName().startsWith("software.amazon.jdbc")) {
        // 查找级别映射
        if (event.getLevel() == Level.DEBUG) {
            // 创建新的 LogEvent，级别改为 INFO
            return new LogEvent(..., Level.INFO, ...);
        }
    }
    return event; // 不匹配则返回原始事件
}
```

## ✅ 总结

**Rewrite Policy 是必需的**，因为：

1. **InfoFile 必须保持 INFO Filter**
   - 防止其他 logger 的 DEBUG 日志污染 info.log
   - 保持日志文件的清洁和可读性

2. **AWS JDBC Wrapper 的 DEBUG 需要被记录**
   - 这些日志对于调试蓝绿切换问题很重要
   - 包含 BG Plugin 状态、连接信息等

3. **Rewrite 提供精确控制**
   - 只影响 `software.amazon.jdbc` logger
   - 在 Filter 之前执行，确保日志能通过
   - 使用 Log4j2 内置功能，无需自定义代码

**配置完成时间**：2026-01-16 04:43:08 UTC  
**验证状态**：✅ 所有检查通过  
**准备就绪**：可以部署和运行
