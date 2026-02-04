#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Spring Boot MySQL Test - Aurora Configuration               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check environment parameter
ENV=${1:-prod}

# Check required environment variables
if [ -z "$AURORA_CLUSTER_ENDPOINT" ]; then
    echo "❌ Error: AURORA_CLUSTER_ENDPOINT is not set"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export AURORA_CLUSTER_ENDPOINT=\"database-1.cluster-xxxxx.us-east-1.rds.amazonaws.com\""
    echo "  export AURORA_DATABASE=\"testdb\""
    echo "  export AURORA_USERNAME=\"admin\""
    echo "  export AURORA_PASSWORD=\"your-password\""
    echo ""
    echo "Or create a .env file and source it:"
    echo "  source .env"
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
echo "📋 Aurora Configuration:"
echo "   Cluster Endpoint: $AURORA_CLUSTER_ENDPOINT"
echo "   Database: ${AURORA_DATABASE:-testdb}"
echo "   Username: ${AURORA_USERNAME:-admin}"
echo "   Password: ********"
if [ -n "$JDBC_PARAMS" ]; then
    echo "   JDBC Params: $JDBC_PARAMS"
fi
echo ""

# Select configuration based on environment
if [ "$ENV" = "dev" ]; then
    echo "🔧 Environment: Development"
    echo "   Profile: aurora-dev"
    # Only set default if not already set
    if [ -z "$WRAPPER_LOG_LEVEL" ]; then
        export WRAPPER_LOG_LEVEL="FINEST"
    fi
    echo "   Log Level: $WRAPPER_LOG_LEVEL"
    echo "   Plugins: initialConnection, auroraConnectionTracker, failover2, efm2, bg"
    PROFILE="aurora-dev"
elif [ "$ENV" = "prod" ]; then
    echo "🚀 Environment: Production"
    echo "   Profile: aurora-prod"
    # Only set default if not already set
    if [ -z "$WRAPPER_LOG_LEVEL" ]; then
        export WRAPPER_LOG_LEVEL="FINE"
    fi
    echo "   Log Level: $WRAPPER_LOG_LEVEL"
    echo "   Plugins: initialConnection, auroraConnectionTracker, failover2, efm2, bg"
    PROFILE="aurora-prod"
else
    echo "❌ Error: Invalid environment '$ENV'"
    echo ""
    echo "Usage: $0 [prod|dev]"
    echo "  prod - Production environment (INFO logs)"
    echo "  dev  - Development environment (FINE logs)"
    echo ""
    echo "Tip: You can override log level with:"
    echo "  export WRAPPER_LOG_LEVEL=FINE"
    echo "  $0 prod"
    echo ""
    exit 1
fi

echo ""
echo "🔍 Testing network connectivity..."

# Test network connectivity
if command -v nc &> /dev/null; then
    if nc -z -w5 "$AURORA_CLUSTER_ENDPOINT" 3306 2>/dev/null; then
        echo "✅ Network connectivity OK"
    else
        echo "⚠️  Warning: Cannot connect to $AURORA_CLUSTER_ENDPOINT:3306"
        echo "   Please check:"
        echo "   - Security group allows inbound traffic on port 3306"
        echo "   - VPC/Network configuration"
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
JAR_FILE=$(ls -t target/*.jar 2>/dev/null | head -1)

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

# Start application
java -jar "$JAR_FILE" --spring.profiles.active="$PROFILE"
