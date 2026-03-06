# Spring Boot Aurora MySQL 测试

Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，支持 Blue/Green Deployment 自动切换测试。

## 功能特性

- AWS Advanced JDBC Wrapper（可配置版本，默认 3.2.0）
- Blue/Green Deployment Plugin 支持
- Failover & EFM Plugin
- HikariCP 连接池
- 多线程持续写入测试
- Spring Boot（可配置版本，默认 3.4.2）
- 可配置 JDK 版本（Spring Boot 2.x 用 JDK 11，Spring Boot 3.x 用 JDK 17+）
- 多实例测试支持（同集群 / 不同集群）

## 环境要求

- Java 11+ 或 17+（取决于 Spring Boot 版本）
- Maven 3.6+
- AWS CLI（用于 CloudFormation 部署）
- Aurora MySQL 集群访问权限
- MySQL 客户端（用于数据库初始化）

> 📖 **新环境搭建**: 如果在全新的 Amazon Linux 2023 EC2 上搭建测试环境，请参考 [EC2 环境搭建指南](EC2_SETUP_GUIDE.md)

## 快速开始

### 1. 克隆并编译

```bash
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test

# 默认构建（Spring Boot 3.4.2, JDK 17, Wrapper 3.2.0）
./build.sh

# 自定义版本构建
./build.sh --sb 2.7.18 --jdk 11                    # Spring Boot 2.x + JDK 11
./build.sh --sb 3.2.0 --jdk 17 --wrapper 3.1.0     # 完全自定义

# 或者直接用 Maven（使用 pom.xml 中的默认版本）
mvn clean package -DskipTests
```

### 2. 部署 Aurora 集群（可选）

```bash
cd cloudformation

# 一键部署（推荐）
DB_PASSWORD=YourPassword123 ./deploy.sh deploy-all

# 或者分步执行：
DB_PASSWORD=YourPassword123 ./deploy.sh deploy    # 创建集群（约 15 分钟）
./deploy.sh init-db                               # 初始化数据库
./deploy.sh create-bluegreen                      # 创建蓝绿部署（约 20-30 分钟）
```

### 3. 配置并运行

**单 service 单 cluster（标准用法）：**

```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="FINE"

./run-aurora.sh prod
```

> 注意：`TABLE_PREFIX` 默认值为 `"default"`，测试表名为 `default_bg_write_test`、`default_bg_test_thread_N`，功能不受影响。

