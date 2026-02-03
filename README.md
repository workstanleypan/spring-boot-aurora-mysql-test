# Spring Boot MySQL Test

Spring Boot 应用测试项目，用于测试与 Docker MySQL 容器的连接。

**日志系统**: 使用与主项目相同的 **JUL → SLF4J → Log4j2** 统一日志架构。

## 功能特性

- ✅ Spring Boot 3.2.1
- ✅ Spring Boot Starter Web (REST API)
- ✅ Spring Boot Starter JDBC (数据库访问)
- ✅ **统一日志系统 (JUL → SLF4J → Log4j2)**
- ✅ HikariCP 连接池
- ✅ MySQL 8.0 支持
- ✅ AWS Advanced JDBC Wrapper 支持
- ✅ Spring Boot Actuator (健康检查)
- ✅ RESTful API

## 日志架构

```
AWS JDBC Wrapper (JUL)
    ↓
SLF4JBridgeHandler (JUL → SLF4J)
    ↓
SLF4J API
    ↓
Log4j2 实现
    ↓
输出到文件和控制台
```

**日志文件**:
- `logs/spring-boot-mysql-test.log` - 主日志
- `logs/jdbc-wrapper.log` - AWS JDBC Wrapper 日志
- `logs/spring-boot.log` - Spring Framework 日志

详细说明请查看: [LOGGING_ARCHITECTURE.md](LOGGING_ARCHITECTURE.md) 或 [统一日志系统说明.md](统一日志系统说明.md)

## 项目结构

```
spring-boot-mysql-test/
├── pom.xml                                    # Maven 配置
├── src/
│   └── main/
│       ├── java/com/test/
│       │   ├── SpringBootMySQLTestApplication.java  # 主应用类
│       │   ├── controller/
│       │   │   └── UserController.java              # REST Controller
│       │   ├── service/
│       │   │   └── UserService.java                 # Service 层
│       │   ├── repository/
│       │   │   └── UserRepository.java              # Repository 层
│       │   └── model/
│       │       └── User.java                        # 实体类
│       └── resources/
│           └── application.yml                      # 配置文件
├── run.sh                                     # 启动脚本
├── test-api.sh                                # API 测试脚本
└── README.md                                  # 本文档
```

## 前置条件

1. **MySQL Docker 容器必须运行**
   ```bash
   cd ..
   ./setup-mysql-docker.sh
   ```

2. **Java 17+**
   ```bash
   java -version
   ```

3. **Maven 3.6+**
   ```bash
   mvn -version
   ```

## 快速开始

### 1. 启动应用（标准 MySQL 驱动）

```bash
cd spring-boot-mysql-test
chmod +x run.sh
./run.sh
```

### 2. 启动应用（AWS Wrapper 驱动）

```bash
./run.sh aws-wrapper
```

### 3. 测试 API

在另一个终端窗口：

```bash
chmod +x test-api.sh
./test-api.sh
```

## API 端点

### 健康检查
```bash
curl http://localhost:8080/actuator/health
```

### 数据库连接测试
```bash
curl http://localhost:8080/api/test
```

### 用户管理

#### 获取所有用户
```bash
curl http://localhost:8080/api/users
```

#### 获取单个用户
```bash
curl http://localhost:8080/api/users/1
```

#### 创建用户
```bash
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User"}'
```

#### 更新用户
```bash
curl -X PUT http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"Updated Name"}'
```

#### 删除用户
```bash
curl -X DELETE http://localhost:8080/api/users/1
```

#### 获取用户统计
```bash
curl http://localhost:8080/api/users/stats
```

## 配置说明

### application.yml

#### 标准 MySQL 配置（默认）
```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/testdb
    username: admin
    password: 570192Py
    driver-class-name: com.mysql.cj.jdbc.Driver
```

#### AWS Wrapper 配置（profile: aws-wrapper）
```yaml
spring:
  datasource:
    url: jdbc:aws-wrapper:mysql://localhost:3306/testdb?wrapperPlugins=failover2,efm2&wrapperLoggerLevel=FINE
    driver-class-name: software.amazon.jdbc.Driver
```

### 日志配置

日志级别可以在 `application.yml` 中配置：

```yaml
logging:
  level:
    root: INFO
    com.test: DEBUG
    org.springframework.jdbc: DEBUG
    com.zaxxer.hikari: DEBUG
```

