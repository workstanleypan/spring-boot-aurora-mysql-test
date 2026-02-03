# Spring Boot Aurora MySQL Test

Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，支持 Blue/Green Deployment 自动切换。

## 功能特性

- AWS Advanced JDBC Wrapper 3.1.0
- Blue/Green Deployment Plugin
- Failover & EFM Plugin
- HikariCP 连接池
- Spring Boot 3.4.2

## 快速开始

```bash
# 1. 配置环境变量
cp .env.template .env
nano .env  # 填入 Aurora 配置

# 2. 构建并启动
source .env
mvn clean package -DskipTests
./run-aurora.sh prod
```

### 环境变量

```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="INFO"  # INFO=生产, FINE=调试
```

### 验证连接

```bash
curl http://localhost:8080/api/test
```

## 核心配置

### JDBC URL 格式

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=INFO
```

**重要**: 必须使用 **集群端点** (Cluster Endpoint)，不能使用实例端点。

### 插件说明

| 插件 | 功能 |
|------|------|
| `initialConnection` | 初始连接处理 |
| `auroraConnectionTracker` | Aurora 连接跟踪 |
| `failover2` | 自动故障转移 |
| `efm2` | 增强故障监控 |
| `bg` | Blue/Green 部署支持 |

### Spring Profiles

| Profile | 说明 |
|---------|------|
| `aurora-prod` | 生产环境，INFO 日志 |
| `aurora-dev` | 开发环境，FINE 日志 |
| `rds-prod` | RDS MySQL 生产环境 |
| `rds-dev` | RDS MySQL 开发环境 |

## HikariCP 连接池配置

```yaml
hikari:
  pool-name: AuroraHikariPool
  minimum-idle: 10
  maximum-pool-size: 50
  idle-timeout: 300000
  max-lifetime: 600000
  connection-timeout: 30000
  connection-test-query: SELECT 1
```

## API 端点

```bash
# 测试连接
curl http://localhost:8080/api/test

# 用户 CRUD
curl http://localhost:8080/api/users

# Blue/Green 测试
curl -X POST http://localhost:8080/api/bluegreen/start
curl http://localhost:8080/api/bluegreen/status
```

## 常见问题

### 连接超时
- 检查安全组是否允许 3306 端口
- 测试: `nc -zv <endpoint> 3306`

### BG Plugin 不工作
- 确保使用集群端点（包含 `.cluster-`）
- 检查 Aurora 版本是否支持 Blue/Green

### 认证失败
- 验证用户名密码
- 检查数据库用户权限

## 项目结构

```
spring-boot-aurora-mysql-test/
├── src/main/
│   ├── java/com/test/
│   │   ├── controller/
│   │   └── service/
│   └── resources/
│       └── application.yml
├── run-aurora.sh
└── run-rds.sh
```

## 更多文档

- [docs/AURORA_CONFIGURATION_GUIDE.md](docs/AURORA_CONFIGURATION_GUIDE.md) - Aurora 配置详解
- [docs/BLUEGREEN_TEST_GUIDE.md](docs/BLUEGREEN_TEST_GUIDE.md) - Blue/Green 测试指南

## License

MIT
