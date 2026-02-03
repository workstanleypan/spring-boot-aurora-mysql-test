# Aurora MySQL 快速开始

## 5 分钟快速配置

### 步骤 1: 准备环境变量

```bash
cd spring-boot-mysql-test

# 复制模板文件
cp .env.template .env

# 编辑 .env 文件，填入你的 Aurora 配置
nano .env
```

编辑内容：
```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="INFO"
```

### 步骤 2: 加载环境变量

```bash
source .env
```

### 步骤 3: 启动应用

```bash
# 生产环境（INFO 日志）
./run-aurora.sh prod

# 或开发环境（FINE 详细日志）
./run-aurora.sh dev
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

如果不想创建 .env 文件：

```bash
AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
./run-aurora.sh prod
```

## 可用的 Profiles

| Profile | 说明 | 日志级别 | 使用场景 |
|---------|------|----------|----------|
| `aurora-prod` | 生产环境 | INFO | 生产部署 |
| `aurora-dev` | 开发环境 | FINE | 开发调试 |
| `aws-wrapper-bg` | 本地测试 | FINE | 本地 MySQL + BG Plugin |
| `default` | 标准 MySQL | - | 本地 MySQL（无 Wrapper） |

## 查看日志

```bash
# 所有日志
tail -f logs/info.log

# JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# BG Plugin 日志
tail -f logs/jdbc-wrapper.log | grep -i "blue.*green"

# 错误日志
tail -f logs/error.log
```

## 常见问题

### 连接超时

```bash
# 测试网络
nc -zv your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306

# 检查安全组
# 确保允许你的 IP 访问端口 3306
```

### 认证失败

```bash
# 测试用户名密码
mysql -h your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com \
      -u admin -p testdb
```

### BG Plugin 不工作

确保使用**集群端点**（包含 `.cluster-`），不是实例端点：

✅ 正确: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`  
❌ 错误: `database-1-instance-1.xxxxx.us-east-1.rds.amazonaws.com`

## 停止应用

```bash
# 查找进程
ps aux | grep spring-boot-mysql-test | grep -v grep

# 停止
pkill -f spring-boot-mysql-test

# 或在运行终端按 Ctrl+C
```

## 下一步

- 查看完整配置指南: [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md)
- 了解 BG Plugin: [查看BG_Plugin日志.md](查看BG_Plugin日志.md)
- Nacos 集成: [NACOS_CONFIGURATION.md](NACOS_CONFIGURATION.md)
