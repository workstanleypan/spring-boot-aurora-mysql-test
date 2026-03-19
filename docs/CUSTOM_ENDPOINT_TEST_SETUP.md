# Custom Endpoint 测试环境配置指南

本文档提供在 EC2 上配置和运行 Custom Endpoint 测试的完整步骤，包含 AWS Console 和 AWS CLI 两种操作方式。

前提条件：
- 已有一个运行中的 Aurora MySQL 集群
- 已有一台与集群在同一 VPC 的 EC2 实例
- EC2 上已部署本项目并完成 `mvn clean package -DskipTests`

---

## 第一部分：IAM 权限配置

Custom Endpoint Plugin 需要调用 `rds:DescribeDBClusterEndpoints` API，因此运行应用的 EC2 必须有对应的 IAM 权限。

### 方式 A：AWS Console 操作

#### A1. 检查 EC2 是否已有 IAM Role

1. 打开 [EC2 Console](https://console.aws.amazon.com/ec2/)
2. 选择你的实例 → 点击 "Security" 标签页
3. 查看 "IAM Role" 字段
   - 如果已有 Role → 跳到 A3（给现有 Role 加权限）
   - 如果为空 → 继续 A2（创建新 Role）

#### A2. 创建 IAM Role 并绑定到 EC2

1. 打开 [IAM Console](https://console.aws.amazon.com/iam/) → Roles → Create role
2. Trusted entity type: 选择 "AWS service"
3. Use case: 选择 "EC2" → Next
4. 暂时不附加 Policy，直接 Next
5. Role name: 输入 `EC2-CustomEndpoint-Role` → Create role
6. 回到 EC2 Console → 选择实例 → Actions → Security → Modify IAM role
7. 选择刚创建的 `EC2-CustomEndpoint-Role` → Update IAM role

#### A3. 添加 rds:DescribeDBClusterEndpoints 权限

1. 打开 [IAM Console](https://console.aws.amazon.com/iam/) → Policies → Create policy
2. 选择 JSON 编辑器，输入：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "rds:DescribeDBClusterEndpoints",
            "Resource": "*"
        }
    ]
}
```

3. Next → Policy name: 输入 `RDS-DescribeClusterEndpoints` → Create policy
4. 回到 Roles → 找到 EC2 绑定的 Role → Attach policies
5. 搜索 `RDS-DescribeClusterEndpoints` → Attach

#### A4. 验证权限

在 EC2 上执行：

```bash
aws rds describe-db-cluster-endpoints --region <your-region> --query 'DBClusterEndpoints[0].Endpoint'
```

返回 endpoint 地址说明权限配置成功。

### 方式 B：AWS CLI 操作

#### B1. 检查 EC2 是否已有 IAM Role

```bash
# 查看实例的 IAM Instance Profile
aws ec2 describe-instances \
    --instance-ids <your-instance-id> \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text
```

如果输出 `None`，需要创建并绑定 Role（B2）。如果已有 Role，跳到 B3。

#### B2. 创建 IAM Role 并绑定到 EC2

```bash
# 1. 创建信任策略文件
cat > /tmp/ec2-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# 2. 创建 Role
aws iam create-role \
    --role-name EC2-CustomEndpoint-Role \
    --assume-role-policy-document file:///tmp/ec2-trust-policy.json

# 3. 创建 Instance Profile
aws iam create-instance-profile \
    --instance-profile-name EC2-CustomEndpoint-Profile

# 4. 将 Role 添加到 Instance Profile
aws iam add-role-to-instance-profile \
    --instance-profile-name EC2-CustomEndpoint-Profile \
    --role-name EC2-CustomEndpoint-Role

# 5. 绑定到 EC2（等待几秒让 Instance Profile 生效）
sleep 5
aws ec2 associate-iam-instance-profile \
    --instance-id <your-instance-id> \
    --iam-instance-profile Name=EC2-CustomEndpoint-Profile
```

#### B3. 添加 rds:DescribeDBClusterEndpoints 权限

```bash
# 1. 创建权限策略文件
cat > /tmp/custom-endpoint-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "rds:DescribeDBClusterEndpoints",
            "Resource": "*"
        }
    ]
}
EOF

# 2. 创建 Policy
aws iam create-policy \
    --policy-name RDS-DescribeClusterEndpoints \
    --policy-document file:///tmp/custom-endpoint-policy.json

