# EC2 Environment Setup Guide

Setup guide for running Blue/Green switchover tests on Amazon Linux 2023.

## Prerequisites

### EC2 Instance Requirements

| Requirement | Recommended | Minimum |
|-------------|-------------|---------|
| Instance Type | t3.medium | t3.small |
| Memory | 4 GB | 2 GB |
| Storage | 20 GB | 10 GB |
| AMI | Amazon Linux 2023 | Amazon Linux 2023 |

### Network Requirements

- EC2 must be in the same VPC as Aurora cluster (or have VPC peering)
- Security group must allow outbound access to Aurora (port 3306)
- For CloudFormation deployment, EC2 needs internet access

### IAM Permissions

If using `deploy.sh` for CloudFormation deployment, the EC2 instance role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "cloudformation:*",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Setup (One Command)

```bash
# Install all required packages
sudo dnf install -y java-17-amazon-corretto-devel maven git mariadb105

# Clone and build
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test
mvn clean package -DskipTests
```

## Step-by-Step Setup

### 1. Update System

```bash
sudo dnf update -y
```

### 2. Install Java 17

Spring Boot 3.x requires Java 17+.

```bash
sudo dnf install -y java-17-amazon-corretto-devel

# Verify
java -version
# openjdk version "17.0.x"
```

### 3. Install Maven

```bash
sudo dnf install -y maven

# Verify
mvn -version
# Apache Maven 3.8.x
```

### 4. Install Git

```bash
sudo dnf install -y git

# Verify
git --version
```

### 5. Install MySQL Client

Required for `deploy.sh init-db` command.

```bash
sudo dnf install -y mariadb105

# Verify
mysql --version
```

### 6. Verify AWS CLI

AWS CLI v2 is pre-installed on AL2023.

```bash
aws --version
# aws-cli/2.x.x
```

## Package Summary

| Package | Purpose | Install Command |
|---------|---------|-----------------|
| `java-17-amazon-corretto-devel` | Java 17 runtime & compiler | `sudo dnf install -y java-17-amazon-corretto-devel` |
| `maven` | Build project | `sudo dnf install -y maven` |
| `git` | Clone repository | `sudo dnf install -y git` |
| `mariadb105` | MySQL client for init-db | `sudo dnf install -y mariadb105` |

## Clone and Build Project

```bash
# Clone repository
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test

# Build (skip tests - no database connection yet)
mvn clean package -DskipTests

# Verify build
ls -la target/*.jar
```

## Configure Environment

```bash
# Copy template
cp .env.template .env

# Edit with your values
vi .env
```

Required variables:
```bash
export AURORA_CLUSTER_ENDPOINT="your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
export AURORA_DATABASE="testdb"
export AURORA_USERNAME="admin"
export AURORA_PASSWORD="your-password"
export WRAPPER_LOG_LEVEL="FINE"
```

## Run Application

```bash
# Load environment
source .env

# Run with Aurora profile
./run-aurora.sh prod
```

## Verify Setup

```bash
# Check application health
curl http://localhost:8080/actuator/health

# Test database connection
curl http://localhost:8080/api/test
```

## Troubleshooting

### Java Version Issues

```bash
# Check installed Java versions
alternatives --display java

# Set Java 17 as default
sudo alternatives --set java /usr/lib/jvm/java-17-amazon-corretto/bin/java
```

### Maven Build Fails (Out of Memory)

For t3.small instances, increase swap:

```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=1024
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Cannot Connect to Aurora

1. Check security group allows EC2 → Aurora (port 3306)
2. Verify EC2 is in same VPC or has VPC peering
3. Test connectivity: `mysql -h <endpoint> -u admin -p`

### AWS CLI Credentials

If using Isengard or temporary credentials:

```bash
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_SESSION_TOKEN=xxx

# Verify
aws sts get-caller-identity
```

## Full Setup Script

Save as `setup.sh` and run:

```bash
#!/bin/bash
set -e

echo "=== AL2023 Blue/Green Test Environment Setup ==="

# Update system
sudo dnf update -y

# Install packages
sudo dnf install -y java-17-amazon-corretto-devel maven git mariadb105

# Verify installations
echo ""
echo "=== Verifying Installations ==="
java -version
mvn -version
git --version
mysql --version
aws --version

# Clone project
echo ""
echo "=== Cloning Project ==="
git clone https://github.com/workstanleypan/spring-boot-aurora-mysql-test.git
cd spring-boot-aurora-mysql-test

# Build
echo ""
echo "=== Building Project ==="
mvn clean package -DskipTests

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "1. cd spring-boot-aurora-mysql-test"
echo "2. cp .env.template .env"
echo "3. Edit .env with your Aurora credentials"
echo "4. source .env && ./run-aurora.sh prod"
```

## Related Documentation

- [README.md](../README.md) - Project overview
- [AURORA_QUICK_START.md](AURORA_QUICK_START.md) - Aurora quick start
- [BLUEGREEN_TEST_GUIDE.md](BLUEGREEN_TEST_GUIDE.md) - Blue/Green test guide
- [CloudFormation README](../cloudformation/README.md) - Deploy Aurora cluster
