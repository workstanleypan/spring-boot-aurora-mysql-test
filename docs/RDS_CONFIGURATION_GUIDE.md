# RDS MySQL 配置指南

## 概述

本指南说明如何配置 Spring Boot 应用连接到 AWS RDS MySQL 实例。

## RDS vs Aurora 的区别

| 特性 | RDS MySQL | Aurora MySQL |
|------|-----------|--------------|
| 端点类型 | 实例端点 | 集群端点 + 实例端点 |
| Blue/Green Plugin | ❌ 不支持 | ✅ 支持 |
| Failover Plugin | ✅ 支持 | ✅ 支持 |
| EFM Plugin | ✅ 支持 | ✅ 支持 |
| 推荐插件 | failover2, efm2 | bg, failover2, efm2 |

## 快速开始

### 1. 创建环境变量文件

```bash
cd spring-boot-mysql-test

# 复制模板
cp .env.rds.template .env.rds

# 编辑配置（填入你的 RDS 信息）
nano .env.rds
```

`.env.rds` 文件内容：
```bash
export RDS_ENDPOINT="database-1.xxxxx.us-east-1.rds.amazonaws.com"
export RDS_DATABASE="testdb"
export RDS_USERNAME="admin"
export RDS_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="INFO"
```

### 2. 加载环境变量并启动

```bash
# 加载环境变量
source .env.rds

# 启动应用（生产环境，使用 AWS Wrapper）
./run-rds.sh prod

# 或启动应用（开发环境，详细日志）
./run-rds.sh dev

# 或启动应用（标准 MySQL 驱动，不使用 AWS Wrapper）
./run-rds.sh standard
```

## 可用的 Profiles

### 1. rds-prod（推荐生产环境）

```bash
./run-rds.sh prod
```

**特点**:
- 使用 AWS JDBC Wrapper
- 插件: failover2, efm2（不含 BG Plugin）
- 日志级别: INFO
- 连接池: 较大配置（initial: 10, max: 50）

**JDBC URL**:
```
jdbc:aws-wrapper:mysql://<rds-endpoint>:3306/<database>?wrapperPlugins=failover2,efm2&wrapperLoggerLevel=INFO
```

### 2. rds-dev（推荐开发环境）

```bash
./run-rds.sh dev
```

**特点**:
- 使用 AWS JDBC Wrapper
- 插件: failover2, efm2
- 日志级别: FINE（详细日志）
- 连接池: 较小配置（initial: 5, max: 20）

**JDBC URL**:
```
jdbc:aws-wrapper:mysql://<rds-endpoint>:3306/<database>?wrapperPlugins=failover2,efm2&wrapperLoggerLevel=FINE
```

### 3. rds-standard（标准 MySQL 驱动）

```bash
./run-rds.sh standard
```

**特点**:
- 使用标准 MySQL Connector/J
- 不使用 AWS Wrapper
- 无特殊插件
- 适合不需要 AWS 特性的场景

**JDBC URL**:
```
jdbc:mysql://<rds-endpoint>:3306/<database>?useSSL=true&requireSSL=true&serverTimezone=UTC
```

## 配置说明

### 环境变量

| 变量名 | 说明 | 示例 | 必需 |
|--------|------|------|------|
| `RDS_ENDPOINT` | RDS 实例端点 | `database-1.xxxxx.us-east-1.rds.amazonaws.com` | ✅ |
| `RDS_DATABASE` | 数据库名称 | `testdb` | ✅ |
| `RDS_USERNAME` | 数据库用户名 | `admin` | ✅ |
| `RDS_PASSWORD` | 数据库密码 | `your-password` | ✅ |
| `WRAPPER_LOG_LEVEL` | 日志级别 | `INFO` 或 `FINE` | ❌ (默认: INFO) |

### 获取 RDS 端点

#### 方法 1: AWS Console

1. 登录 AWS Console
2. 进入 RDS 服务
3. 选择你的数据库实例
4. 在 "Connectivity & security" 标签页找到 "Endpoint"

#### 方法 2: AWS CLI

```bash
# 列出所有 RDS 实例
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address]' --output table

# 获取特定实例的端点
aws rds describe-db-instances \
  --db-instance-identifier database-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

## 网络配置

### 1. 安全组配置

确保 RDS 安全组允许你的应用访问：

```bash
# 入站规则
Type: MySQL/Aurora
Protocol: TCP
Port: 3306
Source: <your-app-security-group> 或 <your-ip>/32
```

### 2. VPC 配置

- **同 VPC**: 应用和 RDS 在同一 VPC，可以直接访问
- **不同 VPC**: 需要配置 VPC Peering 或 Transit Gateway
- **公网访问**: RDS 需要启用公网访问（不推荐生产环境）

### 3. 测试连通性

```bash
# 使用 nc 测试
nc -zv your-rds-endpoint.rds.amazonaws.com 3306

# 使用 telnet 测试
telnet your-rds-endpoint.rds.amazonaws.com 3306

# 使用 MySQL 客户端测试
mysql -h your-rds-endpoint.rds.amazonaws.com -u admin -p testdb
```

## AWS Wrapper 插件说明

### RDS 推荐插件组合

```
wrapperPlugins=failover2,efm2
```

#### failover2 (Failover Plugin v2)

**功能**:
- 自动检测数据库故障
- 自动重连到可用实例
- 支持读写分离

**适用场景**:
- RDS Multi-AZ 部署
- 需要自动故障转移

#### efm2 (Enhanced Failure Monitoring v2)

**功能**:
- 增强的故障检测
- 更快的故障发现
- 减少故障转移时间

**适用场景**:
- 需要快速故障检测
- 高可用性要求

### 为什么不使用 BG Plugin？

**BG (Blue/Green) Plugin 只支持 Aurora**:
- 需要 Aurora 集群端点
- RDS 单实例不支持 Blue/Green 部署
- 在 RDS 上使用会报错

## SSL/TLS 配置

### 启用 SSL 连接

#### 使用 AWS Wrapper

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://...?wrapperPlugins=failover2,efm2&useSSL=true&requireSSL=true
```

