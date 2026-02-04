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
