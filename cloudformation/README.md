# Aurora MySQL Blue/Green Test Environment

一键部署两个 Aurora MySQL 集群并自动创建蓝绿部署。

## 快速开始

```bash
# 1. 部署 Aurora 集群
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# 2. 等待集群就绪后，创建蓝绿部署
./deploy.sh create-bluegreen

# 3. 查看状态
./deploy.sh status
```

## 命令说明

| 命令 | 说明 |
|------|------|
| `deploy` | 部署 VPC、Aurora 集群 |
| `create-bluegreen` | 为两个集群创建蓝绿部署 |
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

## 部署的资源

- 1 个 VPC（含 2 个公有子网）
- 2 个 Aurora MySQL 集群（各 1 个实例）
- 2 个蓝绿部署

## 连接测试

部署完成后，获取连接信息：

```bash
./deploy.sh outputs
```

配置应用：

```bash
# 复制输出的 EnvFileContent 到 .env 文件
cd ../
source .env
./run-aurora.sh prod
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

## 费用估算

- 2 x db.t3.medium: ~$0.08/小时
- 蓝绿部署会创建额外的 Green 集群
- 建议测试完成后及时删除

## 注意事项

1. 蓝绿部署创建需要 10-30 分钟
2. 确保 AWS CLI 已配置正确的凭证
3. 默认允许所有 IP 访问，生产环境请修改 `AllowedCIDR`