日志文件位置：`logs/spring-boot-mysql-test.log`

## 查看 BG Plugin 日志

如果使用 AWS Wrapper 并想查看 Blue/Green Plugin 的日志：

1. 修改 `application.yml` 中的 AWS Wrapper 配置：
   ```yaml
   url: jdbc:aws-wrapper:mysql://localhost:3306/testdb?wrapperPlugins=bg,failover2,efm2&wrapperLoggerLevel=FINE
   ```

2. 启动应用：
   ```bash
   ./run.sh aws-wrapper
   ```

3. 查看日志：
   ```bash
   tail -f logs/spring-boot-mysql-test.log
   ```

**注意**：BG Plugin 需要 Aurora 集群端点，在本地 MySQL 上会失败，但可以看到插件的加载和执行日志。

## 故障排查

### 应用无法启动

1. 检查 MySQL 容器是否运行：
   ```bash
   docker ps | grep mysql-test
   ```

2. 检查端口 8080 是否被占用：
   ```bash
   lsof -i :8080
   ```

3. 查看应用日志：
   ```bash
   tail -f logs/spring-boot-mysql-test.log
   ```

### 数据库连接失败

1. 测试 MySQL 连接：
   ```bash
   docker exec -it mysql-test mysql -uadmin -p570192Py testdb -e "SELECT 1"
   ```

2. 检查数据库配置：
   ```bash
   cat src/main/resources/application.yml
   ```

### AWS Wrapper 问题

1. 确认依赖已安装：
   ```bash
   mvn dependency:tree | grep aws-advanced-jdbc-wrapper
   ```

2. 查看 wrapper 日志（设置 `wrapperLoggerLevel=FINE`）

## 开发说明

### 添加新的 API 端点

1. 在 `UserController.java` 中添加新方法
2. 在 `UserService.java` 中添加业务逻辑
3. 在 `UserRepository.java` 中添加数据访问方法

### 修改数据库配置

编辑 `src/main/resources/application.yml`

### 重新编译

```bash
mvn clean package
```

## 相关文档

- [MySQL Docker 设置](../MYSQL_DOCKER_SETUP.md)
- [AWS Wrapper 测试](../测试AWS_Wrapper与本地MySQL.md)
- [统一日志系统](../UNIFIED_LOGGING_GUIDE.md)

## 技术栈

- Spring Boot 3.2.1
- Spring Web MVC
- Spring JDBC
- HikariCP
- MySQL 8.0
- AWS Advanced JDBC Wrapper 2.6.8
- Logback (Spring Boot 默认)
- Maven

## License

MIT


## Nacos 服务发现

### 快速开始

1. **启动 Nacos 服务器**:
   ```bash
   ./setup-nacos-docker.sh
   ```

2. **启动应用**:
   ```bash
   ./run.sh
   ```

3. **验证集成**:
   ```bash
   ./test-nacos.sh
   ```

4. **访问 Nacos 控制台**:
   - URL: http://localhost:8848/nacos
   - 用户名: nacos
   - 密码: nacos

### 配置说明

应用已配置 Nacos 服务发现：
- 服务名: spring-boot-mysql-test
- 分组: DEFAULT_GROUP
- 命名空间: public
- 元数据: version=1.0.0, env=dev

### 禁用 Nacos

如果不需要 Nacos，使用 `no-nacos` profile：

```bash
./run.sh no-nacos
```

### 文档

- [NACOS_QUICK_START.md](./NACOS_QUICK_START.md) - 快速开始指南
- [NACOS_CONFIGURATION.md](./NACOS_CONFIGURATION.md) - 详细配置说明
- [NACOS_SETUP_SUMMARY.md](./NACOS_SETUP_SUMMARY.md) - 配置总结

## 依赖版本

- Spring Boot: 2.6.8
- Spring Cloud: 2021.0.1
- Spring Cloud Alibaba: 2021.1
- Druid: 1.1.2
- MySQL Connector: 8.0.33
- AWS JDBC Wrapper: 2.6.8
- Nacos Discovery: 2021.1
- Spring Cloud LoadBalancer: 3.1.1

详见 [DEPENDENCY_VERSIONS.md](./DEPENDENCY_VERSIONS.md)
