# Docker Manager 使用指南

## 概述

`docker-manager.sh` 是一个统一的 Docker 容器管理脚本，用于方便地管理 MySQL 和 Nacos 容器。

## 快速开始

### 启动所有容器

```bash
./docker-manager.sh start
```

### 查看状态

```bash
./docker-manager.sh status
```

### 停止所有容器

```bash
./docker-manager.sh stop
```

## 命令说明

### 基本语法

```bash
./docker-manager.sh <command> [service]
```

### 可用命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `start` | 启动容器 | `./docker-manager.sh start` |
| `stop` | 停止容器 | `./docker-manager.sh stop` |
| `restart` | 重启容器 | `./docker-manager.sh restart` |
| `status` | 查看状态 | `./docker-manager.sh status` |
| `logs` | 查看日志 | `./docker-manager.sh logs` |
| `remove` | 删除容器 | `./docker-manager.sh remove` |
| `help` | 显示帮助 | `./docker-manager.sh help` |

### 可用服务

| 服务 | 说明 |
|------|------|
| `mysql` | MySQL 数据库容器 |
| `nacos` | Nacos 服务发现容器 |
| `all` | 所有容器（默认） |

## 使用示例

### 1. 启动容器

```bash
# 启动所有容器
./docker-manager.sh start

# 只启动 MySQL
./docker-manager.sh start mysql

# 只启动 Nacos
./docker-manager.sh start nacos
```

### 2. 停止容器

```bash
# 停止所有容器
./docker-manager.sh stop

# 只停止 MySQL
./docker-manager.sh stop mysql

# 只停止 Nacos
./docker-manager.sh stop nacos
```

### 3. 重启容器

```bash
# 重启所有容器
./docker-manager.sh restart

# 只重启 MySQL
./docker-manager.sh restart mysql

# 只重启 Nacos
./docker-manager.sh restart nacos
```

### 4. 查看状态

```bash
# 查看所有容器状态
./docker-manager.sh status
```

输出示例：
```
╔════════════════════════════════════════════════════════════════╗
║   Docker Container Manager - MySQL & Nacos                    ║
╚════════════════════════════════════════════════════════════════╝

📊 Container Status:

   MySQL (mysql-test): ✅ Running
      Port: 3306
      Database: testdb
      User: admin

   Nacos (nacos-standalone): ✅ Running
      Port: 8848
      Console: http://localhost:8848/nacos
      Username: nacos
      Password: nacos
```

### 5. 查看日志

```bash
# 查看所有容器日志
./docker-manager.sh logs

# 只查看 MySQL 日志
./docker-manager.sh logs mysql

# 只查看 Nacos 日志
./docker-manager.sh logs nacos
```

### 6. 删除容器

```bash
# 删除所有容器（会提示确认）
./docker-manager.sh remove

# 只删除 MySQL 容器
./docker-manager.sh remove mysql

# 只删除 Nacos 容器
./docker-manager.sh remove nacos
```

⚠️ **警告**: 删除容器会丢失所有数据！

## 容器配置

### MySQL 配置

| 配置项 | 值 |
|--------|-----|
| 容器名称 | `mysql-test` |
| 镜像 | `mysql:8.0` |
| 端口 | `3306` |
| Root 密码 | `570192Py` |
| 数据库 | `testdb` |
| 用户名 | `admin` |
| 密码 | `570192Py` |

### Nacos 配置

| 配置项 | 值 |
|--------|-----|
| 容器名称 | `nacos-standalone` |
| 镜像 | `nacos/nacos-server:v2.1.0` |
| 端口 | `8848`, `9848`, `9849` |
| 模式 | `standalone` |
| 用户名 | `nacos` |
| 密码 | `nacos` |

## 连接信息

### MySQL 连接

```bash
# 使用 MySQL 客户端连接
mysql -h localhost -P 3306 -u admin -p
# 密码: 570192Py

# 使用 Docker exec 连接
docker exec -it mysql-test mysql -u admin -p testdb
```

### Nacos 控制台

```
URL: http://localhost:8848/nacos
用户名: nacos
密码: nacos
```

## 常见操作

### 每日开发流程

```bash
# 1. 启动所有容器
./docker-manager.sh start

# 2. 查看状态确认
./docker-manager.sh status

# 3. 启动应用
./run.sh

# 4. 开发完成后停止容器
./docker-manager.sh stop
```

### 问题排查

