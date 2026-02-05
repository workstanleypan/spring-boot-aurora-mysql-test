# AWS JDBC Wrapper Plugin Configuration

## Plugin Configuration

### Aurora MySQL

```
wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg
```

### RDS MySQL

```
wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg
```

## Plugin Description

| Plugin | Function | Aurora | RDS |
|--------|----------|--------|-----|
| `initialConnection` | Initial connection strategy, smart node selection | Required | Not needed |
| `auroraConnectionTracker` | Connection state tracking | Required | Required |
| `failover2` | Automatic failover | Required | Required |
| `efm2` | Enhanced failure monitoring | Required | Required |
| `bg` | Blue/Green deployment support | Required | Required |

### Why RDS doesn't need initialConnection?

RDS is single instance or primary-standby mode, no need to select from multiple read replicas. Aurora has multiple read replicas and needs smart node selection.

## Cluster Identifier Configuration (clusterId & bgdId)

### Parameter Description

| Parameter | Default | Purpose | Storage Content |
|-----------|---------|---------|-----------------|
| `clusterId` | `"1"` | Cluster topology cache identifier | Cluster node topology (Topology) |
| `bgdId` | `"1"` | Blue/Green deployment status identifier | BG switchover status (BlueGreenStatus) |

### Single Cluster Scenario

For single cluster connections, you can use default values or set both to the same value:

```
clusterId=cluster-a&bgdId=cluster-a
```

### Multi-Cluster Scenario (Important!)

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

### What Happens If Not Configured Correctly?

| Scenario | Problem |
|----------|---------|
| Only `clusterId` different | BG status will be confused, Cluster A's switchover may affect Cluster B's connection routing |
| Only `bgdId` different | Topology cache will be confused, may treat Cluster A's nodes as Cluster B's nodes |
| Both same for different clusters | Both problems above will occur |

### How It Works Internally

1. **clusterId**: Used by `RdsHostListProvider` to cache cluster topology. Connections with the same `clusterId` share the topology cache.

2. **bgdId**: Used by `BlueGreenStatusProvider` to store and retrieve BG switchover status. The provider is keyed by `bgdId`.

3. **Relationship**: When `BlueGreenConnectionPlugin` initializes, it gets `clusterId` from `HostListProvider` and creates a `BlueGreenStatusProvider` keyed by `bgdId`. The provider uses `clusterId` for monitor reset events.

## Log Levels

| JUL Level | Log4j2 Level | Description |
|-----------|--------------|-------------|
| SEVERE | ERROR | Only severe errors |
| WARNING | WARN | Warnings and errors |
| INFO | INFO | Basic information |
| FINE | DEBUG | Production recommended, shows BG plugin status |
| FINER | DEBUG | Detailed plugin execution flow |
| FINEST | TRACE | Testing recommended, full debug information |

## Configuration Examples

### Aurora MySQL (Production)

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://cluster.cluster-xxxxx.rds.amazonaws.com:3306/testdb?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

### RDS MySQL (Production)

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://instance.xxxxx.rds.amazonaws.com:3306/testdb?wrapperPlugins=auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
```

## Connection Pool: HikariCP

Spring Boot uses HikariCP by default:

```yaml
spring:
  datasource:
    hikari:
      pool-name: AuroraHikariPool
      minimum-idle: 10
      maximum-pool-size: 50
      idle-timeout: 300000
      max-lifetime: 600000
      connection-timeout: 30000
```

## Verify Plugins

```bash
# View plugin loading logs
grep -i "plugin" logs/wrapper.log

# View BG plugin status
grep -i "blue.*green\|BlueGreen" logs/wrapper.log
```

## Performance Impact

| Plugin | Impact | Notes |
|--------|--------|-------|
| initialConnection | Minimal | Only runs on initial connection |
| auroraConnectionTracker | Minimal | Lightweight tracking |
| failover2 | Low | Background monitoring |
| efm2 | Low | Enhanced monitoring |
| bg | Minimal | Only runs when switchover detected |

**Overall Impact**: < 5% performance overhead, in exchange for high availability and automatic failover.

## Related Documentation

- [AURORA_CONFIGURATION_GUIDE.md](AURORA_CONFIGURATION_GUIDE.md) - Aurora Configuration Guide
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - Blue/Green Test Guide
