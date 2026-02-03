#!/bin/bash

# Docker 容器管理脚本
# 用于管理 MySQL 和 Nacos Docker 容器

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 容器配置
MYSQL_CONTAINER_NAME="mysql-test"
MYSQL_IMAGE="mysql:8.0"
MYSQL_PORT="3306"
MYSQL_ROOT_PASSWORD="570192Py"
MYSQL_DATABASE="testdb"
MYSQL_USER="admin"
MYSQL_PASSWORD="570192Py"

NACOS_CONTAINER_NAME="nacos-standalone"
NACOS_IMAGE="nacos/nacos-server:v2.1.0"
NACOS_PORT="8848"

# 函数：打印标题
print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Docker Container Manager - MySQL & Nacos                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

# 函数：检查容器状态
check_container_status() {
    local container_name=$1
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo -e "${GREEN}✅ Running${NC}"
            return 0
        else
            echo -e "${YELLOW}⏸️  Stopped${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Not exists${NC}"
        return 2
    fi
}

# 函数：显示状态
show_status() {
    print_header
    echo "📊 Container Status:"
    echo ""
    
    echo -n "   MySQL (${MYSQL_CONTAINER_NAME}): "
    check_container_status "$MYSQL_CONTAINER_NAME"
    mysql_status=$?
    
    if [ $mysql_status -eq 0 ]; then
        echo "      Port: ${MYSQL_PORT}"
        echo "      Database: ${MYSQL_DATABASE}"
        echo "      User: ${MYSQL_USER}"
    fi
    
    echo ""
    echo -n "   Nacos (${NACOS_CONTAINER_NAME}): "
    check_container_status "$NACOS_CONTAINER_NAME"
    nacos_status=$?
    
    if [ $nacos_status -eq 0 ]; then
        echo "      Port: ${NACOS_PORT}"
        echo "      Console: http://localhost:${NACOS_PORT}/nacos"
        echo "      Username: nacos"
        echo "      Password: nacos"
    fi
    
    echo ""
}

# 函数：启动 MySQL
start_mysql() {
    echo "🚀 Starting MySQL container..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER_NAME}$"; then
        echo -e "${YELLOW}⚠️  MySQL container is already running${NC}"
        return 0
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER_NAME}$"; then
        echo "   Starting existing container..."
        docker start "$MYSQL_CONTAINER_NAME"
    else
        echo "   Creating new container..."
        docker run -d \
            --name "$MYSQL_CONTAINER_NAME" \
            -p "${MYSQL_PORT}:3306" \
            -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
            -e MYSQL_DATABASE="$MYSQL_DATABASE" \
            -e MYSQL_USER="$MYSQL_USER" \
            -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
            "$MYSQL_IMAGE"
        
        echo "   Waiting for MySQL to be ready..."
        sleep 10
        
        # 初始化数据库
        if [ -f "../setup_database.sql" ]; then
            echo "   Initializing database..."
            docker exec -i "$MYSQL_CONTAINER_NAME" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < ../setup_database.sql
            echo -e "${GREEN}   ✅ Database initialized${NC}"
        fi
    fi
    
    echo -e "${GREEN}✅ MySQL container started${NC}"
    echo "   Connection: mysql -h localhost -P ${MYSQL_PORT} -u ${MYSQL_USER} -p"
    echo ""
}

# 函数：启动 Nacos
start_nacos() {
    echo "🚀 Starting Nacos container..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${NACOS_CONTAINER_NAME}$"; then
        echo -e "${YELLOW}⚠️  Nacos container is already running${NC}"
        return 0
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${NACOS_CONTAINER_NAME}$"; then
        echo "   Starting existing container..."
        docker start "$NACOS_CONTAINER_NAME"
    else
        echo "   Creating new container..."
        docker run -d \
            --name "$NACOS_CONTAINER_NAME" \
            -e MODE=standalone \
            -p "${NACOS_PORT}:8848" \
            -p "9848:9848" \
            -p "9849:9849" \
            "$NACOS_IMAGE"
        
        echo "   Waiting for Nacos to be ready..."
        sleep 15
    fi
    
    echo -e "${GREEN}✅ Nacos container started${NC}"
    echo "   Console: http://localhost:${NACOS_PORT}/nacos"
    echo "   Username: nacos"
    echo "   Password: nacos"
    echo ""
}

# 函数：停止 MySQL
stop_mysql() {
    echo "🛑 Stopping MySQL container..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER_NAME}$"; then
        docker stop "$MYSQL_CONTAINER_NAME"
        echo -e "${GREEN}✅ MySQL container stopped${NC}"
    else
        echo -e "${YELLOW}⚠️  MySQL container is not running${NC}"
    fi
    echo ""
}

# 函数：停止 Nacos
stop_nacos() {
    echo "🛑 Stopping Nacos container..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${NACOS_CONTAINER_NAME}$"; then
        docker stop "$NACOS_CONTAINER_NAME"
        echo -e "${GREEN}✅ Nacos container stopped${NC}"
    else
        echo -e "${YELLOW}⚠️  Nacos container is not running${NC}"
    fi
    echo ""
}

