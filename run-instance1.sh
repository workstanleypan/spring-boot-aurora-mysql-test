#!/bin/bash
# ============================================================
# Instance 1 - Blue/Green Test
# ============================================================
# Scenario A (same cluster): Both instances use AURORA_CLUSTER_ENDPOINT
# Scenario B (different clusters): Instance 1 uses AURORA_CLUSTER_ENDPOINT_1
#   (falls back to AURORA_CLUSTER_ENDPOINT if _1 is not set)
#
# Usage:
#   Scenario A: export AURORA_CLUSTER_ENDPOINT="cluster-a-endpoint"
#               ./run-instance1.sh
#
#   Scenario B: export AURORA_CLUSTER_ENDPOINT_1="cluster-a-endpoint"
#               export AURORA_CLUSTER_ENDPOINT_2="cluster-b-endpoint"
#               ./run-instance1.sh   (uses _1)
#               ./run-instance2.sh   (uses _2)
# ============================================================

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Instance 1 - Blue/Green Test                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ENV=${1:-prod}

# Use AURORA_CLUSTER_ENDPOINT_1 if set, otherwise fall back to AURORA_CLUSTER_ENDPOINT
if [ -n "$AURORA_CLUSTER_ENDPOINT_1" ]; then
    export AURORA_CLUSTER_ENDPOINT="$AURORA_CLUSTER_ENDPOINT_1"
fi

# Use instance-specific username/password/database if set, otherwise fall back to shared ones
export AURORA_USERNAME="${AURORA_USERNAME_1:-${AURORA_USERNAME:-admin}}"
export AURORA_PASSWORD="${AURORA_PASSWORD_1:-${AURORA_PASSWORD}}"
export AURORA_DATABASE="${AURORA_DATABASE_1:-${AURORA_DATABASE:-testdb}}"

if [ -z "$AURORA_CLUSTER_ENDPOINT" ] || [ -z "$AURORA_PASSWORD" ]; then
    echo "❌ Error: Required environment variables not set"
    echo ""
    echo "Scenario A (same cluster, same credentials):"
    echo "   export AURORA_CLUSTER_ENDPOINT=\"cluster-endpoint\""
    echo "   export AURORA_USERNAME=\"admin\""
    echo "   export AURORA_PASSWORD=\"...\""
    echo ""
    echo "Scenario B (different clusters, different credentials):"
    echo "   export AURORA_CLUSTER_ENDPOINT_1=\"cluster-a-endpoint\""
    echo "   export AURORA_USERNAME_1=\"user1\""
    echo "   export AURORA_PASSWORD_1=\"pass1\""
    echo "   export AURORA_CLUSTER_ENDPOINT_2=\"cluster-b-endpoint\""
    echo "   export AURORA_USERNAME_2=\"user2\""
    echo "   export AURORA_PASSWORD_2=\"pass2\""
    exit 1
fi

# Instance 1 config
export SERVER_PORT="${SERVER_PORT_1:-8080}"
export TABLE_PREFIX="${TABLE_PREFIX_1:-inst1}"
export CLUSTER_ID="${CLUSTER_ID_1:-${CLUSTER_ID:-cluster-a}}"
export BGD_ID="${BGD_ID_1:-${BGD_ID:-cluster-a}}"

echo "📋 Instance 1 Configuration:"
echo "   Cluster Endpoint : $AURORA_CLUSTER_ENDPOINT"
echo "   Server Port      : $SERVER_PORT"
echo "   Table Prefix     : $TABLE_PREFIX"
echo "   Cluster ID       : $CLUSTER_ID"
echo "   BGD ID           : $BGD_ID"
echo "   Database         : $AURORA_DATABASE"
echo "   Username         : $AURORA_USERNAME"
echo "   Password         : ********"
echo ""

JAR_FILE=${JAR_FILE:-$(ls -t target/*.jar 2>/dev/null | head -1)}
if [ -z "$JAR_FILE" ]; then
    echo "❌ No JAR found. Run: mvn clean package -DskipTests"
    echo "   Or: ./build.sh --sb 3.4.2 --jdk 17"
    exit 1
fi

if [ "$ENV" = "dev" ]; then
    [ -z "$WRAPPER_LOG_LEVEL" ] && export WRAPPER_LOG_LEVEL="FINEST"
    PROFILE="aurora-dev"
else
    [ -z "$WRAPPER_LOG_LEVEL" ] && export WRAPPER_LOG_LEVEL="FINE"
    PROFILE="aurora-prod"
fi

LOG_DIR="logs/instance1"
mkdir -p "$LOG_DIR"

# Auto-detect JAVA_HOME from JAR filename
source "$(dirname "$0")/detect-java.sh"
detect_java_from_jar "$JAR_FILE"

echo "🚀 Starting Instance 1 on port $SERVER_PORT..."
echo ""

$JAVA_CMD -Dlog.path="$LOG_DIR" -jar "$JAR_FILE" \
    --spring.profiles.active="$PROFILE" \
    --server.port="$SERVER_PORT" \
    --app.table-prefix="$TABLE_PREFIX"
