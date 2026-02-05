# Blue/Green Switchover Test Guide

## Overview

Test AWS JDBC Wrapper behavior during Aurora Blue/Green switchover. Uses HikariCP connection pool with multi-threaded continuous writes.

## Quick Start

### 1. Start Application

```bash
AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
WRAPPER_LOG_LEVEL="FINE" \
./run-aurora.sh prod
```

### 2. Start Test

```bash
# Continuous write test - 10 connections, write every 500ms
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# Check status
curl http://localhost:8080/api/bluegreen/status

# Stop test
curl -X POST http://localhost:8080/api/bluegreen/stop
```

### 3. Execute Blue/Green Switchover

In AWS Console or using CLI:

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <deployment-id> \
  --switchover-timeout 300
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/bluegreen/start-write` | POST | Start continuous write test |
| `/api/bluegreen/start` | POST | Start read/write mixed test |
| `/api/bluegreen/stop` | POST | Stop test |
| `/api/bluegreen/status` | GET | Get test status |
| `/api/bluegreen/help` | GET | Get help information |

### Continuous Write Test Parameters

```bash
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=20&writeIntervalMs=50"
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `numConnections` | 10 | Number of connections (1-100) |
| `writeIntervalMs` | 500 | Write interval in milliseconds (0=fastest) |

### Read/Write Mixed Test Parameters

```bash
curl -X POST http://localhost:8080/api/bluegreen/start \
  -H "Content-Type: application/json" \
  -d '{"numThreads":20,"readsPerSecond":500,"writesPerSecond":10,"durationSeconds":0,"enableWrites":true}'
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `numThreads` | 20 | Number of threads (1-100) |
| `readsPerSecond` | 500 | Reads per second per thread |
| `writesPerSecond` | 10 | Writes per second per thread |
| `durationSeconds` | 3600 | Duration in seconds (0=continuous) |
| `enableWrites` | true | Enable write operations |

## Tech Stack

### Connection Pool: HikariCP

```yaml
spring:
  datasource:
    hikari:
      pool-name: AuroraHikariPool
      minimum-idle: 10
      maximum-pool-size: 50
      connection-timeout: 30000
```

### JDBC Wrapper Plugins

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

## View Logs

```bash
# Wrapper logs
tail -f logs/wrapper.log

# Application logs
tail -f logs/spring-boot.log

# BG Plugin related
grep -i "blue.*green\|BlueGreen" logs/wrapper.log

# Failover related
grep -i "failover" logs/wrapper.log
```

## Monitoring Metrics

### Key Metrics
- **Total Writes**: Cumulative write count
- **Success Rate**: Percentage of successful writes
- **Failover Count**: Number of detected failover events
- **Read-Only Errors**: Errors from writing to read-only node

### Success Criteria
- ✅ Success rate > 95%: High availability
- ✅ Failover detection: Correctly identifies switchover events
- ✅ Auto recovery: Automatically resumes writes after switchover

## Log Level Recommendations

| Environment | JUL Level | Description |
|-------------|-----------|-------------|
| Production | FINE | Shows BG plugin status, connection events |
| Testing | FINEST | Full debug information |

## Troubleshooting

### High Failure Rate
1. Check database connection stability
2. Review Wrapper logs for errors
3. Verify HikariCP connection pool configuration

### Failover Not Detected
1. Confirm using Cluster Endpoint
2. Verify BG Plugin is enabled
3. Check log level setting (recommend FINE)

### Connection Exceptions
```bash
grep -A 20 "Exception" logs/spring-boot.log
grep "HikariPool" logs/spring-boot.log
```

## Related Documentation

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora Configuration Guide
- [PLUGIN_CONFIGURATION.md](PLUGIN_CONFIGURATION.md) - Plugin Configuration
