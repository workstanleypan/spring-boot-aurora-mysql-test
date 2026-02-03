#!/bin/bash

# Aurora BG Plugin 调试模式
# 使用生产配置，但启用详细的 BG Plugin 日志

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Spring Boot MySQL Test - Aurora BG Debug Mode               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 检查必需的环境变量
if [ -z "$AURORA_CLUSTER_ENDPOINT" ]; then
    echo "❌ Error: AURORA_CLUSTER_ENDPOINT is not set"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export AURORA_CLUSTER_ENDPOINT=\"database-2.cluster-xxxxx.us-east-1.rds.amazonaws.com\""
    echo "  export AURORA_DATABASE=\"testdb\""
    echo "  export AURORA_USERNAME=\"admin\""
    echo "  export AURORA_PASSWORD=\"your-password\""
    echo ""
    exit 1
fi

if [ -z "$AURORA_PASSWORD" ]; then
    echo "❌ Error: AURORA_PASSWORD is not set"
    exit 1
fi

# 显示配置信息
echo "📋 Aurora Configuration:"
echo "   Cluster Endpoint: $AURORA_CLUSTER_ENDPOINT"
echo "   Database: ${AURORA_DATABASE:-testdb}"
echo "   Username: ${AURORA_USERNAME:-admin}"
echo "   Password: ********"
echo ""

echo "🔍 BG Debug Mode:"
echo "   Profile: aurora-prod"
echo "   Log Level: FINE (detailed BG Plugin logs)"
echo "   Plugins: initialConnection, auroraConnectionTracker, failover2, efm2, bg"
echo ""
echo "   This mode uses production configuration but enables detailed"
echo "   Blue/Green Plugin logging for debugging purposes."
echo ""

# 设置 FINE 日志级别以查看 BG status
export WRAPPER_LOG_LEVEL="FINE"

echo "🚀 Starting Spring Boot application..."
echo ""

# 启动应用
./run.sh "aurora-prod"

echo ""
echo "💡 Tip: To view BG Plugin logs, run:"
echo "   grep -i 'bg status' logs/jdbc-wrapper.log"
echo "   tail -f logs/jdbc-wrapper.log | grep -i bg"
echo ""
