# 持续蓝绿切换测试指南

## 概述

持续测试模式允许测试程序**无限期运行**，直到手动停止。这对于长期监控蓝绿切换非常有用。

## 快速开始

### 1. 启动持续测试（默认参数）

```bash
cd spring-boot-mysql-test
./test-bluegreen-continuous.sh start-continuous
```

默认配置：
- 20 个线程
- 每线程 500 次读取/秒
- 总负载：10,000 次读取/秒
- **无限期运行**

### 2. 启动持续测试（自定义参数）

```bash
# 10 线程，每线程 200 次读取/秒
./test-bluegreen-continuous.sh start-continuous 10 200
```

### 3. 监控测试状态

```bash
# 每 30 秒更新一次（默认）
./test-bluegreen-continuous.sh monitor

# 每 10 秒更新一次
./test-bluegreen-continuous.sh monitor 10
```

### 4. 停止测试

```bash
./test-bluegreen-continuous.sh stop
```

## 测试模式对比

### 持续模式 (Continuous Mode)

- ✅ 无限期运行，直到手动停止
- ✅ 适合长期监控蓝绿切换
- ✅ 可以在任何时候执行切换
- ✅ 持续收集统计数据
- 🔄 使用 `durationSeconds: 0` 启动

**启动方式：**
```bash
./test-bluegreen-continuous.sh start-continuous [threads] [reads/sec]
```

**API 调用：**
```bash
curl -X POST http://localhost:8080/api/bluegreen/start-continuous \
  -H "Content-Type: application/json" \
  -d '{"numThreads":20,"readsPerSecond":500}'
```

### 定时模式 (Timed Mode)

- ⏱️ 运行指定时间后自动停止
- ✅ 适合有时间限制的测试
- ✅ 自动生成最终报告
- 🔄 使用 `durationSeconds: N` 启动

**启动方式：**
```bash
./test-bluegreen-continuous.sh start-timed [threads] [reads/sec] [duration]
```

**API 调用：**
```bash
curl -X POST http://localhost:8080/api/bluegreen/start \
  -H "Content-Type: application/json" \
  -d '{"numThreads":20,"readsPerSecond":500,"durationSeconds":3600}'
```

## 使用场景

### 场景 1: 长期监控（推荐持续模式）

```bash
# 启动持续测试
./test-bluegreen-continuous.sh start-continuous 10 200

# 在另一个终端监控
./test-bluegreen-continuous.sh monitor

# 执行蓝绿切换（在 AWS Console 或使用 CLI）
# 观察 failover 检测和连接变化

# 完成后停止
./test-bluegreen-continuous.sh stop
```

### 场景 2: 定时压力测试

```bash
# 启动 1 小时的高负载测试
./test-bluegreen-continuous.sh start-timed 50 1000 3600

# 监控状态
./test-bluegreen-continuous.sh monitor

# 测试会在 1 小时后自动停止
```

### 场景 3: 快速验证

```bash
# 快速测试（60秒）
./test-bluegreen-continuous.sh quick-test

# 查看状态
./test-bluegreen-continuous.sh status
```

## API 端点

### POST /api/bluegreen/start-continuous
启动持续测试（无限期运行）

**请求体：**
```json
{
  "numThreads": 20,
  "readsPerSecond": 500
}
```

**响应：**
```json
{
  "status": "started",
  "testId": "BG-1705234567890",
  "configuration": {
    "numThreads": 20,
    "readsPerSecond": 500,
    "totalReadsPerSecond": 10000,
    "mode": "continuous",
    "durationSeconds": "∞ (until manually stopped)"
  },
  "message": "Blue/Green switchover test started in CONTINUOUS mode"
}
```

### GET /api/bluegreen/status
获取测试状态

**响应：**
```json
{
  "running": true,
  "mode": "continuous",
  "statistics": {
    "totalReads": 1500000,
    "successfulReads": 1499500,
    "failedReads": 500,
    "successRate": "99.97%",
    "avgLatency": "5ms",
    "failoverCount": 2,
    "runningTimeSeconds": 3600,
    "runningTime": "1h 0m 0s"
  },
  "connection": {
    "lastEndpoint": "ip-10-0-1-100.ec2.internal:3306 [WRITER]"
  }
}
```

## 监控输出示例

```
═══════════════════════════════════════════════════════════════
  Blue/Green Continuous Test Monitor
  2026-01-20 15:30:45
═══════════════════════════════════════════════════════════════

✅ Test is RUNNING (continuous mode)

📊 Statistics:
  totalReads: 1500000
  successfulReads: 1499500
  failedReads: 500
  successRate: 99.97%
  avgLatency: 5ms
  failoverCount: 2
  runningTimeSeconds: 3600
  runningTime: 1h 0m 0s

🔌 Connection:
  lastEndpoint: ip-10-0-1-100.ec2.internal:3306 [WRITER]

⚠️  Failovers detected: 2

═══════════════════════════════════════════════════════════════
Next update in 30s... (Ctrl+C to stop monitoring)
```

## 日志文件

测试运行时会生成以下日志：

- `logs/spring-boot.log` - 应用日志，包含测试状态和 failover 检测
- `logs/jdbc-wrapper.log` - JDBC Wrapper 日志，包含 BG Plugin 状态
- `logs/ip-metadata.log` - IP 元数据日志，记录连接详情

**查看日志：**
```bash
# 实时查看所有日志
tail -f logs/*.log

# 查看应用日志
tail -f logs/spring-boot.log

# 查看 JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log
```

## 最佳实践

### 1. 启动测试前

- ✅ 确认 Aurora 集群健康
- ✅ 验证连接配置正确
- ✅ 检查日志级别设置

### 2. 运行测试时

- ✅ 使用监控脚本实时查看状态
- ✅ 观察成功率和延迟
- ✅ 记录 failover 发生时间

### 3. 执行蓝绿切换

- ✅ 在测试稳定运行后执行
- ✅ 观察 failover 检测
- ✅ 验证连接端点变化

### 4. 测试完成后

- ✅ 查看最终报告
- ✅ 保存日志文件
- ✅ 分析 failover 时间点

## 故障排查

### 测试无法启动

```bash
# 检查应用是否运行
curl http://localhost:8080/api/test

# 查看应用日志
tail -f logs/spring-boot.log
```

### 高失败率

1. 检查数据库连接稳定性
2. 查看 JDBC Wrapper 日志
3. 验证连接池配置
4. 检查网络延迟

### Failover 未检测到

1. 确认使用 Cluster Endpoint
2. 验证 BG Plugin 已启用
3. 检查日志级别（建议 FINE）
4. 确认切换确实发生

## 命令参考

```bash
# 启动持续测试
./test-bluegreen-continuous.sh start-continuous [threads] [reads/sec]

# 启动定时测试
./test-bluegreen-continuous.sh start-timed [threads] [reads/sec] [duration]

# 停止测试
./test-bluegreen-continuous.sh stop

# 查看状态（一次）
./test-bluegreen-continuous.sh status

# 持续监控
./test-bluegreen-continuous.sh monitor [interval]

# 快速测试
./test-bluegreen-continuous.sh quick-test

# 帮助
./test-bluegreen-continuous.sh help
```

## 相关文档

- `BLUEGREEN_TEST_GUIDE.md` - 完整测试指南
- `AURORA_CONFIGURATION_GUIDE.md` - Aurora 配置
- `WHY_BG_PLUGIN_NEEDS_CLUSTER_ENDPOINT.md` - BG Plugin 说明
- `UNIFIED_LOGGING_GUIDE.md` - 日志配置
