# Blue/Green Switchover Test Guide

## Overview

Test AWS JDBC Wrapper behavior during Aurora Blue/Green switchover. Uses HikariCP connection pool with multi-threaded continuous writes.

## Quick Start

### 0. Build

```bash
# Default build (Spring Boot 3.4.2, JDK 17, Wrapper 3.2.0)
./build.sh

# Custom versions
./build.sh --sb 2.7.18 --jdk 11
./build.sh --sb 3.2.0 --jdk 17 --wrapper 3.1.0

# Show all version combos
./build.sh --list
```

### 1. Start Application

**Single instance:**

```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="FINE"

./run-aurora.sh prod
```

**Multi-instance (Scenario A - same cluster, different tables):**

```bash
# Both instances share the same cluster, same credentials
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"

# Terminal 1
./run-instance1.sh   # port 8080, TABLE_PREFIX=inst1, CLUSTER_ID=cluster-a

# Terminal 2
./run-instance2.sh   # port 8081, TABLE_PREFIX=inst2, CLUSTER_ID=cluster-a
```

**Multi-instance (Scenario B - different clusters, different credentials):**

```bash
# Instance 1 - Cluster A
export AURORA_CLUSTER_ENDPOINT_1="cluster-a.cluster-xxx.rds.amazonaws.com"
export AURORA_USERNAME_1="user_a"
export AURORA_PASSWORD_1="pass_a"

# Instance 2 - Cluster B
export AURORA_CLUSTER_ENDPOINT_2="cluster-b.cluster-yyy.rds.amazonaws.com"
export AURORA_USERNAME_2="user_b"
export AURORA_PASSWORD_2="pass_b"

# Terminal 1
./run-instance1.sh   # port 8080, CLUSTER_ID=cluster-a

# Terminal 2
./run-instance2.sh   # port 8081, CLUSTER_ID=cluster-b
```

### 2. Start Test

```bash
# Continuous write test - 10 connections, write every 500ms
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# For multi-instance: trigger both ports
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"
curl -X POST "http://localhost:8081/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# Check status
curl http://localhost:8080/api/bluegreen/status
curl http://localhost:8081/api/bluegreen/status

# Stop test
curl -X POST http://localhost:8080/api/bluegreen/stop
curl -X POST http://localhost:8081/api/bluegreen/stop
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

## Environment Variables

### Shared (all instances)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AURORA_CLUSTER_ENDPOINT` | Yes* | - | Cluster endpoint (fallback for all instances) |
| `AURORA_USERNAME` | Yes* | admin | Username (fallback for all instances) |
| `AURORA_PASSWORD` | Yes* | - | Password (fallback for all instances) |
| `AURORA_DATABASE` | No | testdb | Database name |
| `WRAPPER_LOG_LEVEL` | No | INFO | SEVERE\|WARNING\|INFO\|FINE\|FINER\|FINEST |

### Per-instance (override shared values)

| Variable | Used by | Fallback |
|----------|---------|----------|
| `AURORA_CLUSTER_ENDPOINT_1` | run-instance1.sh | `AURORA_CLUSTER_ENDPOINT` |
| `AURORA_USERNAME_1` | run-instance1.sh | `AURORA_USERNAME` |
| `AURORA_PASSWORD_1` | run-instance1.sh | `AURORA_PASSWORD` |
| `AURORA_DATABASE_1` | run-instance1.sh | `AURORA_DATABASE` |
| `CLUSTER_ID_1` | run-instance1.sh | `CLUSTER_ID` → `cluster-a` |
| `BGD_ID_1` | run-instance1.sh | `BGD_ID` → `cluster-a` |
| `AURORA_CLUSTER_ENDPOINT_2` | run-instance2.sh | `AURORA_CLUSTER_ENDPOINT` |
| `AURORA_USERNAME_2` | run-instance2.sh | `AURORA_USERNAME` |
| `AURORA_PASSWORD_2` | run-instance2.sh | `AURORA_PASSWORD` |
| `AURORA_DATABASE_2` | run-instance2.sh | `AURORA_DATABASE` |
| `CLUSTER_ID_2` | run-instance2.sh | `cluster-b` (when `_2` endpoint is set) |
| `BGD_ID_2` | run-instance2.sh | `cluster-b` (when `_2` endpoint is set) |

## View Logs

Each instance writes logs to its own directory:

| Instance | Log directory |
|----------|--------------|
| Single (`run-aurora.sh`) | `logs/` |
| Instance 1 (`run-instance1.sh`) | `logs/instance1/` |
| Instance 2 (`run-instance2.sh`) | `logs/instance2/` |

```bash
# Single instance logs
tail -f logs/wrapper-*.log

# Multi-instance logs
tail -f logs/instance1/wrapper-*.log
tail -f logs/instance2/wrapper-*.log

# BG Plugin related
grep -i "blue.*green\|BlueGreen" logs/instance1/wrapper-*.log

# Failover related
grep -i "failover" logs/instance1/wrapper-*.log
```

### Analyze Switchover Results

```bash
# View switchover timeline summary
grep -i "time offset" logs/wrapper-*.log -A 14

# Check BG status changes (FINE level)
grep -i "BG status" logs/wrapper-*.log

# Check BG status changes (FINEST level)
grep -i "Status changed to" logs/wrapper-*.log
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

### Permission Issues (Non-Admin Users)

For non-admin database users, ensure proper permissions are granted on **BOTH** blue and green clusters before switchover:

```sql
GRANT SELECT ON mysql.rds_topology TO 'your_user'@'%';
FLUSH PRIVILEGES;
```

### High Failure Rate
1. Check database connection stability
2. Review Wrapper logs for errors
3. Verify HikariCP connection pool configuration

### Failover Not Detected
1. Confirm using Cluster Endpoint
2. Verify BG Plugin is enabled
3. Check log level setting (recommend FINE)

## Related Documentation

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora Configuration Guide
- [PLUGIN_CONFIGURATION.md](PLUGIN_CONFIGURATION.md) - Plugin Configuration
