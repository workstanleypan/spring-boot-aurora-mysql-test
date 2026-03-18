# Custom Endpoint 开发指南

本文档说明如何在 AWS Advanced JDBC Wrapper 中使用 Custom Endpoint Plugin。

官方参考文档：[UsingTheCustomEndpointPlugin.md](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheCustomEndpointPlugin.md)

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

| 参数 | 说明 |
|------|------|
| `customEndpoint`（加到 wrapperPlugins 中） | 启用 Custom Endpoint Plugin |
| `customEndpointRegion` | 集群所在 region，自定义域名无法自动解析，必须显式指定 |
| `clusterInstanceHostPattern` | 集群实例 DNS 模式（`?.{region}.rds.amazonaws.com`），自定义域名下 wrapper 无法推断 |
| `failoverMode` | 需要根据 custom endpoint 类型设置：`READER` 类型用 `strict-reader`，`ANY` 类型用 `reader-or-writer` |

### 标准 cluster endpoint

```
jdbc:aws-wrapper:mysql://my-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&clusterId=my-cluster-id&bgdId=my-cluster-id
```

### 使用 custom endpoint（以 abcd 为例）

```
jdbc:aws-wrapper:mysql://abcd:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,customEndpoint,failover2,efm2,bg&clusterId=my-cluster-id&bgdId=my-cluster-id&customEndpointRegion=us-east-1&clusterInstanceHostPattern=?.us-east-1.rds.amazonaws.com&failoverMode=reader-or-writer
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
