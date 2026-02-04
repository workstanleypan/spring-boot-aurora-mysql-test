#!/bin/bash
set -e

#==============================================================================
# Aurora MySQL Blue/Green Test Environment
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#==============================================================================
# Load configuration
#==============================================================================
load_config() {
    # Prefer config.local.env
    if [ -f "$SCRIPT_DIR/config.local.env" ]; then
        echo -e "${CYAN}Loading: config.local.env${NC}"
        set -a
        source "$SCRIPT_DIR/config.local.env"
        set +a
    elif [ -f "$SCRIPT_DIR/config.env" ]; then
        echo -e "${CYAN}Loading: config.env${NC}"
        set -a
        source "$SCRIPT_DIR/config.env"
        set +a
    fi

    # Set defaults
    STACK_NAME="${STACK_NAME:-aurora-bg-test}"
    REGION="${AWS_REGION:-${REGION:-us-east-1}}"
    USE_EXISTING_VPC="${USE_EXISTING_VPC:-true}"
    VPC_ID="${VPC_ID:-}"
    SUBNET_IDS="${SUBNET_IDS:-}"
    DB_USERNAME="${DB_USERNAME:-admin}"
    DB_PASSWORD="${DB_PASSWORD:-}"
    DB_NAME="${DB_NAME:-testdb}"
    INSTANCE_CLASS="${INSTANCE_CLASS:-db.t3.medium}"
    
    # Cluster configuration
    CLUSTER_COUNT="${CLUSTER_COUNT:-1}"
    INSTANCES_PER_CLUSTER="${INSTANCES_PER_CLUSTER:-2}"
    ENGINE_VERSION="${ENGINE_VERSION:-8.0.mysql_aurora.3.04.2}"
    TARGET_VERSION="${TARGET_VERSION:-8.0.mysql_aurora.3.10.3}"
}

#==============================================================================
# Help
#==============================================================================
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy              Deploy Aurora clusters"
    echo "  init-db             Initialize database (create test users)"
    echo "  create-bluegreen    Create Blue/Green deployments"
    echo "  status              Show status"
    echo "  outputs             Show stack outputs"
    echo "  delete              Delete everything"
    echo "  show-config         Show current configuration"
    echo ""
    echo "Workflow:"
    echo "  1. ./deploy.sh deploy           # Create clusters"
    echo "  2. ./deploy.sh init-db          # Create test users"
    echo "  3. ./deploy.sh create-bluegreen # Start Blue/Green"
    echo ""
    echo "Examples:"
    echo "  DB_PASSWORD=MyPass ./deploy.sh deploy"
    echo "  CLUSTER_COUNT=2 DB_PASSWORD=MyPass ./deploy.sh deploy"
}

show_config() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Current Configuration                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Stack:           $STACK_NAME"
    echo "Region:          $REGION"
    echo ""
    echo "Clusters:        $CLUSTER_COUNT"
    echo "Instances/Each:  $INSTANCES_PER_CLUSTER"
    echo "Engine Version:  $ENGINE_VERSION"
    echo "Target Version:  $TARGET_VERSION"
    echo "Instance Class:  $INSTANCE_CLASS"
    echo ""
    echo "VPC:             ${VPC_ID:-<auto-detect default>}"
    echo "Database:        $DB_NAME"
    echo "Username:        $DB_USERNAME"
    echo "Password:        ${DB_PASSWORD:+****}"
    echo ""
    
    local total=$((CLUSTER_COUNT * INSTANCES_PER_CLUSTER))
    echo "Total instances: $total"
    echo ""
}

