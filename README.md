# Spring Boot Aurora MySQL Test

Spring Boot application for testing AWS JDBC Wrapper with Aurora MySQL, supporting Blue/Green Deployment automatic switchover testing.

> 📖 **Blue/Green Deployment Runbook**: For comprehensive guidance on using AWS JDBC Wrapper with Blue/Green deployments, see:
> - [AWS JDBC Wrapper Blue/Green Runbook (English)](docs/AWS_JDBC_WRAPPER_BLUEGREEN_RUNBOOK.md)
> - [AWS JDBC Wrapper Blue/Green Runbook (中文)](docs/AWS_JDBC_WRAPPER_BLUEGREEN_RUNBOOK_CN.md)

## Features

- AWS Advanced JDBC Wrapper 3.2.0
- Blue/Green Deployment Plugin Support
- Failover & EFM Plugin
- HikariCP Connection Pool
- Multi-threaded Continuous Write Testing
- Spring Boot 3.4.2

## Prerequisites

- Java 17+
- Maven 3.6+
- AWS CLI (for CloudFormation deployment)
- Access to Aurora MySQL cluster
- MySQL client (for database initialization)

> 📖 **New Environment Setup**: If setting up on a fresh Amazon Linux 2023 EC2 instance, see [EC2 Setup Guide](docs/EC2_SETUP_GUIDE.md) for complete instructions.

## Quick Start

### 1. Clone and Build

```bash
# Clone repository
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test

# Build
mvn clean package -DskipTests

# Or build with tests (requires database connection)
mvn clean package
```

### 2. Deploy Aurora Cluster (Optional)

If you don't have an Aurora cluster, use CloudFormation to create one:

```bash
cd cloudformation

# One-click deployment (recommended): deploy + init-db + create-bluegreen
DB_PASSWORD=YourPassword123 ./deploy.sh deploy-all

# Or step-by-step:
DB_PASSWORD=YourPassword123 ./deploy.sh deploy    # Create cluster (~15 min)
./deploy.sh init-db                               # Initialize database
./deploy.sh create-bluegreen                      # Create Blue/Green (~20-30 min)

# Other commands
./deploy.sh status               # Show status
./deploy.sh outputs              # Get connection info
./deploy.sh list                 # List all stacks
./deploy.sh delete               # Delete everything
```

### 3. Configure and Run

```bash
# Required environment variables
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"

# Optional: Logging and cluster identification
export WRAPPER_LOG_LEVEL="FINE"    # SEVERE|WARNING|INFO|FINE|FINER|FINEST
export CLUSTER_ID="cluster-a"      # Unique per cluster (multi-cluster scenarios)
export BGD_ID="cluster-a"          # Unique per cluster (multi-cluster scenarios)

# Optional: Blue/Green plugin tuning (see docs/PLUGIN_CONFIGURATION.md for details)
export BG_HIGH_MS="100"            # Polling interval during IN_PROGRESS (ms)
export BG_INCREASED_MS="1000"      # Polling interval during CREATED (ms)
export BG_BASELINE_MS="60000"      # Polling interval during normal operation (ms)
export BG_CONNECT_TIMEOUT_MS="30000"      # Connection timeout during switchover (ms)
export BG_SWITCHOVER_TIMEOUT_MS="180000"  # Total switchover timeout (ms)

# Run application
./run-aurora.sh prod

# Or run directly with Maven
mvn spring-boot:run -Dspring-boot.run.profiles=aurora-prod
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

After a Blue/Green switchover, check the wrapper logs:

```bash
# View switchover timeline summary (FINE level and above)
grep -i "time offset" logs/wrapper.log -A 14

# Check BG status changes (FINE level)
grep -i "BG status" logs/wrapper.log

# Check BG status changes (FINEST level)
grep -i "Status changed to" logs/wrapper.log
```

## Build Options

```bash
# Standard build (skip tests)
mvn clean package -DskipTests

# Build with specific profile
mvn clean package -P production

# Build Docker image (if Dockerfile exists)
docker build -t aurora-mysql-test .

# Run JAR directly
java -jar target/spring-boot-aurora-mysql-test-1.0.0.jar --spring.profiles.active=aurora-prod
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
| `AURORA_CLUSTER_ENDPOINT` | Yes | - | Aurora cluster endpoint |
| `AURORA_DATABASE` | Yes | - | Database name |
| `AURORA_USERNAME` | Yes | - | Database username |
| `AURORA_PASSWORD` | Yes | - | Database password |
| `WRAPPER_LOG_LEVEL` | No | INFO | Log level (SEVERE\|WARNING\|INFO\|FINE\|FINER\|FINEST) |
| `CLUSTER_ID` | No | cluster-a | Cluster topology cache identifier (must be unique per cluster) |
| `BGD_ID` | No | cluster-a | Blue/Green deployment identifier (must be unique per cluster) |

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
├── run-aurora.sh
├── run-rds.sh
├── pom.xml
└── README.md
```

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
