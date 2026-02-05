# Spring Boot Aurora MySQL Test

Spring Boot application for testing AWS JDBC Wrapper with Aurora MySQL, supporting Blue/Green Deployment automatic switchover testing.

## Features

- AWS Advanced JDBC Wrapper 3.1.0
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

# Deploy creates a NEW stack each time with timestamp (e.g., aurora-bg-test-0204-1530)
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# Subsequent commands auto-use the last deployed stack
./deploy.sh init-db              # Initialize database
./deploy.sh create-bluegreen     # Create Blue/Green deployment (~20-30 min)
./deploy.sh outputs              # Get connection info

# List all stacks
./deploy.sh list

# Use specific stack
STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh outputs
```

### 3. Configure and Run

```bash
# Set environment variables
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="FINE"  # Options: SEVERE|WARNING|INFO|FINE|FINER|FINEST

# Run application
./run-aurora.sh prod

# Or run directly with Maven
mvn spring-boot:run -Dspring-boot.run.profiles=aurora-prod
```

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
| `BGD_ID` | No | cluster-a | Blue/Green deployment identifier |

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

**Race Condition Warning**: During the transition to IN_PROGRESS phase, there's a brief window where SQL requests may execute before the suspend rules take effect. This can result in `read-only` errors if the request hits the old (blue) cluster after it becomes read-only.

**Important**: For non-admin database users, ensure proper permissions are granted on BOTH blue and green clusters before switchover. See [Connecting with non-admin users](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheBlueGreenPlugin.md#connecting-with-non-admin-users) for required permissions.

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
