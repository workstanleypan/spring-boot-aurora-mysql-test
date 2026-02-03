#!/bin/bash

# Test script for log level rewrite functionality

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Log Level Rewrite Test                                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check which configuration to use
CONFIG_TYPE=${1:-"pattern"}

case "$CONFIG_TYPE" in
    "pattern")
        CONFIG_FILE="log4j2-spring-with-level-rewrite.xml"
        echo -e "${YELLOW}📝 Using Pattern-based rewrite (simple)${NC}"
        ;;
    "policy")
        CONFIG_FILE="log4j2-spring-with-rewrite-policy.xml"
        echo -e "${YELLOW}📝 Using RewritePolicy (advanced)${NC}"
        ;;
    *)
        echo -e "${RED}❌ Invalid config type: $CONFIG_TYPE${NC}"
        echo "Usage: $0 [pattern|policy]"
        exit 1
        ;;
esac

# Backup current config
if [ -f "src/main/resources/log4j2-spring.xml" ]; then
    echo -e "${YELLOW}📦 Backing up current config...${NC}"
    cp src/main/resources/log4j2-spring.xml src/main/resources/log4j2-spring.xml.backup
fi

# Copy test config
echo -e "${YELLOW}📝 Applying test config: $CONFIG_FILE${NC}"
cp "src/main/resources/$CONFIG_FILE" src/main/resources/log4j2-spring.xml

# Clean old logs
echo -e "${YELLOW}🧹 Cleaning old logs...${NC}"
rm -f logs/jdbc-wrapper*.log
rm -f logs/*.log

# Build the project
echo -e "${YELLOW}🔨 Building project...${NC}"
mvn clean package -DskipTests -q

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build successful${NC}"
echo ""

# Start the application with DEBUG level
echo -e "${BLUE}🚀 Starting application with DEBUG level...${NC}"
echo ""

# Set environment variables for Aurora with DEBUG level
export CLUSTER_ENDPOINT="${CLUSTER_ENDPOINT:-your-cluster.cluster-xxx.rds.amazonaws.com}"
export DB_USER="${DB_USER:-admin}"
export DB_PASSWORD="${DB_PASSWORD:-your-password}"
export DB_NAME="${DB_NAME:-testdb}"
export WRAPPER_LOG_LEVEL="FINE"  # DEBUG level

# Start in background
nohup java -jar target/*.jar > /dev/null 2>&1 &
APP_PID=$!

echo -e "${GREEN}✅ Application started (PID: $APP_PID)${NC}"
echo ""

# Wait for application to start
echo -e "${YELLOW}⏳ Waiting for application to start (30 seconds)...${NC}"
sleep 30

# Check if application is running
if ! ps -p $APP_PID > /dev/null; then
    echo -e "${RED}❌ Application failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Application is running${NC}"
echo ""

# Make some API calls to generate logs
echo -e "${BLUE}📡 Making API calls to generate logs...${NC}"
for i in {1..5}; do
    curl -s http://localhost:8080/api/test > /dev/null
    echo -e "  ${GREEN}✓${NC} API call $i"
    sleep 1
done

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Analyzing Log Files                                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Wait a bit for logs to be written
sleep 5

# Check original wrapper log
if [ -f "logs/jdbc-wrapper.log" ]; then
    echo -e "${YELLOW}📄 jdbc-wrapper.log (original levels):${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    DEBUG_COUNT=$(grep -c " DEBUG " logs/jdbc-wrapper.log || echo "0")
    TRACE_COUNT=$(grep -c " TRACE " logs/jdbc-wrapper.log || echo "0")
    INFO_COUNT=$(grep -c " INFO " logs/jdbc-wrapper.log || echo "0")
    
    echo -e "  TRACE logs: ${TRACE_COUNT}"
    echo -e "  DEBUG logs: ${DEBUG_COUNT}"
    echo -e "  INFO logs:  ${INFO_COUNT}"
    echo ""
    
    if [ $DEBUG_COUNT -gt 0 ] || [ $TRACE_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅ Found DEBUG/TRACE logs in original file${NC}"
        echo ""
        echo -e "${YELLOW}Sample DEBUG/TRACE logs:${NC}"
        grep -E " (DEBUG|TRACE) " logs/jdbc-wrapper.log | head -3
    else
        echo -e "${YELLOW}⚠️  No DEBUG/TRACE logs found${NC}"
    fi
else
    echo -e "${RED}❌ jdbc-wrapper.log not found${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check rewritten log
if [ -f "logs/jdbc-wrapper-debug-as-info.log" ]; then
    echo -e "${YELLOW}📄 jdbc-wrapper-debug-as-info.log (rewritten to INFO):${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    DEBUG_COUNT=$(grep -c " DEBUG " logs/jdbc-wrapper-debug-as-info.log || echo "0")
    TRACE_COUNT=$(grep -c " TRACE " logs/jdbc-wrapper-debug-as-info.log || echo "0")
    INFO_COUNT=$(grep -c " INFO " logs/jdbc-wrapper-debug-as-info.log || echo "0")
    
    echo -e "  TRACE logs: ${TRACE_COUNT}"
    echo -e "  DEBUG logs: ${DEBUG_COUNT}"
    echo -e "  INFO logs:  ${INFO_COUNT}"
    echo ""
    
    if [ $INFO_COUNT -gt 0 ] && [ $DEBUG_COUNT -eq 0 ] && [ $TRACE_COUNT -eq 0 ]; then
        echo -e "${GREEN}✅ SUCCESS! All logs are at INFO level${NC}"
        echo ""
        echo -e "${YELLOW}Sample rewritten logs:${NC}"
        grep " INFO " logs/jdbc-wrapper-debug-as-info.log | head -3
    elif [ $DEBUG_COUNT -gt 0 ] || [ $TRACE_COUNT -gt 0 ]; then
        echo -e "${RED}❌ FAILED! Still found DEBUG/TRACE logs${NC}"
    else
        echo -e "${YELLOW}⚠️  No logs found in rewritten file${NC}"
    fi
else
    echo -e "${RED}❌ jdbc-wrapper-debug-as-info.log not found${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Stop the application
echo -e "${YELLOW}🛑 Stopping application...${NC}"
kill $APP_PID
wait $APP_PID 2>/dev/null

echo -e "${GREEN}✅ Application stopped${NC}"
echo ""

# Restore original config
if [ -f "src/main/resources/log4j2-spring.xml.backup" ]; then
    echo -e "${YELLOW}📦 Restoring original config...${NC}"
    mv src/main/resources/log4j2-spring.xml.backup src/main/resources/log4j2-spring.xml
    echo -e "${GREEN}✅ Config restored${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Test Complete                                                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}📝 Log files available for inspection:${NC}"
echo -e "  - logs/jdbc-wrapper.log (original levels)"
echo -e "  - logs/jdbc-wrapper-debug-as-info.log (rewritten to INFO)"
echo -e "  - logs/jdbc-wrapper-info.log (INFO and above)"
echo ""
