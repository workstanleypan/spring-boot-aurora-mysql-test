#!/bin/bash
set -e

#==============================================================================
# Aurora MySQL Blue/Green Test Environment Deployment Script
#==============================================================================

STACK_NAME="${STACK_NAME:-aurora-bg-test}"
REGION="${AWS_REGION:-us-east-1}"
DB_PASSWORD="${DB_PASSWORD:-}"
INSTANCE_CLASS="${INSTANCE_CLASS:-db.t3.medium}"
ENGINE_VERSION="${ENGINE_VERSION:-8.0.mysql_aurora.3.04.2}"
TARGET_ENGINE_VERSION="${TARGET_ENGINE_VERSION:-8.0.mysql_aurora.3.10.0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Aurora MySQL Blue/Green Test Environment                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy              Deploy Aurora clusters (Blue)"
    echo "  create-bluegreen    Create Blue/Green deployments with version upgrade"
    echo "  status              Show deployment status"
    echo "  outputs             Show stack outputs"
    echo "  delete              Delete everything"
    echo ""
    echo "Environment Variables:"
    echo "  STACK_NAME              Stack name (default: aurora-bg-test)"
    echo "  AWS_REGION              AWS region (default: us-east-1)"
    echo "  DB_PASSWORD             Database password (required for deploy)"
    echo "  INSTANCE_CLASS          Instance class (default: db.t3.medium)"
    echo "  ENGINE_VERSION          Blue cluster version (default: 8.0.mysql_aurora.3.04.2)"
    echo "  TARGET_ENGINE_VERSION   Green cluster version (default: 8.0.mysql_aurora.3.10.0)"
    echo ""
    echo "Examples:"
    echo "  # Deploy Blue clusters with 3.04.2"
    echo "  DB_PASSWORD=MyPassword123 ./deploy.sh deploy"
    echo ""
    echo "  # Create Blue/Green with upgrade to 3.10.0 LTS"
    echo "  ./deploy.sh create-bluegreen"
    echo ""
    echo "  # Custom versions"
    echo "  ENGINE_VERSION=8.0.mysql_aurora.3.08.1 TARGET_ENGINE_VERSION=8.0.mysql_aurora.3.10.1 ./deploy.sh deploy"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI is not installed${NC}"
        exit 1
    fi
}

deploy_stack() {
    print_header
    echo -e "${GREEN}Deploying Aurora clusters (Blue)...${NC}"
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: DB_PASSWORD is required${NC}"
        echo "Usage: DB_PASSWORD=YourPassword ./deploy.sh deploy"
        exit 1
    fi

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEMPLATE_FILE="$SCRIPT_DIR/aurora-bluegreen-test.yaml"

    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo -e "${RED}Error: Template file not found: $TEMPLATE_FILE${NC}"
        exit 1
    fi

    echo "Stack Name: $STACK_NAME"
    echo "Region: $REGION"
    echo "Instance Class: $INSTANCE_CLASS"
    echo "Blue Engine Version: $ENGINE_VERSION"
    echo "Target Green Version: $TARGET_ENGINE_VERSION"
    echo ""

    aws cloudformation deploy \
        --stack-name "$STACK_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameter-overrides \
            EnvironmentName="$STACK_NAME" \
            DBPassword="$DB_PASSWORD" \
            InstanceClass="$INSTANCE_CLASS" \
            EngineVersion="$ENGINE_VERSION" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo ""
    echo -e "${GREEN}✅ Blue clusters deployed successfully!${NC}"
    echo ""
    show_outputs
}

