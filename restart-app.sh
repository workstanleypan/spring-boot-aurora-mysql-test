#!/bin/bash

# 重启应用（自动杀掉旧进程）

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PORT=8080

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Restart Spring Boot Application                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 检查端口是否被占用
echo -e "${BLUE}🔍 Checking port $PORT...${NC}"

PID=$(lsof -ti:$PORT 2>/dev/null || true)

if [ -n "$PID" ]; then
    echo -e "${YELLOW}⚠️  Port $PORT is in use by process: $PID${NC}"
    echo ""
    echo -e "${BLUE}📋 Process Information:${NC}"
    ps -p $PID -o pid,ppid,cmd,etime 2>/dev/null || true
    echo ""
    
    echo -e "${YELLOW}🔨 Killing old process...${NC}"
    for pid in $PID; do
        kill -9 $pid 2>/dev/null || true
        echo -e "${GREEN}✅ Killed process $pid${NC}"
    done
    
    # 等待端口释放
    sleep 2
    echo ""
else
    echo -e "${GREEN}✅ Port $PORT is free${NC}"
    echo ""
fi

# 确定使用哪个启动脚本
if [ -n "$AURORA_CLUSTER_ENDPOINT" ]; then
    echo -e "${BLUE}🚀 Starting with Aurora configuration...${NC}"
    ./run-aurora.sh "$@"
elif [ -n "$RDS_ENDPOINT" ]; then
    echo -e "${BLUE}🚀 Starting with RDS configuration...${NC}"
    ./run-rds.sh "$@"
else
    echo -e "${BLUE}🚀 Starting with local MySQL configuration...${NC}"
    
    # 启动应用
    JAR_FILE=$(ls -t target/*.jar 2>/dev/null | head -1)
    
    if [ -z "$JAR_FILE" ]; then
        echo -e "${RED}❌ Error: No JAR file found in target/${NC}"
        echo ""
        echo "Please build the project first:"
        echo "  mvn clean package -DskipTests"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}📦 Using JAR: $JAR_FILE${NC}"
    echo ""
    
    # 后台启动应用
    nohup java -jar "$JAR_FILE" > /dev/null 2>&1 &
    NEW_PID=$!
    
    echo -e "${GREEN}✅ Application started (PID: $NEW_PID)${NC}"
    echo ""
    echo -e "${BLUE}📊 Waiting for application to start...${NC}"
    sleep 5
    
    # 检查应用是否成功启动
    if ps -p $NEW_PID > /dev/null; then
        echo -e "${GREEN}✅ Application is running${NC}"
        echo ""
        echo -e "${BLUE}📝 Useful commands:${NC}"
        echo "   View logs: tail -f logs/spring-boot.log"
        echo "   Test API:  curl http://localhost:8080/api/test"
        echo "   Stop app:  kill $NEW_PID"
    else
        echo -e "${RED}❌ Application failed to start${NC}"
        echo "   Check logs: tail -f logs/spring-boot.log"
        exit 1
    fi
fi
