# Nacos 配置说明

## 概述

本项目已集成 Nacos 服务发现功能，支持服务注册、发现和健康检查。

## 快速开始

### 1. 启动 Nacos 服务器

```bash
cd spring-boot-mysql-test
./setup-nacos-docker.sh
```

这将：
- 安装 Docker（如果未安装）
- 拉取 Nacos Docker 镜像（v2.1.0）
- 启动 Nacos 单机模式容器
- 等待 Nacos 就绪

### 2. 访问 Nacos 控制台

```
URL: http://localhost:8848/nacos
用户名: nacos
密码: nacos
```

### 3. 启动应用

```bash
./run.sh
```

应用将自动注册到 Nacos。

### 4. 验证集成

```bash
./test-nacos.sh
```

## Nacos 配置详解

### application.yml 配置

```yaml
spring:
  application:
    name: spring-boot-mysql-test
  
  cloud:
    nacos:
      discovery:
        enabled: true                    # 启用服务发现
        server-addr: localhost:8848      # Nacos 服务器地址
        namespace: public                # 命名空间
        group: DEFAULT_GROUP             # 分组
        service: ${spring.application.name}  # 服务名
        ip: 127.0.0.1                    # 服务 IP
        port: ${server.port}             # 服务端口
        heart-beat-interval: 5000        # 心跳间隔（毫秒）
        heart-beat-timeout: 15000        # 心跳超时（毫秒）
        metadata:
          version: 1.0.0                 # 版本信息
          env: dev                       # 环境标识
    
    service-registry:
      auto-registration:
        enabled: true                    # 启用自动注册
```

### 配置项说明

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| enabled | false | 是否启用 Nacos 服务发现 |
| server-addr | - | Nacos 服务器地址（必填） |
| namespace | public | 命名空间 ID |
| group | DEFAULT_GROUP | 服务分组 |
| service | ${spring.application.name} | 服务名称 |
| ip | 自动获取 | 服务实例 IP |
| port | ${server.port} | 服务实例端口 |
| heart-beat-interval | 5000 | 心跳间隔（毫秒） |
| heart-beat-timeout | 15000 | 心跳超时（毫秒） |
| metadata | {} | 自定义元数据 |

## 使用场景

### 场景 1: 单机开发（默认）

启用 Nacos，使用本地 Nacos 服务器：

```bash
./run.sh
```

### 场景 2: 禁用 Nacos

如果不需要 Nacos，使用 `no-nacos` profile：

```bash
./run.sh no-nacos
```

或修改 `application.yml`:

```yaml
spring:
  cloud:
    nacos:
      discovery:
        enabled: false
```

### 场景 3: 生产环境

修改 `application.yml` 或使用环境变量：

```yaml
spring:
  cloud:
    nacos:
      discovery:
        server-addr: nacos-cluster.example.com:8848
        namespace: production
        group: PROD_GROUP
        metadata:
          version: 1.0.0
          env: prod
```

或使用环境变量：

```bash
export NACOS_SERVER_ADDR=nacos-cluster.example.com:8848
export NACOS_NAMESPACE=production
./run.sh
```

## Nacos 服务器管理

### Docker 命令

```bash
# 查看容器状态
docker ps | grep nacos

# 查看日志
docker logs -f nacos-standalone

# 停止 Nacos
docker stop nacos-standalone

# 启动 Nacos
docker start nacos-standalone

# 重启 Nacos
docker restart nacos-standalone

# 删除容器
docker rm -f nacos-standalone
```

### 端口说明

| 端口 | 说明 |
|------|------|
| 8848 | HTTP API 端口 |
| 9848 | gRPC 端口（客户端请求） |
| 9849 | gRPC 端口（服务端请求） |

## API 使用

### 1. 查询服务列表

```bash
curl "http://localhost:8848/nacos/v1/ns/service/list?pageNo=1&pageSize=10"
```

### 2. 查询服务实例

```bash
curl "http://localhost:8848/nacos/v1/ns/instance/list?serviceName=spring-boot-mysql-test"
```

### 3. 注册服务实例

```bash
curl -X POST "http://localhost:8848/nacos/v1/ns/instance" \
  -d "serviceName=test-service&ip=127.0.0.1&port=8080"
```

### 4. 注销服务实例

```bash
curl -X DELETE "http://localhost:8848/nacos/v1/ns/instance" \
  -d "serviceName=test-service&ip=127.0.0.1&port=8080"
```

### 5. 健康检查

```bash
curl "http://localhost:8848/nacos/v1/console/health/readiness"
```

## 服务发现示例

### 在代码中使用服务发现

```java
import org.springframework.cloud.client.discovery.DiscoveryClient;
import org.springframework.beans.factory.annotation.Autowired;

@RestController
public class ServiceController {
    
    @Autowired
    private DiscoveryClient discoveryClient;
    
    @GetMapping("/services")
    public List<String> getServices() {
        return discoveryClient.getServices();
    }
    
    @GetMapping("/instances/{serviceName}")
    public List<ServiceInstance> getInstances(@PathVariable String serviceName) {
        return discoveryClient.getInstances(serviceName);
    }
}
```

### 使用 LoadBalancer 调用服务

```java
import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.web.client.RestTemplate;

@Configuration
public class RestTemplateConfig {
    
    @Bean
    @LoadBalanced
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}

@Service
public class RemoteService {
    
    @Autowired
    private RestTemplate restTemplate;
    
    public String callRemoteService() {
        // 使用服务名调用
        return restTemplate.getForObject(
            "http://spring-boot-mysql-test/api/test", 
            String.class
        );
    }
}
```

