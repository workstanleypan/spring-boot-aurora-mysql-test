# Custom Endpoint 开发指南

本文档说明如何在 AWS Advanced JDBC Wrapper 中使用 Custom Endpoint Plugin。

官方参考文档：[UsingTheCustomEndpointPlugin.md](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheCustomEndpointPlugin.md)

## 为什么 Custom Endpoint 需要额外权限

标准 cluster endpoint 和 custom endpoint 的架构差异：

```
┌─────────────────────────────────────────────────────────────────────────┐
│  标准 Cluster Endpoint 模式（不需要 AWS API）                            │
│                                                                         │
│  ┌──────────┐     SQL: SELECT topology     ┌──────────────────────┐    │
│  │          │  ──────────────────────────>  │   Aurora Cluster     │    │
│  │   App    │     数据库连接 (port 3306)     │                      │    │
│  │ + JDBC   │  <──────────────────────────  │  ┌────────┐         │    │
│  │  Wrapper │     返回拓扑信息               │  │Writer  │         │    │
│  │          │                               │  ├────────┤         │    │
│  └──────────┘                               │  │Reader  │         │    │
│                                             │  ├────────┤         │    │
│  failover 插件通过 SQL 查询系统表             │  │Reader  │         │    │
│  获取集群拓扑，完全走数据库连接               │  └────────┘         │    │
│                                             └──────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────┐
│  Custom Endpoint 模式（需要 AWS API + 数据库连接）                       │
│                                                                         │
│                                             ┌──────────────────────┐    │
│                 ② AWS API (HTTPS)           │  AWS RDS 控制面       │    │
│              DescribeDBClusterEndpoints      │                      │    │
│  ┌──────────┐  ─────────────────────────>   │  "my-custom-ep 包含:  │    │
│  │          │                               │   instance-1          │    │
│  │   App    │  <─────────────────────────   │   instance-2"         │    │
│  │ + JDBC   │    返回 endpoint 成员列表      └──────────────────────┘    │
│  │  Wrapper │                                                           │
│  │          │                               ┌──────────────────────┐    │
│  │          │   ① 数据库连接 (port 3306)     │   Aurora Cluster     │    │
│  │          │  ──────────────────────────>  │                      │    │
│  │          │                               │  ┌────────┐         │    │
│  └──────────┘                               │  │Writer  │ ← ✓    │    │
│                                             │  ├────────┤         │    │
│  Custom Endpoint Plugin 需要知道             │  │Reader  │ ← ✓    │    │
│  "哪些实例属于这个 custom endpoint"           │  ├────────┤         │    │
│  这个信息只有 RDS 控制面知道                  │  │Reader  │ ← ✗    │    │
│  → 所以必须调用 AWS API                      │  └────────┘         │    │
│  → 所以需要 AWS 凭证 + IAM 权限              └──────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘

  ✓ = 属于 custom endpoint 的实例（failover 只在这些实例间切换）
  ✗ = 不属于 custom endpoint 的实例（不会被选中）
```

简单说：custom endpoint 的成员信息是 RDS 控制面的元数据，无法通过 SQL 查询获取，所以插件必须调用 AWS API，这就引入了对 AWS 凭证和 IAM 权限的依赖。

## 额外的 Maven 依赖

Custom Endpoint Plugin 需要 AWS Java SDK RDS（v2.7.x or later）作为运行时依赖：

```xml
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>rds</artifactId>
    <version>2.42.14</version>
</dependency>
```

> 注意：该依赖可能有传递依赖（如 AWS Java SDK Core）。如果未使用 Maven 或 Gradle 等包管理器，请参考 Maven Central 确认所需的传递依赖。

## 额外的权限要求

### 第一部分：AWS IAM 权限

运行应用的 IAM 角色/用户必须拥有以下权限：

```json
{
    "Effect": "Allow",
    "Action": "rds:DescribeDBClusterEndpoints",
    "Resource": "*"
}
```

标准 cluster endpoint 不需要任何 RDS API 权限，但 custom endpoint 必须有此权限。

### 第二部分：AWS 凭证

应用运行环境必须能获取到有效的 AWS 凭证（Instance Profile、Task Role、环境变量等）。标准 cluster endpoint 如果只用用户名密码认证，不需要 AWS 凭证；custom endpoint 则必须有。

AWS SDK 依赖默认的凭证提供链（credential provider chain）进行身份认证。如果使用临时凭证（通过 AWS STS、IAM roles 或 SSO 获取），请注意这些凭证有过期时间。凭证过期且未刷新或替换时，会产生 AWS SDK 异常，插件将无法正常工作。为避免中断：

- 确保凭证提供者支持自动刷新（大多数 AWS SDK 凭证提供者会自动处理）
- 在生产环境中监控凭证过期时间
- 为临时凭证配置适当的会话持续时间
- 实现凭证相关故障的错误处理

更多关于 AWS 凭证配置的信息，请参阅 [AWS credentials documentation](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/AwsCredentials.md)。

## URL 配置变化

### 额外的 JDBC 参数（共 4 项）

