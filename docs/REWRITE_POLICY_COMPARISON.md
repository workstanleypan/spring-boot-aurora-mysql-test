# RewritePolicy 方案对比

## 📊 两种方案对比

### 方案 1：自定义 LevelRewritePolicy（旧方案）❌

#### 需要的文件
```
src/main/java/com/test/logging/LevelRewritePolicy.java  ← 自定义 Java 类
src/main/resources/log4j2-spring.xml                     ← 配置文件
```

#### Java 代码
```java
package com.test.logging;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.core.LogEvent;
import org.apache.logging.log4j.core.appender.rewrite.RewritePolicy;
import org.apache.logging.log4j.core.config.plugins.Plugin;
import org.apache.logging.log4j.core.config.plugins.PluginElement;
import org.apache.logging.log4j.core.config.plugins.PluginFactory;
import org.apache.logging.log4j.core.impl.Log4jLogEvent;
import org.apache.logging.log4j.util.ReadOnlyStringMap;

import java.util.HashMap;
import java.util.Map;

@Plugin(name = "LevelRewritePolicy", category = "Core", 
        elementType = "rewritePolicy", printObject = true)
public class LevelRewritePolicy implements RewritePolicy {
    
    private final Map<Level, Level> levelMap;
    
    private LevelRewritePolicy(Map<Level, Level> levelMap) {
        this.levelMap = levelMap;
    }
    
    @PluginFactory
    public static LevelRewritePolicy createPolicy(
            @PluginElement("KeyValuePair") final KeyValuePair[] pairs) {
        Map<Level, Level> map = new HashMap<>();
        if (pairs != null) {
            for (KeyValuePair pair : pairs) {
                Level sourceLevel = Level.getLevel(pair.getKey());
                Level targetLevel = Level.getLevel(pair.getValue());
                if (sourceLevel != null && targetLevel != null) {
                    map.put(sourceLevel, targetLevel);
                }
            }
        }
        return new LevelRewritePolicy(map);
    }
    
    @Override
    public LogEvent rewrite(LogEvent event) {
        Level newLevel = levelMap.get(event.getLevel());
        if (newLevel != null && !newLevel.equals(event.getLevel())) {
            return new Log4jLogEvent.Builder(event).setLevel(newLevel).build();
        }
        return event;
    }
}
```

#### XML 配置
```xml
<Configuration status="WARN" packages="com.test.logging">  ← 必须注册包
    <Appenders>
        <Rewrite name="AmazonJdbcRewrite">
            <LevelRewritePolicy>  ← 使用自定义 Policy
                <KeyValuePair key="TRACE" value="INFO"/>
                <KeyValuePair key="DEBUG" value="INFO"/>
            </LevelRewritePolicy>
            <AppenderRef ref="Console"/>
            <AppenderRef ref="InfoFile"/>
        </Rewrite>
    </Appenders>
</Configuration>
```

#### 缺点
- ❌ 需要编写和维护 Java 代码（~50 行）
- ❌ 需要在 Configuration 中注册 packages
- ❌ 影响**所有** logger 的 TRACE/DEBUG 日志
- ❌ 增加项目复杂度
- ❌ 需要理解 Log4j2 插件机制
- ❌ 升级 Log4j2 时可能需要调整代码

---

### 方案 2：内置 LoggerNameLevelRewritePolicy（新方案）✅

#### 需要的文件
```
src/main/resources/log4j2-spring.xml  ← 仅配置文件
```

#### XML 配置
```xml
<Configuration status="WARN">  ← 无需 packages 属性
    <Appenders>
        <Rewrite name="AmazonJdbcRewrite">
            <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">  ← 内置 Policy
                <KeyValuePair key="TRACE" value="INFO"/>
                <KeyValuePair key="DEBUG" value="INFO"/>
            </LoggerNameLevelRewritePolicy>
            <AppenderRef ref="Console"/>
            <AppenderRef ref="InfoFile"/>
        </Rewrite>
    </Appenders>
    
    <Loggers>
        <Logger name="software.amazon.jdbc" level="all" additivity="false">
            <AppenderRef ref="AmazonJdbcRewrite"/>
        </Logger>
    </Loggers>
</Configuration>
```

#### 优点
- ✅ **零 Java 代码**（纯配置）
- ✅ 无需注册 packages
- ✅ 只影响指定的 logger（`software.amazon.jdbc`）
- ✅ Log4j2 官方支持，稳定可靠
- ✅ 配置简洁明了
- ✅ 易于维护和理解
- ✅ 升级 Log4j2 无需修改代码

---

## 🔍 功能对比

