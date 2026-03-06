# Spring Boot Aurora MySQL Test

Spring Boot application for testing AWS JDBC Wrapper with Aurora MySQL, supporting Blue/Green Deployment automatic switchover testing.

> 📖 **Blue/Green Deployment Runbook**: For comprehensive guidance on using AWS JDBC Wrapper with Blue/Green deployments, see:
> - [AWS JDBC Wrapper Blue/Green Runbook (English)](docs/AWS_JDBC_WRAPPER_BLUEGREEN_RUNBOOK.md)
> - [AWS JDBC Wrapper Blue/Green Runbook (中文)](docs/AWS_JDBC_WRAPPER_BLUEGREEN_RUNBOOK_CN.md)

> 🔗 **AWS Advanced JDBC Wrapper**: We recommend using the latest version for testing. Download from:
> - [GitHub Releases](https://github.com/aws/aws-advanced-jdbc-wrapper/releases)
> - [Maven Central](https://central.sonatype.com/artifact/software.amazon.jdbc/aws-advanced-jdbc-wrapper)

## Features

- AWS Advanced JDBC Wrapper (configurable version, default 3.2.0)
- Blue/Green Deployment Plugin Support
- Failover & EFM Plugin
- HikariCP Connection Pool
- Multi-threaded Continuous Write Testing
- Spring Boot (configurable version, default 3.4.2)
- Configurable JDK version (11 for Spring Boot 2.x, 17+ for Spring Boot 3.x)
- Multi-instance testing support (same cluster / different clusters)

## Prerequisites

- Java 11+ or 17+ (depending on Spring Boot version)
- Maven 3.6+
- AWS CLI (for CloudFormation deployment)
- Access to Aurora MySQL cluster
- MySQL client (for database initialization)

> 📖 **New Environment Setup**: If setting up on a fresh Amazon Linux 2023 EC2 instance, see [EC2 Setup Guide](docs/EC2_SETUP_GUIDE.md) for complete instructions.

## Quick Start

### 1. Clone and Build

```bash
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test

# Default build (Spring Boot 3.4.2, JDK 17, Wrapper 3.2.0)
./build.sh

# Or with custom versions
./build.sh --sb 2.7.18 --jdk 11                    # Spring Boot 2.x + JDK 11
./build.sh --sb 3.2.0 --jdk 17 --wrapper 3.1.0     # Full custom

# Or plain Maven (uses default versions from pom.xml)
mvn clean package -DskipTests
```

### 2. Deploy Aurora Cluster (Optional)

```bash
cd cloudformation

# One-click deployment (recommended)
DB_PASSWORD=YourPassword123 ./deploy.sh deploy-all

# Or step-by-step:
DB_PASSWORD=YourPassword123 ./deploy.sh deploy    # Create cluster (~15 min)
./deploy.sh init-db                               # Initialize database
./deploy.sh create-bluegreen                      # Create Blue/Green (~20-30 min)
```

### 3. Configure and Run

**Single service, single cluster (standard usage):**

```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="FINE"

./run-aurora.sh prod
```

> Note: `TABLE_PREFIX` defaults to `"default"`, so test tables will be named `default_bg_write_test`, `default_bg_test_thread_N`. This has no functional impact.

**Multi-instance testing (see [Multi-Instance Test Guide](#multi-instance-blue-green-testing) below):**

```bash
# Scenario A: Two services, same cluster, different tables
./run-instance1.sh   # port 8080, TABLE_PREFIX=inst1, CLUSTER_ID=cluster-a
./run-instance2.sh   # port 8081, TABLE_PREFIX=inst2, CLUSTER_ID=cluster-a (shared topology cache)

# Scenario B: Two services, different clusters
export AURORA_CLUSTER_ENDPOINT_1="cluster-a.cluster-xxx.rds.amazonaws.com"
export AURORA_USERNAME_1="user_a"
export AURORA_PASSWORD_1="pass_a"
export AURORA_CLUSTER_ENDPOINT_2="cluster-b.cluster-yyy.rds.amazonaws.com"
export AURORA_USERNAME_2="user_b"
export AURORA_PASSWORD_2="pass_b"
./run-instance1.sh   # port 8080, CLUSTER_ID=cluster-a
./run-instance2.sh   # port 8081, CLUSTER_ID=cluster-b (isolated topology cache)
```

> 📖 **Configuration Details**:
> - [Plugin Configuration Guide](docs/PLUGIN_CONFIGURATION.md) - Detailed plugin parameters and multi-cluster setup
> - [Blue/Green Test Guide](docs/BLUEGREEN_TEST_GUIDE.md) - Testing procedures and log analysis
> - [.env.template](.env.template) - Complete environment variable template with comments

### 4. Run Tests

```bash
# Start continuous write test - 10 connections, write every 500ms
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# Check status
curl http://localhost:8080/api/bluegreen/status

# Stop test
curl -X POST http://localhost:8080/api/bluegreen/stop
```

### 5. Analyze Switchover Logs

```bash
# View switchover timeline summary
grep -i "time offset" logs/wrapper.log -A 14

# Check BG status changes (FINE level)
grep -i "BG status" logs/wrapper.log

# Check BG status changes (FINEST level)
grep -i "Status changed to" logs/wrapper.log
```

## Build Options

### Custom Version Build (build.sh)

The `build.sh` script allows you to build with any combination of Spring Boot, JDK, and JDBC Wrapper versions. It automatically handles JDK compatibility checks and JAVA_HOME detection.

```bash
# Show help
./build.sh --help

# Show common version combinations
./build.sh --list

# Default build
./build.sh

# Spring Boot 2.7.x + JDK 11
./build.sh --sb 2.7.18 --jdk 11

# Spring Boot 3.2.x + JDK 17
./build.sh --sb 3.2.0 --jdk 17

# Full custom (Spring Boot + JDK + Wrapper)
./build.sh --sb 3.4.2 --jdk 17 --wrapper 3.1.0
```

The JAR filename includes the version combination for easy identification:
```
target/spring-boot-aurora-mysql-test-sb3.4.2-jdk17-wrapper3.2.0.jar
target/spring-boot-aurora-mysql-test-sb2.7.18-jdk11-wrapper3.2.0.jar
```

**Version compatibility rules:**
| Spring Boot | JDK | Notes |
|-------------|-----|-------|
| 2.7.x | 8, 11, 17 | Last 2.x release |
| 3.0.x - 3.2.x | 17+ | Jakarta EE migration |
| 3.3.x - 3.4.x | 17, 21 | Latest |

### Auto JDK Detection at Runtime

All run scripts (`run-aurora.sh`, `run-instance1.sh`, `run-instance2.sh`) automatically detect the JDK version from the JAR filename and use the matching JAVA_HOME. For example, a JAR built with `--jdk 11` will automatically run with JDK 11.

```bash
# Build with JDK 11
./build.sh --sb 2.7.18 --jdk 11

# Run - automatically uses JDK 11 (detected from JAR name)
./run-aurora.sh prod

# Or specify JAR explicitly
JAR_FILE=target/spring-boot-aurora-mysql-test-sb2.7.18-jdk11-wrapper3.2.0.jar ./run-aurora.sh prod
```

### Plain Maven Build

You can also override versions directly via Maven properties:

```bash
# Override Spring Boot version
mvn clean package -DskipTests -Dspring-boot.version=3.2.0

# Override all versions
mvn clean package -DskipTests \
    -Dspring-boot.version=2.7.18 \
    -Djava.version=11 \
    -Daws-jdbc-wrapper.version=3.2.0
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/bluegreen/start-write` | POST | Start continuous write test |
| `/api/bluegreen/start` | POST | Start read/write mixed test |
| `/api/bluegreen/stop` | POST | Stop test |
| `/api/bluegreen/status` | GET | Get test status |
| `/api/bluegreen/help` | GET | Get help information |
| `/actuator/health` | GET | Health check |
| `/api/test` | GET | Test database connection |

### Continuous Write Test Parameters

```bash
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=20&writeIntervalMs=500"
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `numConnections` | 10 | Number of connections (1-100) |
| `writeIntervalMs` | 100 | Write interval in milliseconds (0=fastest, recommended: 500) |

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AURORA_CLUSTER_ENDPOINT` | Yes | - | Aurora cluster endpoint (fallback for all instances) |
| `AURORA_DATABASE` | No | testdb | Database name |
| `AURORA_USERNAME` | Yes | admin | Database username |
| `AURORA_PASSWORD` | Yes | - | Database password |
| `WRAPPER_LOG_LEVEL` | No | INFO | Log level (SEVERE\|WARNING\|INFO\|FINE\|FINER\|FINEST) |
| `CLUSTER_ID` | No | cluster-a | Cluster topology cache identifier (must be unique per cluster) |
| `BGD_ID` | No | cluster-a | Blue/Green deployment identifier (must be unique per cluster) |
| `SERVER_PORT` | No | 8080 | HTTP server port (use different ports for multi-instance) |
| `TABLE_PREFIX` | No | default | Table name prefix (use different values for multi-instance on same cluster) |

Per-instance overrides (used by `run-instance1.sh` / `run-instance2.sh`):

| Variable | Used by | Fallback |
|----------|---------|----------|
| `AURORA_CLUSTER_ENDPOINT_1` | Instance 1 | `AURORA_CLUSTER_ENDPOINT` |
| `AURORA_USERNAME_1` | Instance 1 | `AURORA_USERNAME` |
| `AURORA_PASSWORD_1` | Instance 1 | `AURORA_PASSWORD` |
| `AURORA_DATABASE_1` | Instance 1 | `AURORA_DATABASE` |
| `AURORA_CLUSTER_ENDPOINT_2` | Instance 2 | `AURORA_CLUSTER_ENDPOINT` |
| `AURORA_USERNAME_2` | Instance 2 | `AURORA_USERNAME` |
| `AURORA_PASSWORD_2` | Instance 2 | `AURORA_PASSWORD` |
| `AURORA_DATABASE_2` | Instance 2 | `AURORA_DATABASE` |

### Blue/Green Plugin Parameters

| Variable | Default | Description |
|----------|---------|-------------|
| `BG_HIGH_MS` | 100 | Status polling interval (ms) during IN_PROGRESS phase |
| `BG_INCREASED_MS` | 1000 | Status polling interval (ms) during CREATED phase |
| `BG_BASELINE_MS` | 60000 | Status polling interval (ms) during normal operation |
| `BG_CONNECT_TIMEOUT_MS` | 30000 | Connection timeout (ms) during switchover |
| `BG_SWITCHOVER_TIMEOUT_MS` | 180000 | Total switchover timeout (ms) |

### Application Profiles

| Profile | Log Level | Use Case |
|---------|-----------|----------|
| `aurora-prod` | FINE | Production |
| `aurora-dev` | FINEST | Development/Debug |

### JDBC URL Format

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

**Important**: 
- Must use **Cluster Endpoint** (contains `.cluster-`)
- Do NOT use `autoreconnect=true`

### Plugin Chain

| Plugin | Function |
|--------|----------|
| `initialConnection` | Initial connection handling |
| `auroraConnectionTracker` | Aurora connection tracking |
| `failover2` | Automatic failover |
| `efm2` | Enhanced failure monitoring |
| `bg` | Blue/Green deployment support |

### Cluster Identifier Configuration (clusterId & bgdId)

| Parameter | Default | Purpose | Storage Content |
|-----------|---------|---------|-----------------|
| `clusterId` | `"1"` | Cluster topology cache identifier | Cluster node topology |
| `bgdId` | `"1"` | Blue/Green deployment status identifier | BG switchover status |

#### Single Cluster Scenario

For single cluster connections, you can use default values or set both to the same value:

```
clusterId=cluster-a&bgdId=cluster-a
```

#### Multi-Cluster Scenario (Important!)

When a single application connects to multiple Aurora clusters, **both `clusterId` and `bgdId` must be set to different values for each cluster**:

```yaml
# Cluster A DataSource
datasource-a:
  url: jdbc:aws-wrapper:mysql://cluster-a.xxx.rds.amazonaws.com:3306/db?
       wrapperPlugins=...bg&
       clusterId=cluster-a&
       bgdId=cluster-a

# Cluster B DataSource
datasource-b:
  url: jdbc:aws-wrapper:mysql://cluster-b.xxx.rds.amazonaws.com:3306/db?
       wrapperPlugins=...bg&
       clusterId=cluster-b&
       bgdId=cluster-b
```

#### What Happens If Not Configured Correctly?

| Scenario | Problem |
|----------|---------|
| Only `clusterId` different | BG status will be confused, Cluster A's switchover may affect Cluster B's connection routing |
| Only `bgdId` different | Topology cache will be confused, may treat Cluster A's nodes as Cluster B's nodes |
| Both same for different clusters | Both problems above will occur |

### Blue/Green Plugin Behavior

The `bg` plugin monitors Blue/Green deployment status and manages traffic during switchover:

| Phase | Polling Interval | Behavior |
|-------|-----------------|----------|
| NOT_CREATED | `BG_BASELINE_MS` | Normal operation |
| CREATED | `BG_INCREASED_MS` | Collecting topology and IP addresses |
| PREPARATION | `BG_HIGH_MS` | Substituting hostnames with IP addresses |
| IN_PROGRESS | `BG_HIGH_MS` | **Suspending all SQL requests** |
| POST | `BG_HIGH_MS` | Monitoring DNS updates |
| COMPLETED | `BG_BASELINE_MS` | Normal operation resumed |

**Important Prerequisites**:
- Ensure the test application has **network access to the green cluster**. The green cluster runs on different instances with different IP addresses.
- For non-admin database users, ensure proper permissions are granted on **BOTH** blue and green clusters before switchover. See [Connecting with non-admin users](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheBlueGreenPlugin.md#connecting-with-non-admin-users) for required permissions.

## Project Structure

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
├── build.sh               # Build with custom Spring Boot / JDK / Wrapper versions
├── detect-java.sh         # Auto-detect JAVA_HOME from JAR filename (sourced by run scripts)
├── run-aurora.sh          # Single service startup script
├── run-instance1.sh       # Multi-instance: Instance 1 (port 8080)
├── run-instance2.sh       # Multi-instance: Instance 2 (port 8081, Scenario A or B)
├── run-rds.sh
├── pom.xml                # Parameterized versions (spring-boot.version, java.version, aws-jdbc-wrapper.version)
└── README.md
```

## Multi-Instance Blue/Green Testing

### Scenario A: Two services on same cluster, different tables

Both instances connect to the same Aurora cluster. They share the same `clusterId`/`bgdId` (shared topology cache), so both detect the same Blue/Green switchover event simultaneously. Table names are isolated via `TABLE_PREFIX`.

```bash
# Terminal 1
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_PASSWORD="your-password"
./run-instance1.sh   # port 8080, TABLE_PREFIX=inst1, CLUSTER_ID=cluster-a

# Terminal 2 (same cluster endpoint)
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_PASSWORD="your-password"
./run-instance2.sh   # port 8081, TABLE_PREFIX=inst2, CLUSTER_ID=cluster-a
```

Expected behavior: Both instances detect the switchover at the same time and recover independently.

### Scenario B: Two services on different clusters

Each instance connects to a different Aurora cluster with its own Blue/Green deployment. They use different `clusterId`/`bgdId` to keep topology caches and BG states fully isolated. Each instance can use its own credentials.

```bash
# Set per-instance endpoints and credentials
export AURORA_CLUSTER_ENDPOINT_1="cluster-a.cluster-xxx.rds.amazonaws.com"
export AURORA_USERNAME_1="user_a"
export AURORA_PASSWORD_1="pass_a"

export AURORA_CLUSTER_ENDPOINT_2="cluster-b.cluster-yyy.rds.amazonaws.com"
export AURORA_USERNAME_2="user_b"
export AURORA_PASSWORD_2="pass_b"

# Terminal 1
./run-instance1.sh   # port 8080, uses _1 vars, CLUSTER_ID=cluster-a

# Terminal 2
./run-instance2.sh   # port 8081, uses _2 vars, CLUSTER_ID=cluster-b
```

Expected behavior: Each instance tracks its own cluster's switchover independently. A switchover on cluster-b has no effect on instance 1.

### Why clusterId and bgdId matter for multi-instance

| Config | Effect |
|--------|--------|
| Same `clusterId` | Instances share topology cache — correct for same cluster |
| Different `clusterId` | Instances have isolated topology caches — required for different clusters |
| Same `bgdId` | Instances share BG switchover state — correct for same cluster |
| Different `bgdId` | Instances have isolated BG states — required for different clusters |

If two instances connecting to **different** clusters share the same `clusterId`/`bgdId`, topology info and BG states will overwrite each other, causing incorrect connection routing.

## Documentation

- [EC2 Setup Guide](docs/EC2_SETUP_GUIDE.md) - Setup test environment on AL2023
- [Aurora Configuration Guide](docs/AURORA_CONFIGURATION_GUIDE.md)
- [Aurora Quick Start](docs/AURORA_QUICK_START.md)
- [Blue/Green Test Guide](docs/BLUEGREEN_TEST_GUIDE.md)
- [Plugin Configuration](docs/PLUGIN_CONFIGURATION.md)
- [CloudFormation Deployment](cloudformation/README.md)
- [中文文档](docs/README_CN.md)

## Cleanup Resources

```bash
cd cloudformation

# Delete last deployed stack
./deploy.sh delete

# Or delete specific stack
STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh delete

# List all stacks to find ones to delete
./deploy.sh list
```

⚠️ **Remember to delete resources after testing to avoid charges!**

## License

Apache 2.0