**多实例测试（详见下方[多实例蓝绿测试](#多实例蓝绿测试)）：**

```bash
# 场景 A：两个 service 连接同一个 cluster，不同表
./run-instance1.sh   # 端口 8080，TABLE_PREFIX=inst1，CLUSTER_ID=cluster-a
./run-instance2.sh   # 端口 8081，TABLE_PREFIX=inst2，CLUSTER_ID=cluster-a（共享 topology 缓存）

# 场景 B：两个 service 分别连接不同的 cluster
export AURORA_CLUSTER_ENDPOINT_1="cluster-a.cluster-xxx.rds.amazonaws.com"
export AURORA_USERNAME_1="user_a"
export AURORA_PASSWORD_1="pass_a"
export AURORA_CLUSTER_ENDPOINT_2="cluster-b.cluster-yyy.rds.amazonaws.com"
export AURORA_USERNAME_2="user_b"
export AURORA_PASSWORD_2="pass_b"
./run-instance1.sh   # 端口 8080，CLUSTER_ID=cluster-a
./run-instance2.sh   # 端口 8081，CLUSTER_ID=cluster-b（独立 topology 缓存）
```

> 📖 **配置详情**:
> - [插件配置指南](PLUGIN_CONFIGURATION.md) - 详细的插件参数和多集群配置
> - [Blue/Green 测试指南](BLUEGREEN_TEST_GUIDE.md) - 测试流程和日志分析
> - [.env.template](../.env.template) - 完整的环境变量模板（含注释）

### 4. 运行测试

```bash
# 启动持续写入测试 - 10个连接，每500ms写入一次
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# 多实例时分别触发两个端口
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"
curl -X POST "http://localhost:8081/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# 查看状态
curl http://localhost:8080/api/bluegreen/status
curl http://localhost:8081/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop
curl -X POST http://localhost:8081/api/bluegreen/stop
```

### 5. 查看日志

每个实例的日志写入独立目录：

| 实例 | 日志目录 |
|------|----------|
| 单实例 (`run-aurora.sh`) | `logs/` |
| 实例 1 (`run-instance1.sh`) | `logs/instance1/` |
| 实例 2 (`run-instance2.sh`) | `logs/instance2/` |

```bash
# 单实例日志
tail -f logs/wrapper-*.log

# 多实例日志
tail -f logs/instance1/wrapper-*.log
tail -f logs/instance2/wrapper-*.log
```

## 编译选项

### 自定义版本构建（build.sh）

`build.sh` 脚本支持任意组合 Spring Boot、JDK 和 JDBC Wrapper 版本进行构建。自动处理 JDK 兼容性检查和 JAVA_HOME 检测。

```bash
# 查看帮助
./build.sh --help

# 查看常用版本组合
./build.sh --list

# 默认构建
./build.sh

# Spring Boot 2.7.x + JDK 11
./build.sh --sb 2.7.18 --jdk 11

# Spring Boot 3.2.x + JDK 17
./build.sh --sb 3.2.0 --jdk 17

# 完全自定义（Spring Boot + JDK + Wrapper）
./build.sh --sb 3.4.2 --jdk 17 --wrapper 3.1.0
```

JAR 文件名包含版本组合信息，便于识别：
```
target/spring-boot-aurora-mysql-test-sb3.4.2-jdk17-wrapper3.2.0.jar
target/spring-boot-aurora-mysql-test-sb2.7.18-jdk11-wrapper3.2.0.jar
```

**版本兼容性规则：**
| Spring Boot | JDK | 说明 |
|-------------|-----|------|
| 2.7.x | 8, 11, 17 | 最后的 2.x 版本 |
| 3.0.x - 3.2.x | 17+ | Jakarta EE 迁移 |
| 3.3.x - 3.4.x | 17, 21 | 最新版本 |

### 运行时自动检测 JDK

所有启动脚本（`run-aurora.sh`、`run-instance1.sh`、`run-instance2.sh`）会自动从 JAR 文件名中检测 JDK 版本，并使用对应的 JAVA_HOME 运行。例如，用 `--jdk 11` 构建的 JAR 会自动用 JDK 11 运行。

```bash
# 用 JDK 11 构建
./build.sh --sb 2.7.18 --jdk 11

# 运行 - 自动使用 JDK 11（从 JAR 文件名检测）
./run-aurora.sh prod

# 或者显式指定 JAR
JAR_FILE=target/spring-boot-aurora-mysql-test-sb2.7.18-jdk11-wrapper3.2.0.jar ./run-aurora.sh prod
```

### 直接使用 Maven 构建

也可以通过 Maven 属性直接覆盖版本：

```bash
# 覆盖 Spring Boot 版本
mvn clean package -DskipTests -Dspring-boot.version=3.2.0

# 覆盖所有版本
mvn clean package -DskipTests \
    -Dspring-boot.version=2.7.18 \
    -Djava.version=11 \
    -Daws-jdbc-wrapper.version=3.2.0
```

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/bluegreen/start-write` | POST | 启动持续写入测试 |
| `/api/bluegreen/start` | POST | 启动读写混合测试 |
| `/api/bluegreen/stop` | POST | 停止测试 |
| `/api/bluegreen/status` | GET | 获取测试状态 |
| `/api/bluegreen/help` | GET | 获取帮助信息 |
| `/actuator/health` | GET | 健康检查 |
| `/api/test` | GET | 测试数据库连接 |

### 持续写入测试参数

```bash
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=20&writeIntervalMs=50"
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `numConnections` | 10 | 连接数量 (1-100) |
| `writeIntervalMs` | 500 | 写入间隔毫秒 (0=最快) |

## 配置说明

### 环境变量

| 变量 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `AURORA_CLUSTER_ENDPOINT` | 是 | - | Aurora 集群端点（所有实例的 fallback） |
| `AURORA_DATABASE` | 否 | testdb | 数据库名称 |
| `AURORA_USERNAME` | 是 | admin | 数据库用户名 |
| `AURORA_PASSWORD` | 是 | - | 数据库密码 |
| `WRAPPER_LOG_LEVEL` | 否 | INFO | 日志级别（SEVERE\|WARNING\|INFO\|FINE\|FINER\|FINEST） |
| `CLUSTER_ID` | 否 | cluster-a | 集群拓扑缓存标识符（多集群时每个集群必须唯一） |
| `BGD_ID` | 否 | cluster-a | Blue/Green 部署状态标识符（多集群时每个集群必须唯一） |
| `SERVER_PORT` | 否 | 8080 | HTTP 服务端口（多实例时使用不同端口） |
| `TABLE_PREFIX` | 否 | default | 测试表名前缀（同一 cluster 多实例时用于隔离表名） |

每个实例可独立覆盖（用于 `run-instance1.sh` / `run-instance2.sh`）：

| 变量 | 使用者 | Fallback |
|------|--------|----------|
| `AURORA_CLUSTER_ENDPOINT_1` | 实例 1 | `AURORA_CLUSTER_ENDPOINT` |
| `AURORA_USERNAME_1` | 实例 1 | `AURORA_USERNAME` |
| `AURORA_PASSWORD_1` | 实例 1 | `AURORA_PASSWORD` |
| `AURORA_DATABASE_1` | 实例 1 | `AURORA_DATABASE` |
| `AURORA_CLUSTER_ENDPOINT_2` | 实例 2 | `AURORA_CLUSTER_ENDPOINT` |
| `AURORA_USERNAME_2` | 实例 2 | `AURORA_USERNAME` |
| `AURORA_PASSWORD_2` | 实例 2 | `AURORA_PASSWORD` |
| `AURORA_DATABASE_2` | 实例 2 | `AURORA_DATABASE` |

### 应用 Profile

| Profile | 日志级别 | 用途 |
|---------|----------|------|
| `aurora-prod` | FINE | 生产环境 |
| `aurora-dev` | FINEST | 开发/调试 |

### JDBC URL 格式

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

**重要**: 
- 必须使用 **集群端点**（包含 `.cluster-`）
- **不要使用** `autoreconnect=true`

### 插件链

| 插件 | 功能 |
|------|------|
| `initialConnection` | 初始连接处理 |
| `auroraConnectionTracker` | Aurora 连接跟踪 |
| `failover2` | 自动故障转移 |
| `efm2` | 增强故障监控 |
| `bg` | Blue/Green 部署支持 |

### 集群标识配置（clusterId 和 bgdId）

| 参数 | 默认值 | 作用 | 存储内容 |
|------|--------|------|----------|
| `clusterId` | `"1"` | 集群拓扑缓存标识符 | 集群节点拓扑信息 |
| `bgdId` | `"1"` | Blue/Green 部署状态标识符 | BG 切换状态 |

#### 单集群场景

单集群连接时，可以使用默认值或设置为相同值：

```
clusterId=cluster-a&bgdId=cluster-a
```

#### 多集群场景（重要！）

当单个应用连接多个 Aurora 集群时，**每个集群的 `clusterId` 和 `bgdId` 必须设置为不同的值**：

```yaml
# 集群 A 数据源
datasource-a:
  url: jdbc:aws-wrapper:mysql://cluster-a.xxx.rds.amazonaws.com:3306/db?
       wrapperPlugins=...bg&
       clusterId=cluster-a&
       bgdId=cluster-a

# 集群 B 数据源
datasource-b:
  url: jdbc:aws-wrapper:mysql://cluster-b.xxx.rds.amazonaws.com:3306/db?
       wrapperPlugins=...bg&
       clusterId=cluster-b&
       bgdId=cluster-b
```

#### 配置错误的后果

| 场景 | 问题 |
|------|------|
| 只设置 `clusterId` 不同 | BG 状态会混乱，集群 A 的切换可能影响集群 B 的连接路由 |
| 只设置 `bgdId` 不同 | 拓扑缓存会混乱，可能把集群 A 的节点当作集群 B 的节点 |
| 两者都相同 | 以上两个问题都会发生 |

## 项目结构

```
spring-boot-aurora-mysql-test/
├── src/main/java/com/test/
│   ├── SpringBootMySQLTestApplication.java
│   ├── controller/
│   │   ├── BlueGreenTestController.java
│   │   └── UserController.java
│   ├── service/
│   │   ├── BlueGreenTestService.java
│   │   └── UserService.java
│   ├── repository/
│   │   └── UserRepository.java
│   └── model/
│       └── User.java
├── src/main/resources/
│   ├── application.yml
│   └── log4j2-spring.xml
├── cloudformation/
│   ├── deploy.sh
│   ├── aurora-bluegreen-test.yaml
│   ├── init-database.sql
│   └── config.env
├── docs/
│   ├── AURORA_CONFIGURATION_GUIDE.md
│   ├── AURORA_QUICK_START.md
│   ├── BLUEGREEN_TEST_GUIDE.md
│   └── PLUGIN_CONFIGURATION.md
├── build.sh               # 自定义版本构建脚本（Spring Boot / JDK / Wrapper）
├── detect-java.sh         # 运行时自动检测 JAVA_HOME（被启动脚本引用）
├── run-aurora.sh          # 单实例启动脚本
├── run-instance1.sh       # 多实例：实例 1（端口 8080）
├── run-instance2.sh       # 多实例：实例 2（端口 8081，场景 A 或 B）
├── run-rds.sh
├── pom.xml                # 版本参数化（spring-boot.version, java.version, aws-jdbc-wrapper.version）
└── README.md
```

## 多实例蓝绿测试

### 场景 A：同一台机器，两个 service 连接同一个 Aurora cluster 的不同表

两个实例连接同一个 Aurora cluster，共享相同的 `clusterId`/`bgdId`（共享 topology 缓存），因此两个实例会同时感知到同一个蓝绿切换事件。通过 `TABLE_PREFIX` 隔离测试表名。

```bash
# 终端 1
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_PASSWORD="your-password"
./run-instance1.sh   # 端口 8080，TABLE_PREFIX=inst1，CLUSTER_ID=cluster-a

# 终端 2（相同的 cluster endpoint）
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_PASSWORD="your-password"
./run-instance2.sh   # 端口 8081，TABLE_PREFIX=inst2，CLUSTER_ID=cluster-a
```

预期行为：两个实例同时检测到切换事件，各自独立恢复连接。

### 场景 B：同一台机器，两个 service 分别连接两个不同的 Aurora cluster

每个实例连接不同的 Aurora cluster，各自有独立的蓝绿部署。使用不同的 `clusterId`/`bgdId` 确保 topology 缓存和 BG 状态完全隔离。每个实例可以使用独立的用户名和密码。

```bash
# 设置每个实例的 endpoint 和凭证
export AURORA_CLUSTER_ENDPOINT_1="cluster-a.cluster-xxx.rds.amazonaws.com"
export AURORA_USERNAME_1="user_a"
export AURORA_PASSWORD_1="pass_a"

export AURORA_CLUSTER_ENDPOINT_2="cluster-b.cluster-yyy.rds.amazonaws.com"
export AURORA_USERNAME_2="user_b"
export AURORA_PASSWORD_2="pass_b"

# 终端 1
./run-instance1.sh   # 端口 8080，使用 _1 变量，CLUSTER_ID=cluster-a

# 终端 2
./run-instance2.sh   # 端口 8081，使用 _2 变量，CLUSTER_ID=cluster-b
```

预期行为：每个实例独立追踪各自 cluster 的切换事件，cluster-b 的切换不影响实例 1。

### clusterId 和 bgdId 对多实例的影响

| 配置 | 效果 |
|------|------|
| 相同 `clusterId` | 实例共享 topology 缓存 — 同一 cluster 时正确 |
| 不同 `clusterId` | 实例有独立的 topology 缓存 — 不同 cluster 时必须如此 |
| 相同 `bgdId` | 实例共享 BG 切换状态 — 同一 cluster 时正确 |
| 不同 `bgdId` | 实例有独立的 BG 状态 — 不同 cluster 时必须如此 |

如果连接**不同** cluster 的两个实例使用了相同的 `clusterId`/`bgdId`，topology 信息和 BG 状态会互相覆盖，导致连接路由错误。

## 文档

- [EC2 环境搭建指南](EC2_SETUP_GUIDE.md) - 在 AL2023 上搭建测试环境
- [Aurora 配置指南](AURORA_CONFIGURATION_GUIDE.md)
- [Aurora 快速开始](AURORA_QUICK_START.md)
- [Blue/Green 测试指南](BLUEGREEN_TEST_GUIDE.md)
- [插件配置说明](PLUGIN_CONFIGURATION.md)
- [CloudFormation 部署](../cloudformation/README_CN.md)

## 清理资源

```bash
cd cloudformation

# 删除最后部署的 stack
./deploy.sh delete

# 或删除指定的 stack
STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh delete

# 列出所有 stacks 查找要删除的
./deploy.sh list
```

⚠️ **测试完成后请及时删除资源，避免产生费用！**

## 许可证

Apache 2.0
