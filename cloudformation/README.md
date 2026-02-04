# Aurora MySQL Blue/Green Test Environment

One-click deployment of Aurora MySQL clusters with Blue/Green deployment test environment.

## Quick Start

```bash
cd cloudformation

# 1. Configure (optional)
cp config.env config.local.env
# Edit config.local.env to set parameters

# 2. Deploy clusters (~15-20 minutes)
DB_PASSWORD=YourPassword123 ./deploy.sh deploy

# 3. Initialize database (create test users)
./deploy.sh init-db

# 4. Create Blue/Green deployment (~20-30 minutes)
./deploy.sh create-bluegreen

# 5. Check status
./deploy.sh status
```

## Configuration File

Edit `config.local.env`:

```bash
# Core configuration
CLUSTER_COUNT=1               # Number of clusters (1-3)
INSTANCES_PER_CLUSTER=2       # Instances per cluster (1-3)
ENGINE_VERSION=8.0.mysql_aurora.3.04.2    # Blue version
TARGET_VERSION=8.0.mysql_aurora.3.10.3    # Green target version

# Database
DB_PASSWORD=YourPassword      # Required
DB_USERNAME=admin
DB_NAME=testdb
INSTANCE_CLASS=db.t3.medium

# VPC (auto-detects default VPC)
USE_EXISTING_VPC=true
VPC_ID=                       # Leave empty for auto-detection
```

## Command Line Examples

```bash
# Single cluster (default)
DB_PASSWORD=MyPass ./deploy.sh deploy

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
| `deploy` | Deploy Aurora clusters |
| `init-db` | Initialize database, create test users |
| `create-bluegreen` | Create Blue/Green deployment |
| `status` | View deployment status |
| `outputs` | Show connection information |
| `show-config` | Show current configuration |
| `delete` | Delete all resources |

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