# 3. 获取 Policy ARN（替换 <account-id>）
# 或者从上一步的输出中获取
POLICY_ARN="arn:aws:iam::<account-id>:policy/RDS-DescribeClusterEndpoints"

# 4. 附加到 Role（替换为实际的 Role 名称）
aws iam attach-role-policy \
    --role-name EC2-CustomEndpoint-Role \
    --policy-arn $POLICY_ARN
```

#### B4. 验证权限

```bash
aws rds describe-db-cluster-endpoints \
    --region <your-region> \
    --query 'DBClusterEndpoints[0].Endpoint'
```

---

## 第二部分：创建 Custom Endpoint

### 方式 A：AWS Console 操作

1. 打开 [RDS Console](https://console.aws.amazon.com/rds/) → Databases
2. 点击你的 Aurora 集群名称
3. 滚动到 "Endpoints" 部分 → 点击 "Create custom endpoint"
4. 配置：
   - Endpoint identifier: 输入名称，如 `my-custom-ep`
   - Endpoint type: 选择 `ANY`（或 `READER`，根据需求）
   - Static members: 选择要包含的实例（或留空表示包含所有）
5. Create endpoint
6. 等待状态变为 "Available"，记下 endpoint 地址

### 方式 B：AWS CLI 操作

```bash
# 1. 创建 custom endpoint（type=ANY，包含所有实例）
aws rds create-db-cluster-endpoint \
    --db-cluster-identifier <your-cluster-name> \
    --db-cluster-endpoint-identifier my-custom-ep \
    --endpoint-type ANY \
    --region <your-region>

# 2. 等待 endpoint 可用
aws rds describe-db-cluster-endpoints \
    --db-cluster-endpoint-identifier my-custom-ep \
    --region <your-region> \
    --query 'DBClusterEndpoints[0].[Status,Endpoint]' \
    --output text

# 输出示例：
# available    my-custom-ep.cluster-custom-xxxxx.<region>.rds.amazonaws.com
```

如果需要创建 READER 类型的 custom endpoint：

```bash
aws rds create-db-cluster-endpoint \
    --db-cluster-identifier <your-cluster-name> \
    --db-cluster-endpoint-identifier my-reader-ep \
    --endpoint-type READER \
    --region <your-region>
```

---

## 第三部分：配置 DNS 映射

将自定义域名映射到 custom endpoint 的实际 IP，模拟客户使用 CNAME 的场景。

### 方式 A：/etc/hosts（最简单，适合测试）

```bash
# 1. 解析 custom endpoint 的 IP
nslookup my-custom-ep.cluster-custom-xxxxx.<region>.rds.amazonaws.com

# 2. 添加映射（替换为实际 IP）
echo "<resolved-ip> my-custom-db" | sudo tee -a /etc/hosts

# 3. 验证
ping -c 1 my-custom-db
```

> ⚠️ 注意：/etc/hosts 是静态映射。如果 Aurora 发生 failover，实例 IP 会变化，需要手动更新。仅适合短期测试。

### 方式 B：Route 53 Private Hosted Zone（更接近生产环境）

#### Console 操作

1. 打开 [Route 53 Console](https://console.aws.amazon.com/route53/) → Hosted zones → Create hosted zone
2. Domain name: 输入 `internal.test`（或任意内部域名）
3. Type: 选择 "Private hosted zone"
4. VPC: 选择集群所在的 VPC → Create
5. 在 hosted zone 中 → Create record
6. 配置：
   - Record name: `my-custom-db`
   - Record type: `CNAME`
   - Value: 填入 custom endpoint 的完整地址（如 `my-custom-ep.cluster-custom-xxxxx.<region>.rds.amazonaws.com`）
   - TTL: `60`
7. Create records

#### CLI 操作

```bash
# 1. 创建 Private Hosted Zone
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
    --name internal.test \
    --caller-reference "custom-ep-test-$(date +%s)" \
    --vpc VPCRegion=<your-region>,VPCId=<your-vpc-id> \
    --query 'HostedZone.Id' \
    --output text)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"

