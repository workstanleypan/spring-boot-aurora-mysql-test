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
    # Save command line environment variables (they take priority)
    local CLI_DB_PASSWORD="${DB_PASSWORD:-}"
    local CLI_STACK_NAME="${STACK_NAME:-}"
    local CLI_REGION="${REGION:-}"
    local CLI_CLUSTER_COUNT="${CLUSTER_COUNT:-}"
    local CLI_INSTANCES_PER_CLUSTER="${INSTANCES_PER_CLUSTER:-}"
    local CLI_ENGINE_VERSION="${ENGINE_VERSION:-}"
    local CLI_TARGET_VERSION="${TARGET_VERSION:-}"
    local CLI_NEW_STACK="${NEW_STACK:-}"
    
    # Load config file
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

    # Command line variables override config file
    [ -n "$CLI_DB_PASSWORD" ] && DB_PASSWORD="$CLI_DB_PASSWORD"
    [ -n "$CLI_STACK_NAME" ] && STACK_NAME="$CLI_STACK_NAME"
    [ -n "$CLI_REGION" ] && REGION="$CLI_REGION"
    [ -n "$CLI_CLUSTER_COUNT" ] && CLUSTER_COUNT="$CLI_CLUSTER_COUNT"
    [ -n "$CLI_INSTANCES_PER_CLUSTER" ] && INSTANCES_PER_CLUSTER="$CLI_INSTANCES_PER_CLUSTER"
    [ -n "$CLI_ENGINE_VERSION" ] && ENGINE_VERSION="$CLI_ENGINE_VERSION"
    [ -n "$CLI_TARGET_VERSION" ] && TARGET_VERSION="$CLI_TARGET_VERSION"
    [ -n "$CLI_NEW_STACK" ] && NEW_STACK="$CLI_NEW_STACK"

    # Set defaults for any remaining empty values
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
    
    # New stack mode: always create new cluster (default: true)
    NEW_STACK="${NEW_STACK:-true}"
}

#==============================================================================
# Help
#==============================================================================
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy              Deploy Aurora clusters (creates NEW stack by default)"
    echo "  init-db             Initialize database (create test users)"
    echo "  create-bluegreen    Create Blue/Green deployments"
    echo "  status              Show status"
    echo "  outputs             Show stack outputs"
    echo "  list                List all aurora-bg-test stacks"
    echo "  delete              Delete everything"
    echo "  show-config         Show current configuration"
    echo ""
    echo "Workflow:"
    echo "  1. ./deploy.sh deploy           # Create NEW cluster (with timestamp)"
    echo "  2. ./deploy.sh init-db          # Create test users"
    echo "  3. ./deploy.sh create-bluegreen # Start Blue/Green"
    echo ""
    echo "Examples:"
    echo "  # Create new cluster (default behavior)"
    echo "  DB_PASSWORD=MyPass ./deploy.sh deploy"
    echo ""
    echo "  # Update existing cluster (set NEW_STACK=false)"
    echo "  NEW_STACK=false STACK_NAME=aurora-bg-test-0204 DB_PASSWORD=MyPass ./deploy.sh deploy"
    echo ""
    echo "  # Use specific stack for other commands"
    echo "  STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh init-db"
    echo "  STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh outputs"
    echo ""
    echo "Environment Variables:"
    echo "  NEW_STACK=true|false   Create new stack (default: true)"
    echo "  STACK_NAME=xxx         Stack name (auto-generated if NEW_STACK=true)"
    echo "  DB_PASSWORD=xxx        Database password (required)"
    echo "  CLUSTER_COUNT=1-3      Number of clusters"
}

show_config() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Current Configuration                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Stack:           $STACK_NAME"
    echo "New Stack Mode:  $NEW_STACK"
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
    
    # Generate unique stack name with timestamp if NEW_STACK=true
    if [ "$NEW_STACK" = "true" ]; then
        TIMESTAMP=$(date +%m%d-%H%M)
        STACK_NAME="aurora-bg-test-${TIMESTAMP}"
        echo -e "${GREEN}Creating NEW stack: $STACK_NAME${NC}"
    fi
    
    # Save stack name to file for subsequent commands
    echo "$STACK_NAME" > "$SCRIPT_DIR/.last-stack-name"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Deploying Aurora MySQL Clusters                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Stack Name: $STACK_NAME${NC}"
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
    echo "  Stack:        $STACK_NAME"
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
    echo -e "${YELLOW}📝 To use this stack for subsequent commands:${NC}"
    echo "   export STACK_NAME=$STACK_NAME"
    echo "   # or"
    echo "   STACK_NAME=$STACK_NAME ./deploy.sh init-db"
    echo ""
    show_outputs
}