#### 使用标准驱动

```yaml
spring:
  datasource:
    url: jdbc:mysql://...?useSSL=true&requireSSL=true&verifyServerCertificate=true
```

### 下载 RDS CA 证书

```bash
# 下载 RDS CA 证书
wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# 配置 JDBC URL
jdbc:mysql://...?useSSL=true&trustCertificateKeyStoreUrl=file:///path/to/global-bundle.pem
```

## 连接池配置

### 根据负载调整

```yaml
# 低负载（< 100 QPS）
druid:
  initial-size: 5
  min-idle: 5
  max-active: 20

# 中等负载（100-1000 QPS）
druid:
  initial-size: 10
  min-idle: 10
  max-active: 50

# 高负载（> 1000 QPS）
druid:
  initial-size: 20
  min-idle: 20
  max-active: 100
```

### RDS 连接限制

检查 RDS 实例的最大连接数：

```sql
SHOW VARIABLES LIKE 'max_connections';
```

确保连接池配置不超过 RDS 限制。

## 验证配置

### 1. 测试网络连通性

```bash
nc -zv your-rds-endpoint.rds.amazonaws.com 3306
```

### 2. 启动应用

```bash
source .env.rds
./run-rds.sh prod
```

### 3. 测试 API

```bash
curl http://localhost:8080/api/test
```

### 4. 查看日志

```bash
# 查看 JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# 查看应用日志
tail -f logs/info.log
```

## 常见问题

### 1. 连接超时

**症状**: `Communications link failure`

**可能原因**:
- 安全组配置错误
- VPC 网络不通
- RDS 实例未运行

**解决方案**:
```bash
# 检查安全组
aws ec2 describe-security-groups --group-ids <security-group-id>

# 检查 RDS 状态
aws rds describe-db-instances --db-instance-identifier database-1
```

### 2. 认证失败

**症状**: `Access denied for user`

**可能原因**:
- 用户名或密码错误
- 用户没有访问权限
- 主机白名单限制

**解决方案**:
```bash
# 测试用户名密码
mysql -h your-rds-endpoint.rds.amazonaws.com -u admin -p testdb
```

### 3. SSL 连接失败

**症状**: SSL 相关错误

**解决方案**:
```bash
# 下载 RDS CA 证书
wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# 在 JDBC URL 中配置证书路径
```

### 4. 连接池耗尽

**症状**: `Cannot get connection from pool`

**解决方案**:
```yaml
# 增加连接池大小
druid:
  max-active: 100
  max-wait: 60000
```

## 性能优化

### 1. 使用连接池

已配置 Druid 连接池，无需额外配置。

### 2. 启用预编译语句缓存

```yaml
druid:
  pool-prepared-statements: true
  max-pool-prepared-statement-per-connection-size: 20
```

### 3. 优化连接验证

```yaml
druid:
  test-while-idle: true
  test-on-borrow: false
  test-on-return: false
  time-between-eviction-runs-millis: 60000
```

### 4. 使用 AWS Wrapper 插件

failover2 和 efm2 插件可以提高可用性和故障恢复速度。

## 监控和日志

### 查看日志

```bash
# 所有日志
tail -f logs/info.log

# JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# 只看 Failover 相关
tail -f logs/jdbc-wrapper.log | grep -i failover

# 错误日志
tail -f logs/error.log
```

### 日志级别

| 级别 | 适用场景 |
|------|----------|
| INFO | 生产环境（推荐） |
| FINE | 开发环境（推荐） |
| FINER | 深度调试 |
| FINEST | 复杂问题排查 |

## 安全最佳实践

### 1. 使用环境变量

✅ 使用 `.env.rds` 文件
❌ 不要在代码中硬编码密码

### 2. 使用 AWS Secrets Manager

```bash
# 从 Secrets Manager 获取密码
export RDS_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id rds/testdb/password \
  --query SecretString \
  --output text)
```

### 3. 启用 SSL/TLS

```yaml
url: jdbc:aws-wrapper:mysql://...?useSSL=true&requireSSL=true
```

### 4. 使用 IAM 数据库认证

```yaml
url: jdbc:aws-wrapper:mysql://...?useAwsIam=true
```

## Profile 对比

| Profile | Driver | Plugins | 日志级别 | 适用场景 |
|---------|--------|---------|----------|----------|
| rds-prod | AWS Wrapper | failover2, efm2 | INFO | 生产环境 |
| rds-dev | AWS Wrapper | failover2, efm2 | FINE | 开发环境 |
| rds-standard | MySQL Connector/J | 无 | - | 标准 MySQL |

## 相关文档

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora 配置指南
- [README.md](README.md) - 项目主文档
- [LOG_FILES_EXPLAINED.md](LOG_FILES_EXPLAINED.md) - 日志文件说明

## 总结

1. ✅ 使用 `.env.rds` 文件管理环境变量
2. ✅ RDS 不支持 BG Plugin，使用 failover2 和 efm2
3. ✅ 选择合适的 profile（prod/dev/standard）
4. ✅ 配置安全组和网络
5. ✅ 启用 SSL/TLS 连接
6. ✅ 监控日志和性能

如有问题，请查看日志文件或参考相关文档。
