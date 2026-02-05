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
    
    # Instance class configuration
    BLUE_INSTANCE_CLASS="${BLUE_INSTANCE_CLASS:-db.r6g.large}"
    GREEN_INSTANCE_CLASS="${GREEN_INSTANCE_CLASS:-db.r6g.xlarge}"
    
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
    echo "  deploy-all          One-click: deploy + init-db + create-bluegreen"
    echo "  init-db             Initialize database (create test users)"
    echo "  create-bluegreen    Create Blue/Green deployments"
    echo "  modify-green        Modify Green cluster instance class (after BG created)"
    echo "  status              Show status"
    echo "  outputs             Show stack outputs"
    echo "  list                List all aurora-bg-test stacks"
    echo "  delete              Delete everything"
    echo "  show-config         Show current configuration"
    echo ""
    echo "Quick Start (one command):"
    echo "  DB_PASSWORD=MyPass ./deploy.sh deploy-all"
    echo ""
    echo "Step-by-step Workflow:"
    echo "  1. ./deploy.sh deploy           # Create NEW cluster (with timestamp)"
    echo "  2. ./deploy.sh init-db          # Create test users"
    echo "  3. ./deploy.sh create-bluegreen # Start Blue/Green"
    echo "  4. ./deploy.sh modify-green     # (Optional) Change Green instance class"
    echo ""
    echo "Examples:"
    echo "  # One-click deployment (recommended)"
    echo "  DB_PASSWORD=MyPass ./deploy.sh deploy-all"
    echo ""
    echo "  # Create new cluster only"
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
    echo "  GREEN_INSTANCE_CLASS   Instance class for Green (used by modify-green)"
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
    echo ""
    echo "Instance Classes:"
    echo "  Blue (Source):  $BLUE_INSTANCE_CLASS"
    echo "  Green (Target): $GREEN_INSTANCE_CLASS"
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
# Deploy All (one-click: deploy + init-db + create-bluegreen)
#==============================================================================
deploy_all() {
    load_config
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   One-Click Deployment: Aurora + Init DB + Blue/Green       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Error: DB_PASSWORD is required${NC}"
        echo "Usage: DB_PASSWORD=YourPassword ./deploy.sh deploy-all"
        exit 1
    fi
    
    # Step 1: Deploy Aurora clusters
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Step 1/3: Deploying Aurora Clusters${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    deploy_stack
    
    # Step 2: Initialize database
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Step 2/3: Initializing Database${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    init_db
    
    # Step 3: Create Blue/Green deployment
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Step 3/3: Creating Blue/Green Deployment${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    create_bluegreen
    
    # Summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   ✅ One-Click Deployment Complete!                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${GREEN}Stack Name: $STACK_NAME${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Wait for Blue/Green deployment to be ready (~20-30 min)"
    echo "     ./deploy.sh status"
    echo ""
    echo "  2. Start your test application:"
    echo "     export AURORA_CLUSTER_ENDPOINT=<cluster-endpoint>"
    echo "     export AURORA_PASSWORD='$DB_PASSWORD'"
    echo "     ./run-aurora.sh prod"
    echo ""
    echo "  3. Start continuous write test:"
    echo "     curl -X POST 'http://localhost:8080/api/bluegreen/start-write?numConnections=10&writeIntervalMs=500'"
    echo ""
    echo "  4. Trigger switchover from AWS Console or CLI"
    echo ""
    
    # Show outputs for easy copy
    show_outputs
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
    echo "  Blue Class:   $BLUE_INSTANCE_CLASS"
    echo "  Green Class:  $GREEN_INSTANCE_CLASS (for Blue/Green deployment)"
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
            BlueInstanceClass="$BLUE_INSTANCE_CLASS" \
            GreenInstanceClass="$GREEN_INSTANCE_CLASS" \
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
    echo "Target Version:     $TARGET_VERSION"
    echo "Blue Instance:      $BLUE_INSTANCE_CLASS"
    echo "Green Instance:     $GREEN_INSTANCE_CLASS"
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
        echo "  Version: $CURRENT -> $TARGET_VERSION"

        # Note: Aurora clusters don't support --target-db-instance-class
        # Green cluster will inherit the same instance class as Blue
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
        return 1
    fi
    
    echo -e "${GREEN}✅ Created $success_count Blue/Green deployment(s)${NC}"
    [ $skip_count -gt 0 ] && echo -e "${YELLOW}Skipped $skip_count cluster(s) (not available)${NC}"
    
    # Check if we need to modify Green instance class
    if [ "$BLUE_INSTANCE_CLASS" != "$GREEN_INSTANCE_CLASS" ]; then
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}Waiting for Green instances to be created...${NC}"
        echo -e "${CYAN}Will modify: $BLUE_INSTANCE_CLASS -> $GREEN_INSTANCE_CLASS${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # Wait for Green instances to appear and become available
        wait_and_modify_green_instances
    else
        echo ""
        echo -e "${YELLOW}Blue/Green deployments take 10-30 minutes to be ready.${NC}"
        echo "Check status: ./deploy.sh status"
    fi
}

#==============================================================================
# Wait for Green instances and modify their class
#==============================================================================
wait_and_modify_green_instances() {
    local max_wait=1800  # 30 minutes max
    local waited=0
    local check_interval=30
    local green_found=false
    
    echo ""
    echo "Waiting for Green instances to be created..."
    
    while [ $waited -lt $max_wait ]; do
        # Find Green instances
        GREEN_INSTANCES=$(aws rds describe-db-instances \
            --query "DBInstances[?contains(DBInstanceIdentifier, \`${STACK_NAME}\`) && contains(DBInstanceIdentifier, \`-green-\`)].DBInstanceIdentifier" \
            --output text \
            --region "$REGION" 2>/dev/null || echo "")
        
        if [ -n "$GREEN_INSTANCES" ] && [ "$GREEN_INSTANCES" != "None" ]; then
            green_found=true
            
            # Check if all Green instances are available
            local all_available=true
            for INSTANCE in $GREEN_INSTANCES; do
                INSTANCE_STATUS=$(aws rds describe-db-instances \
                    --db-instance-identifier "$INSTANCE" \
                    --query 'DBInstances[0].DBInstanceStatus' \
                    --output text \
                    --region "$REGION" 2>/dev/null || echo "unknown")
                
                if [ "$INSTANCE_STATUS" != "available" ]; then
                    all_available=false
                    break
                fi
            done
            
            if [ "$all_available" = true ]; then
                echo ""
                echo -e "${GREEN}Green instances are available!${NC}"
                echo ""
                
                # Now modify the instances
                modify_green_instances
                return 0
            fi
        fi
        
        # Show progress
        if [ "$green_found" = true ]; then
            echo "  Green instances found, waiting for 'available' status... ($waited seconds)"
        else
            echo "  Waiting for Green instances to be created... ($waited seconds)"
        fi
        
        sleep $check_interval
        waited=$((waited + check_interval))
    done
    
    echo ""
    echo -e "${YELLOW}Timeout waiting for Green instances.${NC}"
    echo "You can manually run: ./deploy.sh modify-green"
    return 1
}

#==============================================================================
# Modify Green cluster instance class
#==============================================================================
modify_green_instances() {
    load_config
    resolve_stack_name
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   Modifying Green Cluster Instance Class                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Stack Name: $STACK_NAME${NC}"
    echo "Target Instance Class: $GREEN_INSTANCE_CLASS"
    echo ""
    
    # Find all Green instances (they have "-green-" in their identifier)
    GREEN_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, \`${STACK_NAME}\`) && contains(DBInstanceIdentifier, \`-green-\`)].DBInstanceIdentifier" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -z "$GREEN_INSTANCES" ] || [ "$GREEN_INSTANCES" = "None" ]; then
        echo -e "${YELLOW}No Green instances found. Make sure Blue/Green deployment is created first.${NC}"
        echo ""
        echo "Run: ./deploy.sh create-bluegreen"
        return 1
    fi
    
    local success_count=0
    local skip_count=0
    
    for INSTANCE in $GREEN_INSTANCES; do
        CURRENT_CLASS=$(aws rds describe-db-instances \
            --db-instance-identifier "$INSTANCE" \
            --query 'DBInstances[0].DBInstanceClass' \
            --output text \
            --region "$REGION" 2>/dev/null)
        
        if [ "$CURRENT_CLASS" = "$GREEN_INSTANCE_CLASS" ]; then
            echo -e "${YELLOW}Skipping $INSTANCE (already $GREEN_INSTANCE_CLASS)${NC}"
            skip_count=$((skip_count + 1))
            continue
        fi
        
        echo "Modifying $INSTANCE"
        echo "  $CURRENT_CLASS -> $GREEN_INSTANCE_CLASS"
        
        aws rds modify-db-instance \
            --db-instance-identifier "$INSTANCE" \
            --db-instance-class "$GREEN_INSTANCE_CLASS" \
            --apply-immediately \
            --region "$REGION" > /dev/null 2>&1 && {
            echo -e "${GREEN}  ✅ Modification initiated${NC}"
            success_count=$((success_count + 1))
        } || {
            echo -e "${RED}  ❌ Failed${NC}"
        }
    done
    
    echo ""
    if [ $success_count -gt 0 ]; then
        echo -e "${GREEN}✅ Initiated modification for $success_count instance(s)${NC}"
        echo ""
        echo -e "${YELLOW}Instance modification takes 5-15 minutes.${NC}"
        echo "Check status: ./deploy.sh status"
    fi
    [ $skip_count -gt 0 ] && echo "Skipped $skip_count instance(s) (already target class)"
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
    echo "This will delete:"
    echo "  - Blue/Green deployments"
    echo "  - All clusters matching ${STACK_NAME}-* (including -old1 suffixes)"
    echo "  - CloudFormation stack"
    echo ""
    read -p "Are you sure? (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    # Step 1: Delete Blue/Green deployments
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 1: Deleting Blue/Green deployments..."
    
    # Get BG deployments with their status
    BG_INFO=$(aws rds describe-blue-green-deployments \
        --query "BlueGreenDeployments[?contains(BlueGreenDeploymentName, \`$STACK_NAME\`)].[BlueGreenDeploymentIdentifier,Status]" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$BG_INFO" ] && [ "$BG_INFO" != "None" ]; then
        while read -r BG_ID BG_STATUS; do
            [ -z "$BG_ID" ] && continue
            echo "  Deleting: $BG_ID (status: $BG_STATUS)"
            
            # For SWITCHOVER_COMPLETED status, don't use --delete-target
            if [ "$BG_STATUS" = "SWITCHOVER_COMPLETED" ]; then
                aws rds delete-blue-green-deployment \
                    --blue-green-deployment-identifier "$BG_ID" \
                    --region "$REGION" 2>/dev/null || true
            else
                aws rds delete-blue-green-deployment \
                    --blue-green-deployment-identifier "$BG_ID" \
                    --delete-target \
                    --region "$REGION" 2>/dev/null || true
            fi
        done <<< "$BG_INFO"
        
        echo "  Waiting for Blue/Green deployments to be deleted..."
        local max_wait=300  # 5 minutes max
        local waited=0
        while [ $waited -lt $max_wait ]; do
            REMAINING=$(aws rds describe-blue-green-deployments \
                --query "BlueGreenDeployments[?contains(BlueGreenDeploymentName, \`$STACK_NAME\`)].BlueGreenDeploymentIdentifier" \
                --output text \
                --region "$REGION" 2>/dev/null || echo "")
            
            if [ -z "$REMAINING" ] || [ "$REMAINING" = "None" ]; then
                echo "  All Blue/Green deployments deleted"
                break
            fi
            
            echo "    Still waiting... ($waited seconds)"
            sleep 15
            waited=$((waited + 15))
        done
        
        if [ $waited -ge $max_wait ]; then
            echo -e "${YELLOW}  Warning: Blue/Green deletion timed out, continuing anyway...${NC}"
        fi
    else
        echo "  No Blue/Green deployments found"
    fi

    # Step 2: Find and delete all related DB instances
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 2: Deleting DB instances..."
    
    INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBClusterIdentifier, \`$STACK_NAME\`)].DBInstanceIdentifier" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
        for INSTANCE in $INSTANCES; do
            echo "  Deleting instance: $INSTANCE"
            aws rds delete-db-instance \
                --db-instance-identifier "$INSTANCE" \
                --skip-final-snapshot \
                --region "$REGION" 2>/dev/null &
        done
        wait
        
        echo "  Waiting for instances to be deleted (this may take 5-10 minutes)..."
        for INSTANCE in $INSTANCES; do
            echo "    Waiting for: $INSTANCE"
            aws rds wait db-instance-deleted \
                --db-instance-identifier "$INSTANCE" \
                --region "$REGION" 2>/dev/null || true
        done
    else
        echo "  No DB instances found"
    fi

    # Step 3: Find and delete all related DB clusters
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 3: Deleting DB clusters..."
    
    CLUSTERS=$(aws rds describe-db-clusters \
        --query "DBClusters[?contains(DBClusterIdentifier, \`$STACK_NAME\`)].DBClusterIdentifier" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$CLUSTERS" ] && [ "$CLUSTERS" != "None" ]; then
        for CLUSTER in $CLUSTERS; do
            echo "  Disabling deletion protection: $CLUSTER"
            aws rds modify-db-cluster \
                --db-cluster-identifier "$CLUSTER" \
                --no-deletion-protection \
                --apply-immediately \
                --region "$REGION" 2>/dev/null || true
        done
        
        sleep 5
        
        for CLUSTER in $CLUSTERS; do
            echo "  Deleting cluster: $CLUSTER"
            aws rds delete-db-cluster \
                --db-cluster-identifier "$CLUSTER" \
                --skip-final-snapshot \
                --region "$REGION" 2>/dev/null || true
        done
        
        echo "  Waiting for clusters to be deleted..."
        for CLUSTER in $CLUSTERS; do
            echo "    Waiting for: $CLUSTER"
            aws rds wait db-cluster-deleted \
                --db-cluster-identifier "$CLUSTER" \
                --region "$REGION" 2>/dev/null || true
        done
    else
        echo "  No DB clusters found"
    fi

    # Step 4: Delete CloudFormation stack
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 4: Deleting CloudFormation stack..."
    
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].StackStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$STACK_STATUS" != "NOT_FOUND" ]; then
        aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
        echo "  Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
        echo "  Stack deleted"
    else
        echo "  Stack not found (already deleted or never existed)"
    fi

    # Clear last stack name if it matches
    if [ -f "$SCRIPT_DIR/.last-stack-name" ]; then
        LAST_STACK=$(cat "$SCRIPT_DIR/.last-stack-name")
        if [ "$LAST_STACK" = "$STACK_NAME" ]; then
            rm -f "$SCRIPT_DIR/.last-stack-name"
        fi
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ All resources deleted for: $STACK_NAME${NC}"
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
    deploy-all) deploy_all ;;
    init-db) init_db ;;
    create-bluegreen) create_bluegreen ;;
    modify-green) modify_green_instances ;;
    status) show_status ;;
    outputs) show_outputs ;;
    list) list_stacks ;;
    delete) delete_all ;;
    show-config) show_config ;;
    *) usage; exit 1 ;;
esac
