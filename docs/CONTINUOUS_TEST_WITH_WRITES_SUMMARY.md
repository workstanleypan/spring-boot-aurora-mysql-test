# 持续蓝绿切换测试 - 包含写入操作

## 新功能总结

### ✅ 已实现的功能

1. **持续模式 (Continuous Mode)**
   - 无限期运行，直到手动停止
   - 设置 `durationSeconds: 0` 启动

2. **写入操作 (Write Operations)**
   - 每个线程持续写入数据库
   - 自动创建测试表
   - 检测 read-only 错误
   - 记录写入成功率和延迟

3. **完整统计**
   - 读取统计：总数、成功、失败、成功率、延迟
   - 写入统计：总数、成功、失败、成功率、延迟、read-only 错误
   - Failover 检测
   - 运行时间

4. **保留原有配置**
   - 从 `application.yml` 读取数据库连接
   - 支持日志级别配置
   - HikariCP 连接池配置

## 快速开始

### 1. 启动持续测试（默认配置）

```bash
# 启动应用
./run-aurora.sh

# 在另一个终端启动持续测试
./test-bluegreen-continuous.sh start-continuous

# 监控状态
./test-bluegreen-continuous.sh monitor
```

默认配置：
- 20 个线程
- 每线程 500 次读取/秒
- 每线程 10 次写入/秒
- **无限期运行**

### 2. 自定义配置

```bash
# API 调用
curl -X POST http://localhost:8080/api/bluegreen/start-continuous \
  -H "Content-Type: application/json" \
  -d '{
    "numThreads": 10,
    "readsPerSecond": 200,
    "writesPerSecond": 5
  }'
```

### 3. 查看状态

```bash
curl http://localhost:8080/api/bluegreen/status | jq '.'
```

输出示例：
```json
{
  "running": true,
  "mode": "continuous",
  "statistics": {
    "totalReads": 1500000,
    "successfulReads": 1499500,
    "failedReads": 500,
    "readSuccessRate": "99.97%",
    "avgReadLatency": "5ms",
    "totalWrites": 30000,
    "successfulWrites": 29950,
    "failedWrites": 50,
    "writeSuccessRate": "99.83%",
    "avgWriteLatency": "8ms",
    "readOnlyErrors": 5,
    "failoverCount": 2,
    "runningTimeSeconds": 3600,
    "runningTime": "1h 0m 0s"
  },
  "connection": {
    "lastEndpoint": "ip-10-0-1-100.ec2.internal:3306 [WRITER]"
  }
}
```

## 测试场景

### 场景 1: 长期监控蓝绿切换

```bash
# 启动持续测试
./test-bluegreen-continuous.sh start-continuous

# 监控状态
./test-bluegreen-continuous.sh monitor

# 执行蓝绿切换（在 AWS Console）
# 观察：
# - Failover 检测
# - Read-only 错误
# - 连接端点变化
# - 成功率变化

# 完成后停止
./test-bluegreen-continuous.sh stop
```

### 场景 2: 只读取，不写入

```bash
curl -X POST http://localhost:8080/api/bluegreen/start \
  -H "Content-Type: application/json" \
  -d '{
    "numThreads": 20,
    "readsPerSecond": 500,
    "durationSeconds": 0
  }'
```

注意：默认的 `start` 端点不支持禁用写入，需要使用内部 API。

## 数据库表结构

每个线程创建自己的测试表：

```sql
CREATE TABLE bg_test_thread_1 (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  thread_id INT NOT NULL,
  endpoint VARCHAR(255),
  phase VARCHAR(50),
  test_data TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_thread_id (thread_id),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## 日志输出

### 应用日志 (logs/spring-boot.log)

```
╔════════════════════════════════════════════════════════════════╗
║   Blue/Green Switchover Test - Metadata Reads                 ║
╚════════════════════════════════════════════════════════════════╝

📋 Test Configuration:
   Test ID: BG-1705234567890
   Total Threads: 20
   Reads Per Second (per thread): 500
   Total Reads Per Second: 10000
   Writes Per Second (per thread): 10
   Total Writes Per Second: 200
   Test Duration: ♾️  CONTINUOUS MODE (until manually stopped)

