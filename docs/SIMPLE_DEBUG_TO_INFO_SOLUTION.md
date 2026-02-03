# 简单方案：将 DEBUG 日志写入 InfoFile

## 最简单的解决方案

直接修改 `AmazonJdbcInfoFile` 的配置，移除 ThresholdFilter，让它接受所有级别的日志。

## 实现步骤

### 1. 修改 log4j2-spring.xml

找到 `AmazonJdbcInfoFile` 配置：

```xml
<RollingRandomAccessFile name="AmazonJdbcInfoFile"
                         fileName="${LOG_DIR}/jdbc-wrapper-info.log"
                         filePattern="${LOG_DIR}/archive/history_jdbc_wrapper_info.%d{yyyy-MM-dd}.%i.zip">
    <!-- 移除这行 ThresholdFilter -->
    <!-- <ThresholdFilter level="INFO" onMatch="ACCEPT" onMismatch="DENY" /> -->
    
    <PatternLayout pattern="${FILE_LOG_PATTERN}" charset="${CHARSET}"/>
    <Policies>
        <TimeBasedTriggeringPolicy/>
        <SizeBasedTriggeringPolicy size="500 MB"/>
    </Policies>
    <DefaultRolloverStrategy max="7">
        <Delete basePath="${LOG_DIR}/archive" maxDepth="2">
            <IfFileName glob="history_jdbc_wrapper_info.*"/>
            <IfLastModified age="1d"/>
        </Delete>
    </DefaultRolloverStrategy>
</RollingRandomAccessFile>
```

### 2. 重启应用

```bash
cd spring-boot-mysql-test
./restart-app.sh
```

### 3. 验证

```bash
# 查看 jdbc-wrapper-info.log，应该包含 DEBUG 日志
grep " DEBUG " logs/jdbc-wrapper-info.log

# 对比原始文件
grep " DEBUG " logs/jdbc-wrapper.log
```

## 结果

- `jdbc-wrapper.log`: 所有日志（TRACE/DEBUG/INFO/WARN/ERROR）- 原始级别
- `jdbc-wrapper-info.log`: 所有日志（包括 DEBUG）- 原始级别
- 如果需要显示为 INFO，可以修改 Pattern

## 如果需要显示为 INFO 级别

修改 `AmazonJdbcInfoFile` 的 Pattern：

```xml
<RollingRandomAccessFile name="AmazonJdbcInfoFile"
                         fileName="${LOG_DIR}/jdbc-wrapper-info.log"
                         filePattern="${LOG_DIR}/archive/history_jdbc_wrapper_info.%d{yyyy-MM-dd}.%i.zip">
    <!-- 使用固定 INFO 的 Pattern -->
    <PatternLayout charset="${CHARSET}">
        <Pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} INFO  [%X{X-RequestID}] %pid --- [%t] %-40.40c{1.} [%traceId]: %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}</Pattern>
    </PatternLayout>
    <Policies>
        <TimeBasedTriggeringPolicy/>
        <SizeBasedTriggeringPolicy size="500 MB"/>
    </Policies>
    <DefaultRolloverStrategy max="7">
        <Delete basePath="${LOG_DIR}/archive" maxDepth="2">
            <IfFileName glob="history_jdbc_wrapper_info.*"/>
            <IfLastModified age="1d"/>
        </Delete>
    </DefaultRolloverStrategy>
</RollingRandomAccessFile>
```

这样：
- DEBUG 日志会被写入
- 但显示为 INFO 级别

## 快速执行

```bash
cd spring-boot-mysql-test

# 备份当前配置
cp src/main/resources/log4j2-spring.xml src/main/resources/log4j2-spring.xml.backup

# 编辑配置文件，找到 AmazonJdbcInfoFile，移除或注释掉 ThresholdFilter
# 或者修改 Pattern 为固定 INFO

# 重启应用
./restart-app.sh

# 验证
tail -f logs/jdbc-wrapper-info.log
```
