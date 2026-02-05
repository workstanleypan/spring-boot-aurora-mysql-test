# AWS Advanced JDBC Wrapper Blue/Green Deployment Runbook

This runbook provides comprehensive guidance for using the AWS Advanced JDBC Wrapper (v3.2.0+) with Aurora MySQL Blue/Green Deployments. It covers configuration, testing procedures, monitoring, and troubleshooting.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Configuration](#configuration)
5. [Deployment Workflow](#deployment-workflow)
6. [Testing Procedures](#testing-procedures)
7. [Monitoring and Logging](#monitoring-and-logging)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

### What is Blue/Green Deployment?

Blue/Green Deployment is a release strategy that enables seamless traffic shifting between two identical environments (blue and green) running different versions. For Aurora MySQL, this allows:

- Zero-downtime database upgrades
- Safe rollback capability
- Minimal application disruption during switchover

### What Does the Blue/Green Plugin Do?

The AWS Advanced JDBC Wrapper's `bg` plugin actively manages database connections during Blue/Green switchover by:

1. **Monitoring** - Continuously tracks Blue/Green deployment status
2. **Traffic Management** - Suspends, passes through, or re-routes database traffic appropriately
3. **DNS Handling** - Substitutes hostnames with IP addresses to avoid stale DNS issues
4. **Connection Routing** - Ensures connections go to the correct cluster (blue or green)
5. **Automatic Recovery** - Resumes normal operations after switchover completion

### Supported Configurations

| Database Type | Supported | Notes |
|---------------|-----------|-------|
| Aurora MySQL | ✅ Yes | Engine 3.07+ for full metadata support |
| Aurora PostgreSQL | ✅ Yes | Engine 17.5, 16.9, 15.13, 14.18, 13.21+ |
| RDS MySQL | ✅ Yes | No version restriction |
| RDS PostgreSQL | ✅ Yes | Requires `rds_tools` extension v1.7+ |
| RDS Multi-AZ Cluster | ❌ No | Not supported |
| Aurora Global Database | ❌ No | Not supported |

---

## Prerequisites

### Software Requirements

- Java 17+
- AWS Advanced JDBC Wrapper 3.2.0+
- Spring Boot 3.x (recommended) or compatible framework
- MySQL client (for database initialization)
- AWS CLI (for CloudFormation deployment)

### Network Requirements

- Direct network access to both blue and green cluster endpoints
- Security groups allowing inbound traffic on port 3306
- **Important**: Green cluster runs on different instances with different IP addresses

### Database Permissions

For non-admin users, the following permissions are **required** on **BOTH** blue and green clusters:

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

> ⚠️ **Warning**: If permissions are not granted, the metadata table will not be visible and the Blue/Green plugin will not function properly.

---

## Architecture

### Plugin Chain

The recommended plugin configuration for Aurora MySQL:

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

| Plugin | Purpose |
|--------|---------|
| `initialConnection` | Smart initial connection node selection |
| `auroraConnectionTracker` | Connection state tracking |
| `failover2` | Automatic failover handling |
| `efm2` | Enhanced failure monitoring |
| `bg` | Blue/Green deployment support |

### Blue/Green Plugin State Machine

```
NOT_CREATED → CREATED → PREPARATION → IN_PROGRESS → POST → COMPLETED
     ↑                                                          ↓
     └──────────────────────────────────────────────────────────┘
```

| Phase | Polling Interval | Behavior |
|-------|-----------------|----------|
| NOT_CREATED | `bgBaselineMs` (60s) | Normal operation, no BG deployment detected |
| CREATED | `bgIncreasedMs` (1s) | Collecting topology and IP addresses |
| PREPARATION | `bgHighMs` (100ms) | Substituting hostnames with IP addresses |
| IN_PROGRESS | `bgHighMs` (100ms) | **Suspending all SQL requests** |
| POST | `bgHighMs` (100ms) | Monitoring DNS updates |
| COMPLETED | `bgBaselineMs` (60s) | Normal operation resumed |

### Connection Flow During Switchover

```
Application
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│                  AWS JDBC Wrapper                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Blue/Green Plugin (bg)                  │   │
│  │  • Monitors BG status via metadata table            │   │
│  │  • Suspends requests during IN_PROGRESS             │   │
│  │  • Substitutes DNS with IP addresses                │   │
│  │  • Rejects connections to stale green endpoints     │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Failover2 + EFM2 Plugins                   │   │
│  │  • Detects connection failures                      │   │
│  │  • Handles automatic reconnection                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────┐         ┌─────────────────┐
│  Blue Cluster   │ ──────► │  Green Cluster  │
│  (Source)       │ switch  │  (Target)       │
└─────────────────┘         └─────────────────┘
```

---

## Configuration

### JDBC URL Format

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

### Blue/Green Plugin Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `bgdId` | `1` | Blue/Green deployment identifier. **Must be unique per cluster in multi-cluster scenarios.** |
| `bgConnectTimeoutMs` | `30000` | Connection timeout (ms) during switchover when traffic is suspended |
| `bgBaselineMs` | `60000` | Status polling interval (ms) during normal operation. Keep below 900000ms (15 min) |
| `bgIncreasedMs` | `1000` | Status polling interval (ms) during CREATED phase. Range: 500-2000ms |
| `bgHighMs` | `100` | Status polling interval (ms) during IN_PROGRESS phase. Range: 50-500ms |
| `bgSwitchoverTimeoutMs` | `180000` | Maximum switchover duration (ms). Driver resumes normal operation if exceeded |

### Cluster Identifier Configuration

#### Single Cluster

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://cluster-a.cluster-xxx.rds.amazonaws.com:3306/db?
         wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&
         clusterId=cluster-a&
         bgdId=cluster-a
```

#### Multi-Cluster (Critical!)

When connecting to multiple clusters from a single application, **both `clusterId` and `bgdId` must be unique per cluster**:

```yaml
# Cluster A
datasource-a:
  url: jdbc:aws-wrapper:mysql://cluster-a.xxx.rds.amazonaws.com:3306/db?
       clusterId=cluster-a&bgdId=cluster-a&...

# Cluster B  
datasource-b:
  url: jdbc:aws-wrapper:mysql://cluster-b.xxx.rds.amazonaws.com:3306/db?
       clusterId=cluster-b&bgdId=cluster-b&...
```

| Misconfiguration | Problem |
|------------------|---------|
| Same `clusterId` for different clusters | Topology cache confusion - may route to wrong nodes |
| Same `bgdId` for different clusters | BG status confusion - switchover on one cluster affects another |

### HikariCP Connection Pool Configuration

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
      # Disable leak detection for persistent connection tests
      leak-detection-threshold: 0
```

### Monitoring Connection Configuration

The plugin creates dedicated monitoring connections. Configure them separately using the `blue-green-monitoring-` prefix:

```java
Properties props = new Properties();
// Regular connection timeouts
props.setProperty("connectTimeout", "30000");
props.setProperty("socketTimeout", "30000");
// Monitoring connection timeouts (shorter)
props.setProperty("blue-green-monitoring-connectTimeout", "10000");
props.setProperty("blue-green-monitoring-socketTimeout", "10000");
```

> ⚠️ **Important**: Always provide non-zero socket timeout or connect timeout values.

---

## Deployment Workflow

### Pre-Switchover Checklist

1. **Create Blue/Green Deployment**
   ```bash
   aws rds create-blue-green-deployment \
     --blue-green-deployment-name my-bg-deployment \
     --source arn:aws:rds:region:account:cluster:my-cluster \
     --target-engine-version 8.0.mysql_aurora.3.10.3
   ```

2. **Grant Permissions on Both Clusters**
   ```sql
   -- Run on BOTH blue and green clusters
   GRANT SELECT ON mysql.rds_topology TO 'app_user'@'%';
   FLUSH PRIVILEGES;
   ```

3. **Deploy Application with BG Plugin**
   ```bash
   export WRAPPER_LOG_LEVEL="FINE"
   ./run-aurora.sh prod
   ```

4. **Verify Plugin is Active**
   ```bash
   grep -i "BlueGreen" logs/wrapper-*.log
   # Should see: "BG status: NOT_CREATED" or "BG status: CREATED"
   ```

5. **Wait for Status Collection**
   - Allow 2-5 minutes for the plugin to collect deployment status
   - Verify with: `grep -i "BG status" logs/wrapper-*.log`

### Switchover Execution

1. **Start Continuous Write Test** (optional but recommended)
   ```bash
   curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"
   ```

2. **Initiate Switchover**
   ```bash
   aws rds switchover-blue-green-deployment \
     --blue-green-deployment-identifier <deployment-id> \
     --switchover-timeout 300
   ```

3. **Monitor Progress**
   ```bash
   # Watch BG status changes
   tail -f logs/wrapper-*.log | grep -i "BG status\|Status changed"
   ```

4. **Wait for Completion**
   - Typical switchover: 30-120 seconds
   - Plugin will log: `BG status: COMPLETED`

### Post-Switchover Actions

1. **Verify Application Health**
   ```bash
   curl http://localhost:8080/api/bluegreen/status
   curl http://localhost:8080/actuator/health
   ```

2. **Review Switchover Summary**
   ```bash
   grep -i "time offset" logs/wrapper-*.log -A 14
   ```

3. **Stop Test** (if running)
   ```bash
   curl -X POST http://localhost:8080/api/bluegreen/stop
   ```

4. **Optional: Remove BG Plugin**
   - After successful switchover, the `bg` plugin can be removed
   - No adverse effects if left enabled

5. **Delete Blue/Green Deployment**
   ```bash
   aws rds delete-blue-green-deployment \
     --blue-green-deployment-identifier <deployment-id>
   ```

---

## Testing Procedures

### Start Continuous Write Test

```bash
# 10 connections, write every 500ms
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# 50 connections, write as fast as possible
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=50&writeIntervalMs=0"
```

### Check Test Status

```bash
curl http://localhost:8080/api/bluegreen/status
```

Response:
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

### Stop Test

```bash
curl -X POST http://localhost:8080/api/bluegreen/stop
```

### Success Criteria

| Metric | Target | Description |
|--------|--------|-------------|
| Success Rate | > 99% | Percentage of successful writes |
| Failover Detection | Yes | Plugin correctly identifies switchover |
| Auto Recovery | Yes | Writes resume after switchover |
| Read-Only Errors | 0 | No read-only errors should occur with properly configured BG plugin |

---

## Monitoring and Logging

### Log Levels

| Level | Use Case | What You See |
|-------|----------|--------------|
| `INFO` | Production | Basic status changes |
| `FINE` | Recommended | BG status, switchover summary |
| `FINEST` | Debugging | Full plugin execution details |

### Key Log Patterns

```bash
# View current logs (new file per startup)
tail -f logs/wrapper-*.log

# BG status changes (FINE level)
grep -i "BG status" logs/wrapper-*.log

# Status changes (FINEST level)
grep -i "Status changed to" logs/wrapper-*.log

# Switchover timeline summary
grep -i "time offset" logs/wrapper-*.log -A 14

# Connection events
grep -i "failover\|reconnect" logs/wrapper-*.log

# Errors
grep -i "error\|exception" logs/wrapper-*.log
```

### Switchover Timeline Example

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

### Key Timeline Events

| Event | Description |
|-------|-------------|
| NOT_CREATED | No BG deployment detected |
| CREATED | BG deployment created, collecting topology |
| PREPARATION | Preparing for switchover, substituting DNS with IPs |
| IN_PROGRESS | **Active switchover - SQL requests suspended** |
| POST | Switchover complete, monitoring DNS updates |
| Blue DNS updated | Blue endpoints now point to new (green) cluster |
| Green DNS removed | Old green endpoints no longer accessible |
| COMPLETED | Switchover finished, normal operation resumed |

---

## Troubleshooting

### Common Issues

#### 1. BG Plugin Not Detecting Deployment

**Symptoms:**
- Log shows `BG status: NOT_CREATED` even after creating deployment
- No status changes during switchover

**Solutions:**
- Verify database permissions: `GRANT SELECT ON mysql.rds_topology TO 'user'@'%';`
- Check Aurora MySQL version is 3.07+
- Ensure using cluster endpoint (not instance endpoint)
- Wait 2-5 minutes for status collection

#### 2. Connection Pool Exhaustion

**Symptoms:**
- `Connection is not available, request timed out after 30000ms`
- `total=50, active=50, idle=0, waiting=49`

**Solutions:**
- Increase `maximum-pool-size` to match or exceed thread count
- Reduce `connection-timeout` for faster failure
- Reduce concurrent test threads

```yaml
hikari:
  maximum-pool-size: 120
  connection-timeout: 10000
```

#### 3. High Failure Rate During Switchover

**Symptoms:**
- Many failed writes during IN_PROGRESS phase
- Read-only errors

**Solutions:**
- This is expected behavior - plugin suspends requests during switchover
- Ensure `bgSwitchoverTimeoutMs` is sufficient (default 180000ms)
- Check network connectivity to green cluster

#### 4. Permissions Error

**Symptoms:**
- `Access denied for user` errors
- Plugin cannot read metadata table

**Solutions:**
- Grant permissions on **BOTH** blue and green clusters:
  ```sql
  GRANT SELECT ON mysql.rds_topology TO 'user'@'%';
  FLUSH PRIVILEGES;
  ```

#### 5. Multi-Cluster Confusion

**Symptoms:**
- Switchover on Cluster A affects Cluster B connections
- Wrong topology information

**Solutions:**
- Ensure unique `clusterId` and `bgdId` for each cluster
- Verify configuration in JDBC URL

### Debug Commands

```bash
# Check plugin loading
grep -i "plugin.*loaded\|plugin.*initialized" logs/wrapper-*.log

# Check BG metadata access
grep -i "rds_topology\|metadata" logs/wrapper-*.log

# Check connection events
grep -i "connection.*opened\|connection.*closed" logs/wrapper-*.log

# Check for errors
grep -i "error\|exception\|failed" logs/wrapper-*.log | head -50
```

---

## Best Practices

### Pre-Switchover

1. **Test in Non-Production First**
   - Always test Blue/Green switchover in a staging environment

2. **Grant Permissions Early**
   - Grant permissions on both clusters before creating BG deployment

3. **Use FINE Log Level**
   - Set `wrapperLoggerLevel=FINE` to capture switchover summary

4. **Verify Network Access**
   - Ensure application can reach green cluster IP addresses

5. **Size Connection Pool Appropriately**
   - Pool size should match or exceed concurrent thread count

### During Switchover

1. **Monitor Logs**
   - Watch for BG status changes in real-time

2. **Expect Brief Suspension**
   - SQL requests are suspended during IN_PROGRESS phase (typically 30-60 seconds)

3. **Don't Panic on Errors**
   - Some connection errors are expected during transition

### Post-Switchover

1. **Review Timeline Summary**
   - Check switchover duration and events

2. **Verify Application Health**
   - Confirm writes are succeeding to new cluster

3. **Clean Up**
   - Delete BG deployment after successful switchover
   - Optionally remove `bg` plugin from configuration

### Multi-Cluster Environments

1. **Always Use Unique Identifiers**
   - Set unique `clusterId` and `bgdId` for each cluster

2. **Test Each Cluster Independently**
   - Verify BG plugin works for each cluster before production

3. **Document Configuration**
   - Maintain clear documentation of cluster-to-identifier mappings

---

## Quick Reference

### Environment Variables

```bash
# Required
export AURORA_CLUSTER_ENDPOINT="cluster.cluster-xxx.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="password"

# Recommended
export WRAPPER_LOG_LEVEL="FINE"
export CLUSTER_ID="cluster-a"
export BGD_ID="cluster-a"

# Optional (defaults shown)
export BG_HIGH_MS="100"
export BG_INCREASED_MS="1000"
export BG_BASELINE_MS="60000"
export BG_CONNECT_TIMEOUT_MS="30000"
export BG_SWITCHOVER_TIMEOUT_MS="180000"
```

### Common Commands

```bash
# Start application
./run-aurora.sh prod

# Start write test
curl -X POST "http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500"

# Check status
curl http://localhost:8080/api/bluegreen/status

# Stop test
curl -X POST http://localhost:8080/api/bluegreen/stop

# View BG status
grep -i "BG status" logs/wrapper-*.log

# View switchover summary
grep -i "time offset" logs/wrapper-*.log -A 14
```

### AWS CLI Commands

```bash
# Create Blue/Green deployment
aws rds create-blue-green-deployment \
  --blue-green-deployment-name my-bg \
  --source arn:aws:rds:region:account:cluster:my-cluster \
  --target-engine-version 8.0.mysql_aurora.3.10.3

# Check status
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier <id>

# Execute switchover
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <id> \
  --switchover-timeout 300

# Delete deployment
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier <id>
```

---

## References

- [AWS Advanced JDBC Wrapper Documentation](https://github.com/aws/aws-advanced-jdbc-wrapper)
- [Blue/Green Plugin Documentation](https://github.com/aws/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/using-plugins/UsingTheBlueGreenPlugin.md)
- [Aurora Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments.html)
- [RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html)
