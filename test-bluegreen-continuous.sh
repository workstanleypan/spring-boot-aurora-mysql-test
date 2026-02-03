#!/bin/bash

# Blue/Green Continuous Test Script
# 用于启动和监控持续运行的蓝绿切换测试

BASE_URL="http://localhost:8080/api/bluegreen"
MONITOR_INTERVAL=30  # 监控间隔（秒）

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if app is running
check_app() {
    if ! curl -s -f "$BASE_URL/help" > /dev/null 2>&1; then
        print_error "Application is not running at $BASE_URL"
        print_info "Please start the application first:"
        echo "  cd spring-boot-mysql-test"
        echo "  ./run-aurora.sh"
        exit 1
    fi
}

# Function to start continuous test
start_continuous() {
    local threads=${1:-20}
    local reads_per_sec=${2:-500}
    
    print_info "Starting CONTINUOUS test..."
    print_info "Threads: $threads"
    print_info "Reads per second (per thread): $reads_per_sec"
    print_info "Total reads per second: $((threads * reads_per_sec))"
    print_warning "Test will run INDEFINITELY until manually stopped"
    echo ""
    
    local response=$(curl -s -X POST "$BASE_URL/start-continuous" \
        -H "Content-Type: application/json" \
        -d "{\"numThreads\":$threads,\"readsPerSecond\":$reads_per_sec}")
    
    if echo "$response" | jq -e '.status == "started"' > /dev/null 2>&1; then
        print_success "Test started successfully!"
        echo ""
        echo "$response" | jq '.'
        echo ""
        print_info "Test is now running in CONTINUOUS mode"
        print_info "Use './test-bluegreen-continuous.sh monitor' to watch progress"
        print_info "Use './test-bluegreen-continuous.sh stop' to stop the test"
    else
        print_error "Failed to start test"
        echo "$response" | jq '.'
        exit 1
    fi
}

# Function to start timed test
start_timed() {
    local threads=${1:-20}
    local reads_per_sec=${2:-500}
    local duration=${3:-3600}
    
    print_info "Starting TIMED test..."
    print_info "Threads: $threads"
    print_info "Reads per second (per thread): $reads_per_sec"
    print_info "Duration: $duration seconds"
    echo ""
    
    local response=$(curl -s -X POST "$BASE_URL/start" \
        -H "Content-Type: application/json" \
        -d "{\"numThreads\":$threads,\"readsPerSecond\":$reads_per_sec,\"durationSeconds\":$duration}")
    
    if echo "$response" | jq -e '.status == "started"' > /dev/null 2>&1; then
        print_success "Test started successfully!"
        echo ""
        echo "$response" | jq '.'
    else
        print_error "Failed to start test"
        echo "$response" | jq '.'
        exit 1
    fi
}

# Function to stop test
stop_test() {
    print_info "Stopping test..."
    
    local response=$(curl -s -X POST "$BASE_URL/stop")
    
    if echo "$response" | jq -e '.status == "stopped"' > /dev/null 2>&1; then
        print_success "Test stopped successfully!"
        echo ""
        echo "$response" | jq '.'
    else
        print_error "Failed to stop test"
        echo "$response" | jq '.'
        exit 1
    fi
}

# Function to get status once
get_status() {
    local response=$(curl -s "$BASE_URL/status")
    
    if [ $? -eq 0 ]; then
        echo "$response" | jq '.'
    else
        print_error "Failed to get status"
        exit 1
    fi
}

# Function to monitor test continuously
monitor_test() {
    local interval=${1:-$MONITOR_INTERVAL}
    
    print_info "Monitoring test status (interval: ${interval}s)"
    print_info "Press Ctrl+C to stop monitoring (test will continue running)"
    echo ""
    
    while true; do
        clear
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Blue/Green Continuous Test Monitor"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        local response=$(curl -s "$BASE_URL/status")
        
        if [ $? -eq 0 ]; then
            local running=$(echo "$response" | jq -r '.running')
            local mode=$(echo "$response" | jq -r '.mode')
            
            if [ "$running" = "true" ]; then
                print_success "Test is RUNNING ($mode mode)"
            else
                print_warning "Test is NOT running"
            fi
            
            echo ""
            echo "📊 Statistics:"
            echo "$response" | jq -r '.statistics | to_entries[] | "  \(.key): \(.value)"'
            
            echo ""
            echo "🔌 Connection:"
            echo "$response" | jq -r '.connection | to_entries[] | "  \(.key): \(.value)"'
            
            # Check for failovers
            local failovers=$(echo "$response" | jq -r '.statistics.failoverCount')
            if [ "$failovers" != "0" ]; then
                echo ""
                print_warning "Failovers detected: $failovers"
            fi
            
            # Check success rate
            local success_rate=$(echo "$response" | jq -r '.statistics.successRate' | sed 's/%//')
            if (( $(echo "$success_rate < 95" | bc -l) )); then
                echo ""
                print_warning "Success rate below 95%: ${success_rate}%"
            fi
        else
            print_error "Failed to get status"
        fi
        
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "Next update in ${interval}s... (Ctrl+C to stop monitoring)"
        
        sleep "$interval"
    done
}

# Function to show help
show_help() {
    cat << EOF
Blue/Green Continuous Test Script

Usage: $0 <command> [options]

Commands:
  start-continuous [threads] [reads/sec]
      启动持续测试（无限期运行）
      默认: threads=20, reads/sec=500
      示例: $0 start-continuous 10 200

  start-timed [threads] [reads/sec] [duration]
      启动定时测试
      默认: threads=20, reads/sec=500, duration=3600
      示例: $0 start-timed 10 200 1800

  stop
      停止当前运行的测试

  status
      获取当前测试状态（一次）

  monitor [interval]
      持续监控测试状态
      默认: interval=30秒
      示例: $0 monitor 10

  quick-test
      快速测试（5线程, 100读/秒, 60秒）

  help
      显示此帮助信息

Examples:
  # 启动持续测试（默认参数）
  $0 start-continuous

  # 启动持续测试（自定义参数）
  $0 start-continuous 10 200

  # 启动定时测试（1小时）
  $0 start-timed 20 500 3600

  # 监控测试状态
  $0 monitor

  # 停止测试
  $0 stop

Test Modes:
  CONTINUOUS: 测试将无限期运行，直到手动停止
              适合长期监控蓝绿切换
              
  TIMED:      测试运行指定时间后自动停止
              适合有时间限制的测试场景

Monitoring:
  - 每30秒（或自定义间隔）更新一次状态
  - 显示总读取次数、成功率、失败次数
  - 显示 failover 次数和当前连接端点
  - 按 Ctrl+C 停止监控（测试继续运行）

Logs:
  - Application: logs/spring-boot.log
  - JDBC Wrapper: logs/jdbc-wrapper.log
  - IP Metadata: logs/ip-metadata.log

EOF
}

# Main script
main() {
    local command=${1:-help}
    
    case "$command" in
        start-continuous)
            check_app
            start_continuous "${2:-20}" "${3:-500}"
            ;;
        start-timed)
            check_app
            start_timed "${2:-20}" "${3:-500}" "${4:-3600}"
            ;;
        stop)
            check_app
            stop_test
            ;;
        status)
            check_app
            get_status
            ;;
        monitor)
            check_app
            monitor_test "${2:-$MONITOR_INTERVAL}"
            ;;
        quick-test)
            check_app
            print_info "Starting quick test (5 threads, 100 reads/sec, 60 seconds)..."
            curl -s -X POST "$BASE_URL/quick-test" | jq '.'
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