| 参数 | 说明 | 官方文档 |
|------|------|----------|
| `customEndpoint`（加到 wrapperPlugins 中） | 启用 Custom Endpoint Plugin | [Custom Endpoint Plugin](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheCustomEndpointPlugin.md) |
| `customEndpointRegion` | 集群所在 region，自定义域名无法自动解析，必须显式指定 | [Custom Endpoint Plugin](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheCustomEndpointPlugin.md) |
| `clusterInstanceHostPattern` | 集群实例 DNS 模式，自定义域名下 wrapper 无法推断，需手动指定 | [Failover Plugin - Host Pattern](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheFailoverPlugin.md#host-pattern) |
| `failoverMode` | 需要根据 custom endpoint 类型设置：`READER` 类型用 `strict-reader`，`ANY` 类型用 `reader-or-writer` | [Failover Plugin - failoverMode](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheFailoverPlugin.md#failover-parameters) |

### 参数推导说明

以实际场景为例：
- 自定义域名（custom endpoint）：`my-custom-db`
- 集群 cluster endpoint：`my-aurora-cluster.cluster-abc123def456.ap-southeast-1.rds.amazonaws.com`

#### customEndpointRegion

官方文档说明：`The region of the cluster's custom endpoints. If not specified, the region will be parsed from the URL.`

标准 RDS URL（如 `xxx.ap-southeast-1.rds.amazonaws.com`）中包含 region 信息，wrapper 可以自动解析。但自定义域名 `my-custom-db` 中没有 region 信息，所以必须显式指定。从 cluster endpoint 中可以看到 region 是 `ap-southeast-1`。

```
customEndpointRegion=ap-southeast-1
```

#### clusterInstanceHostPattern

官方文档说明：`This parameter is not required unless connecting to an AWS RDS cluster via an IP address or custom domain URL. In those cases, this parameter specifies the cluster instance DNS pattern that will be used to build a complete instance endpoint. A "?" character in this pattern should be used as a placeholder for the DB instance identifiers.`

Aurora 的 DNS 命名规则：
- Cluster endpoint: `<cluster-name>.cluster-<unique-id>.<region>.rds.amazonaws.com`
- Instance endpoint: `<instance-id>.<unique-id>.<region>.rds.amazonaws.com`

从 cluster endpoint 中提取：
```
my-aurora-cluster.cluster-abc123def456.ap-southeast-1.rds.amazonaws.com
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                          去掉 "cluster-" 前缀后的部分就是实例 endpoint 的后缀
```

cluster endpoint 中 `.cluster-` 后面的部分是 `abc123def456.ap-southeast-1.rds.amazonaws.com`，这就是实例 endpoint 的域名后缀。加上 `?` 占位符：

```
clusterInstanceHostPattern=?.abc123def456.ap-southeast-1.rds.amazonaws.com
```

#### failoverMode

官方文档说明：`If you are using the failover plugin, set the failover parameter failoverMode according to the custom endpoint type.`

- Custom endpoint 类型为 `ANY` → `failoverMode=reader-or-writer`
- Custom endpoint 类型为 `READER` → `failoverMode=strict-reader`

#### 完整配置示例

```bash
export AURORA_CUSTOM_ENDPOINT="my-custom-db"
export CUSTOM_ENDPOINT_REGION="ap-southeast-1"
export CLUSTER_INSTANCE_HOST_PATTERN="?.abc123def456.ap-southeast-1.rds.amazonaws.com"
export FAILOVER_MODE="reader-or-writer"
```

### 标准 cluster endpoint

```
jdbc:aws-wrapper:mysql://my-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&clusterId=my-cluster-id&bgdId=my-cluster-id
```

### 使用 custom endpoint（以 my-custom-db 为例）

```
jdbc:aws-wrapper:mysql://my-custom-db:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,customEndpoint,failover2,efm2,bg&clusterId=my-cluster-id&bgdId=my-cluster-id&customEndpointRegion=ap-southeast-1&clusterInstanceHostPattern=?.abc123def456.ap-southeast-1.rds.amazonaws.com&failoverMode=reader-or-writer
```

## 快速开始

### 1. 部署基础设施（包含 Custom Endpoint）

```bash
cd cloudformation
./deploy.sh
```

CloudFormation 模板会自动创建一个 type=ANY 的 custom endpoint。

### 2. 配置 DNS 映射

将自定义域名指向实际的 custom endpoint IP：

```bash
# 查询 custom endpoint 的 IP
nslookup <custom-endpoint-address-from-cloudformation-output>

# 添加到 /etc/hosts
echo "<resolved-ip> abcd" | sudo tee -a /etc/hosts
```

### 3. 设置环境变量并启动

```bash
source .env

export AURORA_CUSTOM_ENDPOINT="abcd"
export CUSTOM_ENDPOINT_REGION="us-east-1"
export CLUSTER_INSTANCE_HOST_PATTERN="?.us-east-1.rds.amazonaws.com"
export FAILOVER_MODE="reader-or-writer"

./run-custom-endpoint.sh prod
```
