#!/bin/bash

# Blue/Green Status 诊断脚本

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Blue/Green Status 诊断                                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查必需的环境变量
if [ -z "$AURORA_CLUSTER_ENDPOINT" ] || [ -z "$AURORA_USERNAME" ] || [ -z "$AURORA_PASSWORD" ]; then
    echo -e "${RED}❌ 缺少必需的环境变量${NC}"
    echo ""
    echo "请设置："
    echo "  export AURORA_CLUSTER_ENDPOINT=\"database-2.cluster-xxx.rds.amazonaws.com\""
    echo "  export AURORA_USERNAME=\"admin\""
    echo "  export AURORA_PASSWORD=\"your-password\""
    echo "  export AURORA_DATABASE=\"testdb\""
    echo ""
    exit 1
fi

DATABASE="${AURORA_DATABASE:-testdb}"

echo -e "${YELLOW}📋 连接信息:${NC}"
echo "  Endpoint: $AURORA_CLUSTER_ENDPOINT"
echo "  Database: $DATABASE"
echo "  Username: $AURORA_USERNAME"
echo ""

# 1. 检查 mysql.rds_topology 表是否存在（关键！）
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}1. 检查 mysql.rds_topology 表是否存在（关键检查）...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

RESULT=$(mysql -h "$AURORA_CLUSTER_ENDPOINT" -u "$AURORA_USERNAME" -p"$AURORA_PASSWORD" -N -e \
  "SELECT 1 FROM information_schema.tables WHERE table_schema = 'mysql' AND table_name = 'rds_topology';" 2>&1)

if echo "$RESULT" | grep -q "1"; then
    echo -e "  ${GREEN}✅ mysql.rds_topology 表存在${NC}"
    echo ""
    echo "  查询表内容:"
    mysql -h "$AURORA_CLUSTER_ENDPOINT" -u "$AURORA_USERNAME" -p"$AURORA_PASSWORD" -t \
      -e "SELECT * FROM mysql.rds_topology;" 2>&1 | head -20
else
    echo -e "  ${RED}❌ mysql.rds_topology 表不存在${NC}"
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}这就是为什么 BG status 一直是 NOT_CREATED！${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "根据 AWS JDBC Wrapper 源码:"
    echo "  isBlueGreenStatusAvailable() 检查这个表是否存在"
    echo "  如果表不存在 → 返回 false → 设置状态为 NOT_CREATED"
    echo ""
fi

echo ""

# 2. 查询 mysql.ro_replica_status 表
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}2. 查询 mysql.ro_replica_status 表（Blue/Green 状态）...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

mysql -h "$AURORA_CLUSTER_ENDPOINT" -u "$AURORA_USERNAME" -p"$AURORA_PASSWORD" -t \
  -e "SELECT * FROM mysql.ro_replica_status;" 2>&1 | head -30

echo ""

# 3. 检查应用日志
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}3. 检查应用日志中的 BG 状态...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -f "logs/jdbc-wrapper.log" ]; then
    echo "最近 10 条 BG status 日志:"
    grep "BG status:" logs/jdbc-wrapper.log | tail -10
    echo ""
    
    echo "BG status 统计:"
    NOT_CREATED=$(grep -c 'BG status: NOT_CREATED' logs/jdbc-wrapper.log)
    CREATED=$(grep -c 'BG status: CREATED' logs/jdbc-wrapper.log)
    
    echo "  NOT_CREATED: $NOT_CREATED"
    echo "  CREATED: $CREATED"
    echo ""
fi

echo ""

# 4. 检查连接端点
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}4. 检查连接端点类型...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if grep -q "\.cluster-" logs/jdbc-wrapper.log 2>/dev/null; then
    echo -e "  ${GREEN}✅ 使用 Cluster Endpoint${NC}"
else
    echo -e "  ${RED}❌ 未使用 Cluster Endpoint${NC}"
    echo -e "  ${YELLOW}BG Plugin 需要 Cluster Endpoint！${NC}"
fi

echo ""

# 5. 检查 Aurora 版本
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}5. 检查 Aurora 版本...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

VERSION=$(mysql -h "$AURORA_CLUSTER_ENDPOINT" -u "$AURORA_USERNAME" -p"$AURORA_PASSWORD" -N -e \
  "SELECT @@aurora_version;" 2>&1)

if [ $? -eq 0 ]; then
    echo "  Aurora Version: $VERSION"
    echo ""
    echo "  Blue/Green 支持的最低版本:"
    echo "    - Aurora MySQL 5.7: 2.10.0+"
    echo "    - Aurora MySQL 8.0: 3.02.0+"
else
    echo -e "  ${YELLOW}⚠️  无法查询 Aurora 版本${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  诊断结论                                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}如果 BG status 一直是 NOT_CREATED，最可能的原因是:${NC}"
echo ""
echo "1. ${RED}mysql.rds_topology 表不存在${NC}"
echo "   → 这个表只在创建 Blue/Green 部署后才会出现"
echo "   → 即使绿色集群 ready，如果没有通过 AWS 创建 Blue/Green 部署，表也不会存在"
echo ""
echo "2. ${YELLOW}解决方法:${NC}"
echo "   a) 在 AWS RDS Console 中创建 Blue/Green 部署"
echo "   b) 或使用 AWS CLI:"
echo "      aws rds create-blue-green-deployment \\"
echo "        --blue-green-deployment-name my-deployment \\"
echo "        --source-arn arn:aws:rds:us-east-1:xxx:cluster:$CLUSTER_ID \\"
echo "        --target-engine-version <version>"
echo ""
echo "3. ${YELLOW}重要提示:${NC}"
echo "   - 绿色集群 ready ≠ Blue/Green 部署已创建"
echo "   - 必须通过 AWS Blue/Green 部署功能创建"
echo "   - 不是简单的创建一个新集群"
echo ""