🔍 Test Scenario:
   - All 20 threads: Continuous metadata reads (500/sec each)
   - All 20 threads: Database writes (10/sec each)
   - Monitoring for Blue/Green switchover events
   - Tracking connection state and failover behavior
   - ♾️  Running in CONTINUOUS mode - will not stop automatically

🚀 [2026-01-20 15:30:00.000] Starting 20 metadata read threads...
✍️  [2026-01-20 15:30:00.100] Write-Thread-1: Starting CONTINUOUS writes (10/sec)...
...
```

### Read-Only 错误检测

```
╔════════════════════════════════════════════════════════════════╗
║  🎯 READ-ONLY ERROR DETECTED! 🎯                              ║
╚════════════════════════════════════════════════════════════════╝
[2026-01-20 15:35:00.000] Write-Thread-5 Write #1234
Error Code: 1290
SQL State: HY000
Message: The MySQL server is running with the --read-only option
Current endpoint: ip-10-0-1-100.ec2.internal:3306 [READER]
```

## 监控指标

### 关键指标

**读取操作：**
- 总读取次数
- 成功率 (目标: > 95%)
- 平均延迟 (目标: < 50ms)

**写入操作：**
- 总写入次数
- 成功率 (目标: > 95%)
- 平均延迟 (目标: < 100ms)
- Read-only 错误次数

**Failover：**
- Failover 检测次数
- 连接端点变化

## 与原始测试的对比

### MultiThreadBlueGreenTestWithUnifiedLogging.java

**相同点：**
- ✅ 多线程元数据读取
- ✅ Failover 检测
- ✅ 连接状态监控
- ✅ 详细日志记录
- ✅ 统一日志系统

**新增功能：**
- ✅ 持续模式（无限期运行）
- ✅ 写入操作
- ✅ Read-only 错误检测
- ✅ REST API 控制
- ✅ 实时状态查询
- ✅ Spring Boot 集成
- ✅ HikariCP 连接池

## 配置说明

### application.yml

```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://${CLUSTER_ENDPOINT}/${DB_NAME}?wrapperPlugins=initialConnection,auroraConnectionTracker,failover2,efm2,bg&wrapperLoggerLevel=FINE
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    driver-class-name: software.amazon.jdbc.Driver
    hikari:
      maximum-pool-size: 30
      minimum-idle: 20
      connection-timeout: 30000
```

### 环境变量

```bash
export CLUSTER_ENDPOINT=my-cluster.cluster-xxx.rds.amazonaws.com
export DB_USER=admin
export DB_PASSWORD=password
export DB_NAME=testdb
```

## 故障排查

### 写入失败率高

1. 检查是否连接到 Writer 端点
2. 查看 read-only 错误数量
3. 验证 BG Plugin 状态
4. 检查连接池配置

### Read-Only 错误持续出现

1. 确认使用 Cluster Endpoint
2. 验证 BG Plugin 已启用
3. 检查蓝绿切换是否完成
4. 查看 JDBC Wrapper 日志

### 测试无法启动

```bash
# 检查应用状态
curl http://localhost:8080/api/test

# 查看日志
tail -f logs/spring-boot.log

# 检查数据库连接
mysql -h $CLUSTER_ENDPOINT -u $DB_USER -p$DB_PASSWORD -e "SELECT 1"
```

## 相关文档

- `CONTINUOUS_TEST_GUIDE.md` - 完整测试指南
- `CONTINUOUS_TEST_QUICK_START.md` - 快速开始
- `BLUEGREEN_TEST_GUIDE.md` - 蓝绿测试说明
- `UNIFIED_LOGGING_GUIDE.md` - 日志配置
- `AURORA_CONFIGURATION_GUIDE.md` - Aurora 配置

## API 参考

### POST /api/bluegreen/start-continuous
启动持续测试

### GET /api/bluegreen/status
获取测试状态

### POST /api/bluegreen/stop
停止测试

### GET /api/bluegreen/help
获取帮助信息
