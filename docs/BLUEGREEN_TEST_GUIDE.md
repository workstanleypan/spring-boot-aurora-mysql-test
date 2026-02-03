# Blue/Green Switchover Test Guide

## 概述

测试 AWS JDBC Wrapper 在 Aurora 蓝绿切换时的表现。使用 HikariCP 连接池和多线程持续写入。

## 快速开始

### 1. 启动应用

```bash
AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
WRAPPER_LOG_LEVEL="FINE" \
./run-aurora.sh prod
```

### 2. 启动测试

```bash
# 持续写入测试 - 10个连接，每100ms写入一次
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=100"

# 查看状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop
```

### 3. 执行蓝绿切换

在 AWS Console 或使用 CLI 触发切换：

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <deployment-id> \
  --switchover-timeout 300
```

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/bluegreen/start-write` | POST | 启动持续写入测试 |
| `/api/bluegreen/start` | POST | 启动读写混合测试 |
| `/api/bluegreen/stop` | POST | 停止测试 |
| `/api/bluegreen/status` | GET | 获取测试状态 |
| `/api/bluegreen/help` | GET | 获取帮助信息 |

### 持续写入测试参数

```bash
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=20&writeIntervalMs=50"
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `numConnections` | 10 | 连接数量 (1-100) |
| `writeIntervalMs` | 100 | 写入间隔毫秒 (0=最快) |

### 读写混合测试参数

```bash
curl -X POST http://localhost:8080/api/bluegreen/start \
  -H "Content-Type: application/json" \
  -d '{"numThreads":20,"readsPerSecond":500,"writesPerSecond":10,"durationSeconds":0,"enableWrites":true}'
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `numThreads` | 20 | 线程数 (1-100) |
| `readsPerSecond` | 500 | 每线程每秒读取次数 |
| `writesPerSecond` | 10 | 每线程每秒写入次数 |
| `durationSeconds` | 3600 | 持续时间秒 (0=持续模式) |
| `enableWrites` | true | 是否启用写入 |

## 技术栈

### 连接池: HikariCP

```yaml
spring:
  datasource:
    hikari:
      pool-name: AuroraHikariPool
      minimum-idle: 10
      maximum-pool-size: 50
      connection-timeout: 30000
```

### JDBC Wrapper 插件

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

## 查看日志

```bash
# Wrapper 日志
tail -f logs/wrapper.log

# 应用日志
tail -f logs/spring-boot.log

# BG Plugin 相关
grep -i "blue.*green\|BlueGreen" logs/wrapper.log

# Failover 相关
grep -i "failover" logs/wrapper.log
```

## 监控指标

### 关键指标
- **总写入次数**: 累计写入次数
- **成功率**: 成功写入的百分比
- **Failover 次数**: 检测到的 failover 事件数量
- **Read-Only 错误**: 写入到只读节点的错误次数

### 成功标准
- ✅ 成功率 > 95%: 高可用性
- ✅ Failover 检测: 正确识别切换事件
- ✅ 自动恢复: 切换后自动恢复写入

## 日志级别建议

| 环境 | JUL 级别 | 说明 |
|------|----------|------|
| 生产 | FINE | 显示 BG 插件状态、连接事件 |
| 测试 | FINEST | 完整调试信息 |

## 故障排查

### 高失败率
1. 检查数据库连接稳定性
2. 查看 Wrapper 日志中的错误
3. 验证 HikariCP 连接池配置

### Failover 未检测到
1. 确认使用 Cluster Endpoint
2. 验证 BG Plugin 已启用
3. 检查日志级别设置 (建议 FINE)

### 连接异常
```bash
grep -A 20 "Exception" logs/spring-boot.log
grep "HikariPool" logs/spring-boot.log
```

## 相关文档

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora 配置指南
- [PLUGIN_CONFIGURATION.md](PLUGIN_CONFIGURATION.md) - 插件配置说明
