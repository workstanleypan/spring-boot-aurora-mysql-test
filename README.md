# Spring Boot Aurora MySQL Test

Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，支持 Blue/Green Deployment 自动切换。

## 功能特性

- AWS Advanced JDBC Wrapper 3.1.0
- Blue/Green Deployment Plugin
- Failover & EFM Plugin
- HikariCP 连接池
- Spring Boot 3.4.2

## 一键部署测试环境

```bash
cd cloudformation

# 1. 部署 Aurora 集群
./deploy.sh deploy

# 2. 初始化数据库
./deploy.sh init-db

# 3. 创建蓝绿部署
./deploy.sh create-bluegreen

# 4. 查看状态
./deploy.sh status
```

详细说明见 [cloudformation/README.md](cloudformation/README.md)

## 默认配置

| 配置项 | 默认值 |
|--------|--------|
| 数据库密码 | AuroraTest123! |
| Blue 版本 | 3.04.2 |
| Green 版本 | 3.10.3 (LTS) |
| 实例类型 | db.t3.medium |

## 启动应用

```bash
# 获取连接信息
cd cloudformation && ./deploy.sh outputs

# 配置环境变量
cd ..
export AURORA_CLUSTER_ENDPOINT="<cluster-endpoint>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="AuroraTest123!"

# 启动
./run-aurora.sh prod
```

## 核心配置

### JDBC URL 格式

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=INFO
```

**重要**: 必须使用 **集群端点** (Cluster Endpoint)。

### 插件说明

| 插件 | 功能 |
|------|------|
| `initialConnection` | 初始连接处理 |
| `auroraConnectionTracker` | Aurora 连接跟踪 |
| `failover2` | 自动故障转移 |
| `efm2` | 增强故障监控 |
| `bg` | Blue/Green 部署支持 |

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

## 清理资源

```bash
cd cloudformation
./deploy.sh delete
```

## License

MIT
