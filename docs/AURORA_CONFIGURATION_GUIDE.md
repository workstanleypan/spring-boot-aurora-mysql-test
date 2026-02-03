# Aurora MySQL 配置指南

## 概述

本指南说明如何配置 Spring Boot 应用连接到真实的 AWS Aurora MySQL 集群，并启用 Blue/Green Deployment Plugin。

## 前提条件

### 1. Aurora 集群信息

你需要准备以下信息：

- **集群端点 (Cluster Endpoint)**: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`
- **数据库名称**: `testdb`
- **用户名**: `admin`
- **密码**: `your-password`
- **端口**: `3306` (默认)
- **区域**: `us-east-1` (或你的 Aurora 所在区域)

### 2. 网络访问

确保你的应用可以访问 Aurora 集群：

- **VPC 内部访问**: 应用部署在同一 VPC 或通过 VPC Peering 连接
- **安全组配置**: Aurora 安全组允许应用的入站流量（端口 3306）
- **公网访问**: 如果需要从本地测试，确保 Aurora 启用了公网访问

### 3. IAM 权限（可选）

如果使用 IAM 数据库认证：

- 应用的 IAM 角色需要 `rds-db:connect` 权限
- Aurora 集群启用了 IAM 数据库认证

## 配置方法

### 方法 1: 使用环境变量（推荐）

#### 1.1 创建环境变量配置文件

```bash
# 创建 .env 文件（不要提交到 Git）
cat > spring-boot-mysql-test/.env << 'EOF'
# Aurora 集群配置
export AURORA_CLUSTER_ENDPOINT="database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="INFO"  # 生产环境使用 INFO，开发环境使用 FINE
EOF

# 添加到 .gitignore
echo ".env" >> spring-boot-mysql-test/.gitignore
```

#### 1.2 加载环境变量并启动

```bash
# 加载环境变量
source spring-boot-mysql-test/.env

# 启动应用（生产环境配置）
cd spring-boot-mysql-test
./run.sh aurora-prod

# 或者启动应用（开发环境配置，详细日志）
./run.sh aurora-dev
```

### 方法 2: 直接在命令行设置环境变量

```bash
# 一次性设置所有环境变量并启动
cd spring-boot-mysql-test

AURORA_CLUSTER_ENDPOINT="database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
WRAPPER_LOG_LEVEL="INFO" \
./run.sh aurora-prod
```

### 方法 3: 修改 application.yml（不推荐）

直接修改 `src/main/resources/application.yml` 中的默认值：

```yaml
spring:
  config:
    activate:
      on-profile: aurora-prod
  datasource:
    url: jdbc:aws-wrapper:mysql://your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com:3306/testdb?wrapperPlugins=bg,failover2,efm2&wrapperLoggerLevel=INFO
    username: admin
    password: your-password
```

⚠️ **注意**: 不要将密码提交到 Git 仓库！

## Profile 说明

### aurora-prod (生产环境)

- **日志级别**: INFO（只记录重要信息）
- **连接池**: 较大的连接池配置（initial: 10, max: 50）
- **适用场景**: 生产环境部署

```bash
./run.sh aurora-prod
```

### aurora-dev (开发环境)

- **日志级别**: FINE（详细的 Plugin 执行日志）
- **连接池**: 较小的连接池配置（initial: 5, max: 20）
- **适用场景**: 开发调试、查看 BG Plugin 日志

```bash
./run.sh aurora-dev
```

## JDBC URL 参数说明

### 必需参数

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>
```

- **cluster-endpoint**: 必须使用 **集群端点**（Cluster Endpoint），不能使用实例端点
- **database**: 数据库名称

### Wrapper 插件参数

```
?wrapperPlugins=bg,failover2,efm2&wrapperLoggerLevel=INFO
```

#### wrapperPlugins

插件执行顺序（从左到右）：

1. **bg** (Blue/Green Plugin)
   - 检测 Blue/Green 部署切换
   - 自动刷新拓扑
   - **要求**: 必须使用集群端点

2. **failover2** (Failover Plugin v2)
   - 自动故障转移
   - Writer 节点失败时切换到新的 Writer

3. **efm2** (Enhanced Failure Monitoring v2)
   - 增强的故障检测
   - 更快的故障发现

#### wrapperLoggerLevel

日志级别选项：

| 级别 | 说明 | 适用场景 |
|------|------|----------|
| SEVERE | 只记录严重错误 | 生产环境（最小日志） |
| WARNING | 记录警告和错误 | 生产环境 |
| **INFO** | 记录基本信息 | **生产环境（推荐）** |
| CONFIG | 记录配置信息 | 调试配置问题 |
| **FINE** | 记录详细执行流程 | **开发环境（推荐）** |
| FINER | 更详细的日志 | 深度调试 |
| FINEST | 最详细的日志 | 复杂问题排查 |

## 验证配置

### 1. 检查应用启动日志

```bash
# 查看启动日志
tail -f logs/info.log

# 应该看到类似的日志：
# Opening connection to jdbc:aws-wrapper:mysql://your-cluster.cluster-xxxxx...
# [bgdId: '1'] Blue/Green Deployments is supported
```

### 2. 检查 JDBC Wrapper 日志

```bash
# 查看 wrapper 日志
tail -f logs/jdbc-wrapper.log

# 查找 BG Plugin 相关日志
grep -i "blue.*green\|BlueGreen" logs/jdbc-wrapper.log
```

### 3. 测试 API 端点

