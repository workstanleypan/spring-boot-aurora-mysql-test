#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Spring Boot MySQL Test - API Testing                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

BASE_URL="http://localhost:8080/api"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试函数
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}📋 Test: ${description}${NC}"
    echo "   Method: $method"
    echo "   Endpoint: $endpoint"
    
    if [ -n "$data" ]; then
        echo "   Data: $data"
        response=$(curl -s -X $method -H "Content-Type: application/json" -d "$data" "${BASE_URL}${endpoint}")
    else
        response=$(curl -s -X $method "${BASE_URL}${endpoint}")
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Response:${NC}"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        echo -e "${RED}❌ Request failed${NC}"
    fi
}

# 等待应用启动
echo "⏳ Waiting for application to start..."
for i in {1..30}; do
    if curl -s http://localhost:8080/actuator/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Application is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Application failed to start${NC}"
        exit 1
    fi
    sleep 1
done

echo ""
echo "🧪 Starting API tests..."

# 1. Health Check
test_endpoint "GET" "/actuator/health" "" "Health Check"

# 2. Database Connection Test
test_endpoint "GET" "/test" "" "Database Connection Test"

# 3. Get User Stats
test_endpoint "GET" "/users/stats" "" "Get User Statistics"

# 4. Get All Users
test_endpoint "GET" "/users" "" "Get All Users"

# 5. Create User
test_endpoint "POST" "/users" '{"name":"Spring Boot Test User"}' "Create New User"

# 6. Get All Users Again
test_endpoint "GET" "/users" "" "Get All Users (After Creation)"

# 7. Get User by ID
test_endpoint "GET" "/users/1" "" "Get User by ID (1)"

# 8. Update User
test_endpoint "PUT" "/users/1" '{"name":"Updated User Name"}' "Update User (ID 1)"

# 9. Get User by ID Again
test_endpoint "GET" "/users/1" "" "Get User by ID (After Update)"

# 10. Delete User
test_endpoint "DELETE" "/users/1" "" "Delete User (ID 1)"

# 11. Get All Users Final
test_endpoint "GET" "/users" "" "Get All Users (After Deletion)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ All tests completed!${NC}"
echo ""
