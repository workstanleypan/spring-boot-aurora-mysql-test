#!/bin/bash

# Blue/Green Switchover Test API 测试脚本
# 用于测试 AWS JDBC Wrapper 在蓝绿切换时的表现

BASE_URL="http://localhost:8080/api/bluegreen"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印帮助信息
print_help() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Blue/Green Switchover Test API - 测试脚本                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  help              显示 API 帮助信息"
    echo "  start             启动测试 (默认参数)"
    echo "  start-custom      启动测试 (自定义参数)"
    echo "  quick-test        快速测试 (5线程, 60秒)"
    echo "  status            查看测试状态"
    echo "  stop              停止测试"
    echo "  monitor           持续监控测试状态 (每5秒刷新)"
    echo ""
    echo "示例:"
    echo "  $0 start                    # 启动默认测试 (20线程, 500读/秒, 1小时)"
    echo "  $0 start-custom 10 200 1800 # 启动自定义测试 (10线程, 200读/秒, 30分钟)"
    echo "  $0 quick-test               # 快速测试 (5线程, 100读/秒, 60秒)"
    echo "  $0 status                   # 查看当前状态"
    echo "  $0 monitor                  # 持续监控"
    echo "  $0 stop                     # 停止测试"
    echo ""
}

# 获取 API 帮助
get_api_help() {
    echo -e "${BLUE}📖 获取 API 帮助信息...${NC}"
    echo ""
    curl -s "$BASE_URL/help" | jq '.' || echo "Failed to get help"
}

# 启动测试 (默认参数)
start_test() {
    echo -e "${GREEN}🚀 启动 Blue/Green 切换测试 (默认参数)...${NC}"
    echo ""
    curl -s -X POST "$BASE_URL/start" \
        -H "Content-Type: application/json" | jq '.'
}

# 启动测试 (自定义参数)
start_custom_test() {
    local threads=${1:-20}
    local reads=${2:-500}
    local duration=${3:-3600}
    
    echo -e "${GREEN}🚀 启动 Blue/Green 切换测试 (自定义参数)...${NC}"
    echo -e "   线程数: ${threads}"
    echo -e "   每线程读取/秒: ${reads}"
    echo -e "   总读取/秒: $((threads * reads))"
    echo -e "   持续时间: ${duration}秒 ($((duration / 60))分钟)"
    echo ""
    
    curl -s -X POST "$BASE_URL/start" \
        -H "Content-Type: application/json" \
        -d "{\"numThreads\":${threads},\"readsPerSecond\":${reads},\"durationSeconds\":${duration}}" | jq '.'
}

# 快速测试
quick_test() {
    echo -e "${GREEN}⚡ 启动快速测试 (5线程, 100读/秒, 60秒)...${NC}"
    echo ""
    curl -s -X POST "$BASE_URL/quick-test" \
        -H "Content-Type: application/json" | jq '.'
}

# 获取状态
get_status() {
    curl -s "$BASE_URL/status" | jq '.'
}

# 停止测试
stop_test() {
    echo -e "${RED}🛑 停止测试...${NC}"
    echo ""
    curl -s -X POST "$BASE_URL/stop" \
        -H "Content-Type: application/json" | jq '.'
}

# 持续监控
monitor_test() {
    echo -e "${BLUE}📊 持续监控测试状态 (按 Ctrl+C 退出)...${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║  Blue/Green Test Status - $(date '+%Y-%m-%d %H:%M:%S')              ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        STATUS=$(curl -s "$BASE_URL/status")
        
        if [ $? -eq 0 ]; then
            echo "$STATUS" | jq '.'
            
            # 提取关键指标
            RUNNING=$(echo "$STATUS" | jq -r '.running')
            TOTAL=$(echo "$STATUS" | jq -r '.statistics.totalReads')
            SUCCESS=$(echo "$STATUS" | jq -r '.statistics.successfulReads')
            FAILED=$(echo "$STATUS" | jq -r '.statistics.failedReads')
            SUCCESS_RATE=$(echo "$STATUS" | jq -r '.statistics.successRate')
            FAILOVERS=$(echo "$STATUS" | jq -r '.statistics.failoverCount')
            ENDPOINT=$(echo "$STATUS" | jq -r '.connection.lastEndpoint')
            
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            
            if [ "$RUNNING" = "true" ]; then
                echo -e "状态: ${GREEN}运行中${NC}"
            else
                echo -e "状态: ${YELLOW}已停止${NC}"
            fi
            
            echo -e "总读取: ${TOTAL}"
            echo -e "成功: ${GREEN}${SUCCESS}${NC}"
            echo -e "失败: ${RED}${FAILED}${NC}"
            echo -e "成功率: ${SUCCESS_RATE}"
            echo -e "Failover次数: ${FAILOVERS}"
            echo -e "当前端点: ${ENDPOINT}"
            
            if [ "$FAILOVERS" != "0" ]; then
                echo ""
                echo -e "${YELLOW}⚠️  检测到 Failover 事件!${NC}"
            fi
        else
            echo -e "${RED}❌ 无法获取状态${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "下次刷新: 5秒后 (按 Ctrl+C 退出)"
        
        sleep 5
    done
}

# 主逻辑
case "${1:-help}" in
    help)
        get_api_help
        ;;
    start)
        start_test
        ;;
    start-custom)
        start_custom_test "$2" "$3" "$4"
        ;;
    quick-test)
        quick_test
        ;;
    status)
        get_status
        ;;
    stop)
        stop_test
        ;;
    monitor)
        monitor_test
        ;;
    *)
        print_help
        ;;
esac
