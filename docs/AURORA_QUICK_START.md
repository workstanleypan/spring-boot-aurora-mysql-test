# Aurora MySQL Quick Start

## 5-Minute Setup

### Step 1: Start Application

```bash
AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
./run-aurora.sh prod
```

### Step 2: Verify Connection

```bash
curl http://localhost:8080/api/test
```

### Step 3: Start Test

```bash
# Continuous write test
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# Check status
curl http://localhost:8080/api/bluegreen/status

# Stop test
curl -X POST http://localhost:8080/api/bluegreen/stop
```

## Available Profiles

| Profile | Log Level | Use Case |
|---------|-----------|----------|
| `aurora-prod` | FINE | Production |
| `aurora-dev` | FINEST | Development/Debug |

```bash
./run-aurora.sh prod   # Production
./run-aurora.sh dev    # Development
```

## Tech Stack

- **Connection Pool**: HikariCP (Spring Boot default)
- **JDBC Wrapper**: AWS Advanced JDBC Wrapper 3.1.0
- **Plugins**: initialConnection, auroraConnectionTracker, failover2, efm2, bg

## View Logs

```bash
# Wrapper logs
tail -f logs/wrapper.log

# Application logs
tail -f logs/spring-boot.log

# BG Plugin logs
grep -i "blue.*green" logs/wrapper.log
```

## Common Issues

### Connection Timeout

```bash
nc -zv your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306
```

### BG Plugin Not Working

Ensure you're using **Cluster Endpoint** (contains `.cluster-`):

✅ Correct: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`  
❌ Wrong: `database-1-instance-1.xxxxx.us-east-1.rds.amazonaws.com`

## Next Steps

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Full Configuration Guide
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - Blue/Green Test Guide