| 特性 | 自定义 Policy | 内置 Policy |
|------|--------------|-------------|
| Java 代码 | ❌ 需要 ~50 行 | ✅ 不需要 |
| 配置复杂度 | ⚠️ 中等 | ✅ 简单 |
| 影响范围 | ❌ 所有 logger | ✅ 指定 logger |
| 维护成本 | ❌ 高 | ✅ 低 |
| Log4j2 版本要求 | 2.0+ | 2.4+ |
| 官方支持 | ❌ 否 | ✅ 是 |
| 灵活性 | ⚠️ 可自定义逻辑 | ✅ 满足常见需求 |

---

## 📈 迁移步骤

### 从自定义 Policy 迁移到内置 Policy

#### 1. 备份自定义类
```bash
mv src/main/java/com/test/logging/LevelRewritePolicy.java \
   src/main/java/com/test/logging/LevelRewritePolicy.java.bak
```

#### 2. 更新 log4j2-spring.xml

**移除 packages 属性：**
```xml
<!-- 旧配置 -->
<Configuration status="WARN" packages="com.test.logging">

<!-- 新配置 -->
<Configuration status="WARN">
```

**更新 Rewrite 配置：**
```xml
<!-- 旧配置 -->
<Rewrite name="AmazonJdbcRewrite">
    <LevelRewritePolicy>
        <KeyValuePair key="TRACE" value="INFO"/>
        <KeyValuePair key="DEBUG" value="INFO"/>
    </LevelRewritePolicy>
    <AppenderRef ref="Console"/>
    <AppenderRef ref="InfoFile"/>
</Rewrite>

<!-- 新配置 -->
<Rewrite name="AmazonJdbcRewrite">
    <LoggerNameLevelRewritePolicy logger="software.amazon.jdbc">
        <KeyValuePair key="TRACE" value="INFO"/>
        <KeyValuePair key="DEBUG" value="INFO"/>
    </LoggerNameLevelRewritePolicy>
    <AppenderRef ref="Console"/>
    <AppenderRef ref="InfoFile"/>
</Rewrite>
```

#### 3. 重新构建
```bash
mvn clean package -DskipTests
```

#### 4. 验证
```bash
./test-builtin-rewrite.sh
```

---

## 🎯 使用场景

### 适合使用内置 LoggerNameLevelRewritePolicy
- ✅ 只需要重写特定 logger 的日志级别
- ✅ 简单的级别映射（TRACE→INFO, DEBUG→INFO 等）
- ✅ 希望减少代码维护
- ✅ 标准的日志重写需求

### 可能需要自定义 Policy
- ⚠️ 需要复杂的日志转换逻辑
- ⚠️ 需要修改日志消息内容（不仅仅是级别）
- ⚠️ 需要基于日志内容动态决定级别
- ⚠️ 需要添加额外的上下文信息

---

## 📚 技术细节

### LoggerNameLevelRewritePolicy 源码位置
```
org.apache.logging.log4j.core.appender.rewrite.LoggerNameLevelRewritePolicy
```

### 关键方法
```java
@PluginFactory
public static LoggerNameLevelRewritePolicy createPolicy(
    @PluginAttribute("logger") String loggerNamePrefix,
    @PluginElement("KeyValuePair") KeyValuePair[] levelPairs)

public LogEvent rewrite(LogEvent event)
```

### 工作原理
1. 检查 LogEvent 的 logger 名称是否以 `loggerNamePrefix` 开头
2. 如果匹配，查找 levelPairs 中是否有对应的级别映射
3. 如果找到映射，创建新的 LogEvent 并替换级别
4. 返回新的或原始的 LogEvent

---

## ✅ 验证清单

迁移完成后，确认以下项目：

- [ ] `LevelRewritePolicy.java` 已删除或重命名为 `.bak`
- [ ] `log4j2-spring.xml` 中移除了 `packages` 属性
- [ ] 使用 `<LoggerNameLevelRewritePolicy>` 替代 `<LevelRewritePolicy>`
- [ ] 添加了 `logger` 属性指定目标 logger
- [ ] `mvn clean package` 构建成功
- [ ] JAR 中不包含 `LevelRewritePolicy.class`
- [ ] JAR 中包含更新后的 `log4j2-spring.xml`
- [ ] Log4j2 版本 >= 2.4

---

## 🎓 总结

**推荐使用内置的 `LoggerNameLevelRewritePolicy`**，因为：

1. **简单**：零 Java 代码，纯配置
2. **可靠**：Log4j2 官方支持
3. **精确**：只影响指定的 logger
4. **易维护**：配置清晰，易于理解

除非有特殊的自定义需求，否则内置 Policy 完全能满足日志级别重写的需求。

---

**迁移完成时间**：2026-01-16 04:07:18 UTC  
**Log4j2 版本**：2.17.2  
**构建状态**：✅ SUCCESS
