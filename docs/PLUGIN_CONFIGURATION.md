# AWS JDBC Wrapper 插件配置说明

## 插件配置

### Aurora MySQL

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

### RDS MySQL

```
wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg
```

## 插件说明

| 插件 | 功能 | Aurora | RDS |
|------|------|--------|-----|
| `initialConnection` | 初始连接策略，智能选择最佳节点 | ✅ 需要 | ❌ 不需要 |
| `auroraConnectionTracker` | 连接状态追踪 | ✅ 需要 | ✅ 需要 |
| `failover2` | 自动故障转移 | ✅ 需要 | ✅ 需要 |
| `efm2` | 增强故障监控 | ✅ 需要 | ✅ 需要 |
| `bg` | Blue/Green 部署支持 | ✅ 需要 | ✅ 需要 |

### 为什么 RDS 不需要 initialConnection？

RDS 是单实例或主备模式，没有多个读副本需要选择初始连接策略。Aurora 有多个读副本，需要智能选择最佳节点。

## 日志级别

| JUL 级别 | Log4j2 级别 | 说明 |
|----------|-------------|------|
| SEVERE | ERROR | 只记录严重错误 |
| WARNING | WARN | 记录警告和错误 |
| INFO | INFO | 基本信息 |
| FINE | DEBUG | 生产环境推荐，显示 BG 插件状态 |
| FINER | DEBUG | 详细插件执行流程 |
| FINEST | TRACE | 测试环境推荐，完整调试信息 |

## 配置示例

### Aurora MySQL (生产环境)

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://cluster.cluster-xxxxx.rds.amazonaws.com:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

### RDS MySQL (生产环境)

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://instance.xxxxx.rds.amazonaws.com:3306/testdb?wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

## 连接池: HikariCP

Spring Boot 默认使用 HikariCP 连接池：

```yaml
spring:
  datasource:
    hikari:
      pool-name: AuroraHikariPool
      minimum-idle: 10
      maximum-pool-size: 50
      idle-timeout: 300000
      max-lifetime: 600000
      connection-timeout: 30000
```

## 验证插件

```bash
# 查看插件加载日志
grep -i "plugin" logs/wrapper.log

# 查看 BG 插件状态
grep -i "blue.*green\|BlueGreen" logs/wrapper.log
```

## 性能影响

| 插件 | 性能影响 | 说明 |
|------|---------|------|
| initialConnection | 极小 | 只在初始连接时执行 |
| auroraConnectionTracker | 极小 | 轻量级追踪 |
| failover2 | 小 | 后台监控 |
| efm2 | 小 | 增强监控 |
| bg | 极小 | 只在检测到切换时执行 |

**总体影响**: < 5% 的性能开销，换来高可用性和自动故障转移。

## 相关文档

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora 配置指南
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - 蓝绿测试指南