# 函数：删除 MySQL
remove_mysql() {
    echo "🗑️  Removing MySQL container..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER_NAME}$"; then
        docker stop "$MYSQL_CONTAINER_NAME"
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER_NAME}$"; then
        docker rm "$MYSQL_CONTAINER_NAME"
        echo -e "${GREEN}✅ MySQL container removed${NC}"
    else
        echo -e "${YELLOW}⚠️  MySQL container does not exist${NC}"
    fi
    echo ""
}

# 函数：删除 Nacos
remove_nacos() {
    echo "🗑️  Removing Nacos container..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${NACOS_CONTAINER_NAME}$"; then
        docker stop "$NACOS_CONTAINER_NAME"
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${NACOS_CONTAINER_NAME}$"; then
        docker rm "$NACOS_CONTAINER_NAME"
        echo -e "${GREEN}✅ Nacos container removed${NC}"
    else
        echo -e "${YELLOW}⚠️  Nacos container does not exist${NC}"
    fi
    echo ""
}

# 函数：重启 MySQL
restart_mysql() {
    stop_mysql
    start_mysql
}

# 函数：重启 Nacos
restart_nacos() {
    stop_nacos
    start_nacos
}

# 函数：查看 MySQL 日志
logs_mysql() {
    echo "📋 MySQL container logs (last 50 lines):"
    echo ""
    docker logs --tail 50 "$MYSQL_CONTAINER_NAME"
}

# 函数：查看 Nacos 日志
logs_nacos() {
    echo "📋 Nacos container logs (last 50 lines):"
    echo ""
    docker logs --tail 50 "$NACOS_CONTAINER_NAME"
}

# 函数：显示帮助
show_help() {
    print_header
    echo "Usage: $0 <command> [service]"
    echo ""
    echo "Commands:"
    echo "  start [service]    - Start containers (mysql, nacos, or all)"
    echo "  stop [service]     - Stop containers (mysql, nacos, or all)"
    echo "  restart [service]  - Restart containers (mysql, nacos, or all)"
    echo "  status             - Show container status"
    echo "  logs [service]     - Show container logs (mysql or nacos)"
    echo "  remove [service]   - Remove containers (mysql, nacos, or all)"
    echo "  help               - Show this help message"
    echo ""
    echo "Services:"
    echo "  mysql              - MySQL database container"
    echo "  nacos              - Nacos service discovery container"
    echo "  all                - All containers (default)"
    echo ""
    echo "Examples:"
    echo "  $0 start           - Start all containers"
    echo "  $0 start mysql     - Start only MySQL"
    echo "  $0 stop nacos      - Stop only Nacos"
    echo "  $0 restart all     - Restart all containers"
    echo "  $0 status          - Show status of all containers"
    echo "  $0 logs mysql      - Show MySQL logs"
    echo ""
}

# 主逻辑
main() {
    local command=${1:-help}
    local service=${2:-all}
    
    case "$command" in
        start)
            print_header
            case "$service" in
                mysql)
                    start_mysql
                    ;;
                nacos)
                    start_nacos
                    ;;
                all)
                    start_mysql
                    start_nacos
                    ;;
                *)
                    echo -e "${RED}❌ Unknown service: $service${NC}"
                    echo "   Valid services: mysql, nacos, all"
                    exit 1
                    ;;
            esac
            show_status
            ;;
            
        stop)
            print_header
            case "$service" in
                mysql)
                    stop_mysql
                    ;;
                nacos)
                    stop_nacos
                    ;;
                all)
                    stop_mysql
                    stop_nacos
                    ;;
                *)
                    echo -e "${RED}❌ Unknown service: $service${NC}"
                    echo "   Valid services: mysql, nacos, all"
                    exit 1
                    ;;
            esac
            show_status
            ;;
            
        restart)
            print_header
            case "$service" in
                mysql)
                    restart_mysql
                    ;;
                nacos)
                    restart_nacos
                    ;;
                all)
                    restart_mysql
                    restart_nacos
                    ;;
                *)
                    echo -e "${RED}❌ Unknown service: $service${NC}"
                    echo "   Valid services: mysql, nacos, all"
                    exit 1
                    ;;
            esac
            show_status
            ;;
            
        status)
            show_status
            ;;
            
        logs)
            print_header
            case "$service" in
                mysql)
                    logs_mysql
                    ;;
                nacos)
                    logs_nacos
                    ;;
                all)
                    logs_mysql
                    echo ""
                    echo "─────────────────────────────────────────────────────────────"
                    echo ""
                    logs_nacos
                    ;;
                *)
                    echo -e "${RED}❌ Unknown service: $service${NC}"
                    echo "   Valid services: mysql, nacos, all"
                    exit 1
                    ;;
            esac
            ;;
            
        remove)
            print_header
            echo -e "${YELLOW}⚠️  Warning: This will remove the containers and all data!${NC}"
            read -p "Are you sure? (yes/no): " confirm
            if [ "$confirm" != "yes" ]; then
                echo "Cancelled."
                exit 0
            fi
            
            case "$service" in
                mysql)
                    remove_mysql
                    ;;
                nacos)
                    remove_nacos
                    ;;
                all)
                    remove_mysql
                    remove_nacos
                    ;;
                *)
                    echo -e "${RED}❌ Unknown service: $service${NC}"
                    echo "   Valid services: mysql, nacos, all"
                    exit 1
                    ;;
            esac
            show_status
            ;;
            
        help|--help|-h)
            show_help
            ;;
            
        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Error: Docker is not installed${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# 执行主函数
main "$@"
