# Aurora MySQL Configuration Guide

## Overview

This guide explains how to configure a Spring Boot application to connect to AWS Aurora MySQL cluster with Blue/Green Deployment Plugin enabled.

## JDBC URL Details

### Complete Format

![JDBC URL Format](images/jdbc-url-format.png)

**Example:**
```
jdbc:aws-wrapper:mysql://my-cluster.cluster-xxx.us-east-1.rds.amazonaws.com/testdb?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&clusterId=my-cluster&bgdId=my-cluster
```

### Parameter Description

| Color | Parameter | Description |
|-------|-----------|-------------|
| Red | `writer_cluster_endpoint`, `database_name` | Business-specific connection parameters |
| Green | `characterEncoding=utf8` | Native MySQL connection parameters |
| Yellow | `wrapperPlugins=...`, `wrapperLoggerLevel=...` | **Required Wrapper parameters (Important)** |
| Purple | `clusterId=name&bgdId=name` | Cluster identifier parameters (see below) |

### Important Notes

1. **Do NOT use** `autoreconnect=true` - It interferes with Wrapper's failover mechanism
2. **Must use Cluster Endpoint**, not instance endpoint

### Cluster Identifier Parameters (clusterId & bgdId)

The wrapper uses two identifier parameters to maintain separate internal state per cluster:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `clusterId` | `"1"` | Topology cache key — connections with the same `clusterId` share cached cluster topology (node list) and monitoring threads |
| `bgdId` | `"1"` | Blue/Green deployment status key — connections with the same `bgdId` share BG switchover state |

#### Why clusterId Matters

The driver cannot always determine which cluster a connection belongs to from the URL alone (e.g. IP addresses, custom domains, proxy endpoints may all point to the same cluster). `clusterId` lets you explicitly tell the driver which connections belong to the same cluster so they can share topology cache and monitors.

#### Single Cluster

If your application connects to only one Aurora cluster, both parameters are optional (they default to `"1"`). You can also set them explicitly for clarity:

```
jdbc:aws-wrapper:mysql://my-cluster.cluster-xxx.rds.amazonaws.com/testdb?...&clusterId=my-cluster&bgdId=my-cluster
```

#### Multi-Cluster (Important!)

When a single application connects to multiple Aurora clusters, **both `clusterId` and `bgdId` must be set to unique values per cluster**:

| Scenario | Problem |
|----------|---------|
| Same `clusterId` for different clusters | Topology cache collision — one cluster's node list overwrites the other's, causing incorrect failover |
| Same `bgdId` for different clusters | BG status confusion — one cluster's switchover may affect the other's connection routing |
| Both same for different clusters | Both problems above |

#### Multi-Cluster Example

If an application connects to both cluster-a and cluster-b:

**URL for cluster-a:**
```
jdbc:aws-wrapper:mysql://cluster-a.cluster-xxx.rds.amazonaws.com/database?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&clusterId=cluster-a&bgdId=cluster-a
```

**URL for cluster-b:**
```
jdbc:aws-wrapper:mysql://cluster-b.cluster-xxx.rds.amazonaws.com/database?characterEncoding=utf8&wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE&clusterId=cluster-b&bgdId=cluster-b
```

> For detailed internals on how `clusterId` works (cache isolation diagrams, code examples), see the [AWS JDBC Wrapper ClusterId documentation](https://github.com/awslabs/aws-advanced-jdbc-wrapper/blob/main/docs/using-the-jdbc-driver/ClusterId.md).

## Prerequisites

### 1. Aurora Cluster Information

- **Cluster Endpoint**: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`
- **Database Name**: `testdb`
- **Username**: `admin`
- **Password**: `your-password`

### 2. Network Access

- Aurora security group allows inbound traffic on port 3306
- Application deployed in same VPC or connected via VPC Peering

## Quick Configuration

### Using Environment Variables

```bash
AURORA_CLUSTER_ENDPOINT="database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com" \
AURORA_DATABASE="testdb" \
AURORA_USERNAME="admin" \
AURORA_PASSWORD="your-password" \
WRAPPER_LOG_LEVEL="FINE" \
./run-aurora.sh prod
```

## Profiles

| Profile | Log Level | Pool Size (min-idle / max) | Connection Timeout | Use Case |
|---------|-----------|---------------------------|-------------------|----------|
| `aurora-prod` | INFO | 20 / 120 | 10s | Production |
| `aurora-dev` | FINE | 5 / 20 | 10s | Development/Debug |

## Tech Stack

### Connection Pool: HikariCP

Spring Boot uses HikariCP by default, configured in `application.yml`:

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
      leak-detection-threshold: 0
```

### Wrapper Plugins

| Plugin | Function |
|--------|----------|
| `initialConnection` | Initial connection handling |
| `auroraConnectionTracker` | Aurora connection tracking |
| `failover2` | Automatic failover |
| `efm2` | Enhanced failure monitoring |
| `bg` | Blue/Green deployment support |

### Log Levels

| JUL Level | Log4j2 Level | Description |
|-----------|--------------|-------------|
| INFO | INFO | Basic information |
| FINE | DEBUG | Production recommended, shows BG plugin status |
| FINER | DEBUG | Detailed plugin execution flow |
| FINEST | TRACE | Testing recommended, full debug information |

## Verification

### 1. Test Connection

```bash
curl http://localhost:8080/api/test
```

### 2. View Logs

```bash
# Wrapper logs
tail -f logs/wrapper.log

# BG Plugin related
grep -i "blue.*green\|BlueGreen" logs/wrapper.log
```

## Troubleshooting

### Connection Timeout

```bash
# Test network connectivity
nc -zv your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306
```

### BG Plugin Not Supported

Ensure you're using **Cluster Endpoint** (contains `.cluster-`), not instance endpoint:

✅ Correct: `database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com`  
❌ Wrong: `database-1-instance-1.xxxxx.us-east-1.rds.amazonaws.com`

## Related Documentation

- [AURORA_QUICK_START.md](AURORA_QUICK_START.md) - Quick Start
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - Blue/Green Test Guide
- [PLUGIN_CONFIGURATION.md](PLUGIN_CONFIGURATION.md) - Plugin Configuration