#==============================================================================
# Initialize database
#==============================================================================
init_db() {
    load_config
    resolve_stack_name
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Initializing Database                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Stack Name: $STACK_NAME${NC}"
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: DB_PASSWORD is required${NC}"
        exit 1
    fi

    SQL_FILE="$SCRIPT_DIR/init-database.sql"
    
    # Initialize all clusters in the stack by querying RDS directly
    local success_count=0
    local fail_count=0
    
    for i in $(seq 1 3); do
        CLUSTER_ID="${STACK_NAME}-cluster-$i"
        
        # Get endpoint directly from RDS (more reliable than CloudFormation outputs)
        ENDPOINT=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER_ID" \
            --query 'DBClusters[0].Endpoint' \
            --output text \
            --region "$REGION" 2>/dev/null)

        if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "None" ]; then
            continue
        fi

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Cluster $i: $ENDPOINT"
        echo "Database: $DB_NAME"
        echo ""
        
        echo "Creating test users and tables..."
        
        if mysql -h "$ENDPOINT" -u "$DB_USERNAME" -p"$DB_PASSWORD" < "$SQL_FILE" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Cluster $i initialized!${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${RED}  ❌ Cluster $i failed${NC}"
            fail_count=$((fail_count + 1))
        fi
        echo ""
    done
    
    if [ $success_count -eq 0 ]; then
        echo -e "${RED}Error: No clusters were initialized. Is the stack deployed?${NC}"
        exit 1
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${GREEN}✅ Database initialization complete!${NC}"
    echo "   Success: $success_count cluster(s)"
    [ $fail_count -gt 0 ] && echo -e "   ${YELLOW}Failed: $fail_count cluster(s)${NC}"
    echo ""
    echo "Test users created:"
    echo "  - testuser1 / testuser"
    echo "  - testuser2 / testuser"
    echo "  - testuser3 / testuser"
    echo ""
    echo "Permissions: SELECT on mysql.*, ALL on testdb.*"
}

#==============================================================================
# Blue/Green deployment
#==============================================================================
create_bluegreen() {
    load_config
    resolve_stack_name
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Creating Blue/Green Deployments                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Stack Name: $STACK_NAME${NC}"
    echo "Target Version: $TARGET_VERSION"
    echo ""

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    local success_count=0
    local skip_count=0

    for i in $(seq 1 3); do
        CLUSTER="${STACK_NAME}-cluster-$i"
        
        STATUS=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER" \
            --query 'DBClusters[0].Status' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "not-found")
        
        if [ "$STATUS" = "not-found" ] || [ -z "$STATUS" ]; then
            continue
        fi
        
        if [ "$STATUS" != "available" ]; then
            echo -e "${YELLOW}Skipping $CLUSTER (status: $STATUS)${NC}"
            skip_count=$((skip_count + 1))
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
        success_count=$((success_count + 1))
    done

    echo ""
    if [ $success_count -eq 0 ]; then
        echo -e "${RED}No Blue/Green deployments were created.${NC}"
    else
        echo -e "${GREEN}✅ Created $success_count Blue/Green deployment(s)${NC}"
    fi
    [ $skip_count -gt 0 ] && echo -e "${YELLOW}Skipped $skip_count cluster(s) (not available)${NC}"
    echo ""
    echo -e "${YELLOW}Blue/Green deployments take 10-30 minutes.${NC}"
}

#==============================================================================
# Status
#==============================================================================
show_status() {
    load_config
    resolve_stack_name
    
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
    resolve_stack_name
    
    echo ""
    echo -e "${CYAN}Stack: $STACK_NAME${NC}"
    echo ""
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[*].[OutputKey, OutputValue]' \
        --output table \
        --region "$REGION" 2>/dev/null || echo "Stack not found"
}

#==============================================================================
# List all stacks
#==============================================================================
list_stacks() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Aurora Blue/Green Test Stacks                             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Show last used stack
    if [ -f "$SCRIPT_DIR/.last-stack-name" ]; then
        LAST_STACK=$(cat "$SCRIPT_DIR/.last-stack-name")
        echo -e "${GREEN}Last deployed: $LAST_STACK${NC}"
        echo ""
    fi
    
    echo "All aurora-bg-test stacks:"
    aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_IN_PROGRESS UPDATE_IN_PROGRESS \
        --query "StackSummaries[?contains(StackName, \`aurora-bg-test\`)].[StackName, StackStatus, CreationTime]" \
        --output table \
        --region "$REGION" 2>/dev/null || echo "  None found"
    echo ""
}

#==============================================================================
# Delete
#==============================================================================
delete_all() {
    load_config
    resolve_stack_name
    
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

    # Clear last stack name if it matches
    if [ -f "$SCRIPT_DIR/.last-stack-name" ]; then
        LAST_STACK=$(cat "$SCRIPT_DIR/.last-stack-name")
        if [ "$LAST_STACK" = "$STACK_NAME" ]; then
            rm -f "$SCRIPT_DIR/.last-stack-name"
        fi
    fi

    echo -e "${GREEN}✅ Deleted!${NC}"
}

#==============================================================================
# Resolve stack name (use last deployed if not specified)
#==============================================================================
resolve_stack_name() {
    # If STACK_NAME is still default and we have a last-stack-name file, use it
    if [ "$STACK_NAME" = "aurora-bg-test" ] && [ -f "$SCRIPT_DIR/.last-stack-name" ]; then
        STACK_NAME=$(cat "$SCRIPT_DIR/.last-stack-name")
        echo -e "${CYAN}Using last deployed stack: $STACK_NAME${NC}"
    fi
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
    list) list_stacks ;;
    delete) delete_all ;;
    show-config) show_config ;;
    *) usage; exit 1 ;;
esac
