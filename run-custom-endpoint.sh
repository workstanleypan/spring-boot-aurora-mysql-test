#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Spring Boot MySQL Test - Custom Endpoint (Custom Domain)    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check environment parameter
ENV=${1:-prod}

# Check required environment variables
if [ -z "$AURORA_CUSTOM_ENDPOINT" ]; then
    echo "❌ Error: AURORA_CUSTOM_ENDPOINT is not set"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export AURORA_CUSTOM_ENDPOINT=\"abcd\"                    # Custom domain / CNAME"
    echo "  export CUSTOM_ENDPOINT_REGION=\"us-east-1\"               # Cluster region"
    echo "  export CLUSTER_INSTANCE_HOST_PATTERN=\"?.us-east-1.rds.amazonaws.com\""
    echo "  export FAILOVER_MODE=\"reader-or-writer\"                 # or strict-reader"
    echo "  export AURORA_DATABASE=\"testdb\""
    echo "  export AURORA_USERNAME=\"admin\""
    echo "  export AURORA_PASSWORD=\"your-password\""
    echo ""
    echo "Or create a .env file and source it:"
    echo "  source .env"
    echo ""
    exit 1
fi

if [ -z "$CUSTOM_ENDPOINT_REGION" ]; then
    echo "❌ Error: CUSTOM_ENDPOINT_REGION is not set"
    echo ""
    echo "Custom domain cannot be auto-parsed for region."
    echo "Please set: export CUSTOM_ENDPOINT_REGION=\"us-east-1\""
    echo ""
    exit 1
fi

if [ -z "$CLUSTER_INSTANCE_HOST_PATTERN" ]; then
    echo "❌ Error: CLUSTER_INSTANCE_HOST_PATTERN is not set"
    echo ""
    echo "Custom domain cannot be auto-parsed for instance host pattern."
    echo "Please set: export CLUSTER_INSTANCE_HOST_PATTERN=\"?.${CUSTOM_ENDPOINT_REGION}.rds.amazonaws.com\""
    echo ""
    exit 1
fi

if [ -z "$AURORA_PASSWORD" ]; then
    echo "❌ Error: AURORA_PASSWORD is not set"
    echo ""
    echo "Please set: export AURORA_PASSWORD=\"your-password\""
    echo ""
    exit 1
fi

# Display configuration
echo "📋 Custom Endpoint Configuration:"
echo "   Custom Endpoint:    $AURORA_CUSTOM_ENDPOINT"
echo "   Region:             $CUSTOM_ENDPOINT_REGION"
echo "   Host Pattern:       $CLUSTER_INSTANCE_HOST_PATTERN"
echo "   Failover Mode:      ${FAILOVER_MODE:-reader-or-writer}"
echo "   Database:           ${AURORA_DATABASE:-testdb}"
echo "   Username:           ${AURORA_USERNAME:-admin}"
echo "   Password:           ********"
if [ -n "$JDBC_PARAMS" ]; then
    echo "   JDBC Params:        $JDBC_PARAMS"
fi
echo ""

# Select configuration based on environment
if [ "$ENV" = "dev" ]; then
    echo "🔧 Environment: Development"
    echo "   Profile: custom-endpoint-dev"
    if [ -z "$WRAPPER_LOG_LEVEL" ]; then
        export WRAPPER_LOG_LEVEL="FINEST"
    fi
    echo "   Log Level: $WRAPPER_LOG_LEVEL"
    echo "   Plugins: initialConnection, auroraConnectionTracker, customEndpoint, failover2, efm2, bg"
    PROFILE="custom-endpoint-dev"
elif [ "$ENV" = "prod" ]; then
    echo "🚀 Environment: Production"
    echo "   Profile: custom-endpoint-prod"
    if [ -z "$WRAPPER_LOG_LEVEL" ]; then
        export WRAPPER_LOG_LEVEL="FINE"
    fi
    echo "   Log Level: $WRAPPER_LOG_LEVEL"
    echo "   Plugins: initialConnection, auroraConnectionTracker, customEndpoint, failover2, efm2, bg"
    PROFILE="custom-endpoint-prod"