create_bluegreen() {
    print_header
    echo -e "${GREEN}Creating Blue/Green deployments with version upgrade...${NC}"
    echo ""
    echo "Blue Version: $ENGINE_VERSION"
    echo "Green Version (Target): $TARGET_ENGINE_VERSION"
    echo ""

    # Get cluster identifiers
    CLUSTER1="${STACK_NAME}-cluster-1"
    CLUSTER2="${STACK_NAME}-cluster-2"

    # Check if clusters exist and are available
    for CLUSTER in "$CLUSTER1" "$CLUSTER2"; do
        echo "Checking cluster: $CLUSTER"
        STATUS=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].Status' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "not-found")
        
        if [ "$STATUS" != "available" ]; then
            echo -e "${RED}Error: Cluster $CLUSTER is not available (status: $STATUS)${NC}"
            exit 1
        fi
        
        CURRENT_VERSION=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].EngineVersion' \
            --output text \
            --region "$REGION")
        echo -e "${GREEN}  ✅ $CLUSTER is available (version: $CURRENT_VERSION)${NC}"
    done

    echo ""

    # Get AWS account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Create Blue/Green deployment for Cluster 1 with target version
    echo "Creating Blue/Green deployment for $CLUSTER1..."
    echo "  Source: $ENGINE_VERSION -> Target: $TARGET_ENGINE_VERSION"
    BG1_ID=$(aws rds create-blue-green-deployment \
        --blue-green-deployment-name "${STACK_NAME}-bg-1" \
        --source "arn:aws:rds:${REGION}:${ACCOUNT_ID}:cluster:${CLUSTER1}" \
        --target-engine-version "$TARGET_ENGINE_VERSION" \
        --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
        --output text \
        --region "$REGION")
    echo -e "${GREEN}  ✅ Created: $BG1_ID${NC}"

    # Create Blue/Green deployment for Cluster 2 with target version
    echo "Creating Blue/Green deployment for $CLUSTER2..."
    echo "  Source: $ENGINE_VERSION -> Target: $TARGET_ENGINE_VERSION"
    BG2_ID=$(aws rds create-blue-green-deployment \
        --blue-green-deployment-name "${STACK_NAME}-bg-2" \
        --source "arn:aws:rds:${REGION}:${ACCOUNT_ID}:cluster:${CLUSTER2}" \
        --target-engine-version "$TARGET_ENGINE_VERSION" \
        --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
        --output text \
        --region "$REGION")
    echo -e "${GREEN}  ✅ Created: $BG2_ID${NC}"

    echo ""
    echo -e "${GREEN}✅ Blue/Green deployments created!${NC}"
    echo ""
    echo "Blue/Green Deployment IDs:"
    echo "  Cluster 1: $BG1_ID"
    echo "  Cluster 2: $BG2_ID"
    echo ""
    echo "Version Upgrade:"
    echo "  Blue (Source):  $ENGINE_VERSION"
    echo "  Green (Target): $TARGET_ENGINE_VERSION"
    echo ""
    echo -e "${YELLOW}Note: It takes 10-30 minutes for Blue/Green deployments to be ready.${NC}"
    echo "Run './deploy.sh status' to check progress."
}

show_status() {
    print_header
    echo -e "${GREEN}Deployment Status${NC}"
    echo ""

    # Stack status
    echo "CloudFormation Stack:"
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].StackStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "NOT_FOUND")
    echo "  Status: $STACK_STATUS"
    echo ""

    # Cluster status
    echo "Aurora Clusters:"
    for CLUSTER in "${STACK_NAME}-cluster-1" "${STACK_NAME}-cluster-2"; do
        STATUS=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].Status' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "not-found")
        echo "  $CLUSTER: $STATUS"
    done
    echo ""

    # Blue/Green deployment status
    echo "Blue/Green Deployments:"
    aws rds describe-blue-green-deployments \
        --query 'BlueGreenDeployments[?contains(BlueGreenDeploymentName, `'"$STACK_NAME"'`)].[BlueGreenDeploymentName, Status]' \
        --output table \
        --region "$REGION" 2>/dev/null || echo "  No Blue/Green deployments found"
}

show_outputs() {
    echo -e "${GREEN}Stack Outputs:${NC}"
    echo ""
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[*].[OutputKey, OutputValue]' \
        --output table \
        --region "$REGION"
}

delete_all() {
    print_header
    echo -e "${YELLOW}⚠️  This will delete all resources!${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi

    echo ""
    echo "Deleting Blue/Green deployments..."
    
    # Delete Blue/Green deployments first
    BG_IDS=$(aws rds describe-blue-green-deployments \
        --query 'BlueGreenDeployments[?contains(BlueGreenDeploymentName, `'"$STACK_NAME"'`)].BlueGreenDeploymentIdentifier' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    for BG_ID in $BG_IDS; do
        if [ -n "$BG_ID" ]; then
            echo "  Deleting $BG_ID..."
            aws rds delete-blue-green-deployment \
                --blue-green-deployment-identifier "$BG_ID" \
                --delete-target \
                --region "$REGION" 2>/dev/null || true
        fi
    done

    echo ""
    echo "Waiting for Blue/Green deployments to be deleted..."
    sleep 30

    echo ""
    echo "Deleting CloudFormation stack..."
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION"

    echo ""
    echo "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION" || true

    echo ""
    echo -e "${GREEN}✅ All resources deleted!${NC}"
}

# Main
check_aws_cli

case "${1:-}" in
    deploy)
        deploy_stack
        ;;
    create-bluegreen)
        create_bluegreen
        ;;
    status)
        show_status
        ;;
    outputs)
        show_outputs
        ;;
    delete)
        delete_all
        ;;
    *)
        usage
        exit 1
        ;;
esac