```bash
# 测试数据库连接
curl http://localhost:8080/api/test

# 应该返回：
# {
#   "message": "Database connection successful",
#   "driver": "Amazon Web Services (AWS) Advanced JDBC Wrapper",
#   "database": "MySQL",
#   "version": "8.0.x",
#   ...
# }
```

### 4. 查看连接信息

```bash
# 查询当前连接的端点
curl http://localhost:8080/api/users

# 检查日志中的连接信息
grep "Connected to" logs/jdbc-wrapper.log
```

## 常见问题

### 1. 连接超时

**症状**: `Communications link failure`

**原因**:
- 网络不通（安全组、VPC 配置）
- 集群端点错误
- Aurora 集群未启动

**解决方案**:
```bash
# 测试网络连通性
telnet your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306

# 或使用 nc
nc -zv your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306
```

### 2. 认证失败

**症状**: `Access denied for user`

**原因**:
- 用户名或密码错误
- 用户没有访问权限
- 主机白名单限制

**解决方案**:
```bash
# 使用 MySQL 客户端测试
mysql -h your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com \
      -u admin -p testdb
```

### 3. BG Plugin 不支持

**症状**: `Blue/Green Deployments isn't supported`

**原因**:
- 使用了实例端点而不是集群端点
- Aurora 版本不支持 Blue/Green 部署

**解决方案**:
- 确保使用集群端点（包含 `.cluster-`）
- 检查 Aurora 版本是否支持 Blue/Green 部署

### 4. SSL/TLS 连接问题

**症状**: SSL 相关错误

**解决方案**:
```yaml
# 在 JDBC URL 中添加 SSL 参数
url: jdbc:aws-wrapper:mysql://...?wrapperPlugins=bg,failover2,efm2&useSSL=true&requireSSL=true
```

## 安全最佳实践

### 1. 使用 AWS Secrets Manager

```bash
# 从 Secrets Manager 获取密码
export AURORA_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id aurora/testdb/password \
  --query SecretString \
  --output text)
```

### 2. 使用 IAM 数据库认证

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://...?useAwsIam=true
    username: iam_user
    # 不需要密码，使用 IAM 认证
```

### 3. 加密连接

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://...?useSSL=true&requireSSL=true&verifyServerCertificate=true
```

### 4. 使用环境变量

- ✅ 使用环境变量存储敏感信息
- ✅ 使用 `.env` 文件（不提交到 Git）
- ❌ 不要在代码中硬编码密码
- ❌ 不要将密码提交到版本控制

## 监控和日志

### 查看实时日志

```bash
# 所有日志
tail -f logs/info.log

# JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# 只看 BG Plugin 相关
tail -f logs/jdbc-wrapper.log | grep -i "blue.*green\|BlueGreen"

# 错误日志
tail -f logs/error.log
```

### 日志文件说明

| 文件 | 内容 | 级别 |
|------|------|------|
| `info.log` | 所有 INFO+ 日志 | INFO, WARN, ERROR |
| `jdbc-wrapper.log` | JDBC Wrapper 所有日志 | TRACE, DEBUG, INFO, WARN, ERROR |
| `error.log` | 只有错误日志 | ERROR |
| `spring-boot.log` | Spring Boot 框架日志 | INFO+ |

## 性能优化

### 连接池配置

根据应用负载调整连接池大小：

```yaml
druid:
  # 低负载（< 100 QPS）
  initial-size: 5
  min-idle: 5
  max-active: 20
  
  # 中等负载（100-1000 QPS）
  initial-size: 10
  min-idle: 10
  max-active: 50
  
  # 高负载（> 1000 QPS）
  initial-size: 20
  min-idle: 20
  max-active: 100
```

### Wrapper 插件优化

```yaml
# 生产环境：只启用必要的插件
wrapperPlugins=bg,failover2

# 开发环境：启用所有插件
wrapperPlugins=bg,failover2,efm2
```

## 相关文档

- [README.md](README.md) - 项目主文档
- [NACOS_CONFIGURATION.md](NACOS_CONFIGURATION.md) - Nacos 配置说明
- [查看BG_Plugin日志.md](查看BG_Plugin日志.md) - BG Plugin 日志查看指南
- [WHY_BG_PLUGIN_NEEDS_CLUSTER_ENDPOINT.md](../WHY_BG_PLUGIN_NEEDS_CLUSTER_ENDPOINT.md) - 为什么需要集群端点

## 快速开始脚本

创建一个快速启动脚本：

```bash
#!/bin/bash
# run-aurora.sh

# 设置 Aurora 配置
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"

# 选择环境
ENV=${1:-prod}

if [ "$ENV" = "dev" ]; then
    echo "🚀 Starting with aurora-dev profile (detailed logs)..."
    export WRAPPER_LOG_LEVEL="FINE"
    ./run.sh aurora-dev
else
    echo "🚀 Starting with aurora-prod profile (production)..."
    export WRAPPER_LOG_LEVEL="INFO"
    ./run.sh aurora-prod
fi
```

使用方法：

```bash
# 生产环境
./run-aurora.sh prod

# 开发环境
./run-aurora.sh dev
```

## 总结

1. **使用集群端点** - BG Plugin 必需
2. **使用环境变量** - 保护敏感信息
3. **选择合适的 profile** - prod 或 dev
4. **监控日志** - 确保 BG Plugin 正常工作
5. **测试连接** - 验证配置正确

如有问题，请查看日志文件或参考相关文档。
