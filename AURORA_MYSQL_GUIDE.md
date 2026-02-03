# Aurora MySQL 连接指南

本项目是一个 Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，特别是 Blue/Green Deployment 场景。

## 快速开始

### 1. 配置环境变量

```bash
# 复制模板
cp .env.template .env

# 编辑配置
nano .env
```

填入你的 Aurora 配置：
```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="INFO"
```

### 2. 启动应用

```bash
# 加载环境变量
source .env

# 生产环境
./run-aurora.sh prod

# 开发环境（详细日志）
./run-aurora.sh dev
```

### 3. 验证连接

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

### 日志级别

| 级别 | 用途 |
|------|------|
| `INFO` | 生产环境 |
| `FINE` | 开发调试 |

## Spring Profiles

| Profile | 说明 |
|---------|------|
| `aurora-prod` | 生产环境，INFO 日志 |
| `aurora-dev` | 开发环境，FINE 日志 |
| `rds-prod` | RDS MySQL 生产环境 |
| `rds-dev` | RDS MySQL 开发环境 |

## Blue/Green 切换测试

### 启动测试

```bash
# 快速测试
./test-bluegreen-api.sh quick-test

# 标准测试
./test-bluegreen-api.sh start

# 自定义测试 (线程数, 读取/秒, 持续秒数)
./test-bluegreen-api.sh start-custom 10 200 1800
```

### 监控状态

```bash
./test-bluegreen-api.sh monitor
```

### 查看日志

```bash
# 应用日志
tail -f logs/spring-boot.log

# JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log
```

## 连接池配置 (Druid)

```yaml
druid:
  initial-size: 10
  min-idle: 10
  max-active: 50
  max-wait: 60000
  validation-query: SELECT 1
  test-while-idle: true
```

## 常见问题

### 连接超时
- 检查安全组是否允许 3306 端口
- 确认 VPC 网络配置正确
- 测试: `nc -zv <endpoint> 3306`

### BG Plugin 不工作
- 确保使用集群端点（包含 `.cluster-`）
- 检查 Aurora 版本是否支持 Blue/Green

### 认证失败
- 验证用户名密码
- 检查数据库用户权限

## 文件结构

```
spring-boot-mysql-test/
├── src/main/
│   ├── java/com/test/
│   │   ├── controller/
│   │   │   ├── UserController.java
│   │   │   └── BlueGreenTestController.java
│   │   ├── service/
│   │   │   ├── UserService.java
│   │   │   └── BlueGreenTestService.java
│   │   └── ...
│   └── resources/
│       ├── application.yml
│       └── log4j2-spring.xml
├── run-aurora.sh          # Aurora 启动脚本
├── test-bluegreen-api.sh  # BG 测试脚本
└── docs/                  # 详细文档
```

## 更多文档

- [Aurora 配置详解](docs/AURORA_CONFIGURATION_GUIDE.md)
- [Blue/Green 测试指南](docs/BLUEGREEN_TEST_GUIDE.md)
- [插件配置](docs/PLUGIN_CONFIGURATION.md)
- [生产优化](docs/PRODUCTION_OPTIMIZATION.md)
