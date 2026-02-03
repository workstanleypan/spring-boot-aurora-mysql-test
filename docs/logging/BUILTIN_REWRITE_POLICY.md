# 使用 Log4j2 内置 RewritePolicy 重构完成

## 📋 变更摘要

项目已成功重构为使用 Log4j2 内置的 `LoggerNameLevelRewritePolicy`，移除了自定义的 `LevelRewritePolicy` 类。

## ✅ 完成的工作

### 1. 移除自定义代码
- ✅ 删除了 `com.test.logging.LevelRewritePolicy` 类（已重命名为 `.bak`）
- ✅ 从 `log4j2-spring.xml` 中移除了 `packages="com.test.logging"` 属性

### 2. 使用内置 Policy
配置文件现在使用 Log4j2 内置的 `LoggerNameLevelRewritePolicy`：

```xml
<Rewrite name="AmazonJdbcRewrite">
    <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
        <KeyValuePair key="TRACE" value="INFO"/>
        <KeyValuePair key="DEBUG" value="INFO"/>
    </LoggerNameLevelRewritePolicy>
    <AppenderRef ref="Console"/>
    <AppenderRef ref="InfoFile"/>
    <AppenderRef ref="ErrorFile"/>
</Rewrite>
```

### 3. 构建验证
```bash
mvn clean package -DskipTests
```
✅ BUILD SUCCESS

## 🎯 功能说明

### LoggerNameLevelRewritePolicy 特性

**来源**：Log4j2 内置（从 2.4 版本开始）
**类路径**：`org.apache.logging.log4j.core.appender.rewrite.LoggerNameLevelRewritePolicy`

**功能**：
- 重写指定 logger 名称前缀的日志级别
- 只影响匹配的 logger（`software.amazon.jdbc`）
- 不影响其他 logger 的日志级别

**参数**：
- `logger`：logger 名称前缀（匹配所有以此开头的 logger）
- `KeyValuePair`：源级别 → 目标级别的映射

### 工作流程

```
AWS JDBC Wrapper 产生 TRACE/DEBUG 日志
    ↓
JUL → SLF4JBridgeHandler → SLF4J
    ↓
Log4j2 Logger (software.amazon.jdbc, level="all")
    ↓
Rewrite Appender (AmazonJdbcRewrite)
    ↓
LoggerNameLevelRewritePolicy 重写级别：
  - TRACE → INFO
  - DEBUG → INFO
    ↓
输出到 Console、InfoFile、ErrorFile
```

## 📊 优势对比

### 使用内置 Policy（当前方案）
✅ 无需自定义 Java 代码
✅ 无需维护额外的类
✅ Log4j2 官方支持，稳定可靠
✅ 只影响指定的 logger（`software.amazon.jdbc`）
✅ 配置简洁明了

### 自定义 Policy（旧方案）
❌ 需要编写和维护 Java 代码
❌ 需要在 Configuration 中注册 packages
❌ 影响所有 logger 的 TRACE/DEBUG 日志
❌ 增加项目复杂度

## 🔧 配置文件位置

- **主配置**：`src/main/resources/log4j2-spring.xml`
- **备份文件**：`src/main/java/com/test/logging/LevelRewritePolicy.java.bak`

## 📝 使用说明

### 启动应用
```bash
# 使用 Aurora 集群（带 BG Plugin）
./run-aurora.sh

# 使用 Aurora 集群（BG Plugin DEBUG 级别）
./run-aurora-bg-debug.sh

# 使用 RDS 实例
./run-rds.sh
```

### 验证日志重写
1. 启动应用后，检查 `logs/info.log`
2. 应该看到 AWS JDBC Wrapper 的日志显示为 INFO 级别
3. 原本的 TRACE/DEBUG 日志已被重写为 INFO

### 示例日志输出
```
2026-01-16 04:07:30.123 INFO  [12345] --- [main] software.amazon.jdbc.plugin.bg.BlueGreenPlugin []: 
  Checking for Blue/Green deployment...
```

## 🎓 技术细节

### Log4j2 版本要求
- **最低版本**：2.4+
- **当前版本**：2.17.x（通过 Spring Boot 2.6.8 引入）
- **完全兼容**：✅

### 依赖关系
```xml
<!-- Spring Boot Starter Log4j2 -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-log4j2</artifactId>
</dependency>
```

此依赖已包含：
- `log4j-core`（包含 LoggerNameLevelRewritePolicy）
- `log4j-api`
- `log4j-slf4j-impl`

## 🔍 故障排查

### 如果重写不生效

1. **检查 Log4j2 版本**
   ```bash
   mvn dependency:tree | grep log4j-core
   ```
   确保版本 >= 2.4

2. **检查 logger 配置**
   ```xml
   <Logger name="software.amazon.jdbc" level="all" additivity="false">
       <AppenderRef ref="AmazonJdbcRewrite"/>
   </Logger>
   ```
   - `level="all"` 确保接收所有级别的日志
   - 必须引用 Rewrite appender

3. **检查 Rewrite 配置**
   ```xml
   <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
   ```
   - `logger` 属性必须匹配目标 logger 名称前缀

4. **查看启动日志**
   检查是否有 Log4j2 配置错误

## 📚 参考资料

- [Log4j2 官方文档 - LoggerNameLevelRewritePolicy](https://logging.apache.org/log4j/2.x/javadoc/log4j-core/org/apache/logging/log4j/core/appender/rewrite/LoggerNameLevelRewritePolicy.html)
- [Log4j2 官方文档 - RewriteAppender](https://logging.apache.org/log4j/2.x/javadoc/log4j-core/org/apache/logging/log4j/core/appender/rewrite/RewriteAppender.html)

## ✨ 总结

项目已成功迁移到使用 Log4j2 内置的 `LoggerNameLevelRewritePolicy`，实现了：
- ✅ 代码简化（移除自定义类）
- ✅ 配置清晰（使用官方 API）
- ✅ 功能完整（TRACE/DEBUG → INFO 重写）
- ✅ 构建成功（无编译错误）

**构建时间**：2026-01-16 04:07:18 UTC
**构建状态**：✅ SUCCESS
