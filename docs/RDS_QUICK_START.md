# RDS MySQL 快速开始

## 5 分钟快速配置

### 步骤 1: 准备环境变量

```bash
cd spring-boot-mysql-test

# 复制模板文件
cp .env.rds.template .env.rds

# 编辑 .env.rds 文件，填入你的 RDS 配置
nano .env.rds
```

编辑内容：
```bash
export RDS_ENDPOINT="your-rds-endpoint.rds.amazonaws.com"
export RDS_DATABASE="testdb"
export RDS_USERNAME="admin"
export RDS_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="INFO"
```

### 步骤 2: 加载环境变量

```bash
source .env.rds
```

### 步骤 3: 启动应用

```bash
# 生产环境（INFO 日志，AWS Wrapper）
./run-rds.sh prod

# 或开发环境（FINE 详细日志，AWS Wrapper）
./run-rds.sh dev

# 或标准驱动（无 AWS Wrapper）
./run-rds.sh standard
```

### 步骤 4: 验证连接

在另一个终端：

```bash
# 测试连接
curl http://localhost:8080/api/test

# 查看日志
tail -f logs/jdbc-wrapper.log
```

## 一行命令启动

如果不想创建 .env.rds 文件：

```bash
RDS_ENDPOINT="your-rds-endpoint.rds.amazonaws.com" \
RDS_DATABASE="testdb" \
RDS_USERNAME="admin" \
RDS_PASSWORD="your-password" \
./run-rds.sh prod
```

## 可用的 Profiles

| Profile | 说明 | 日志级别 | 插件 | 使用场景 |
|---------|------|----------|------|----------|
| `rds-prod` | 生产环境 | INFO | failover2, efm2 | 生产部署 |
| `rds-dev` | 开发环境 | FINE | failover2, efm2 | 开发调试 |
| `rds-standard` | 标准驱动 | - | 无 | 不需要 AWS 特性 |

## RDS vs Aurora

| 特性 | RDS MySQL | Aurora MySQL |
|------|-----------|--------------|
| 端点类型 | 实例端点 | 集群端点 |
| BG Plugin | ❌ 不支持 | ✅ 支持 |
| Failover | ✅ 支持 | ✅ 支持 |
| 推荐插件 | failover2, efm2 | bg, failover2, efm2 |

## 查看日志

```bash
# 所有日志
tail -f logs/info.log

# JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# Failover 相关日志
tail -f logs/jdbc-wrapper.log | grep -i failover

# 错误日志
tail -f logs/error.log
```

## 常见问题

### 连接超时

```bash
# 测试网络
nc -zv your-rds-endpoint.rds.amazonaws.com 3306

# 检查安全组
# 确保允许你的 IP 访问端口 3306
```

### 认证失败

```bash
# 测试用户名密码
mysql -h your-rds-endpoint.rds.amazonaws.com \
      -u admin -p testdb
```

### 获取 RDS 端点

```bash
# 使用 AWS CLI
aws rds describe-db-instances \
  --db-instance-identifier database-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

## 停止应用

```bash
# 查找进程
ps aux | grep spring-boot-mysql-test | grep -v grep

# 停止
pkill -f spring-boot-mysql-test

# 或在运行终端按 Ctrl+C
```

## 下一步

- 查看完整配置指南: [RDS_CONFIGURATION_GUIDE.md](RDS_CONFIGURATION_GUIDE.md)
- 了解日志系统: [LOG_FILES_EXPLAINED.md](LOG_FILES_EXPLAINED.md)
- Aurora 配置: [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md)