#==============================================================================
# Deploy
#==============================================================================
deploy_stack() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Deploying Aurora MySQL Clusters                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: DB_PASSWORD is required${NC}"
        exit 1
    fi

    # Validate parameters
    if [ "$CLUSTER_COUNT" -lt 1 ] || [ "$CLUSTER_COUNT" -gt 3 ]; then
        echo -e "${RED}Error: CLUSTER_COUNT must be 1-3${NC}"
        exit 1
    fi

    TEMPLATE_FILE="$SCRIPT_DIR/aurora-bluegreen-test.yaml"

    # Auto-detect VPC and subnets
    if [ "$USE_EXISTING_VPC" = "true" ]; then
        if [ -z "$VPC_ID" ]; then
            echo "Auto-detecting default VPC..."
            VPC_ID=$(aws ec2 describe-vpcs \
                --filters "Name=is-default,Values=true" \
                --query 'Vpcs[0].VpcId' \
                --output text \
                --region "$REGION" 2>/dev/null)
            
            if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
                echo -e "${RED}Error: No default VPC found${NC}"
                exit 1
            fi
            echo "  Found: $VPC_ID"
        fi

        # Get VPC CIDR
        if [ -z "$VPC_CIDR" ]; then
            VPC_CIDR=$(aws ec2 describe-vpcs \
                --vpc-ids "$VPC_ID" \
                --query 'Vpcs[0].CidrBlock' \
                --output text \
                --region "$REGION" 2>/dev/null)
            echo "  VPC CIDR: $VPC_CIDR"
        fi

        if [ -z "$SUBNET_IDS" ]; then
            echo "Auto-detecting subnets..."
            SUBNET_IDS=$(aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=$VPC_ID" \
                --query 'Subnets[*].SubnetId' \
                --output text \
                --region "$REGION" 2>/dev/null | tr '\t' ',')
            SUBNET_IDS=$(echo "$SUBNET_IDS" | cut -d',' -f1,2)
            echo "  Found: $SUBNET_IDS"
        fi
    else
        VPC_CIDR="10.0.0.0/16"
    fi

    echo ""
    echo "Deploying:"
    echo "  Clusters:     $CLUSTER_COUNT"
    echo "  Instances:    $INSTANCES_PER_CLUSTER per cluster"
    echo "  Version:      $ENGINE_VERSION"
    echo "  VPC:          $VPC_ID"
    echo "  VPC CIDR:     $VPC_CIDR (security group)"
    echo "  Public IP:    DISABLED"
    echo ""

    aws cloudformation deploy \
        --stack-name "$STACK_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameter-overrides \
            EnvironmentName="$STACK_NAME" \
            DBUsername="$DB_USERNAME" \
            DBPassword="$DB_PASSWORD" \
            DBName="$DB_NAME" \
            ClusterCount="$CLUSTER_COUNT" \
            InstancesPerCluster="$INSTANCES_PER_CLUSTER" \
            EngineVersion="$ENGINE_VERSION" \
            InstanceClass="$INSTANCE_CLASS" \
            UseExistingVpc="$USE_EXISTING_VPC" \
            VpcId="$VPC_ID" \
            VpcCidr="$VPC_CIDR" \
            SubnetIds="$SUBNET_IDS" \
        --region "$REGION" \
        --no-fail-on-empty-changeset

    echo ""
    echo -e "${GREEN}✅ Deployment complete!${NC}"
    echo ""
    show_outputs
}

#==============================================================================
# Initialize database
#==============================================================================
init_db() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Initializing Database                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Get cluster endpoint
    ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='Cluster1Endpoint'].OutputValue" \
        --output text \
        --region "$REGION" 2>/dev/null)

    if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "None" ]; then
        echo -e "${RED}Error: Cannot find cluster endpoint. Is the stack deployed?${NC}"
        exit 1
    fi

    echo "Cluster Endpoint: $ENDPOINT"
    echo "Database: $DB_NAME"
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: DB_PASSWORD is required${NC}"
        exit 1
    fi

    SQL_FILE="$SCRIPT_DIR/init-database.sql"
    
    echo "Creating test users and tables..."
    echo ""
    
    mysql -h "$ENDPOINT" -u "$DB_USERNAME" -p"$DB_PASSWORD" < "$SQL_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ Database initialized!${NC}"
        echo ""
        echo "Test users created:"
        echo "  - testuser1 / testuser"
        echo "  - testuser2 / testuser"
        echo "  - testuser3 / testuser"
        echo ""
        echo "Permissions: SELECT on mysql.*, ALL on testdb.*"
    else
        echo -e "${RED}Failed to initialize database${NC}"
        echo "Make sure you can connect to the cluster from this machine."
        exit 1
    fi
}