```bash
# 1. 查看容器状态
./docker-manager.sh status

# 2. 查看日志
./docker-manager.sh logs mysql
./docker-manager.sh logs nacos

# 3. 重启容器
./docker-manager.sh restart mysql
```

### 清理和重建

```bash
# 1. 停止容器
./docker-manager.sh stop

# 2. 删除容器
./docker-manager.sh remove

# 3. 重新启动（会创建新容器）
./docker-manager.sh start
```

## 自动化脚本

### 创建别名

在 `~/.bashrc` 或 `~/.zshrc` 中添加：

```bash
alias dm='cd /path/to/spring-boot-mysql-test && ./docker-manager.sh'
```

然后可以这样使用：

```bash
dm start
dm status
dm stop
```

### 开机自动启动

创建 systemd 服务（可选）：

```bash
# 创建服务文件
sudo nano /etc/systemd/system/dev-containers.service
```

内容：
```ini
[Unit]
Description=Development Containers (MySQL & Nacos)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/path/to/spring-boot-mysql-test/docker-manager.sh start
ExecStop=/path/to/spring-boot-mysql-test/docker-manager.sh stop

[Install]
WantedBy=multi-user.target
```

启用服务：
```bash
sudo systemctl enable dev-containers
sudo systemctl start dev-containers
```

## 故障排查

### 容器无法启动

```bash
# 1. 检查 Docker 是否运行
sudo systemctl status docker

# 2. 检查端口是否被占用
sudo netstat -tlnp | grep 3306
sudo netstat -tlnp | grep 8848

# 3. 查看容器日志
./docker-manager.sh logs mysql
./docker-manager.sh logs nacos

# 4. 删除并重建
./docker-manager.sh remove
./docker-manager.sh start
```

### MySQL 连接失败

```bash
# 1. 检查容器状态
./docker-manager.sh status

# 2. 检查 MySQL 日志
./docker-manager.sh logs mysql

# 3. 测试连接
mysql -h localhost -P 3306 -u admin -p

# 4. 重启 MySQL
./docker-manager.sh restart mysql
```

### Nacos 无法访问

```bash
# 1. 检查容器状态
./docker-manager.sh status

# 2. 检查 Nacos 日志
./docker-manager.sh logs nacos

# 3. 测试访问
curl http://localhost:8848/nacos

# 4. 重启 Nacos
./docker-manager.sh restart nacos
```

## 高级用法

### 修改配置

编辑 `docker-manager.sh` 文件，修改以下变量：

```bash
# MySQL 配置
MYSQL_CONTAINER_NAME="mysql-test"
MYSQL_IMAGE="mysql:8.0"
MYSQL_PORT="3306"
MYSQL_ROOT_PASSWORD="570192Py"
MYSQL_DATABASE="testdb"
MYSQL_USER="admin"
MYSQL_PASSWORD="570192Py"

# Nacos 配置
NACOS_CONTAINER_NAME="nacos-standalone"
NACOS_IMAGE="nacos/nacos-server:v2.1.0"
NACOS_PORT="8848"
```

### 数据持久化

如果需要数据持久化，可以添加 volume 挂载：

```bash
# MySQL 数据持久化
docker run -d \
    --name mysql-test \
    -v mysql-data:/var/lib/mysql \
    ...

# Nacos 数据持久化
docker run -d \
    --name nacos-standalone \
    -v nacos-data:/home/nacos/data \
    ...
```

## 与其他脚本集成

### 与 run.sh 集成

```bash
# 在 run.sh 开始时检查容器
if ! docker ps | grep -q mysql-test; then
    echo "Starting MySQL container..."
    ./docker-manager.sh start mysql
fi
```

### 与 CI/CD 集成

```bash
# 在 CI/CD 脚本中
./docker-manager.sh start
./run.sh
./test-api.sh
./docker-manager.sh stop
```

## 相关文档

- [README.md](README.md) - 项目主文档
- [快速开始.md](快速开始.md) - 快速开始指南
- [NACOS_QUICK_START.md](NACOS_QUICK_START.md) - Nacos 快速开始

## 总结

`docker-manager.sh` 提供了一个简单统一的方式来管理开发环境中的 Docker 容器：

- ✅ 一键启动/停止所有容器
- ✅ 独立管理 MySQL 和 Nacos
- ✅ 查看状态和日志
- ✅ 安全删除容器
- ✅ 彩色输出，易于阅读

使用这个脚本可以大大简化日常开发流程！
