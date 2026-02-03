# AWS JDBC Wrapper 插件配置说明

## 插件配置对比

### RDS MySQL

```
wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg
```

**插件说明**:
1. **auroraConnectionTracker**: Aurora 连接追踪器
2. **failover2**: 故障转移插件 v2
3. **efm2**: 增强故障监控 v2
4. **bg**: Blue/Green 部署插件

### Aurora MySQL

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

**插件说明**:
1. **initialConnection**: 初始连接策略插件
2. **auroraConnectionTracker**: Aurora 连接追踪器
3. **failover2**: 故障转移插件 v2
4. **efm2**: 增强故障监控 v2
5. **bg**: Blue/Green 部署插件

## 关键区别

| 特性 | RDS MySQL | Aurora MySQL |
|------|-----------|--------------|
| initialConnection 插件 | ❌ 不需要 | ✅ 需要 |
| auroraConnectionTracker | ✅ 需要 | ✅ 需要 |
| failover2 | ✅ 需要 | ✅ 需要 |
| efm2 | ✅ 需要 | ✅ 需要 |
| bg (Blue/Green) | ✅ 支持 | ✅ 支持 |
| 端点类型 | 实例端点 | 集群端点 |

## 插件详细说明

### 1. initialConnection (仅 Aurora)

**功能**:
- 优化 Aurora 集群的初始连接策略
- 智能选择最佳的初始连接节点
- 提高连接建立速度

**为什么 RDS 不需要**:
- RDS 是单实例或 Multi-AZ（主备模式）
- 没有多个读副本需要选择
- 连接策略相对简单

**为什么 Aurora 需要**:
- Aurora 有多个读副本
- 需要智能选择最佳节点
- 优化读写分离场景

### 2. auroraConnectionTracker (RDS 和 Aurora 都需要)

**功能**:
- 追踪连接状态
- 监控连接健康
- 管理连接生命周期

**适用场景**:
- RDS MySQL with Blue/Green
- Aurora MySQL
- 需要连接追踪的场景

### 3. failover2 (RDS 和 Aurora 都需要)

**功能**:
- 自动检测数据库故障
- 自动重连到可用实例
- 支持读写分离

**适用场景**:
- RDS Multi-AZ 部署
- Aurora 集群
- 需要高可用性

### 4. efm2 (RDS 和 Aurora 都需要)

**功能**:
- 增强的故障检测
- 更快的故障发现
- 减少故障转移时间

**适用场景**:
- 需要快速故障检测
- 高可用性要求
- 生产环境

### 5. bg (RDS 和 Aurora 都支持)

**功能**:
- 检测 Blue/Green 部署切换
- 自动刷新拓扑
- 无缝切换到新环境

**适用场景**:
- RDS MySQL with Blue/Green Deployment
- Aurora MySQL with Blue/Green Deployment
- 需要零停机升级

## 插件执行顺序

### RDS MySQL

```
请求 → auroraConnectionTracker → failover2 → efm2 → bg → 数据库
```

### Aurora MySQL

```
请求 → initialConnection → auroraConnectionTracker → failover2 → efm2 → bg → 数据库
```

## 配置示例

### RDS MySQL 配置

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://database-1.xxxxx.us-east-1.rds.amazonaws.com:3306/testdb?wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=INFO
```

### Aurora MySQL 配置

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=INFO
```

## 日志中的插件信息

### 启动时

```
Loading plugins: [auroraConnectionTracker, failover2, efm2, bg]
Initializing plugin: auroraConnectionTracker
Initializing plugin: failover2
Initializing plugin: efm2
Initializing plugin: bg
Plugin chain: [auroraConnectionTracker, failover2, efm2, bg]
```

### 连接时

```
[auroraConnectionTracker] Tracking connection to database-1
[failover2] Monitoring connection health
[efm2] Enhanced monitoring enabled
[bg] Checking for Blue/Green deployment
```

## 常见问题

### Q1: 为什么 RDS 不需要 initialConnection？

**A**: RDS 是单实例或主备模式，没有多个读副本需要选择初始连接策略。Aurora 有多个读副本，需要智能选择最佳节点。

### Q2: RDS MySQL 真的支持 Blue/Green 吗？

**A**: 是的！RDS MySQL 从某个版本开始支持 Blue/Green 部署功能，可以使用 bg 插件。

### Q3: 插件顺序重要吗？

**A**: 是的！插件按照配置的顺序执行。推荐的顺序是：
- Aurora: `initialConnection → auroraConnectionTracker → failover2 → efm2 → bg`
- RDS: `auroraConnectionTracker → failover2 → efm2 → bg`

### Q4: 可以只使用部分插件吗？

**A**: 可以，但不推荐。完整的插件链提供最佳的可用性和性能。

### Q5: 如何验证插件是否工作？

**A**: 查看日志：
```bash
grep -i "plugin" logs/jdbc-wrapper.log
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

## 最佳实践

### 生产环境

```yaml
# RDS MySQL
wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg
wrapperLoggerLevel=INFO

# Aurora MySQL
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
wrapperLoggerLevel=INFO
```

### 开发环境

```yaml
# RDS MySQL
wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg
wrapperLoggerLevel=FINE

# Aurora MySQL
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
wrapperLoggerLevel=FINE
```

### 测试环境

```yaml
# 可以使用更详细的日志
wrapperLoggerLevel=FINEST
```

## 相关文档

- [RDS_CONFIGURATION_GUIDE.md](RDS_CONFIGURATION_GUIDE.md) - RDS 配置指南
- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora 配置指南
- [LOG_FILES_EXPLAINED.md](LOG_FILES_EXPLAINED.md) - 日志文件说明

## 总结

1. ✅ RDS MySQL 支持 Blue/Green 部署
2. ✅ RDS 使用: `auroraConnectionTracker,failover2,efm2,bg`
3. ✅ Aurora 使用: `initialConnection,auroraConnectionTracker,failover2,efm2,bg`
4. ✅ 主要区别是 Aurora 需要 `initialConnection` 插件
5. ✅ 插件顺序很重要，按推荐顺序配置

感谢指正！配置已更新为正确的插件组合。
