# Spring IoC 快速参考

## 🎯 核心概念

### IoC (Inversion of Control) - 控制反转
```
传统方式：你控制对象的创建
Spring 方式：Spring 控制对象的创建
```

### DI (Dependency Injection) - 依赖注入
```
传统方式：你手动创建依赖
Spring 方式：Spring 自动注入依赖
```

## 📝 常用注解

### 声明 Bean
```java
@Component       // 通用组件
@Service         // 服务层
@Repository      // 数据访问层
@Controller      // Web 控制器
@RestController  // REST API 控制器
@Configuration   // 配置类
```

### 注入依赖
```java
@Autowired       // 自动注入
@Resource        // 按名称注入
@Inject          // JSR-330 标准注入
@Value           // 注入配置值
```

### 生命周期
```java
@PostConstruct   // Bean 初始化后执行
@PreDestroy      // Bean 销毁前执行
```

## 🔄 生命周期扩展点

### 1. BeanFactoryPostProcessor（最早）
```java
@Component
public class MyInitializer implements BeanFactoryPostProcessor {
    @Override
    public void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
        // 在所有 Bean 实例化之前执行
        // 用于：全局初始化、修改 Bean 定义
    }
}
```
**执行时机**：Bean 实例化之前  
**用途**：JUL Bridge 初始化、全局配置

### 2. @PostConstruct
```java
@Component
public class MyService {
    @PostConstruct
    public void init() {
        // 在这个 Bean 的依赖注入完成后执行
        // 用于：Bean 级别的初始化
    }
}
```
**执行时机**：Bean 依赖注入完成后  
**用途**：初始化 Bean 的状态

### 3. @EventListener
```java
@Component
public class MyListener {
    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        // 在应用完全启动后执行
        // 用于：启动后的任务
    }
}
```
**执行时机**：应用完全启动后  
**用途**：启动后的初始化任务

## 📊 执行顺序

```
1. main() 开始
    ↓
2. BeanFactoryPostProcessor.postProcessBeanFactory()  ← JulBridgeInitializer
    ↓
3. Bean 构造函数
    ↓
4. @Autowired 依赖注入
    ↓
5. @PostConstruct
    ↓
6. ApplicationReadyEvent
    ↓
7. 应用就绪
```

## 💡 为什么不需要手动调用？

### 传统方式 ❌
```java
public static void main(String[] args) {
    initJulBridge();  // 手动调用
    SpringApplication.run(...);
}
```

### Spring 方式 ✅
```java
@Component  // Spring 自动管理
public class JulBridgeInitializer implements BeanFactoryPostProcessor {
    @Override
    public void postProcessBeanFactory(...) {
        // Spring 自动在正确的时机调用
    }
}
```

## 🎓 关键理解

### 1. Spring 是容器
- 管理所有 Bean 的生命周期
- 自动创建、初始化、销毁

### 2. @Component 是声明
- 告诉 Spring："我是一个 Bean"
- Spring 自动扫描并注册

### 3. 接口是契约
- `BeanFactoryPostProcessor` 是 Spring 的扩展点
- Spring 保证在特定时机调用

### 4. 你只需要声明
- 声明需要什么（@Component, @Autowired）
- Spring 负责实现

## ✅ 最佳实践

### ✅ 推荐
```java
@Component
public class MyInitializer implements BeanFactoryPostProcessor {
    @Override
    public void postProcessBeanFactory(...) {
        // 初始化代码
    }
}
```

### ❌ 不推荐
```java
public static void main(String[] args) {
    // 手动初始化
    MyInitializer.init();
    SpringApplication.run(...);
}
```

## 📚 相关文档

- `SPRING_LIFECYCLE_EXPLAINED.md` - 详细的生命周期说明
- `MANUAL_VS_SPRING_COMPARISON.md` - 手动 vs Spring 对比

## 🎯 记住

> **"Don't call us, we'll call you"**  
> （不要调用我们，我们会调用你）

这就是 Spring IoC 的核心思想！
