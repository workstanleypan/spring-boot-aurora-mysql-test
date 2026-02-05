# Aurora MySQL Blue/Green Test Environment

One-click deployment of Aurora MySQL clusters with Blue/Green deployment test environment.

## Quick Start

```bash
cd cloudformation

# 1. Configure (optional)
cp config.env config.local.env
# Edit config.local.env to set parameters

# 2. Deploy clusters (~15-20 minutes)
# Each deploy creates a NEW stack with timestamp (e.g., aurora-bg-test-0204-1530)
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# 3. Initialize database (create test users)
# Automatically uses the last deployed stack
./deploy.sh init-db

# 4. Create Blue/Green deployment (~20-30 minutes)
./deploy.sh create-bluegreen

# 5. Check status
./deploy.sh status

# 6. List all stacks
./deploy.sh list
```

## Stack Naming

By default, each `deploy` command creates a **new stack** with a unique timestamp:
- Stack name format: `aurora-bg-test-MMDD-HHMM` (e.g., `aurora-bg-test-0204-1530`)
- Subsequent commands (`init-db`, `outputs`, etc.) automatically use the last deployed stack
- Use `./deploy.sh list` to see all created stacks

To update an existing stack instead of creating a new one:
```bash
NEW_STACK=false STACK_NAME=aurora-bg-test-0204-1530 DB_PASSWORD=MyPass ./deploy.sh deploy
```

## Configuration File

Edit `config.local.env`:

```bash
# Core configuration
CLUSTER_COUNT=1               # Number of clusters (1-3)
INSTANCES_PER_CLUSTER=2       # Instances per cluster (1-3)
ENGINE_VERSION=8.0.mysql_aurora.3.04.2    # Blue version
TARGET_VERSION=8.0.mysql_aurora.3.10.3    # Green target version
NEW_STACK=true                # true=create new stack, false=update existing

# Instance Class Configuration
BLUE_INSTANCE_CLASS=db.r6g.large      # Blue (source) cluster
GREEN_INSTANCE_CLASS=db.r6g.xlarge    # Green (target) cluster - larger for faster binlog catchup

# Database
DB_PASSWORD=YourPassword      # Required
DB_USERNAME=admin
DB_NAME=testdb

# VPC (auto-detects default VPC)
USE_EXISTING_VPC=true
VPC_ID=                       # Leave empty for auto-detection
```

## Instance Class Strategy

The Green cluster can use a larger instance class than Blue to speed up binlog replication during switchover:

| Scenario | Blue Instance | Green Instance | Benefit |
|----------|---------------|----------------|---------|
| Cost-optimized | db.r6g.large | db.r6g.large | Same cost |
| Fast switchover | db.r6g.large | db.r6g.xlarge | 2x faster binlog catchup |
| High-load production | db.r6g.xlarge | db.r6g.2xlarge | Minimal switchover time |

**Why larger Green instance?**
- Binlog replication speed is limited by the **target (Green)** cluster's resources
- More vCPUs = more `replica_parallel_workers` = faster binlog catchup
- After switchover, you can downgrade the instance if needed

## Command Line Examples

```bash
# Create new cluster (default behavior)
DB_PASSWORD=MyPass ./deploy.sh deploy
# Creates: aurora-bg-test-0204-1530

# Subsequent commands auto-use last deployed stack
./deploy.sh init-db
./deploy.sh outputs
./deploy.sh create-bluegreen

# List all stacks
./deploy.sh list

# Use specific stack
STACK_NAME=aurora-bg-test-0204-1530 ./deploy.sh outputs

# Update existing stack (instead of creating new)
NEW_STACK=false STACK_NAME=aurora-bg-test-0204-1530 DB_PASSWORD=MyPass ./deploy.sh deploy

# 2 clusters
CLUSTER_COUNT=2 DB_PASSWORD=MyPass ./deploy.sh deploy

# 3 clusters, 3 instances each
CLUSTER_COUNT=3 INSTANCES_PER_CLUSTER=3 DB_PASSWORD=MyPass ./deploy.sh deploy

# Specify version
ENGINE_VERSION=8.0.mysql_aurora.3.08.0 DB_PASSWORD=MyPass ./deploy.sh deploy
```

## Commands

| Command | Description |
|---------|-------------|
| `deploy` | Deploy Aurora clusters (creates NEW stack by default) |
| `init-db` | Initialize database, create test users |
| `create-bluegreen` | Create Blue/Green deployment |
| `status` | View deployment status |
| `outputs` | Show connection information |
| `list` | List all aurora-bg-test stacks |
| `show-config` | Show current configuration |
| `delete` | Delete all resources |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEW_STACK` | true | Create new stack with timestamp |
| `STACK_NAME` | aurora-bg-test | Stack name (auto-generated if NEW_STACK=true) |
| `DB_PASSWORD` | - | Database password (required) |
| `CLUSTER_COUNT` | 1 | Number of clusters (1-3) |
| `INSTANCES_PER_CLUSTER` | 2 | Instances per cluster |
| `BLUE_INSTANCE_CLASS` | db.r6g.large | Blue cluster instance class |
| `GREEN_INSTANCE_CLASS` | db.r6g.xlarge | Green cluster instance class |

## Test Users

The `init-db` command creates the following test users:

| User | Password | Permissions |
|------|----------|-------------|
| testuser1 | testuser | SELECT on mysql.*, ALL on testdb.* |
| testuser2 | testuser | SELECT on mysql.*, ALL on testdb.* |
| testuser3 | testuser | SELECT on mysql.*, ALL on testdb.* |

## Security Notes

- Aurora clusters are **not publicly accessible** (PubliclyAccessible: false)
- Security group only allows VPC internal access (auto-detects VPC CIDR)
- Database access requires EC2 instance within the same VPC

## Connect Application

```bash
# Get connection information
./deploy.sh outputs

# Configure environment variables
export AURORA_CLUSTER_ENDPOINT="<from outputs>"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="testuser1"
export AURORA_PASSWORD="testuser"

# Run application
cd ..
./run-aurora.sh
```

## Execute Blue/Green Switchover

```bash
# View Blue/Green deployment ID
./deploy.sh status

# Execute switchover
aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier <bg-id> \
    --switchover-timeout 300
```

## Cleanup Resources

```bash
./deploy.sh delete
```

⚠️ **Please delete resources promptly after testing to avoid charges!**

## Cost Estimate

- db.t3.medium: ~$0.04/hour/instance
- Default configuration (1 cluster × 2 instances): ~$0.08/hour
- During Blue/Green deployment, Green instances double the cost

## Troubleshooting

```bash
# CloudFormation events
aws cloudformation describe-stack-events --stack-name aurora-bg-test

# Test connection (requires VPC access)
nc -zv <cluster-endpoint> 3306

# Blue/Green deployment status
aws rds describe-blue-green-deployments
```

## Supported Aurora Versions

**Blue Cluster Versions:**
- 3.04.x (MySQL 8.0.28)
- 3.08.x (MySQL 8.0.36)
- 3.09.x (MySQL 8.0.37)

**Green Target Versions:**
- 3.10.x LTS (MySQL 8.0.39) - Recommended
