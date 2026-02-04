# Aurora MySQL 配置指南

## 概述

本指南说明如何配置 Spring Boot 应用连接到 AWS Aurora MySQL 集群，并启用 Blue/Green Deployment Plugin。

## JDBC URL 详解

### 完整格式

![JDBC URL 格式说明](images/jdbc-url-format.png)

**实际示例:**
```
jdbc:aws-wrapper:mysql://my-cluster.cluster-xxx.us-east-1.rds.amazonaws.com/testdb?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&bgdId=my-cluster
```

### 参数说明

| 颜色标记 | 参数 | 说明 |
|----------|------|------|
| 红色 | `writer_cluster_endpoint`, `database_name` | 根据业务修改的连接参数 |
| 绿色 | `characterEncoding=utf8` | 原生 MySQL 连接参数 |
| 黄色 | `wrapperPlugins=...`, `wrapperLoggerLevel=...` | **必备的 Wrapper 连接参数（重要）** |
| 紫色 | `bgdId=clustername` | 多集群场景需要配置（见下文） |

### ⚠️ 重要注意事项

1. **不要使用** `autoreconnect=true` - 会干扰 Wrapper 的故障转移机制
2. **必须使用集群端点** (Cluster Endpoint)，不能使用实例端点

### bgdId 参数说明

**单集群场景**: 如果应用只连接一个 Aurora MySQL cluster，可以不配置 `bgdId`

**多集群场景**: 如果同一个应用同时连接不同的 Aurora MySQL cluster，需要添加独特数值的 `bgdId`（建议为集群名称），连接到同一个 cluster 的连接需要使用同一个 `bgdId`

#### 多集群配置示例

如同一个应用同时连接 cluster-a 和 cluster-b 两个 Aurora DB cluster:

**连接到 cluster-a 的 URL:**
```
jdbc:aws-wrapper:mysql://cluster-a.cluster-xxx.rds.amazonaws.com/database?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&bgdId=cluster-a
```

**连接到 cluster-b 的 URL:**
```
jdbc:aws-wrapper:mysql://cluster-b.cluster-xxx.rds.amazonaws.com/database?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&bgdId=cluster-b
```

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
