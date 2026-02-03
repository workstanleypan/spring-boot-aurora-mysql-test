# Nacos 快速开始

## 5 分钟快速上手

### 1. 启动 Nacos 服务器

```bash
cd spring-boot-mysql-test
./setup-nacos-docker.sh
```

等待 30-60 秒，直到看到：

```
✅ Nacos is ready!
🌐 Nacos Console: http://localhost:8848/nacos
```

### 2. 启动应用

```bash
./run.sh
```

看到以下日志表示成功：

```
nacos registry, DEFAULT_GROUP spring-boot-mysql-test 127.0.0.1:8080 register finished
```

### 3. 验证集成

```bash
./test-nacos.sh
```

应该看到：

```
✅ Nacos integration is working correctly
```

### 4. 访问 Nacos 控制台

打开浏览器访问：http://localhost:8848/nacos

```
用户名: nacos
密码: nacos
```

在"服务管理" -> "服务列表"中可以看到 `spring-boot-mysql-test` 服务。

## 常用命令

### Nacos 管理

```bash
# 查看 Nacos 状态
docker ps | grep nacos

# 查看 Nacos 日志
docker logs -f nacos-standalone

# 停止 Nacos
docker stop nacos-standalone

# 启动 Nacos
docker start nacos-standalone

# 重启 Nacos
docker restart nacos-standalone
```

### 应用管理

```bash
# 启动应用（启用 Nacos）
./run.sh

# 启动应用（禁用 Nacos）
./run.sh no-nacos

# 测试 API
curl http://localhost:8080/api/test

# 测试 Nacos 集成
./test-nacos.sh
```

### API 查询

```bash
# 查询服务列表
curl "http://localhost:8848/nacos/v1/ns/service/list?pageNo=1&pageSize=10"

# 查询服务实例
curl "http://localhost:8848/nacos/v1/ns/instance/list?serviceName=spring-boot-mysql-test"

# 健康检查
curl "http://localhost:8848/nacos/v1/console/health/readiness"
```

## 配置说明

### 默认配置（application.yml）

```yaml
spring:
  cloud:
    nacos:
      discovery:
        enabled: true                    # 启用 Nacos
        server-addr: localhost:8848      # Nacos 地址
        namespace: public                # 命名空间
        group: DEFAULT_GROUP             # 分组
        metadata:
          version: 1.0.0                 # 版本
          env: dev                       # 环境
```

### 禁用 Nacos

方法 1: 使用 profile

```bash
./run.sh no-nacos
```

方法 2: 修改配置

```yaml
spring:
  cloud:
    nacos:
      discovery:
        enabled: false
```

## 服务发现示例

### 查询所有服务

```bash
curl "http://localhost:8848/nacos/v1/ns/service/list?pageNo=1&pageSize=10"
```

### 查询服务实例

```bash
curl "http://localhost:8848/nacos/v1/ns/instance/list?serviceName=spring-boot-mysql-test"
```

返回示例：

```json
{
    "hosts": [
        {
            "ip": "127.0.0.1",
            "port": 8080,
            "healthy": true,
            "metadata": {
                "version": "1.0.0",
                "env": "dev"
            }
        }
    ]
}
```

## 故障排查

### 问题 1: Nacos 启动失败

```bash
# 查看日志
docker logs nacos-standalone

# 检查端口占用
netstat -tlnp | grep 8848

# 重新启动
docker restart nacos-standalone
```

### 问题 2: 服务注册失败

```bash
# 检查 Nacos 是否运行
curl http://localhost:8848/nacos/v1/console/health/readiness

# 查看应用日志
tail -f logs/spring-boot-mysql-test.log | grep nacos

# 使用 no-nacos profile
./run.sh no-nacos
```

### 问题 3: 服务不健康

```bash
# 检查应用健康状态
curl http://localhost:8080/actuator/health

# 查看 Nacos 控制台
# 访问 http://localhost:8848/nacos
# 查看服务详情
```

## 下一步

### 1. 多实例部署

启动多个应用实例：

```bash
# 实例 1（端口 8080）
./run.sh

# 实例 2（端口 8081）
SERVER_PORT=8081 ./run.sh
```

在 Nacos 控制台可以看到 2 个实例。

### 2. 负载均衡

使用 Spring Cloud LoadBalancer 调用服务：

```java
@Autowired
private RestTemplate restTemplate;

// 使用服务名调用
String result = restTemplate.getForObject(
    "http://spring-boot-mysql-test/api/test", 
    String.class
);
```

### 3. 配置管理

Nacos 还支持配置管理，可以集中管理应用配置。

### 4. 生产环境

- 部署 Nacos 集群（3 个节点）
- 使用 MySQL 作为数据源
- 配置命名空间隔离环境
- 启用认证和授权

## 参考文档

- [NACOS_CONFIGURATION.md](./NACOS_CONFIGURATION.md) - 详细配置说明
- [Nacos 官方文档](https://nacos.io/zh-cn/docs/what-is-nacos.html)
- [Spring Cloud Alibaba](https://github.com/alibaba/spring-cloud-alibaba/wiki)

## 总结

✅ **已完成**:
- Nacos Docker 部署
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

🎉 **Nacos 配置完成！**
