# TRACE 日志过多问题 - 快速修复指南

## 问题症状

- ✅ 日志文件快速增长
- ✅ 大量 TRACE 级别日志
- ✅ 只看到 `BlueGreenStatusMonitor` 日志
- ✅ 日志量比预期多很多

## 快速修复

### 1. 已修复的代码

**JulBridgeInitializer.java** - 已更新 ✅

```java
// ✅ 修复：移除了显式设置 AWS JDBC logger 级别
// ❌ 之前：awsJdbcLogger.setLevel(Level.ALL);  // 会接受所有 TRACE 日志
// ✅ 现在：让 wrapperLoggerLevel 在 JDBC URL 中控制
```

### 2. 验证 JDBC URL 配置

**检查 application.yml：**

```bash
grep "wrapperLoggerLevel" spring-boot-mysql-test/src/main/resources/application.yml
```

**应该看到：**
```yaml
url: jdbc:aws-wrapper:mysql://...?wrapperLoggerLevel=FINE
                                                      ↑
                                        ⭐ 确保这个参数存在
```

### 3. 重新编译和启动

```bash
cd spring-boot-mysql-test

# 重新编译
mvn clean compile

# 启动应用
./run-aurora.sh
```

### 4. 验证修复

```bash
# 等待几分钟后检查日志
tail -100 logs/jdbc-wrapper.log

# 检查 TRACE 日志数量（应该为 0）
grep "TRACE" logs/jdbc-wrapper.log | wc -l

# 检查 FINE 日志数量（应该适量）
grep "FINE" logs/jdbc-wrapper.log | wc -l
```

## 日志级别说明

### wrapperLoggerLevel 参数值

| 级别 | 用途 | 日志量 |
|------|------|--------|
| `INFO` | 生产环境 | 最少 |
| `FINE` | 调试蓝绿切换 | 适中 ⭐ 推荐 |
| `FINER` | 详细调试 | 较多 |
| `FINEST` | 完整调试 | 非常多 ⚠️ 慎用 |

### 推荐配置

**调试蓝绿切换：**
```yaml
wrapperLoggerLevel=FINE
```

**生产环境：**
```yaml
wrapperLoggerLevel=INFO
```

## 动态调整日志级别

### 方法 1: 环境变量

```bash
# 设置环境变量
export JDBC_LOG_LEVEL=FINE

# 在 application.yml 中使用
url: jdbc:aws-wrapper:mysql://...?wrapperLoggerLevel=${JDBC_LOG_LEVEL:FINE}
```

### 方法 2: 启动参数

```bash
# 启动时指定
./run-aurora.sh FINE

# 或使用 Spring Boot 参数
java -jar app.jar --spring.datasource.url="jdbc:aws-wrapper:mysql://...?wrapperLoggerLevel=FINE"
```

## 常见问题

### Q: 为什么只看到 BlueGreenStatusMonitor？

**A:** `BlueGreenStatusMonitor` 是 `BlueGreenStatusProvider` 的监控线程，会持续运行并输出日志。

### Q: 为什么 TRACE 日志这么多？

**A:** 监控线程在蓝绿切换期间会提高检查频率到 100ms，每秒产生 10 次 TRACE 日志。

### Q: 如何完全禁用 TRACE 日志？

**A:** 
1. 确保 `wrapperLoggerLevel` 不是 `FINEST`
2. 使用 `FINE` 或 `INFO` 级别
3. 不要在 JUL 中显式设置 AWS JDBC logger 级别

### Q: 修复后还是有很多日志？

**A:** 检查：
1. JDBC URL 中的 `wrapperLoggerLevel` 参数
2. 是否有多个数据源配置
3. 是否有其他地方设置了 JUL logger 级别

## 验证清单

- [ ] JulBridgeInitializer 已更新（不设置 AWS JDBC logger）
- [ ] application.yml 包含 `wrapperLoggerLevel=FINE`
- [ ] 重新编译应用
- [ ] 重启应用
- [ ] 检查日志文件，确认没有 TRACE 日志
- [ ] 日志量可控，不会快速增长

## 对比

### 修复前

```
2026-01-20 15:30:00.001 TRACE ... BlueGreenStatusMonitor: Checking status...
2026-01-20 15:30:00.101 TRACE ... BlueGreenStatusMonitor: Checking status...
2026-01-20 15:30:00.201 TRACE ... BlueGreenStatusMonitor: Checking status...
... (每 100ms 一次，日志爆炸)
```

### 修复后

```
2026-01-20 15:30:00.000 FINE  ... BlueGreenConnectionPlugin: BG Plugin initialized
2026-01-20 15:30:05.000 FINE  ... BlueGreenStatusProvider: Status check completed
... (只有重要的 FINE 级别日志)
```

## 相关文档

- `TRACE_LOG_ISSUE_ANALYSIS.md` - 详细问题分析
- `UNIFIED_LOGGING_GUIDE.md` - 统一日志系统说明
- `LOG_LEVEL_REWRITE_QUICK_REF.md` - 日志级别重写参考
