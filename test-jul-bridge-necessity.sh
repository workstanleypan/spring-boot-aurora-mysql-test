#!/bin/bash

# Test script to verify if JulBridgeInitializer is necessary
# This script will temporarily disable JulBridgeInitializer and test logging

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Backup file
JUL_BRIDGE_FILE="src/main/java/com/test/config/JulBridgeInitializer.java"
JUL_BRIDGE_BACKUP="${JUL_BRIDGE_FILE}.test-backup"

# Check if file exists
if [ ! -f "$JUL_BRIDGE_FILE" ]; then
    print_error "JulBridgeInitializer.java not found!"
    exit 1
fi

print_header "JUL Bridge Necessity Test"

print_info "This test will:"
echo "  1. Test WITH JulBridgeInitializer (baseline)"
echo "  2. Test WITHOUT JulBridgeInitializer (comparison)"
echo "  3. Compare the results"
echo ""

read -p "Press Enter to continue or Ctrl+C to cancel..."

# Function to count log lines
count_jdbc_logs() {
    local log_file=$1
    if [ -f "$log_file" ]; then
        grep -c "software.amazon.jdbc" "$log_file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to run test
run_test() {
    local test_name=$1
    local with_bridge=$2
    
    print_header "Test: $test_name"
    
    # Clean logs
    print_info "Cleaning old logs..."
    rm -f logs/*.log
    
    # Compile
    print_info "Compiling..."
    mvn clean compile -q
    
    if [ $? -ne 0 ]; then
        print_error "Compilation failed!"
        return 1
    fi
    
    # Start application in background
    print_info "Starting application..."
    java -jar target/spring-boot-mysql-test-1.0-SNAPSHOT.jar > /tmp/spring-boot-console-$test_name.log 2>&1 &
    APP_PID=$!
    
    print_info "Application PID: $APP_PID"
    
    # Wait for startup
    print_info "Waiting for application to start (30 seconds)..."
    sleep 30
    
    # Check if app is running
    if ! ps -p $APP_PID > /dev/null; then
        print_error "Application failed to start!"
        cat /tmp/spring-boot-console-$test_name.log
        return 1
    fi
    
    # Test database connection
    print_info "Testing database connection..."
    curl -s http://localhost:8080/api/test > /tmp/api-test-$test_name.json
    
    if [ $? -eq 0 ]; then
        print_success "API call successful"
        cat /tmp/api-test-$test_name.json | jq '.'
    else
        print_warning "API call failed"
    fi
    
    # Wait a bit more for logs
    print_info "Waiting for logs to be written (10 seconds)..."
    sleep 10
    
    # Stop application
    print_info "Stopping application..."
    kill $APP_PID 2>/dev/null || true
    sleep 5
    
    # Force kill if still running
    if ps -p $APP_PID > /dev/null 2>&1; then
        print_warning "Force killing application..."
        kill -9 $APP_PID 2>/dev/null || true
    fi
    
    # Analyze logs
    print_header "Log Analysis: $test_name"
    
    echo "📊 Log Files:"
    ls -lh logs/*.log 2>/dev/null || echo "  No log files found"
    echo ""
    
    echo "📊 JDBC Wrapper Logs:"
    if [ -f "logs/jdbc-wrapper.log" ]; then
        local jdbc_log_count=$(count_jdbc_logs "logs/jdbc-wrapper.log")
        echo "  jdbc-wrapper.log: $jdbc_log_count lines with 'software.amazon.jdbc'"
        
        if [ "$jdbc_log_count" -gt 0 ]; then
            print_success "JDBC Wrapper logs found in file"
            echo ""
            echo "Sample logs:"
            grep "software.amazon.jdbc" logs/jdbc-wrapper.log | head -5
        else
            print_warning "No JDBC Wrapper logs in file"
        fi
    else
        print_warning "jdbc-wrapper.log not found"
    fi
    echo ""
    
    echo "📊 Console Output:"
    if [ -f "/tmp/spring-boot-console-$test_name.log" ]; then
        local console_jdbc_count=$(grep -c "software.amazon.jdbc" /tmp/spring-boot-console-$test_name.log 2>/dev/null || echo "0")
        echo "  Console: $console_jdbc_count lines with 'software.amazon.jdbc'"
        
        if [ "$console_jdbc_count" -gt 0 ]; then
            print_info "JDBC Wrapper logs found in console"
            echo ""
            echo "Sample console logs:"
            grep "software.amazon.jdbc" /tmp/spring-boot-console-$test_name.log | head -5
        else
            print_info "No JDBC Wrapper logs in console"
        fi
    fi
    echo ""
    
    # Save results
    echo "$jdbc_log_count" > /tmp/test-result-$test_name.txt
}

# Test 1: WITH JulBridgeInitializer
print_header "Phase 1: Test WITH JulBridgeInitializer"
run_test "with-bridge" true
RESULT_WITH=$(cat /tmp/test-result-with-bridge.txt)

echo ""
read -p "Press Enter to continue to Phase 2..."

# Test 2: WITHOUT JulBridgeInitializer
print_header "Phase 2: Test WITHOUT JulBridgeInitializer"

print_info "Disabling JulBridgeInitializer..."
mv "$JUL_BRIDGE_FILE" "$JUL_BRIDGE_BACKUP"
print_success "JulBridgeInitializer disabled"

run_test "without-bridge" false
RESULT_WITHOUT=$(cat /tmp/test-result-without-bridge.txt)

# Restore JulBridgeInitializer
print_info "Restoring JulBridgeInitializer..."
mv "$JUL_BRIDGE_BACKUP" "$JUL_BRIDGE_FILE"
print_success "JulBridgeInitializer restored"

# Compare results
print_header "Test Results Comparison"

echo "📊 JDBC Wrapper Log Lines:"
echo "  WITH JulBridgeInitializer:    $RESULT_WITH lines"
echo "  WITHOUT JulBridgeInitializer: $RESULT_WITHOUT lines"
echo ""

if [ "$RESULT_WITH" -gt 0 ] && [ "$RESULT_WITHOUT" -eq 0 ]; then
    print_error "CONCLUSION: JulBridgeInitializer IS NECESSARY!"
    echo ""
    echo "Without JulBridgeInitializer:"
    echo "  ❌ No JDBC Wrapper logs in log files"
    echo "  ❌ Logs are lost or only in console"
    echo "  ❌ Cannot use Log4j2 to control JDBC Wrapper logging"
    echo ""
    echo "With JulBridgeInitializer:"
    echo "  ✅ JDBC Wrapper logs properly captured"
    echo "  ✅ Logs written to files"
    echo "  ✅ Log4j2 controls formatting and output"
elif [ "$RESULT_WITH" -gt 0 ] && [ "$RESULT_WITHOUT" -gt 0 ]; then
    print_warning "CONCLUSION: JulBridgeInitializer MAY NOT BE NECESSARY"
    echo ""
    echo "Both configurations produced logs, but check:"
    echo "  - Log format (JUL vs Log4j2)"
    echo "  - Log file locations"
    echo "  - Log level control"
else
    print_warning "CONCLUSION: INCONCLUSIVE"
    echo ""
    echo "Neither configuration produced JDBC Wrapper logs."
    echo "Possible reasons:"
    echo "  - Database connection not established"
    echo "  - JDBC Wrapper not used"
    echo "  - Log level too high"
fi

echo ""
print_info "Test artifacts saved:"
echo "  - /tmp/spring-boot-console-with-bridge.log"
echo "  - /tmp/spring-boot-console-without-bridge.log"
echo "  - /tmp/api-test-with-bridge.json"
echo "  - /tmp/api-test-without-bridge.json"
echo ""

print_success "Test completed!"
