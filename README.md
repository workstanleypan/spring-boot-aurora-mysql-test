# Spring Boot Aurora MySQL Test

Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，支持 Blue/Green Deployment 自动切换测试。

## 功能特性

- AWS Advanced JDBC Wrapper 3.1.0
- Blue/Green Deployment Plugin 支持
- Failover & EFM Plugin
- HikariCP 连接池
- 多线程持续写入测试
- Spring Boot 3.4.2

## 快速开始

### 1. 部署 Aurora 集群

```bash
cd cloudformation
./deploy.sh deploy
./deploy.sh init-db
./deploy.sh create-bluegreen
```

### 2. 启动应用

```bash
# 配置环境变量
export AURORA_CLUSTER_ENDPOINT="<cluster-endpoint>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="<password>"
export WRAPPER_LOG_LEVEL="FINEST"  # 可选: SEVERE|WARNING|INFO|FINE|FINER|FINEST

# 启动
./run-aurora.sh prod
```

### 3. 启动测试

```bash
# 持续写入测试 - 10个连接，每100ms写入一次
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=100"

# 查看状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop
```

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/bluegreen/start-write` | POST | 启动持续写入测试 |
| `/api/bluegreen/start` | POST | 启动读写混合测试 |
| `/api/bluegreen/stop` | POST | 停止测试 |
| `/api/bluegreen/status` | GET | 获取测试状态 |
| `/api/bluegreen/help` | GET | 获取帮助信息 |
| `/actuator/health` | GET | 健康检查 |

### 持续写入测试参数

```bash
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=20&writeIntervalMs=50"
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `numConnections` | 10 | 连接数量 (1-100) |
| `writeIntervalMs` | 100 | 写入间隔毫秒 (0=最快) |

## JDBC 配置

### 插件链

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

| 插件 | 功能 |
|------|------|
| `initialConnection` | 初始连接处理 |
| `auroraConnectionTracker` | Aurora 连接跟踪 |
| `failover2` | 自动故障转移 |
| `efm2` | 增强故障监控 |
| `bg` | Blue/Green 部署支持 |

### 日志级别

通过 `WRAPPER_LOG_LEVEL` 环境变量控制：

| 级别 | 说明 |
|------|------|
| `INFO` | 默认，基本信息 |
| `FINE` | 显示 BG 插件状态、连接事件 |
| `FINER` | 详细插件执行流程 |
| `FINEST` | 最详细调试信息 |

## 文档

- [Aurora 配置指南](docs/AURORA_CONFIGURATION_GUIDE.md)
- [Aurora 快速开始](docs/AURORA_QUICK_START.md)
- [Blue/Green 测试指南](docs/BLUEGREEN_TEST_GUIDE.md)
- [插件配置说明](docs/PLUGIN_CONFIGURATION.md)
- [CloudFormation 部署](cloudformation/README.md)

## 清理资源

```bash
cd cloudformation
./deploy.sh delete
```

## License

MIT