## 命名空间和分组

### 命名空间（Namespace）

用于环境隔离：

- `public`（默认）：公共命名空间
- `dev`：开发环境
- `test`：测试环境
- `prod`：生产环境

配置：

```yaml
spring:
  cloud:
    nacos:
      discovery:
        namespace: dev  # 命名空间 ID
```

### 分组（Group）

用于业务隔离：

- `DEFAULT_GROUP`（默认）
- `ORDER_GROUP`：订单服务组
- `USER_GROUP`：用户服务组

配置：

```yaml
spring:
  cloud:
    nacos:
      discovery:
        group: ORDER_GROUP
```

## 元数据（Metadata）

自定义服务实例元数据：

```yaml
spring:
  cloud:
    nacos:
      discovery:
        metadata:
          version: 1.0.0
          env: dev
          region: us-east-1
          zone: zone-a
          weight: 100
```

在代码中获取元数据：

```java
List<ServiceInstance> instances = discoveryClient.getInstances("spring-boot-mysql-test");
for (ServiceInstance instance : instances) {
    Map<String, String> metadata = instance.getMetadata();
    String version = metadata.get("version");
    String env = metadata.get("env");
}
```

## 健康检查

Nacos 会定期检查服务实例的健康状态。

### 配置健康检查

```yaml
spring:
  cloud:
    nacos:
      discovery:
        heart-beat-interval: 5000   # 心跳间隔（毫秒）
        heart-beat-timeout: 15000   # 心跳超时（毫秒）
```

### 自定义健康检查

```java
@Component
public class CustomHealthIndicator implements HealthIndicator {
    
    @Override
    public Health health() {
        // 自定义健康检查逻辑
        boolean healthy = checkDatabaseConnection();
        
        if (healthy) {
            return Health.up()
                .withDetail("database", "connected")
                .build();
        } else {
            return Health.down()
                .withDetail("database", "disconnected")
                .build();
        }
    }
}
```

## 故障排查

### 问题 1: 服务注册失败

**症状**: 应用启动失败，提示无法连接 Nacos

**解决方案**:

1. 检查 Nacos 是否运行：
   ```bash
   docker ps | grep nacos
   ```

2. 检查 Nacos 健康状态：
   ```bash
   curl http://localhost:8848/nacos/v1/console/health/readiness
   ```

3. 查看 Nacos 日志：
   ```bash
   docker logs nacos-standalone
   ```

4. 使用 `no-nacos` profile 禁用 Nacos：
   ```bash
   ./run.sh no-nacos
   ```

### 问题 2: 服务实例不健康

**症状**: 服务注册成功但显示不健康

**解决方案**:

1. 检查应用健康端点：
   ```bash
   curl http://localhost:8080/actuator/health
   ```

2. 调整心跳配置：
   ```yaml
   spring:
     cloud:
       nacos:
         discovery:
           heart-beat-interval: 10000
           heart-beat-timeout: 30000
   ```

### 问题 3: 无法发现服务

**症状**: 调用其他服务时找不到实例

**解决方案**:

1. 检查命名空间和分组是否一致
2. 检查服务名是否正确
3. 使用 Nacos 控制台查看服务列表

## 性能优化

### 1. 缓存配置

```yaml
spring:
  cloud:
    nacos:
      discovery:
        cache-millis: 10000  # 缓存时间（毫秒）
```

### 2. 心跳优化

```yaml
spring:
  cloud:
    nacos:
      discovery:
        heart-beat-interval: 10000  # 增加心跳间隔
```

### 3. 批量注册

如果有多个实例，可以使用批量注册 API。

## 安全配置

### 1. 启用认证

Nacos 2.x 默认启用认证。

### 2. 配置用户名密码

```yaml
spring:
  cloud:
    nacos:
      discovery:
        username: nacos
        password: nacos
```

### 3. 使用 AccessKey

```yaml
spring:
  cloud:
    nacos:
      discovery:
        access-key: your-access-key
        secret-key: your-secret-key
```

## 集群部署

### Nacos 集群配置

1. 准备 3 个 Nacos 节点
2. 配置集群地址列表
3. 使用 MySQL 作为数据源

```yaml
spring:
  cloud:
    nacos:
      discovery:
        server-addr: nacos1:8848,nacos2:8848,nacos3:8848
```

## 监控和日志

### 1. 查看 Nacos 日志

```bash
docker logs -f nacos-standalone
```

### 2. 查看应用日志

```bash
tail -f logs/spring-boot-mysql-test.log | grep nacos
```

### 3. Nacos 监控指标

访问 Nacos 控制台的"监控"页面查看：
- 服务数量
- 实例数量
- 健康实例数量
- 请求 QPS

## 参考资源

- [Nacos 官方文档](https://nacos.io/zh-cn/docs/what-is-nacos.html)
- [Spring Cloud Alibaba Nacos Discovery](https://github.com/alibaba/spring-cloud-alibaba/wiki/Nacos-discovery)
- [Nacos Docker 部署](https://nacos.io/zh-cn/docs/quick-start-docker.html)

## 总结

✅ **已完成配置**:
- Nacos Docker 部署脚本
- Spring Boot Nacos 集成
- 服务注册和发现
- 健康检查
- 元数据配置

✅ **可用功能**:
- 服务注册
- 服务发现
- 健康检查
- 负载均衡
- 元数据管理

✅ **测试工具**:
- `setup-nacos-docker.sh` - 部署 Nacos
- `test-nacos.sh` - 测试集成
- Nacos 控制台 - 可视化管理
