# 🚀 快速参考 - 内置 RewritePolicy

## ⚡ 一键命令

```bash
# 构建项目
mvn clean package -DskipTests

# 验证配置
./test-builtin-rewrite.sh

# 启动应用（Aurora）
./run-aurora.sh

# 启动应用（Aurora BG Debug）
./run-aurora-bg-debug.sh

# 启动应用（RDS）
./run-rds.sh
```

## 📋 核心配置

### log4j2-spring.xml
```xml
<Configuration status="WARN">
    <Appenders>
        <Rewrite name="AmazonJdbcRewrite">
            <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
                <KeyValuePair key="TRACE" value="INFO"/>
                <KeyValuePair key="DEBUG" value="INFO"/>
            </LoggerNameLevelRewritePolicy>
            <AppenderRef ref="Console"/>
            <AppenderRef ref="InfoFile"/>
        </Rewrite>
    </Appenders>
    
    <Loggers>
        <Logger name="software.amazon.jdbc" level="all" additivity="false">
            <AppenderRef ref="AmazonJdbcRewrite"/>
        </Logger>
    </Loggers>
</Configuration>
```

## ✅ 关键点

- ✅ **零 Java 代码**：纯配置方案
- ✅ **内置 Policy**：`LoggerNameLevelRewritePolicy`
- ✅ **精确控制**：只影响 `software.amazon.jdbc`
- ✅ **Log4j2 2.4+**：当前使用 2.17.2

## 📊 日志流程

```
AWS JDBC Wrapper (TRACE/DEBUG)
    ↓
LoggerNameLevelRewritePolicy
    ↓
重写为 INFO
    ↓
输出到文件和控制台
```

## 📁 重要文件

| 文件 | 说明 |
|------|------|
| `log4j2-spring.xml` | 主配置文件 |
| `BUILTIN_REWRITE_POLICY.md` | 详细说明 |
| `REWRITE_POLICY_COMPARISON.md` | 方案对比 |
| `BUILD_SUCCESS_SUMMARY.md` | 构建总结 |
| `test-builtin-rewrite.sh` | 验证脚本 |

## 🔍 验证方法

```bash
# 1. 检查 JAR 配置
./test-builtin-rewrite.sh

# 2. 查看日志文件
tail -f logs/info.log

# 3. 确认日志级别
grep "software.amazon.jdbc" logs/info.log | head -5
```

## 💡 常见问题

**Q: 为什么选择内置 Policy？**  
A: 简单、可靠、零代码、官方支持

**Q: 会影响其他 logger 吗？**  
A: 不会，只影响 `software.amazon.jdbc`

**Q: 需要什么版本的 Log4j2？**  
A: 2.4+（当前 2.17.2）

**Q: 如何调整重写规则？**  
A: 修改 `log4j2-spring.xml` 中的 `KeyValuePair`

## 🎯 下一步

1. ✅ 构建完成
2. ✅ 配置验证
3. 🚀 启动应用
4. 📊 查看日志
5. 🧪 测试蓝绿切换

---

**版本**: 1.0.0  
**构建时间**: 2026-01-16 04:07:18 UTC  
**状态**: ✅ READY
