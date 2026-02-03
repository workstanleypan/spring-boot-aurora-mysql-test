# Aurora MySQL Blue/Green Test Environment

一键部署 Aurora MySQL 集群并创建蓝绿部署（支持版本升级）。

## 快速开始

```bash
# 1. 部署 Blue 集群 (3.04.2)
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# 2. 创建蓝绿部署，升级到 3.10.0 LTS
./deploy.sh create-bluegreen

# 3. 查看状态
./deploy.sh status
```

## 版本升级场景

默认配置：
- **Blue 集群**: 8.0.mysql_aurora.3.04.2
- **Green 集群**: 8.0.mysql_aurora.3.10.0 (LTS)

自定义版本：
```bash
# 使用 3.08.1 作为 Blue，升级到 3.10.1
ENGINE_VERSION=8.0.mysql_aurora.3.08.1 \
TARGET_ENGINE_VERSION=8.0.mysql_aurora.3.10.1 \
DB_PASSWORD=YourPassword123 \
./deploy.sh deploy

./deploy.sh create-bluegreen
```

## 支持的版本

| Blue 集群版本 | Green 集群版本 (LTS) |
|--------------|---------------------|
| 3.04.2, 3.04.3 | 3.10.0, 3.10.1 |
| 3.08.0, 3.08.1 | 3.10.0, 3.10.1 |
| 3.09.0, 3.09.1 | 3.10.0, 3.10.1 |

## 命令说明

| 命令 | 说明 |
|------|------|
| `deploy` | 部署 VPC 和 Blue Aurora 集群 |
| `create-bluegreen` | 创建蓝绿部署（升级到 Green 版本） |
| `status` | 查看部署状态 |
| `outputs` | 显示 CloudFormation 输出 |
| `delete` | 删除所有资源 |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `STACK_NAME` | aurora-bg-test | CloudFormation 栈名称 |
| `AWS_REGION` | us-east-1 | AWS 区域 |
| `DB_PASSWORD` | - | 数据库密码（必填） |
| `INSTANCE_CLASS` | db.t3.medium | 实例类型 |
| `ENGINE_VERSION` | 8.0.mysql_aurora.3.04.2 | Blue 集群版本 |
| `TARGET_ENGINE_VERSION` | 8.0.mysql_aurora.3.10.0 | Green 集群版本 |

## 部署流程

```
1. deploy
   └── 创建 VPC、子网、安全组
   └── 创建 2 个 Aurora 集群 (Blue, 版本 3.04.2)

2. create-bluegreen
   └── 为每个集群创建蓝绿部署
   └── Green 集群自动升级到 3.10.0 LTS
   └── 等待 10-30 分钟

3. 测试应用连接
   └── 应用连接到 Blue 集群
   └── 执行 switchover 切换到 Green

4. delete
   └── 删除蓝绿部署
   └── 删除 CloudFormation 栈
```

## 执行蓝绿切换

```bash
# 查看蓝绿部署状态
./deploy.sh status

# 执行切换（将流量切换到 Green 集群）
aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier <bg-id> \
    --switchover-timeout 300
```

## 连接应用

```bash
# 获取连接信息
./deploy.sh outputs

# 配置应用
cd ../
cat > .env << 'EOF'
export AURORA_CLUSTER_ENDPOINT="<cluster-endpoint>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="<your-password>"
export WRAPPER_LOG_LEVEL="INFO"
EOF

source .env
./run-aurora.sh prod
```

## 清理资源

```bash
./deploy.sh delete
```

## 费用估算

- 2 x db.t3.medium Blue 集群: ~$0.08/小时
- 2 x db.t3.medium Green 集群 (蓝绿部署): ~$0.08/小时
- 总计: ~$0.16/小时（蓝绿部署期间）

**建议测试完成后及时删除资源！**