else
    echo "❌ Error: Invalid environment '$ENV'"
    echo ""
    echo "Usage: $0 [prod|dev]"
    echo "  prod - Production environment (INFO logs)"
    echo "  dev  - Development environment (FINE logs)"
    echo ""
    exit 1
fi

echo ""
echo "⚠️  Prerequisites:"
echo "   1. AWS credentials available (Instance Profile, Task Role, env vars, etc.)"
echo "   2. IAM permission: rds:DescribeDBClusterEndpoints"
echo "   3. DNS resolution: '$AURORA_CUSTOM_ENDPOINT' must resolve to the actual custom endpoint IP"
echo "      (via /etc/hosts, Route 53 CNAME, or other DNS)"
echo ""

echo "🔍 Testing DNS resolution for '$AURORA_CUSTOM_ENDPOINT'..."
if command -v nslookup &> /dev/null; then
    if nslookup "$AURORA_CUSTOM_ENDPOINT" > /dev/null 2>&1; then
        RESOLVED_IP=$(nslookup "$AURORA_CUSTOM_ENDPOINT" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
        if [ -z "$RESOLVED_IP" ]; then
            RESOLVED_IP=$(getent hosts "$AURORA_CUSTOM_ENDPOINT" 2>/dev/null | awk '{print $1}')
        fi
        echo "✅ DNS resolution OK: $AURORA_CUSTOM_ENDPOINT -> ${RESOLVED_IP:-resolved}"
    else
        echo "⚠️  Warning: Cannot resolve '$AURORA_CUSTOM_ENDPOINT'"
        echo "   Please ensure DNS is configured (e.g. /etc/hosts or Route 53 CNAME)"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
elif command -v getent &> /dev/null; then
    if getent hosts "$AURORA_CUSTOM_ENDPOINT" > /dev/null 2>&1; then
        RESOLVED_IP=$(getent hosts "$AURORA_CUSTOM_ENDPOINT" | awk '{print $1}')
        echo "✅ DNS resolution OK: $AURORA_CUSTOM_ENDPOINT -> $RESOLVED_IP"
    else
        echo "⚠️  Warning: Cannot resolve '$AURORA_CUSTOM_ENDPOINT'"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "⚠️  nslookup/getent not found, skipping DNS check"
fi

echo ""
echo "🔍 Testing network connectivity to '$AURORA_CUSTOM_ENDPOINT:3306'..."
if command -v nc &> /dev/null; then
    if nc -z -w5 "$AURORA_CUSTOM_ENDPOINT" 3306 2>/dev/null; then
        echo "✅ Network connectivity OK"
    else
        echo "⚠️  Warning: Cannot connect to $AURORA_CUSTOM_ENDPOINT:3306"
        echo "   Please check:"
        echo "   - DNS resolution is correct"
        echo "   - Security group allows inbound traffic on port 3306"
        echo "   - Aurora cluster is running"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "⚠️  nc command not found, skipping connectivity test"
fi

echo ""
echo "🚀 Starting Spring Boot application..."
echo ""

# Start application
JAR_FILE=${JAR_FILE:-$(ls -t target/*.jar 2>/dev/null | head -1)}

if [ -z "$JAR_FILE" ]; then
    echo "❌ Error: No JAR file found in target/"
    echo ""
    echo "Please build the project first:"
    echo "  mvn clean package -DskipTests"
    echo ""
    exit 1
fi

echo "📦 Using JAR: $JAR_FILE"
echo ""

# Auto-detect JAVA_HOME from JAR filename
source "$(dirname "$0")/detect-java.sh"
detect_java_from_jar "$JAR_FILE"
echo ""

# Archive old logs before starting
LOG_DIR="logs"
ARCHIVE_DIR="$LOG_DIR/archive"

if [ -d "$LOG_DIR" ]; then
    if ls "$LOG_DIR"/*.log 1> /dev/null 2>&1; then
        echo "📁 Archiving old logs..."
        mkdir -p "$ARCHIVE_DIR"
        mv "$LOG_DIR"/*.log "$ARCHIVE_DIR/" 2>/dev/null
        echo "✅ Old logs moved to $ARCHIVE_DIR/"
        echo ""
    fi
fi

# Start application
$JAVA_CMD -jar "$JAR_FILE" --spring.profiles.active="$PROFILE"
