# Aurora MySQL 配置指南

## 概述

本指南说明如何配置 Spring Boot 应用连接到 AWS Aurora MySQL 集群，并启用 Blue/Green Deployment Plugin。

## 前提条件

### 1. Aurora 集群信息

- **集群端点 (Cluster Endpoint)**: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`
- **数据库名称**: `testdb`
- **用户名**: `admin`
- **密码**: `your-password`

### 2. 网络访问

- Aurora 安全组允许应用的入站流量（端口 3306）
- 应用部署在同一 VPC 或通过 VPC Peering 连接

## 快速配置

### 使用环境变量启动

```bash
AURORA_CLUSTER_ENDPOINT="database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
WRAPPER_LOG_LEVEL="FINE" \
./run-aurora.sh prod
```

## Profile 说明

| Profile | 日志级别 | 连接池 | 使用场景 |
|---------|----------|--------|----------|
| `aurora-prod` | FINE | max: 50 | 生产环境 |
| `aurora-dev` | FINEST | max: 20 | 开发调试 |

## 技术栈

### 连接池: HikariCP

Spring Boot 默认使用 HikariCP 连接池，配置在 `application.yml`:

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

### JDBC URL 格式

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

**重要**: 必须使用 **集群端点** (Cluster Endpoint)。

### Wrapper 插件

| 插件 | 功能 |
|------|------|
| `initialConnection` | 初始连接处理 |
| `auroraConnectionTracker` | Aurora 连接跟踪 |
| `failover2` | 自动故障转移 |
| `efm2` | 增强故障监控 |
| `bg` | Blue/Green 部署支持 |

### 日志级别

| JUL 级别 | Log4j2 级别 | 说明 |
|----------|-------------|------|
| INFO | INFO | 基本信息 |
| FINE | DEBUG | 生产环境推荐，显示 BG 插件状态 |
| FINER | DEBUG | 详细插件执行流程 |
| FINEST | TRACE | 测试环境推荐，完整调试信息 |

## 验证配置

### 1. 测试连接

```bash
curl http://localhost:8080/api/test
```

### 2. 查看日志

```bash
# Wrapper 日志
tail -f logs/wrapper.log

# BG Plugin 相关
grep -i "blue.*green\|BlueGreen" logs/wrapper.log
```

## 常见问题

### 连接超时

```bash
# 测试网络连通性
nc -zv your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306
```

### BG Plugin 不支持

确保使用**集群端点**（包含 `.cluster-`），不是实例端点：

✅ 正确: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`  
❌ 错误: `database-1-instance-1.xxxxx.us-east-1.rds.amazonaws.com`

## 相关文档

- [AURORA_QUICK_START.md](AURORA_QUICK_START.md) - 快速开始
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - 蓝绿测试指南
- [PLUGIN_CONFIGURATION.md](PLUGIN_CONFIGURATION.md) - 插件配置说明