#==============================================================================
# Blue/Green deployment
#==============================================================================
create_bluegreen() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Creating Blue/Green Deployments                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Target Version: $TARGET_VERSION"
    echo ""

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    for i in $(seq 1 $CLUSTER_COUNT); do
        CLUSTER="${STACK_NAME}-cluster-$i"
        
        STATUS=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].Status' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "not-found")
        
        if [ "$STATUS" != "available" ]; then
            echo -e "${YELLOW}Skipping $CLUSTER (status: $STATUS)${NC}"
            continue
        fi

        CURRENT=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].EngineVersion' \
            --output text \
            --region "$REGION")

        echo "Creating Blue/Green for $CLUSTER"
        echo "  $CURRENT -> $TARGET_VERSION"

        BG_ID=$(aws rds create-blue-green-deployment \
            --blue-green-deployment-name "${STACK_NAME}-bg-$i" \
            --source "arn:aws:rds:${REGION}:${ACCOUNT_ID}:cluster:${CLUSTER}" \
            --target-engine-version "$TARGET_VERSION" \
            --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
            --output text \
            --region "$REGION" 2>&1) || {
            echo -e "${RED}  Failed: $BG_ID${NC}"
            continue
        }
        
        echo -e "${GREEN}  ✅ Created: $BG_ID${NC}"
    done

    echo ""
    echo -e "${YELLOW}Blue/Green deployments take 10-30 minutes.${NC}"
}

#==============================================================================
# Status
#==============================================================================
show_status() {
    load_config
    
    echo ""
    echo "Stack: $STACK_NAME"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].StackStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "NOT_FOUND"

    echo ""
    echo "Clusters:"
    for i in $(seq 1 3); do
        CLUSTER="${STACK_NAME}-cluster-$i"
        INFO=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].[Status, EngineVersion]' \
            --output text \
            --region "$REGION" 2>/dev/null) || continue
        echo "  $CLUSTER: $INFO"
    done

    echo ""
    echo "Blue/Green:"
    aws rds describe-blue-green-deployments \
        --query "BlueGreenDeployments[?contains(BlueGreenDeploymentName, \`$STACK_NAME\`)].[BlueGreenDeploymentName, Status]" \
        --output table \
        --region "$REGION" 2>/dev/null || echo "  None"
}

show_outputs() {
    load_config
    
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[*].[OutputKey, OutputValue]' \
        --output table \
        --region "$REGION" 2>/dev/null || echo "Stack not found"
}

#==============================================================================
# Delete
#==============================================================================
delete_all() {
    load_config
    
    echo -e "${YELLOW}⚠️  Delete all resources for: $STACK_NAME${NC}"
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    echo "Deleting Blue/Green deployments..."
    BG_IDS=$(aws rds describe-blue-green-deployments \
        --query "BlueGreenDeployments[?contains(BlueGreenDeploymentName, \`$STACK_NAME\`)].BlueGreenDeploymentIdentifier" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    for BG_ID in $BG_IDS; do
        [ -n "$BG_ID" ] && aws rds delete-blue-green-deployment \
            --blue-green-deployment-identifier "$BG_ID" \
            --delete-target \
            --region "$REGION" 2>/dev/null || true
    done

    echo "Deleting CloudFormation stack..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" || true

    echo -e "${GREEN}✅ Deleted!${NC}"
}

#==============================================================================
# Main entry
#==============================================================================
case "${1:-}" in
    deploy) deploy_stack ;;
    init-db) init_db ;;
    create-bluegreen) create_bluegreen ;;
    status) show_status ;;
    outputs) show_outputs ;;
    delete) delete_all ;;
    show-config) show_config ;;
    *) usage; exit 1 ;;
esac
