#!/bin/bash
# ============================================================
# Instance 2 - Blue/Green Test
# ============================================================
# Scenario A (same cluster):
#   Both instances use the same AURORA_CLUSTER_ENDPOINT
#   CLUSTER_ID defaults to "cluster-a" (same as instance1, shared topology cache)
#
# Scenario B (different clusters):
#   Set AURORA_CLUSTER_ENDPOINT_2 to a DIFFERENT cluster
#   CLUSTER_ID_2 and BGD_ID_2 default to "cluster-b" (isolated topology cache)
#
# Usage:
#   Scenario A: export AURORA_CLUSTER_ENDPOINT="same-cluster-endpoint"
#               ./run-instance2.sh
#
#   Scenario B: export AURORA_CLUSTER_ENDPOINT_1="cluster-a-endpoint"
#               export AURORA_CLUSTER_ENDPOINT_2="cluster-b-endpoint"
#               ./run-instance1.sh   (uses _1)
#               ./run-instance2.sh   (uses _2)
# ============================================================

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Instance 2 - Blue/Green Test                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ENV=${1:-prod}

# Use AURORA_CLUSTER_ENDPOINT_2 if set, otherwise fall back to AURORA_CLUSTER_ENDPOINT (Scenario A)
if [ -n "$AURORA_CLUSTER_ENDPOINT_2" ]; then
    echo "🔀 Scenario B: Different cluster detected (AURORA_CLUSTER_ENDPOINT_2)"
    export AURORA_CLUSTER_ENDPOINT="$AURORA_CLUSTER_ENDPOINT_2"
    export CLUSTER_ID="${CLUSTER_ID_2:-cluster-b}"
    export BGD_ID="${BGD_ID_2:-cluster-b}"
    export AURORA_USERNAME="${AURORA_USERNAME_2:-${AURORA_USERNAME:-admin}}"
    export AURORA_PASSWORD="${AURORA_PASSWORD_2:-${AURORA_PASSWORD}}"
    export AURORA_DATABASE="${AURORA_DATABASE_2:-${AURORA_DATABASE:-testdb}}"
    SCENARIO="B - Different Clusters"
else
    echo "🔗 Scenario A: Same cluster as Instance 1"
    export CLUSTER_ID="${CLUSTER_ID:-cluster-a}"
    export BGD_ID="${BGD_ID:-cluster-a}"
    export AURORA_USERNAME="${AURORA_USERNAME:-admin}"
    export AURORA_DATABASE="${AURORA_DATABASE:-testdb}"
    SCENARIO="A - Same Cluster"
fi

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

# Instance 2 config
export SERVER_PORT="${SERVER_PORT_2:-8081}"
export TABLE_PREFIX="${TABLE_PREFIX_2:-inst2}"

echo "📋 Instance 2 Configuration:"
echo "   Scenario         : $SCENARIO"
echo "   Cluster Endpoint : $AURORA_CLUSTER_ENDPOINT"
echo "   Server Port      : $SERVER_PORT"
echo "   Table Prefix     : $TABLE_PREFIX"
echo "   Cluster ID       : $CLUSTER_ID"
echo "   BGD ID           : $BGD_ID"
echo "   Database         : $AURORA_DATABASE"
echo "   Username         : $AURORA_USERNAME"
echo "   Password         : ********"
echo ""

if [ "$SCENARIO" = "A - Same Cluster" ]; then
    echo "ℹ️  Scenario A: Shared topology cache with Instance 1"
    echo "   Both instances will detect the same BG switchover event"
    echo "   Tables: inst2_bg_write_test, inst2_bg_test_thread_N"
else
    echo "ℹ️  Scenario B: Isolated topology cache from Instance 1"
    echo "   Each instance tracks its own cluster's BG switchover independently"
    echo "   Tables: inst2_bg_write_test, inst2_bg_test_thread_N"
fi
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

LOG_DIR="logs/instance2"
mkdir -p "$LOG_DIR"

# Auto-detect JAVA_HOME from JAR filename
source "$(dirname "$0")/detect-java.sh"
detect_java_from_jar "$JAR_FILE"

echo "🚀 Starting Instance 2 on port $SERVER_PORT..."
echo ""

$JAVA_CMD -Dlog.path="$LOG_DIR" -jar "$JAR_FILE" \
    --spring.profiles.active="$PROFILE" \
    --server.port="$SERVER_PORT" \
    --app.table-prefix="$TABLE_PREFIX"
