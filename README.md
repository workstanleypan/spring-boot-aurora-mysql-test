# Spring Boot Aurora MySQL Test

Spring Boot application for testing AWS JDBC Wrapper with Aurora MySQL, supporting Blue/Green Deployment automatic switchover.

## Features

- AWS Advanced JDBC Wrapper 3.1.0
- Blue/Green Deployment Plugin Support
- Failover & EFM Plugin
- HikariCP Connection Pool
- Multi-threaded Continuous Write Testing
- Spring Boot 3.4.2

## Quick Start

### 1. Deploy Aurora Cluster

```bash
cd cloudformation
./deploy.sh deploy
./deploy.sh init-db
./deploy.sh create-bluegreen
```

### 2. Start Application

```bash
export AURORA_CLUSTER_ENDPOINT="<cluster-endpoint>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="<password>"
export WRAPPER_LOG_LEVEL="FINE"

./run-aurora.sh prod
```

### 3. Run Tests

```bash
# Continuous write test
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=100"

# Check status
curl http://localhost:8080/api/bluegreen/status

# Stop test
curl -X POST http://localhost:8080/api/bluegreen/stop
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/bluegreen/start-write` | POST | Start continuous write test |
| `/api/bluegreen/start` | POST | Start read/write mixed test |
| `/api/bluegreen/stop` | POST | Stop test |
| `/api/bluegreen/status` | GET | Get test status |
| `/api/bluegreen/help` | GET | Get help information |

## JDBC Configuration

### URL Format

```
jdbc:aws-wrapper:mysql://<cluster-endpoint>:3306/<database>?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&bgdId=<cluster-name>
```

**Important**: Must use Cluster Endpoint. Do NOT use `autoreconnect=true`.

### Plugin Chain

| Plugin | Function |
|--------|----------|
| `initialConnection` | Initial connection handling |
| `auroraConnectionTracker` | Aurora connection tracking |
| `failover2` | Automatic failover |
| `efm2` | Enhanced failure monitoring |
| `bg` | Blue/Green deployment support |

### Log Levels

| Level | Description |
|-------|-------------|
| `FINE` | Production recommended |
| `FINEST` | Testing recommended |

## Documentation

- [Configuration Guide](docs/AURORA_CONFIGURATION_GUIDE.md)
- [Quick Start](docs/AURORA_QUICK_START.md)
- [Test Guide](docs/BLUEGREEN_TEST_GUIDE.md)
- [Chinese Docs](docs/README_CN.md)

## License

Apache 2.0
