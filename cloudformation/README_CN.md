# Aurora MySQL 蓝绿测试环境

一键部署 Aurora MySQL 集群并创建蓝绿部署测试环境。

## 快速开始

```bash
cd cloudformation

# 1. 配置（可选）
cp config.env config.local.env
# 编辑 config.local.env 设置参数

# 2. 部署集群 (~15-20 分钟)
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# 3. 初始化数据库（创建测试用户）
./deploy.sh init-db

# 4. 创建蓝绿部署 (~20-30 分钟)
./deploy.sh create-bluegreen

# 5. 查看状态
./deploy.sh status
```

## 配置文件

编辑 `config.local.env`：

```bash
# 核心配置
CLUSTER_COUNT=1               # 集群数量 (1-3)
INSTANCES_PER_CLUSTER=2       # 每集群实例数 (1-3)
ENGINE_VERSION=8.0.mysql_aurora.3.04.2    # Blue 版本
TARGET_VERSION=8.0.mysql_aurora.3.10.3    # Green 目标版本

# 数据库
DB_PASSWORD=YourPassword      # 必填
DB_USERNAME=admin
DB_NAME=testdb
INSTANCE_CLASS=db.t3.medium

# VPC（自动检测默认 VPC）
USE_EXISTING_VPC=true
VPC_ID=                       # 留空自动检测
```

## 命令行示例

```bash
# 单集群（默认）
DB_PASSWORD=MyPass ./deploy.sh deploy

# 2 个集群
CLUSTER_COUNT=2 DB_PASSWORD=MyPass ./deploy.sh deploy

# 3 个集群，每个 3 实例
CLUSTER_COUNT=3 INSTANCES_PER_CLUSTER=3 DB_PASSWORD=MyPass ./deploy.sh deploy

# 指定版本
ENGINE_VERSION=8.0.mysql_aurora.3.08.0 DB_PASSWORD=MyPass ./deploy.sh deploy
```

## 命令说明

| 命令 | 说明 |
|------|------|
| `deploy` | 部署 Aurora 集群 |
| `init-db` | 初始化数据库，创建测试用户 |
| `create-bluegreen` | 创建蓝绿部署 |
| `status` | 查看部署状态 |
| `outputs` | 显示连接信息 |
| `show-config` | 显示当前配置 |
| `delete` | 删除所有资源 |

## 测试用户

`init-db` 命令创建以下测试用户：

| 用户 | 密码 | 权限 |
|------|------|------|
| testuser1 | testuser | SELECT on mysql.*, ALL on testdb.* |
| testuser2 | testuser | SELECT on mysql.*, ALL on testdb.* |
| testuser3 | testuser | SELECT on mysql.*, ALL on testdb.* |

## 安全说明

- Aurora 集群**不对外公开**（PubliclyAccessible: false）
- 安全组仅允许 VPC 内部访问（自动检测 VPC CIDR）
- 需要从同一 VPC 内的 EC2 实例访问数据库

## 连接应用

```bash
# 获取连接信息
./deploy.sh outputs

# 配置环境变量
export AURORA_CLUSTER_ENDPOINT="<从 outputs 获取>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="testuser1"
export AURORA_PASSWORD="testuser"

# 运行应用
cd ..
./run-aurora.sh
```

## 执行蓝绿切换

```bash
# 查看蓝绿部署 ID
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

⚠️ **测试完成后请及时删除资源，避免产生费用！**

## 费用估算

- db.t3.medium: ~$0.04/小时/实例
- 默认配置 (1 集群 × 2 实例): ~$0.08/小时
- 蓝绿部署期间 Green 实例: 费用翻倍

## 故障排查

```bash
# CloudFormation 事件
aws cloudformation describe-stack-events --stack-name aurora-bg-test

# 测试连接（需要在 VPC 内）
nc -zv <cluster-endpoint> 3306

# 蓝绿部署状态
aws rds describe-blue-green-deployments
```

## 支持的 Aurora 版本

**Blue 集群版本：**
- 3.04.x (MySQL 8.0.28)
- 3.08.x (MySQL 8.0.36)
- 3.09.x (MySQL 8.0.37)

**Green 目标版本：**
- 3.10.x LTS (MySQL 8.0.39) - 推荐
