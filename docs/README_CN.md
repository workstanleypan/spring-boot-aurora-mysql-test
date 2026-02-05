# Spring Boot Aurora MySQL 测试

Spring Boot 应用，用于测试 AWS JDBC Wrapper 连接 Aurora MySQL，支持 Blue/Green Deployment 自动切换测试。

## 功能特性

- AWS Advanced JDBC Wrapper 3.2.0
- Blue/Green Deployment Plugin 支持
- Failover & EFM Plugin
- HikariCP 连接池
- 多线程持续写入测试
- Spring Boot 3.4.2

## 环境要求

- Java 17+
- Maven 3.6+
- AWS CLI（用于 CloudFormation 部署）
- Aurora MySQL 集群访问权限
- MySQL 客户端（用于数据库初始化）

> 📖 **新环境搭建**: 如果在全新的 Amazon Linux 2023 EC2 上搭建测试环境，请参考 [EC2 环境搭建指南](EC2_SETUP_GUIDE.md)

## 快速开始

### 1. 克隆并编译

```bash
# 克隆仓库
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test

# 编译（跳过测试）
mvn clean package -DskipTests

# 或者带测试编译（需要数据库连接）
mvn clean package
```

### 2. 部署 Aurora 集群（可选）

如果没有 Aurora 集群，可以使用 CloudFormation 创建：

```bash
cd cloudformation

# 每次部署会创建新的 stack，名称带时间戳（如 aurora-bg-test-0204-1530）
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# 后续命令自动使用最后部署的 stack
./deploy.sh init-db              # 初始化数据库
./deploy.sh create-bluegreen     # 创建蓝绿部署（约 20-30 分钟）
./deploy.sh outputs              # 获取连接信息

# 列出所有 stacks
./deploy.sh list

# 使用指定的 stack
STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh outputs
```

### 3. 配置并运行

```bash
# 必需的环境变量
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"

# 可选：日志和集群标识
export WRAPPER_LOG_LEVEL="FINE"    # SEVERE|WARNING|INFO|FINE|FINER|FINEST
export CLUSTER_ID="cluster-a"      # 多集群场景下每个集群必须唯一
export BGD_ID="cluster-a"          # 多集群场景下每个集群必须唯一

# 可选：Blue/Green 插件调优（详见 PLUGIN_CONFIGURATION.md）
export BG_HIGH_MS="100"            # IN_PROGRESS 阶段轮询间隔（毫秒）
export BG_INCREASED_MS="1000"      # CREATED 阶段轮询间隔（毫秒）
export BG_BASELINE_MS="60000"      # 正常运行时轮询间隔（毫秒）
export BG_CONNECT_TIMEOUT_MS="30000"      # 切换期间连接超时（毫秒）
export BG_SWITCHOVER_TIMEOUT_MS="180000"  # 切换总超时（毫秒）

# 运行应用
./run-aurora.sh prod

# 或者使用 Maven 直接运行
mvn spring-boot:run -Dspring-boot.run.profiles=aurora-prod
```

> 📖 **配置详情**:
> - [插件配置指南](PLUGIN_CONFIGURATION.md) - 详细的插件参数和多集群配置
> - [Blue/Green 测试指南](BLUEGREEN_TEST_GUIDE.md) - 测试流程和日志分析
> - [.env.template](../.env.template) - 完整的环境变量模板（含注释）

### 4. 运行测试

```bash
# 启动持续写入测试 - 10个连接，每500ms写入一次
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# 查看状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop
```

## 编译选项

```bash
# 标准编译（跳过测试）
mvn clean package -DskipTests

# 使用特定 profile 编译
mvn clean package -P production

# 构建 Docker 镜像（如果有 Dockerfile）
docker build -t aurora-mysql-test .

# 直接运行 JAR
java -jar target/spring-boot-aurora-mysql-test-1.0.0.jar --spring.profiles.active=aurora-prod
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

| 变量 | 必需 | 说明 |
|------|------|------|
| `AURORA_CLUSTER_ENDPOINT` | 是 | Aurora 集群端点 |
| `AURORA_DATABASE` | 是 | 数据库名称 |
| `AURORA_USERNAME` | 是 | 数据库用户名 |
| `AURORA_PASSWORD` | 是 | 数据库密码 |
| `WRAPPER_LOG_LEVEL` | 否 | 日志级别（默认: INFO） |

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
├── run-aurora.sh
├── run-rds.sh
├── pom.xml
└── README.md
```

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