# 2. 创建 CNAME 记录
cat > /tmp/route53-record.json << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "my-custom-db.internal.test",
                "Type": "CNAME",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "my-custom-ep.cluster-custom-xxxxx.<region>.rds.amazonaws.com"
                    }
                ]
            }
        }
    ]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file:///tmp/route53-record.json

# 3. 验证（可能需要等待几秒）
nslookup my-custom-db.internal.test
```

> 使用 Route 53 CNAME 的好处：Aurora failover 后 custom endpoint DNS 会自动更新指向新 IP，CNAME 跟着解析，不需要手动干预。

---

## 第四部分：配置环境变量并启动测试

### 1. 获取 cluster endpoint 信息

```bash
# 查看集群的 cluster endpoint
aws rds describe-db-clusters \
    --db-cluster-identifier <your-cluster-name> \
    --region <your-region> \
    --query 'DBClusters[0].Endpoint' \
    --output text

# 输出示例：
# <your-cluster-name>.cluster-xxxxx.<region>.rds.amazonaws.com
```

### 2. 推导 clusterInstanceHostPattern

从 cluster endpoint 中提取：

```
<your-cluster-name>.cluster-xxxxx.<region>.rds.amazonaws.com
                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                            去掉 "cluster-" 前缀 → xxxxx.<region>.rds.amazonaws.com
                            加上 ? 占位符 → ?.xxxxx.<region>.rds.amazonaws.com
```

### 3. 设置环境变量

```bash
# 基础配置
source .env

# Custom endpoint 配置
export AURORA_CUSTOM_ENDPOINT="my-custom-db"           # /etc/hosts 方式
# export AURORA_CUSTOM_ENDPOINT="my-custom-db.internal.test"  # Route 53 方式
export CUSTOM_ENDPOINT_REGION="<your-region>"
export CLUSTER_INSTANCE_HOST_PATTERN="?.xxxxx.<region>.rds.amazonaws.com"
export FAILOVER_MODE="reader-or-writer"                # ANY 类型用这个
# export FAILOVER_MODE="strict-reader"                 # READER 类型用这个
```

### 4. 启动应用

```bash
./run-custom-endpoint.sh prod
```

脚本会自动：
- 校验所有必要的环境变量
- 检查 DNS 解析
- 测试网络连通性
- 使用 `custom-endpoint-prod` profile 启动应用

### 5. 运行测试

应用启动后，通过现有的 API 接口运行测试：

```bash
# 快速连接测试
curl http://localhost:8080/api/test

# 启动 Blue/Green 读写测试
curl -X POST http://localhost:8080/api/bluegreen/start \
    -H "Content-Type: application/json" \
    -d '{"numThreads": 10, "readsPerSecond": 100, "writesPerSecond": 5, "durationSeconds": 300}'

# 查看测试状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop
```

---

## 清理资源

### 删除 Custom Endpoint

Console: RDS Console → 集群 → Endpoints → 选择 custom endpoint → Delete

```bash
aws rds delete-db-cluster-endpoint \
    --db-cluster-endpoint-identifier my-custom-ep \
    --region <your-region>
```

### 删除 Route 53 记录（如果使用了方式 B）

Console: Route 53 → Hosted zones → 选择 zone → 删除 CNAME 记录 → 删除 hosted zone

```bash
# 删除记录（将 Action 改为 DELETE）
# 删除 hosted zone
aws route53 delete-hosted-zone --id $HOSTED_ZONE_ID
```

### 清理 /etc/hosts（如果使用了方式 A）

```bash
sudo sed -i '/my-custom-db/d' /etc/hosts
```

### 删除 IAM 资源（如果是新创建的）

Console: IAM Console → 分别删除 Policy、Role、Instance Profile

```bash
aws iam detach-role-policy \
    --role-name EC2-CustomEndpoint-Role \
    --policy-arn arn:aws:iam::<account-id>:policy/RDS-DescribeClusterEndpoints

aws iam delete-policy \
    --policy-arn arn:aws:iam::<account-id>:policy/RDS-DescribeClusterEndpoints

aws iam remove-role-from-instance-profile \
    --instance-profile-name EC2-CustomEndpoint-Profile \
    --role-name EC2-CustomEndpoint-Role

aws iam delete-instance-profile \
    --instance-profile-name EC2-CustomEndpoint-Profile

aws iam delete-role \
    --role-name EC2-CustomEndpoint-Role
```
