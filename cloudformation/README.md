# Aurora MySQL Blue/Green Test Environment

一键部署 Aurora MySQL 集群并创建蓝绿部署（支持版本升级到 3.10.x LTS）。

## 快速开始

```bash
cd cloudformation

# 1. 部署 Aurora 集群 (约 15-20 分钟)
./deploy.sh deploy

# 2. 初始化数据库表
./deploy.sh init-db

# 3. 创建蓝绿部署 (约 20-30 分钟)
./deploy.sh create-bluegreen

# 4. 查看状态
./deploy.sh status
```

## 默认配置

| 配置项 | 默认值 |
|--------|--------|
| 栈名称 | aurora-bg-test |
| 区域 | us-east-1 |
| 数据库密码 | AuroraTest123! |
| 实例类型 | db.t3.medium |
| Blue 版本 | 8.0.mysql_aurora.3.04.2 |
| Green 版本 | 8.0.mysql_aurora.3.10.3 (LTS) |

## 部署的资源

- 1 个 VPC（含 2 个公有子网）
- 2 个 Aurora MySQL 集群
  - 每个集群 2 个实例（1 Writer + 1 Reader）
- 2 个蓝绿部署（升级到 3.10.3 LTS）

## 命令说明

| 命令 | 说明 |
|------|------|
| `deploy` | 部署 VPC 和 Aurora 集群 |
| `init-db` | 初始化数据库表 |
| `create-bluegreen` | 创建蓝绿部署 |
| `status` | 查看部署状态 |
| `outputs` | 显示连接信息 |
| `delete` | 删除所有资源 |

## 数据库表结构

初始化脚本创建以下表：

```sql
-- 用户表
users (id, name, email, created_at, updated_at)

-- 测试数据表
test_data (id, data_key, data_value, version, created_at, updated_at)

-- 连接日志表（用于跟踪切换）
connection_log (id, connection_id, server_id, aurora_version, is_writer, logged_at)
```

## 连接应用

部署完成后：

```bash
# 获取连接信息
./deploy.sh outputs

# 配置应用环境变量
cd ..
cat > .env << 'EOF'
export AURORA_CLUSTER_ENDPOINT="<从 outputs 获取>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="AuroraTest123!"
export WRAPPER_LOG_LEVEL="INFO"
EOF

source .env
./run-aurora.sh prod
```

## 执行蓝绿切换

```bash
# 查看蓝绿部署状态
./deploy.sh status

# 执行切换
aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier <bg-id> \
    --switchover-timeout 300
```

## 清理资源

```bash
./deploy.sh delete
```

**重要：测试完成后请及时删除资源，避免产生不必要的费用！**

## 费用估算

- 4 x db.t3.medium 实例: ~$0.16/小时
- 蓝绿部署期间额外 4 个 Green 实例: ~$0.16/小时
- 总计: ~$0.32/小时（蓝绿部署期间）

## 故障排查

### 部署失败
```bash
# 查看 CloudFormation 事件
aws cloudformation describe-stack-events --stack-name aurora-bg-test
```

### 连接失败
```bash
# 检查安全组
# 确保你的 IP 在 AllowedCIDR 范围内（默认 0.0.0.0/0）

# 测试连接
nc -zv <cluster-endpoint> 3306
```

### 蓝绿部署失败
```bash
# 查看详细状态
aws rds describe-blue-green-deployments
```
