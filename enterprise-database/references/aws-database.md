# AWS Database Deployment Guide

## Table of Contents
1. [Service Selection](#service-selection)
2. [RDS / Aurora (PostgreSQL & MySQL)](#rds--aurora)
3. [DocumentDB (MongoDB-Compatible)](#documentdb)
4. [ElastiCache (Redis)](#elasticache)
5. [DynamoDB](#dynamodb-setup)
6. [Networking & Security](#networking--security)
7. [Infrastructure as Code (Terraform)](#infrastructure-as-code)
8. [Monitoring & Alerting](#monitoring--alerting)
9. [Cost Optimization](#cost-optimization)

---

## Service Selection

| Use Case | AWS Service | Notes |
|----------|------------|-------|
| Relational (default choice) | **RDS PostgreSQL** or **Aurora PostgreSQL** | Aurora for higher availability and performance needs |
| Relational (MySQL required) | **RDS MySQL** or **Aurora MySQL** | Only when MySQL is specifically required |
| Document store | **DocumentDB** | MongoDB-compatible, not full MongoDB feature parity |
| Key-value / caching | **ElastiCache Redis** | Managed Redis with clustering |
| Key-value at scale | **DynamoDB** | Serverless, fully managed |
| Time-series | **Timestream** | Purpose-built for IoT and time-series |
| Search | **OpenSearch** | Elasticsearch-compatible |

### Aurora vs Standard RDS

Choose **Aurora** when you need:
- Automatic storage scaling (up to 128TB)
- 5x throughput improvement over standard PostgreSQL
- Up to 15 read replicas (vs 5 for standard RDS)
- Global Database for cross-region replication
- Serverless v2 for variable workloads

Choose **standard RDS** when:
- Cost sensitivity is high (Aurora is ~20% more expensive)
- Your workload is small/predictable
- You want exact PostgreSQL version compatibility

---

## RDS / Aurora

### Terraform: Production Aurora PostgreSQL Cluster

```hcl
# VPC and Subnets (assumed to exist)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.project}-db-subnet" }
}

# Security Group
resource "aws_security_group" "db" {
  name_prefix = "${var.project}-db-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]  # Only from app servers
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Parameter Group (tuned settings)
resource "aws_rds_cluster_parameter_group" "main" {
  family = "aurora-postgresql16"
  name   = "${var.project}-cluster-params"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pgaudit"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries > 1 second
  }
  parameter {
    name  = "pgaudit.log"
    value = "write,ddl"
  }
}

# Aurora Cluster
resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.project}-db"
  engine             = "aurora-postgresql"
  engine_version     = "16.4"

  database_name   = var.db_name
  master_username = var.db_username
  # Use Secrets Manager for password management
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # Backup
  backup_retention_period = 35          # Maximum retention
  preferred_backup_window = "03:00-04:00"
  copy_tags_to_snapshot   = true

  # Encryption
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn  # Customer-managed key

  # Protection
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-db-final"

  # Enhanced monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
}

# Writer instance
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project}-db-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class  # e.g., "db.r6g.xlarge"
  engine             = "aurora-postgresql"

  monitoring_interval = 15
  monitoring_role_arn = var.monitoring_role_arn

  performance_insights_enabled = true
  performance_insights_retention_period = 731  # 2 years
}

# Reader instance(s)
resource "aws_rds_cluster_instance" "reader" {
  count              = var.reader_count  # e.g., 1-2 for most workloads
  identifier         = "${var.project}-db-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = "aurora-postgresql"

  monitoring_interval = 15
  monitoring_role_arn = var.monitoring_role_arn

  performance_insights_enabled = true
}

# Store connection info in Secrets Manager
resource "aws_secretsmanager_secret" "db_connection" {
  name = "${var.project}/database/connection"
}

resource "aws_secretsmanager_secret_version" "db_connection" {
  secret_id = aws_secretsmanager_secret.db_connection.id
  secret_string = jsonencode({
    host     = aws_rds_cluster.main.endpoint
    reader   = aws_rds_cluster.main.reader_endpoint
    port     = 5432
    dbname   = var.db_name
    username = var.db_username
  })
}
```

### Aurora Serverless v2

For variable or unpredictable workloads:

```hcl
resource "aws_rds_cluster" "serverless" {
  cluster_identifier = "${var.project}-db"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"  # Serverless v2 uses provisioned mode

  serverlessv2_scaling_configuration {
    min_capacity = 0.5   # Minimum ACUs (can scale to zero-ish)
    max_capacity = 64    # Maximum ACUs
  }
  # ... other settings same as above
}

resource "aws_rds_cluster_instance" "serverless" {
  identifier         = "${var.project}-db-serverless"
  cluster_identifier = aws_rds_cluster.serverless.id
  instance_class     = "db.serverless"
  engine             = "aurora-postgresql"
}
```

---

## DocumentDB

```hcl
resource "aws_docdb_cluster" "main" {
  cluster_identifier = "${var.project}-docdb"
  engine             = "docdb"

  master_username = var.docdb_username
  master_password = var.docdb_password  # Use Secrets Manager

  db_subnet_group_name   = aws_docdb_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.docdb.id]

  backup_retention_period = 35
  storage_encrypted       = true
  kms_key_id             = var.kms_key_arn
  deletion_protection    = true

  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
}

resource "aws_docdb_cluster_instance" "main" {
  count              = 3  # 1 primary + 2 replicas
  identifier         = "${var.project}-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = "db.r6g.large"
}
```

**DocumentDB Limitations** (compared to full MongoDB):
- No client-side field-level encryption
- No change streams across collections
- Limited aggregation pipeline operators
- No `$where` or server-side JavaScript
- Check the compatibility matrix before committing

---

## ElastiCache

```hcl
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project}-redis"
  description          = "${var.project} Redis cluster"

  node_type            = "cache.r6g.large"
  num_cache_clusters   = 3  # 1 primary + 2 replicas

  engine               = "redis"
  engine_version       = "7.1"
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token  # Use Secrets Manager

  # Backup
  snapshot_retention_limit = 7
  snapshot_window          = "03:00-05:00"

  # Maintenance
  maintenance_window       = "sun:05:00-sun:07:00"
  auto_minor_version_upgrade = true
  automatic_failover_enabled = true
  multi_az_enabled          = true
}

resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.project}-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}
```

---

## DynamoDB Setup

```hcl
resource "aws_dynamodb_table" "main" {
  name         = "${var.project}-data"
  billing_mode = "PAY_PER_REQUEST"  # On-demand; switch to PROVISIONED when patterns stabilize
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  # Encryption with customer-managed key
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # TTL for auto-expiring items
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}
```

---

## Networking & Security

### VPC Architecture for Databases

```
┌─────────────────────────────────────────────────┐
│                     VPC                          │
│  ┌──────────────────────────────────────────┐   │
│  │         Public Subnets (ALB only)        │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │     Private Subnets (App Servers/ECS)    │   │
│  │         ↓ Security Group allows ↓        │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │   Isolated Subnets (Databases)           │   │
│  │   - No internet access (no NAT)          │   │
│  │   - Only accessible from app subnets     │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Secrets Management

Never hardcode credentials. Use AWS Secrets Manager with automatic rotation:

```hcl
# Enable automatic password rotation for RDS
resource "aws_secretsmanager_secret_rotation" "db" {
  secret_id           = aws_secretsmanager_secret.db_connection.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

In application code:
```typescript
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const client = new SecretsManagerClient({});
const secret = await client.send(
  new GetSecretValueCommand({ SecretId: 'my-project/database/connection' })
);
const dbConfig = JSON.parse(secret.SecretString!);
```

---

## Monitoring & Alerting

### CloudWatch Alarms (Essential)

```hcl
# High CPU
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.project}-db-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [var.sns_topic_arn]
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.main.id }
}

# Low free storage
resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.project}-db-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5000000000  # 5GB
  alarm_actions       = [var.sns_topic_arn]
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.main.id }
}

# High connection count
resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.project}-db-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 150
  alarm_actions       = [var.sns_topic_arn]
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.main.id }
}
```

### Performance Insights

Enable Performance Insights on all RDS/Aurora instances. It provides:
- Top SQL queries by load
- Wait event analysis
- Historical performance data (free tier: 7 days, paid: up to 2 years)

---

## Cost Optimization

| Strategy | Savings | Trade-off |
|----------|---------|-----------|
| Reserved Instances (1-year) | ~30-40% | Commitment, less flexibility |
| Reserved Instances (3-year) | ~50-60% | Longer commitment |
| Aurora Serverless v2 | Variable | Pay-per-use, some cold start latency |
| Right-sizing instances | 20-50% | Requires monitoring to find optimal size |
| Read replicas for reads | Reduces primary load | Eventual consistency for reads |
| DynamoDB on-demand → provisioned | 30-50% at steady-state | Requires capacity planning |
| ElastiCache reserved nodes | ~30-40% | Commitment |
