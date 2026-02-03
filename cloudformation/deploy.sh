#!/bin/bash
set -e

#==============================================================================
# Aurora MySQL Blue/Green Test Environment Deployment Script
#==============================================================================

STACK_NAME="${STACK_NAME:-aurora-bg-test}"
REGION="${AWS_REGION:-us-east-1}"
DB_PASSWORD="${DB_PASSWORD:-}"
INSTANCE_CLASS="${INSTANCE_CLASS:-db.t3.medium}"

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
    echo "  deploy              Deploy Aurora clusters"
    echo "  create-bluegreen    Create Blue/Green deployments for both clusters"
    echo "  status              Show deployment status"
    echo "  outputs             Show stack outputs"
    echo "  delete              Delete everything"
    echo ""
    echo "Environment Variables:"
    echo "  STACK_NAME          Stack name (default: aurora-bg-test)"
    echo "  AWS_REGION          AWS region (default: us-east-1)"
    echo "  DB_PASSWORD         Database password (required for deploy)"
    echo "  INSTANCE_CLASS      Instance class (default: db.t3.medium)"
    echo ""
    echo "Examples:"
    echo "  DB_PASSWORD=MyPassword123 $0 deploy"
    echo "  $0 create-bluegreen"
    echo "  $0 status"
    echo "  $0 delete"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI is not installed${NC}"
        exit 1
    fi
}

deploy_stack() {
    print_header
    echo -e "${GREEN}Deploying Aurora clusters...${NC}"
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: DB_PASSWORD is required${NC}"
        echo "Usage: DB_PASSWORD=YourPassword $0 deploy"
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
    echo ""

    aws cloudformation deploy \
        --stack-name "$STACK_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameter-overrides \
            EnvironmentName="$STACK_NAME" \
            DBPassword="$DB_PASSWORD" \
            InstanceClass="$INSTANCE_CLASS" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo ""
    echo -e "${GREEN}✅ Stack deployed successfully!${NC}"
    echo ""
    show_outputs
}

create_bluegreen() {
    print_header
    echo -e "${GREEN}Creating Blue/Green deployments...${NC}"
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
        echo -e "${GREEN}  ✅ $CLUSTER is available${NC}"
    done

    echo ""

    # Create Blue/Green deployment for Cluster 1
    echo "Creating Blue/Green deployment for $CLUSTER1..."
    BG1_ID=$(aws rds create-blue-green-deployment \
        --blue-green-deployment-name "${STACK_NAME}-bg-1" \
        --source "arn:aws:rds:${REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER1}" \
        --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
        --output text \
        --region "$REGION")
    echo -e "${GREEN}  ✅ Created: $BG1_ID${NC}"

    # Create Blue/Green deployment for Cluster 2
    echo "Creating Blue/Green deployment for $CLUSTER2..."
    BG2_ID=$(aws rds create-blue-green-deployment \
        --blue-green-deployment-name "${STACK_NAME}-bg-2" \
        --source "arn:aws:rds:${REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER2}" \
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
    echo -e "${YELLOW}Note: It takes 10-30 minutes for Blue/Green deployments to be ready.${NC}"
    echo "Run '$0 status' to check progress."
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
