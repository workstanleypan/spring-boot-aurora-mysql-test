#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Spring Boot MySQL Test - RDS Configuration                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check environment parameter
ENV=${1:-prod}

# Check required environment variables
if [ -z "$RDS_ENDPOINT" ]; then
    echo "❌ Error: RDS_ENDPOINT is not set"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export RDS_ENDPOINT=\"database-1.xxxxx.us-east-1.rds.amazonaws.com\""
    echo "  export RDS_DATABASE=\"testdb\""
    echo "  export RDS_USERNAME=\"admin\""
    echo "  export RDS_PASSWORD=\"your-password\""
    echo ""
    echo "Or create a .env file and source it:"
    echo "  source .env.rds"
    echo ""
    exit 1
fi

if [ -z "$RDS_PASSWORD" ]; then
    echo "❌ Error: RDS_PASSWORD is not set"
    echo ""
    echo "Please set: export RDS_PASSWORD=\"your-password\""
    echo ""
    exit 1
fi

# Display configuration
echo "📋 RDS Configuration:"
echo "   Endpoint: $RDS_ENDPOINT"
echo "   Database: ${RDS_DATABASE:-testdb}"
echo "   Username: ${RDS_USERNAME:-admin}"
echo "   Password: ********"
if [ -n "$JDBC_PARAMS" ]; then
    echo "   JDBC Params: $JDBC_PARAMS"
fi
echo ""

# Select configuration based on environment
if [ "$ENV" = "dev" ]; then
    echo "🔧 Environment: Development"
    echo "   Profile: rds-dev"
    # Only set default if not already set
    if [ -z "$WRAPPER_LOG_LEVEL" ]; then
        export WRAPPER_LOG_LEVEL="FINE"
    fi
    echo "   Log Level: $WRAPPER_LOG_LEVEL"
    echo "   Plugins: auroraConnectionTracker, failover2, efm2, bg"
    PROFILE="rds-dev"
elif [ "$ENV" = "prod" ]; then
    echo "🚀 Environment: Production"
    echo "   Profile: rds-prod"
    # Only set default if not already set
    if [ -z "$WRAPPER_LOG_LEVEL" ]; then
        export WRAPPER_LOG_LEVEL="INFO"
    fi
    echo "   Log Level: $WRAPPER_LOG_LEVEL"
    echo "   Plugins: auroraConnectionTracker, failover2, efm2, bg"
    PROFILE="rds-prod"
elif [ "$ENV" = "standard" ]; then
    echo "📦 Environment: Standard (No AWS Wrapper)"
    echo "   Profile: rds-standard"
    echo "   Driver: MySQL Connector/J"
    echo "   No AWS Wrapper plugins"
    PROFILE="rds-standard"
else
    echo "❌ Error: Invalid environment '$ENV'"
    echo ""
    echo "Usage: $0 [prod|dev|standard]"
    echo "  prod     - Production environment (INFO logs, AWS Wrapper)"
    echo "  dev      - Development environment (FINE logs, AWS Wrapper)"
    echo "  standard - Standard MySQL driver (no AWS Wrapper)"
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
    if nc -z -w5 "$RDS_ENDPOINT" 3306 2>/dev/null; then
        echo "✅ Network connectivity OK"
    else
        echo "⚠️  Warning: Cannot connect to $RDS_ENDPOINT:3306"
        echo "   Please check:"
        echo "   - Security group allows inbound traffic on port 3306"
        echo "   - VPC/Network configuration"
        echo "   - RDS instance is running"
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

# Archive old logs before starting
LOG_DIR="logs"
ARCHIVE_DIR="$LOG_DIR/archive"

if [ -d "$LOG_DIR" ]; then
    # Check if there are any log files to archive
    if ls "$LOG_DIR"/*.log 1> /dev/null 2>&1; then
        echo "📁 Archiving old logs..."
        mkdir -p "$ARCHIVE_DIR"
        mv "$LOG_DIR"/*.log "$ARCHIVE_DIR/" 2>/dev/null
        echo "✅ Old logs moved to $ARCHIVE_DIR/"
        echo ""
    fi
fi

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

java -jar "$JAR_FILE" --spring.profiles.active="$PROFILE"
