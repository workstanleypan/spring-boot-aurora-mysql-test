# Blue/Green Switchover Test Guide

## 概述

这个测试服务模拟 `MultiThreadBlueGreenTestWithUnifiedLogging.java` 的行为，用于在 Spring Boot 环境中测试 AWS JDBC Wrapper 在 Aurora 蓝绿切换时的表现。

## 测试场景

### 核心功能
- **多线程元数据读取**: 持续高频读取数据库元数据
- **Failover 检测**: 自动检测和记录 failover 事件
- **连接状态监控**: 跟踪连接端点变化
- **详细日志记录**: 记录所有关键事件和异常

### 测试流程
1. 启动多个线程（默认 20 个）
2. 每个线程持续读取数据库元数据（默认 500 次/秒）
3. 监控线程定期报告统计信息（每 30 秒）
4. 检测 failover 事件和连接异常
5. 测试结束后生成详细报告

## 快速开始

### 1. 启动应用

```bash
# 使用 Aurora 配置启动
cd spring-boot-mysql-test
./run-aurora.sh

# 或使用 BG Plugin 调试模式
./run-aurora-bg-debug.sh
```

### 2. 启动测试

#### 方式 1: 使用测试脚本（推荐）

```bash
# 查看帮助
./test-bluegreen-api.sh

# 快速测试 (5线程, 60秒)
./test-bluegreen-api.sh quick-test

# 启动默认测试 (20线程, 500读/秒, 1小时)
./test-bluegreen-api.sh start

# 启动自定义测试
./test-bluegreen-api.sh start-custom 10 200 1800
# 参数: 线程数 读取/秒 持续时间(秒)

# 持续监控状态
./test-bluegreen-api.sh monitor

# 停止测试
./test-bluegreen-api.sh stop
```

#### 方式 2: 直接使用 curl

```bash
# 启动默认测试
curl -X POST http://localhost:8080/api/bluegreen/start

# 启动自定义测试
curl -X POST http://localhost:8080/api/bluegreen/start \
  -H "Content-Type: application/json" \
  -d '{
    "numThreads": 10,
    "readsPerSecond": 200,
    "durationSeconds": 1800
  }'

# 快速测试
curl -X POST http://localhost:8080/api/bluegreen/quick-test

# 查看状态
curl http://localhost:8080/api/bluegreen/status

# 停止测试
curl -X POST http://localhost:8080/api/bluegreen/stop

# 获取帮助
curl http://localhost:8080/api/bluegreen/help
```

### 3. 执行蓝绿切换

在测试运行期间，在 AWS Console 中执行 Blue/Green 切换：

```bash
# 使用 AWS CLI 触发切换
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <deployment-id> \
  --switchover-timeout 300
```

### 4. 查看日志

```bash
# 查看应用日志
tail -f logs/spring-boot.log

# 查看 JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log

# 查看 IP 元数据日志
tail -f logs/ip-metadata.log

# 查看所有日志
tail -f logs/*.log
```

## API 端点

### POST /api/bluegreen/start
启动蓝绿切换测试

**请求体** (可选):
```json
{
  "numThreads": 20,
  "readsPerSecond": 500,
  "durationSeconds": 3600
}
```

**参数说明**:
- `numThreads`: 线程数 (1-100, 默认: 20)
- `readsPerSecond`: 每线程每秒读取次数 (1-10000, 默认: 500)
- `durationSeconds`: 测试持续时间(秒) (10-86400, 默认: 3600)

**响应**:
```json
{
  "status": "started",
  "testId": "BG-1705234567890",
  "configuration": {
    "numThreads": 20,
    "readsPerSecond": 500,
    "totalReadsPerSecond": 10000,
    "durationSeconds": 3600
  },
  "message": "Blue/Green switchover test started successfully"
}
```

### GET /api/bluegreen/status
获取当前测试状态

**响应**:
```json
{
  "running": true,
  "statistics": {
    "totalReads": 150000,
    "successfulReads": 149950,
    "failedReads": 50,
    "successRate": "99.97%",
    "avgLatency": "5ms",
    "failoverCount": 1
  },
  "connection": {
    "lastEndpoint": "ip-10-0-1-100.ec2.internal:3306 [WRITER]"
  }
}
```

### POST /api/bluegreen/stop
停止当前运行的测试

**响应**:
```json
{
  "status": "stopped",
  "message": "Test stopped successfully"
}
```

### POST /api/bluegreen/quick-test
快速测试 (5线程, 100读/秒, 60秒)

### GET /api/bluegreen/help
获取 API 帮助信息

## 测试参数建议

