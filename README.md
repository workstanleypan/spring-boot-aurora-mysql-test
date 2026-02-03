# Spring Boot Aurora MySQL Test

Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，支持 Blue/Green Deployment 自动切换。

## 功能特性

- ✅ AWS Advanced JDBC Wrapper 3.1.0
- ✅ Blue/Green Deployment Plugin
- ✅ Failover & EFM Plugin
- ✅ HikariCP 连接池
- ✅ Logback 日志
- ✅ Blue/Green 切换测试 API

## 快速开始

```bash
# 1. 配置环境变量
cp .env.template .env
# 编辑 .env 填入 Aurora 配置

# 2. 加载配置
source .env

# 3. 构建
mvn clean package -DskipTests

# 4. 启动
./run-aurora.sh prod
```

## 环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `AURORA_CLUSTER_ENDPOINT` | 集群端点 | `xxx.cluster-xxx.us-east-1.rds.amazonaws.com` |
| `AURORA_DATABASE` | 数据库名 | `testdb` |
| `AURORA_USERNAME` | 用户名 | `admin` |
| `AURORA_PASSWORD` | 密码 | - |
| `WRAPPER_LOG_LEVEL` | 日志级别 | `INFO` / `FINE` |

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

## 脚本

| 脚本 | 说明 |
|------|------|
| `run-aurora.sh` | 启动应用连接 Aurora |
| `run-rds.sh` | 启动应用连接 RDS |
| `test-bluegreen-api.sh` | Blue/Green 切换测试 |
| `test-bluegreen-continuous.sh` | 持续测试 |

## 文档

- [Aurora MySQL 连接指南](AURORA_MYSQL_GUIDE.md) - 完整配置说明
- [docs/](docs/) - 详细文档

## 技术栈

- Spring Boot 3.4.2
- AWS Advanced JDBC Wrapper 3.1.0
- HikariCP (Spring Boot default)
- MySQL Connector/J
- Logback

## License

MIT
