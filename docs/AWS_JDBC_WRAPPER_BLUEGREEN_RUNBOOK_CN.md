# AWS Advanced JDBC Wrapper Blue/Green 部署运维手册

本手册提供使用 AWS Advanced JDBC Wrapper (v3.2.0+) 配合 Aurora MySQL Blue/Green 部署的完整指南，涵盖配置、测试流程、监控和故障排除。

## 目录

1. [概述](#概述)
2. [前置条件](#前置条件)
3. [架构](#架构)
4. [配置](#配置)
5. [部署流程](#部署流程)
6. [测试流程](#测试流程)
7. [监控与日志](#监控与日志)
8. [故障排除](#故障排除)
9. [最佳实践](#最佳实践)

---

## 概述

### 什么是 Blue/Green 部署？

Blue/Green 部署是一种发布策略，可以在两个相同的环境（蓝色和绿色）之间无缝切换流量。对于 Aurora MySQL，这允许：

- 零停机数据库升级
- 安全的回滚能力
- 切换期间最小化应用中断

### Blue/Green 插件的作用

AWS Advanced JDBC Wrapper 的 `bg` 插件在 Blue/Green 切换期间主动管理数据库连接：

1. **监控** - 持续跟踪 Blue/Green 部署状态
2. **流量管理** - 适当地暂停、透传或重新路由数据库流量
3. **DNS 处理** - 用 IP 地址替换主机名以避免 DNS 缓存问题
4. **连接路由** - 确保连接到正确的集群（蓝色或绿色）
5. **自动恢复** - 切换完成后恢复正常操作

### 支持的配置

| 数据库类型 | 支持 | 说明 |
|-----------|------|------|
| Aurora MySQL | ✅ 是 | 引擎版本 3.07+ 支持完整元数据 |
| Aurora PostgreSQL | ✅ 是 | 引擎版本 17.5, 16.9, 15.13, 14.18, 13.21+ |
| RDS MySQL | ✅ 是 | 无版本限制 |
| RDS PostgreSQL | ✅ 是 | 需要 `rds_tools` 扩展 v1.7+ |
| RDS Multi-AZ 集群 | ❌ 否 | 不支持 |
| Aurora Global Database | ❌ 否 | 不支持 |

---

## 前置条件

### 软件要求

- Java 17+
- AWS Advanced JDBC Wrapper 3.2.0+
- Spring Boot 3.x（推荐）或兼容框架
- MySQL 客户端（用于数据库初始化）
- AWS CLI（用于 CloudFormation 部署）

### 网络要求

- 可直接访问蓝色和绿色集群端点
- 安全组允许 3306 端口入站流量
- **重要**：绿色集群运行在不同的实例上，具有不同的 IP 地址

### 数据库权限

对于非管理员用户，以下权限在**蓝色和绿色集群上都是必需的**：

**Aurora MySQL:**
```sql
GRANT SELECT ON mysql.rds_topology TO 'your_user'@'%';
FLUSH PRIVILEGES;
```

**RDS MySQL:**
```sql
GRANT SELECT ON mysql.rds_topology TO 'your_user'@'%';
FLUSH PRIVILEGES;
```

**RDS PostgreSQL:**
```sql
CREATE EXTENSION IF NOT EXISTS rds_tools;
GRANT USAGE ON SCHEMA rds_tools TO your_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rds_tools TO your_user;
```

> ⚠️ **警告**：如果未授予权限，元数据表将不可见，Blue/Green 插件将无法正常工作。

---

## 架构

### 插件链

Aurora MySQL 推荐的插件配置：

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

| 插件 | 用途 |
|------|------|
| `initialConnection` | 智能初始连接节点选择 |
| `auroraConnectionTracker` | 连接状态跟踪 |
| `failover2` | 自动故障转移处理 |
| `efm2` | 增强故障监控 |
| `bg` | Blue/Green 部署支持 |

### Blue/Green 插件状态机

```
NOT_CREATED → CREATED → PREPARATION → IN_PROGRESS → POST → COMPLETED
     ↑                                                          ↓
     └──────────────────────────────────────────────────────────┘
```

| 阶段 | 轮询间隔 | 行为 |
|------|---------|------|
| NOT_CREATED | `bgBaselineMs` (60秒) | 正常操作，未检测到 BG 部署 |
| CREATED | `bgIncreasedMs` (1秒) | 收集拓扑和 IP 地址 |
| PREPARATION | `bgHighMs` (100毫秒) | 用 IP 地址替换主机名 |
| IN_PROGRESS | `bgHighMs` (100毫秒) | **暂停所有 SQL 请求** |
| POST | `bgHighMs` (100毫秒) | 监控 DNS 更新 |
| COMPLETED | `bgBaselineMs` (60秒) | 恢复正常操作 |

### 切换期间的连接流程

```
应用程序
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│                  AWS JDBC Wrapper                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Blue/Green 插件 (bg)                    │   │
│  │  • 通过元数据表监控 BG 状态                          │   │
│  │  • IN_PROGRESS 期间暂停请求                         │   │
│  │  • 用 IP 地址替换 DNS                               │   │
│  │  • 拒绝连接到过期的绿色端点                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Failover2 + EFM2 插件                      │   │
│  │  • 检测连接失败                                      │   │
│  │  • 处理自动重连                                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────┐         ┌─────────────────┐
│  蓝色集群       │ ──────► │  绿色集群       │
│  (源)          │  切换    │  (目标)         │
└─────────────────┘         └─────────────────┘
```

---

## 配置

### JDBC URL 格式

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?
    wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&
    wrapperLoggerLevel=FINE&
    clusterId=<unique-cluster-id>&
    bgdId=<unique-bg-id>&
    bgHighMs=100&
    bgIncreasedMs=1000&
    bgBaselineMs=60000&
    bgConnectTimeoutMs=30000&
    bgSwitchoverTimeoutMs=180000
```

### Blue/Green 插件参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `bgdId` | `1` | Blue/Green 部署标识符。**多集群场景下必须唯一。** |
| `bgConnectTimeoutMs` | `30000` | 切换期间流量暂停时的连接超时（毫秒） |
| `bgBaselineMs` | `60000` | 正常操作期间的状态轮询间隔（毫秒）。保持在 900000ms（15分钟）以下 |
| `bgIncreasedMs` | `1000` | CREATED 阶段的状态轮询间隔（毫秒）。范围：500-2000ms |
| `bgHighMs` | `100` | IN_PROGRESS 阶段的状态轮询间隔（毫秒）。范围：50-500ms |
| `bgSwitchoverTimeoutMs` | `180000` | 最大切换持续时间（毫秒）。超时后驱动程序恢复正常操作 |

### 集群标识符配置

#### 单集群

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://cluster-a.cluster-xxx.rds.amazonaws.com:3306/db?
         wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&
         clusterId=cluster-a&
         bgdId=cluster-a
```

#### 多集群（关键！）

当单个应用连接多个集群时，**每个集群的 `clusterId` 和 `bgdId` 必须唯一**：

```yaml
# 集群 A
datasource-a:
  url: jdbc:aws-wrapper:mysql://cluster-a.xxx.rds.amazonaws.com:3306/db?
       clusterId=cluster-a&bgdId=cluster-a&...

# 集群 B  
datasource-b:
  url: jdbc:aws-wrapper:mysql://cluster-b.xxx.rds.amazonaws.com:3306/db?
       clusterId=cluster-b&bgdId=cluster-b&...
```

| 错误配置 | 问题 |
|---------|------|
| 不同集群使用相同 `clusterId` | 拓扑缓存混乱 - 可能路由到错误节点 |
| 不同集群使用相同 `bgdId` | BG 状态混乱 - 一个集群的切换影响另一个 |

### HikariCP 连接池配置

```yaml
spring:
  datasource:
    hikari:
      pool-name: AuroraHikariPool
      minimum-idle: 20
      maximum-pool-size: 120
      idle-timeout: 300000
      max-lifetime: 600000
      connection-timeout: 10000
      validation-timeout: 5000
      connection-test-query: SELECT 1
      # 禁用泄漏检测（持久连接测试）
      leak-detection-threshold: 0
```

### 监控连接配置

插件创建专用监控连接。使用 `blue-green-monitoring-` 前缀单独配置：

```java
Properties props = new Properties();
// 常规连接超时
props.setProperty("connectTimeout", "30000");
props.setProperty("socketTimeout", "30000");
// 监控连接超时（更短）
props.setProperty("blue-green-monitoring-connectTimeout", "10000");
props.setProperty("blue-green-monitoring-socketTimeout", "10000");
```

> ⚠️ **重要**：始终提供非零的 socket 超时或连接超时值。

---

## 部署流程

### 切换前检查清单

1. **创建 Blue/Green 部署**
   ```bash
   aws rds create-blue-green-deployment \
     --blue-green-deployment-name my-bg-deployment \
     --source arn:aws:rds:region:account:cluster:my-cluster \
     --target-engine-version 8.0.mysql_aurora.3.10.3
   ```

2. **在两个集群上授予权限**
   ```sql
   -- 在蓝色和绿色集群上都运行
   GRANT SELECT ON mysql.rds_topology TO 'app_user'@'%';
   FLUSH PRIVILEGES;
   ```

3. **部署带 BG 插件的应用**
   ```bash
   export WRAPPER_LOG_LEVEL="FINE"
   ./run-aurora.sh prod
   ```

4. **验证插件已激活**
   ```bash
   grep -i "BlueGreen" logs/wrapper-*.log
   # 应该看到: "BG status: NOT_CREATED" 或 "BG status: CREATED"
   ```

5. **等待状态收集**
   - 等待 2-5 分钟让插件收集部署状态
   - 验证: `grep -i "BG status" logs/wrapper-*.log`

### 执行切换

1. **启动持续写入测试**（可选但推荐）
   ```bash
   curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"
   ```

2. **发起切换**
   ```bash
   aws rds switchover-blue-green-deployment \
     --blue-green-deployment-identifier <deployment-id> \
     --switchover-timeout 300
   ```

3. **监控进度**
   ```bash
   # 观察 BG 状态变化
   tail -f logs/wrapper-*.log | grep -i "BG status\|Status changed"
   ```

4. **等待完成**
   - 典型切换时间：30-120 秒
   - 插件将记录：`BG status: COMPLETED`

### 切换后操作

1. **验证应用健康**
   ```bash
   curl http://localhost:8080/api/bluegreen/status
   curl http://localhost:8080/actuator/health
   ```

2. **查看切换摘要**
   ```bash
   grep -i "time offset" logs/wrapper-*.log -A 14
   ```

3. **停止测试**（如果正在运行）
   ```bash
   curl -X POST http://localhost:8080/api/bluegreen/stop
   ```

4. **可选：移除 BG 插件**
   - 成功切换后，可以移除 `bg` 插件
   - 保留也不会有负面影响

5. **删除 Blue/Green 部署**
   ```bash
   aws rds delete-blue-green-deployment \
     --blue-green-deployment-identifier <deployment-id>
   ```

---

## 测试流程

### 启动持续写入测试

```bash
# 10 个连接，每 500ms 写入一次
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# 50 个连接，尽可能快地写入
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=50&writeIntervalMs=0"
```

### 检查测试状态

```bash
curl http://localhost:8080/api/bluegreen/status
```

响应：
```json
{
  "running": true,
  "continuousMode": true,
  "enableWrites": true,
  "totalWrites": 12500,
  "successfulWrites": 12498,
  "failedWrites": 2,
  "readOnlyErrors": 0,
  "failoverCount": 1,
  "lastEndpoint": "ip-10-1-4-150:3306 [WRITER]",
  "avgWriteLatency": 8,
  "runningTime": 125
}
```

### 停止测试

```bash
curl -X POST http://localhost:8080/api/bluegreen/stop
```

### 成功标准

| 指标 | 目标 | 说明 |
|------|------|------|
| 成功率 | > 99% | 成功写入的百分比 |
| 故障转移检测 | 是 | 插件正确识别切换 |
| 自动恢复 | 是 | 切换后写入恢复 |
| 只读错误 | 0 | 正确配置 BG 插件后不应出现只读错误 |

---

## 监控与日志

### 日志级别

| 级别 | 使用场景 | 显示内容 |
|------|---------|---------|
| `INFO` | 生产环境 | 基本状态变化 |
| `FINE` | 推荐 | BG 状态、切换摘要 |
| `FINEST` | 调试 | 完整插件执行详情 |

### 关键日志模式

```bash
# 查看当前日志（每次启动新文件）
tail -f logs/wrapper-*.log

# BG 状态变化（FINE 级别）
grep -i "BG status" logs/wrapper-*.log

# 状态变化（FINEST 级别）
grep -i "Status changed to" logs/wrapper-*.log

# 切换时间线摘要
grep -i "time offset" logs/wrapper-*.log -A 14

# 连接事件
grep -i "failover\|reconnect" logs/wrapper-*.log

# 错误
grep -i "error\|exception" logs/wrapper-*.log
```

### 切换时间线示例

```
[2025-11-14 15:59:52.084] [INFO] [bgdId: '1']
---------------------------------------------------------------------------------------
timestamp                         time offset (ms)                                event
---------------------------------------------------------------------------------------
    2025-11-14T23:58:18.519Z             -28178 ms                          NOT_CREATED
    2025-11-14T23:58:19.172Z             -27525 ms                              CREATED
    2025-11-14T23:58:39.279Z              -7418 ms                          PREPARATION
    2025-11-14T23:58:46.697Z                  0 ms               Monitors reset - start
    2025-11-14T23:58:46.697Z                  0 ms                          IN_PROGRESS
    2025-11-14T23:58:49.788Z               3090 ms                                 POST
    2025-11-14T23:59:03.373Z              16675 ms               Green topology changed
    2025-11-14T23:59:03.374Z              16677 ms      Monitors reset - green topology
    2025-11-14T23:59:19.815Z              33117 ms                     Blue DNS updated
    2025-11-14T23:59:52.081Z              65383 ms                    Green DNS removed
    2025-11-14T23:59:52.082Z              65384 ms                            COMPLETED
---------------------------------------------------------------------------------------
```

### 关键时间线事件

| 事件 | 说明 |
|------|------|
| NOT_CREATED | 未检测到 BG 部署 |
| CREATED | BG 部署已创建，正在收集拓扑 |
| PREPARATION | 准备切换，用 IP 替换 DNS |
| IN_PROGRESS | **活跃切换 - SQL 请求暂停** |
| POST | 切换完成，监控 DNS 更新 |
| Blue DNS updated | 蓝色端点现在指向新（绿色）集群 |
| Green DNS removed | 旧绿色端点不再可访问 |
| COMPLETED | 切换完成，恢复正常操作 |

---

## 故障排除

### 常见问题

#### 1. BG 插件未检测到部署

**症状：**
- 日志显示 `BG status: NOT_CREATED` 即使已创建部署
- 切换期间无状态变化

**解决方案：**
- 验证数据库权限：`GRANT SELECT ON mysql.rds_topology TO 'user'@'%';`
- 检查 Aurora MySQL 版本是否为 3.07+
- 确保使用集群端点（不是实例端点）
- 等待 2-5 分钟让状态收集完成

#### 2. 连接池耗尽

**症状：**
- `Connection is not available, request timed out after 30000ms`
- `total=50, active=50, idle=0, waiting=49`

**解决方案：**
- 增加 `maximum-pool-size` 以匹配或超过线程数
- 减少 `connection-timeout` 以更快失败
- 减少并发测试线程

```yaml
hikari:
  maximum-pool-size: 120
  connection-timeout: 10000
```

#### 3. 切换期间高失败率

**症状：**
- IN_PROGRESS 阶段大量写入失败
- 只读错误

**解决方案：**
- 这是预期行为 - 插件在切换期间暂停请求
- 确保 `bgSwitchoverTimeoutMs` 足够（默认 180000ms）
- 检查到绿色集群的网络连接

#### 4. 权限错误

**症状：**
- `Access denied for user` 错误
- 插件无法读取元数据表

**解决方案：**
- 在**蓝色和绿色集群上都**授予权限：
  ```sql
  GRANT SELECT ON mysql.rds_topology TO 'user'@'%';
  FLUSH PRIVILEGES;
  ```

#### 5. 多集群混乱

**症状：**
- 集群 A 的切换影响集群 B 的连接
- 错误的拓扑信息

**解决方案：**
- 确保每个集群使用唯一的 `clusterId` 和 `bgdId`
- 验证 JDBC URL 中的配置

### 调试命令

```bash
# 检查插件加载
grep -i "plugin.*loaded\|plugin.*initialized" logs/wrapper-*.log

# 检查 BG 元数据访问
grep -i "rds_topology\|metadata" logs/wrapper-*.log

# 检查连接事件
grep -i "connection.*opened\|connection.*closed" logs/wrapper-*.log

# 检查错误
grep -i "error\|exception\|failed" logs/wrapper-*.log | head -50
```

---

## 最佳实践

### 切换前

1. **先在非生产环境测试**
   - 始终在预发布环境测试 Blue/Green 切换

2. **提前授予权限**
   - 在创建 BG 部署前在两个集群上授予权限

3. **使用 FINE 日志级别**
   - 设置 `wrapperLoggerLevel=FINE` 以捕获切换摘要

4. **验证网络访问**
   - 确保应用可以访问绿色集群 IP 地址

5. **适当调整连接池大小**
   - 池大小应匹配或超过并发线程数

### 切换期间

1. **监控日志**
   - 实时观察 BG 状态变化

2. **预期短暂暂停**
   - IN_PROGRESS 阶段 SQL 请求暂停（通常 30-60 秒）

3. **不要对错误恐慌**
   - 过渡期间一些连接错误是预期的

### 切换后

1. **查看时间线摘要**
   - 检查切换持续时间和事件

2. **验证应用健康**
   - 确认写入成功到新集群

3. **清理**
   - 成功切换后删除 BG 部署
   - 可选择从配置中移除 `bg` 插件

### 多集群环境

1. **始终使用唯一标识符**
   - 为每个集群设置唯一的 `clusterId` 和 `bgdId`

2. **独立测试每个集群**
   - 生产前验证每个集群的 BG 插件工作正常

3. **记录配置**
   - 维护集群到标识符映射的清晰文档

---

## 快速参考

### 环境变量

```bash
# 必需
export AURORA_CLUSTER_ENDPOINT="cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="password"

# 推荐
export WRAPPER_LOG_LEVEL="FINE"
export CLUSTER_ID="cluster-a"
export BGD_ID="cluster-a"

# 可选（显示默认值）
export BG_HIGH_MS="100"
export BG_INCREASED_MS="1000"
export BG_BASELINE_MS="60000"
export BG_CONNECT_TIMEOUT_MS="30000"
export BG_SWITCHOVER_TIMEOUT_MS="180000"
```

### 常用命令

```bash
# 启动应用
./run-aurora.sh prod

# 启动写入测试
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# 检查状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop

# 查看 BG 状态
grep -i "BG status" logs/wrapper-*.log

# 查看切换摘要
grep -i "time offset" logs/wrapper-*.log -A 14
```

### AWS CLI 命令

```bash
# 创建 Blue/Green 部署
aws rds create-blue-green-deployment \
  --blue-green-deployment-name my-bg \
  --source arn:aws:rds:region:account:cluster:my-cluster \
  --target-engine-version 8.0.mysql_aurora.3.10.3

# 检查状态
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier <id>

# 执行切换
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <id> \
  --switchover-timeout 300

# 删除部署
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier <id>
```

---

## 参考资料

- [AWS Advanced JDBC Wrapper 文档](https://github.com/aws/aws-advanced-jdbc-wrapper)
- [Blue/Green 插件文档](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheBlueGreenPlugin.md)
- [Aurora Blue/Green 部署](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments.html)
- [RDS Blue/Green 部署](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html)