### 快速验证测试
```json
{
  "numThreads": 5,
  "readsPerSecond": 100,
  "durationSeconds": 60
}
```
- 用途: 快速验证配置是否正确
- 总负载: 500 读/秒
- 持续时间: 1 分钟

### 标准压力测试
```json
{
  "numThreads": 20,
  "readsPerSecond": 500,
  "durationSeconds": 3600
}
```
- 用途: 标准蓝绿切换测试
- 总负载: 10,000 读/秒
- 持续时间: 1 小时

### 高负载测试
```json
{
  "numThreads": 50,
  "readsPerSecond": 1000,
  "durationSeconds": 1800
}
```
- 用途: 高负载场景测试
- 总负载: 50,000 读/秒
- 持续时间: 30 分钟

### 长时间稳定性测试
```json
{
  "numThreads": 10,
  "readsPerSecond": 200,
  "durationSeconds": 7200
}
```
- 用途: 长时间稳定性验证
- 总负载: 2,000 读/秒
- 持续时间: 2 小时

## 日志说明

### 应用日志 (logs/spring-boot.log)
- 测试启动/停止事件
- 线程状态报告
- Failover 检测
- 异常分析

### JDBC Wrapper 日志 (logs/jdbc-wrapper.log)
- BG Plugin 状态
- 连接池事件
- Failover 插件决策
- 拓扑刷新事件

### IP 元数据日志 (logs/ip-metadata.log)
- 当前连接 IP
- 表名匹配结果
- 元数据读取详情

## 监控指标

### 关键指标
1. **总读取次数**: 累计元数据读取次数
2. **成功率**: 成功读取的百分比
3. **失败次数**: 失败的读取次数
4. **平均延迟**: 每次读取的平均耗时
5. **Failover 次数**: 检测到的 failover 事件数量
6. **当前端点**: 最后一次连接的数据库端点

### 成功标准
- ✅ 成功率 > 95%: 高可用性
- ✅ 平均延迟 < 50ms: 良好性能
- ✅ Failover 检测: 正确识别切换事件
- ✅ 无连接泄漏: 所有连接正确归还连接池

## 故障排查

### 测试无法启动
```bash
# 检查应用是否运行
curl http://localhost:8080/api/test

# 检查数据库连接
curl http://localhost:8080/api/test | jq '.database'

# 查看应用日志
tail -f logs/spring-boot.log
```

### 高失败率
1. 检查数据库连接稳定性
2. 查看 JDBC Wrapper 日志中的错误
3. 验证连接池配置
4. 检查网络延迟

### Failover 未检测到
1. 确认使用 Cluster Endpoint
2. 验证 BG Plugin 已启用
3. 检查日志级别设置 (建议 FINE)
4. 确认切换确实发生

### 连接异常
```bash
# 查看详细的异常堆栈
grep -A 20 "Exception" logs/spring-boot.log

# 查看 Wrapper 状态
grep "BG Plugin" logs/jdbc-wrapper.log

# 查看连接池状态
grep "HikariPool" logs/spring-boot.log
```

## 与原始测试的对比

### 相同点
- ✅ 多线程元数据读取
- ✅ Failover 检测逻辑
- ✅ 连接状态监控
- ✅ 详细日志记录
- ✅ 统计报告生成

### 差异点
- 🔄 使用 Spring Boot DataSource (HikariCP)
- 🔄 REST API 控制接口
- 🔄 实时状态查询
- 🔄 可动态启动/停止

## 最佳实践

1. **测试前准备**
   - 确认 Aurora 集群健康
   - 验证连接配置正确
   - 设置适当的日志级别

2. **执行测试**
   - 先运行快速测试验证
   - 使用监控脚本实时查看状态
   - 在测试稳定后执行切换

3. **分析结果**
   - 查看最终报告
   - 分析 Failover 时间点
   - 检查成功率和延迟

4. **日志保存**
   - 保存完整日志用于分析
   - 记录切换时间点
   - 对比切换前后的指标

## 相关文件

- `BlueGreenTestService.java`: 核心测试服务
- `BlueGreenTestController.java`: REST API 控制器
- `test-bluegreen-api.sh`: 测试脚本
- `log4j2-spring.xml`: 日志配置
- `application.yml`: 应用配置

## 参考

- 原始实现: `/src/main/java/MultiThreadBlueGreenTestWithUnifiedLogging.java`
- 日志配置: `UNIFIED_LOGGING_GUIDE.md`
- Aurora 配置: `AURORA_CONFIGURATION_GUIDE.md`
- BG Plugin 说明: `WHY_BG_PLUGIN_NEEDS_CLUSTER_ENDPOINT.md`
