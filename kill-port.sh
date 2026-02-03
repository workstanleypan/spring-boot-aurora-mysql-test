#!/bin/bash

# 杀掉占用指定端口的进程

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PORT=${1:-8080}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Kill Process on Port                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${BLUE}🔍 Checking port $PORT...${NC}"
echo ""

# 查找占用端口的进程
PID=$(lsof -ti:$PORT 2>/dev/null || true)

if [ -z "$PID" ]; then
    echo -e "${GREEN}✅ Port $PORT is not in use${NC}"
    echo ""
    exit 0
fi

echo -e "${YELLOW}⚠️  Port $PORT is in use by process(es): $PID${NC}"
echo ""

# 显示进程信息
echo -e "${BLUE}📋 Process Information:${NC}"
ps -p $PID -o pid,ppid,cmd,etime 2>/dev/null || true
echo ""

# 确认是否杀掉进程
read -p "Do you want to kill this process? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}🔨 Killing process(es)...${NC}"

# 杀掉进程
for pid in $PID; do
    kill -9 $pid 2>/dev/null || true
    echo -e "${GREEN}✅ Killed process $pid${NC}"
done

echo ""
echo -e "${GREEN}✅ Port $PORT is now free${NC}"
echo ""
