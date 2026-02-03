# Log Level Rewrite - 编译成功 ✅

## 状态

✅ **方案2 (RewritePolicy) 编译成功！**

```bash
[INFO] BUILD SUCCESS
[INFO] Total time:  4.682 s
```

## 快速使用

### 方案1: 固定Pattern（最简单）

```bash
cd spring-boot-mysql-test

# 使用方案1配置
cp src/main/resources/log4j2-spring-with-level-rewrite.xml \
   src/main/resources/log4j2-spring.xml

# 重启应用
./restart-app.sh
```

### 方案2: RewritePolicy（已编译成功）

```bash
cd spring-boot-mysql-test

# 使用方案2配置
cp src/main/resources/log4j2-spring-with-rewrite-policy.xml \
   src/main/resources/log4j2-spring.xml

# 已经编译好，直接重启
./restart-app.sh
```

## 验证

```bash
# 启动应用（DEBUG级别）
./run-aurora-bg-debug.sh

# 等待几秒后，查看日志
tail -f logs/jdbc-wrapper-debug-as-info.log

# 应该看到所有日志都显示为 INFO 级别
```

## 对比效果

### 原始日志 (jdbc-wrapper.log)
```
2026-01-14 08:15:30.123 DEBUG ... Connection established
2026-01-14 08:15:30.456 TRACE ... Plugin execution details
2026-01-14 08:15:30.789 INFO  ... Connection successful
```

### 改写后日志 (jdbc-wrapper-debug-as-info.log)
```
2026-01-14 08:15:30.123 INFO  ... Connection established
2026-01-14 08:15:30.456 INFO  ... Plugin execution details
```

注意：
- 方案1: 只改变显示格式（INFO 是硬编码在 Pattern 中）
- 方案2: 真正改变日志级别（使用 LevelRewritePolicy 类）

## 生成的日志文件

| 文件 | 内容 | 方案1 | 方案2 |
|------|------|-------|-------|
| `jdbc-wrapper.log` | 所有日志（原始级别） | ✅ | ✅ |
| `jdbc-wrapper-info.log` | INFO及以上（原始级别） | ✅ | ✅ |
| `jdbc-wrapper-debug-as-info.log` | DEBUG/TRACE改写为INFO | ✅ 显示为INFO | ✅ 真正是INFO |

## 性能对比

- **方案1**: 几乎无性能影响（只改变显示格式）
- **方案2**: 轻微性能影响（需要创建新的 LogEvent 对象）

推荐：
- 开发/测试环境：使用方案1
- 生产环境：根据需求选择

## 故障排查

### 如果日志文件为空

```bash
# 1. 检查 JDBC URL 中的日志级别
grep "wrapperLoggerLevel" src/main/resources/application.yml
# 应该是: FINE 或 FINER

# 2. 检查配置文件
ls -la src/main/resources/log4j2-spring.xml

# 3. 查看应用日志
tail -f logs/spring-boot.log | grep -i "log4j"
```

### 如果级别没有改变

```bash
# 方案1: 检查 Pattern
grep "FILE_LOG_PATTERN_INFO_ONLY" src/main/resources/log4j2-spring.xml

# 方案2: 检查 packages 属性
grep 'packages="com.test.logging"' src/main/resources/log4j2-spring.xml

# 重新编译和重启
mvn clean package -DskipTests
./restart-app.sh
```

## 测试脚本

```bash
# 自动化测试
./test-level-rewrite.sh pattern   # 测试方案1
./test-level-rewrite.sh policy    # 测试方案2
```

## 相关文档

- 详细指南: `LOG_LEVEL_REWRITE_GUIDE.md`
- 快速参考: `LOG_LEVEL_REWRITE_QUICK_REF.md`
- 日志说明: `LOG_FILES_EXPLAINED.md`

## 总结

✅ 两种方案都可以使用  
✅ 方案2已成功编译  
✅ 可以根据需求选择合适的方案  
✅ 所有配置文件和代码都已就绪  

开始使用吧！🚀
