# 持续蓝绿切换测试 - 快速开始

## 一键启动持续测试

```bash
cd spring-boot-mysql-test

# 1. 启动应用（如果还没启动）
./run-aurora.sh

# 2. 启动持续测试（在另一个终端）
./test-bluegreen-continuous.sh start-continuous

# 3. 监控测试状态（在第三个终端）
./test-bluegreen-continuous.sh monitor
```

## 测试会做什么？

- ✅ **无限期运行** - 直到你手动停止
- ✅ **持续读取元数据** - 模拟真实数据库访问
- ✅ **自动检测 Failover** - 监控蓝绿切换事件
- ✅ **实时统计** - 成功率、延迟、failover 次数

## 执行蓝绿切换

测试运行后，在 AWS Console 执行蓝绿切换：

```bash
# 使用 AWS CLI
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <deployment-id> \
  --switchover-timeout 300
```

## 停止测试

```bash
./test-bluegreen-continuous.sh stop
```

## 常用命令

```bash
# 启动持续测试（默认：20线程，500读/秒）
./test-bluegreen-continuous.sh start-continuous

# 启动持续测试（自定义：10线程，200读/秒）
./test-bluegreen-continuous.sh start-continuous 10 200

# 查看状态（一次）
./test-bluegreen-continuous.sh status

# 持续监控（每30秒更新）
./test-bluegreen-continuous.sh monitor

# 持续监控（每10秒更新）
./test-bluegreen-continuous.sh monitor 10

# 停止测试
./test-bluegreen-continuous.sh stop
```

## 查看日志

```bash
# 实时查看所有日志
tail -f logs/*.log

# 只看应用日志
tail -f logs/spring-boot.log

# 只看 JDBC Wrapper 日志
tail -f logs/jdbc-wrapper.log
```

## 成功标准

- ✅ 成功率 > 95%
- ✅ 平均延迟 < 50ms
- ✅ 检测到 Failover 事件
- ✅ 连接端点正确切换

## 完整文档

详细说明请查看：`CONTINUOUS_TEST_GUIDE.md`
