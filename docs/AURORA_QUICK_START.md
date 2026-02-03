# Aurora MySQL 快速开始

## 5 分钟快速配置

### 步骤 1: 启动应用

```bash
AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
./run-aurora.sh prod
```

### 步骤 2: 验证连接

```bash
curl http://localhost:8080/api/test
```

### 步骤 3: 启动测试

```bash
# 持续写入测试
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=100"

# 查看状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop
```

## 可用的 Profiles

| Profile | 日志级别 | 使用场景 |
|---------|----------|----------|
| `aurora-prod` | FINE | 生产环境 |
| `aurora-dev` | FINEST | 开发调试 |

```bash
./run-aurora.sh prod   # 生产环境
./run-aurora.sh dev    # 开发环境
```

## 技术栈

- **连接池**: HikariCP (Spring Boot 默认)
- **JDBC Wrapper**: AWS Advanced JDBC Wrapper 3.1.0
- **插件**: initialConnection, auroraConnectionTracker, failover2, efm2, bg

## 查看日志

```bash
# Wrapper 日志
tail -f logs/wrapper.log

# 应用日志
tail -f logs/spring-boot.log

# BG Plugin 日志
grep -i "blue.*green" logs/wrapper.log
```

## 常见问题

### 连接超时

```bash
nc -zv your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306
```

### BG Plugin 不工作

确保使用**集群端点**（包含 `.cluster-`）：

✅ 正确: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`  
❌ 错误: `database-1-instance-1.xxxxx.us-east-1.rds.amazonaws.com`

## 下一步

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - 完整配置指南
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - 蓝绿测试指南
