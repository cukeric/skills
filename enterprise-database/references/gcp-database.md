# GCP Database Deployment Guide

## Table of Contents
1. [Service Selection](#service-selection)
2. [Cloud SQL (PostgreSQL & MySQL)](#cloud-sql)
3. [Firestore / Bigtable](#firestore--bigtable)
4. [Memorystore (Redis)](#memorystore)
5. [AlloyDB](#alloydb)
6. [Networking & Security](#networking--security)
7. [Infrastructure as Code (Terraform)](#infrastructure-as-code)
8. [Monitoring & Alerting](#monitoring--alerting)

---

## Service Selection

| Use Case | GCP Service | Notes |
|----------|------------|-------|
| Relational (default) | **Cloud SQL for PostgreSQL** | Fully managed, familiar PostgreSQL |
| Relational (high performance) | **AlloyDB** | PostgreSQL-compatible, up to 4x faster for transactional, 100x for analytical |
| Relational (MySQL) | **Cloud SQL for MySQL** | Only when MySQL is required |
| Document store | **Firestore** | Serverless, real-time sync, good for mobile/web apps |
| Wide-column (massive scale) | **Bigtable** | For IoT, time-series, analytics at petabyte scale |
| Caching | **Memorystore for Redis** | Managed Redis |
| Key-value at scale | **Bigtable** or **Firestore** | Depending on access patterns |
| Search | **Vertex AI Search** or self-managed OpenSearch | |

### AlloyDB vs Cloud SQL

Choose **AlloyDB** when:
- You need higher transactional performance than Cloud SQL offers
- You have mixed transactional + analytical workloads (HTAP)
- You're running complex queries on large datasets
- Budget allows (AlloyDB is premium-priced)

Choose **Cloud SQL** when:
- Standard PostgreSQL performance is sufficient
- Cost optimization is important
- You want the simplest managed PostgreSQL option

---

## Cloud SQL

### Terraform: Production Cloud SQL PostgreSQL

```hcl
# Cloud SQL Instance
resource "google_sql_database_instance" "main" {
  name             = "${var.project}-pg"
  database_version = "POSTGRES_16"
  region           = var.region
  project          = var.gcp_project

  settings {
    tier              = "db-custom-4-16384"  # 4 vCPUs, 16GB RAM
    availability_type = "REGIONAL"            # High availability (multi-zone)
    disk_type         = "PD_SSD"
    disk_size         = 100                   # GB, auto-resize enabled below
    disk_autoresize   = true
    disk_autoresize_limit = 500               # Max auto-resize to 500GB

    # Network — Private IP only
    ip_configuration {
      ipv4_enabled                                  = false  # No public IP
      private_network                               = var.vpc_id
      enable_private_path_for_google_cloud_services = true
    }

    # Backup
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }

    # Maintenance
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3
      update_track = "stable"
    }

    # Database flags (tuning)
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements,pgaudit"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
    database_flags {
      name  = "pgaudit.log"
      value = "write,ddl"
    }
    database_flags {
      name  = "max_connections"
      value = "200"
    }

    # Insights (query performance)
    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 4096
      record_application_tags = true
      record_client_address   = true
    }

    # Deletion protection
    deletion_protection_enabled = true
  }

  deletion_protection = true
}

# Database
resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
  project  = var.gcp_project
}

# Users
resource "google_sql_user" "app" {
  name     = var.db_app_username
  instance = google_sql_database_instance.main.name
  password = var.db_app_password  # Use Secret Manager
  project  = var.gcp_project
}

# Read Replica
resource "google_sql_database_instance" "replica" {
  name                 = "${var.project}-pg-replica"
  master_instance_name = google_sql_database_instance.main.name
  database_version     = "POSTGRES_16"
  region               = var.region
  project              = var.gcp_project

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = "db-custom-4-16384"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 100
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}
```

### Cloud SQL Auth Proxy

The recommended way to connect to Cloud SQL from applications:

```bash
# Run the proxy sidecar
cloud-sql-proxy --private-ip ${PROJECT}:${REGION}:${INSTANCE_NAME}

# Application connects to localhost:5432 — proxy handles auth and encryption
```

For GKE (Kubernetes):
```yaml
# Add as a sidecar container
containers:
  - name: cloud-sql-proxy
    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2
    args:
      - "--private-ip"
      - "--structured-logs"
      - "${PROJECT}:${REGION}:${INSTANCE}"
    securityContext:
      runAsNonRoot: true
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
```

---

## Firestore / Bigtable

### Firestore (Serverless Document Store)

Use Firestore (Native mode) for:
- Mobile/web apps needing real-time sync
- Serverless applications
- Moderate-scale document storage

```hcl
resource "google_firestore_database" "main" {
  project     = var.gcp_project
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # Point-in-time recovery
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"

  # Deletion protection
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
}

# Security rules (deploy via Firebase CLI)
# firestore.rules
# rules_version = '2';
# service cloud.firestore {
#   match /databases/{database}/documents {
#     match /users/{userId} {
#       allow read, write: if request.auth != null && request.auth.uid == userId;
#     }
#   }
# }
```

### Bigtable (Wide-Column at Scale)

Use Bigtable for:
- Time-series data (IoT, metrics, financial data)
- Analytics workloads at petabyte scale
- High-throughput, low-latency key-value operations

```hcl
resource "google_bigtable_instance" "main" {
  name    = "${var.project}-bigtable"
  project = var.gcp_project

  cluster {
    cluster_id   = "${var.project}-bt-cluster-1"
    zone         = "${var.region}-a"
    num_nodes    = 3          # Minimum 3 for production
    storage_type = "SSD"
  }

  # Optional: multi-cluster for high availability
  cluster {
    cluster_id   = "${var.project}-bt-cluster-2"
    zone         = "${var.region}-b"
    num_nodes    = 3
    storage_type = "SSD"
  }

  deletion_protection = true
}

resource "google_bigtable_table" "events" {
  name          = "events"
  instance_name = google_bigtable_instance.main.name
  project       = var.gcp_project

  column_family { family = "data" }
  column_family { family = "metadata" }

  # Garbage collection policy (auto-delete old data)
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigtable_gc_policy" "events_data" {
  instance_name = google_bigtable_instance.main.name
  table         = google_bigtable_table.events.name
  column_family = "data"
  project       = var.gcp_project

  max_age {
    duration = "720h"  # 30 days
  }
}
```

---

## Memorystore

```hcl
resource "google_redis_instance" "main" {
  name           = "${var.project}-redis"
  tier           = "STANDARD_HA"  # High availability with replica
  memory_size_gb = 4
  region         = var.region
  project        = var.gcp_project

  redis_version  = "REDIS_7_2"

  authorized_network = var.vpc_id

  # TLS
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  # Persistence
  persistence_config {
    persistence_mode    = "RDB"
    rdb_snapshot_period = "ONE_HOUR"
  }

  # Maintenance
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 3
        minutes = 0
      }
    }
  }

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }
}
```

---

## AlloyDB

Google's PostgreSQL-compatible database for demanding workloads:

```hcl
resource "google_alloydb_cluster" "main" {
  cluster_id = "${var.project}-alloydb"
  location   = var.region
  project    = var.gcp_project

  network_config {
    network = var.vpc_id
  }

  automated_backup_policy {
    enabled = true
    backup_window = "03:00"
    
    weekly_schedule {
      days_of_week = ["MONDAY", "WEDNESDAY", "FRIDAY"]
      start_times {
        hours = 3
      }
    }

    quantity_based_retention {
      count = 14
    }
  }

  continuous_backup_config {
    enabled              = true
    recovery_window_days = 14
  }
}

resource "google_alloydb_instance" "primary" {
  cluster       = google_alloydb_cluster.main.name
  instance_id   = "${var.project}-alloydb-primary"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = 4
  }

  query_insights_config {
    query_string_length     = 4096
    record_application_tags = true
    record_client_address   = true
    query_plans_per_minute  = 5
  }
}

# Read pool for analytics
resource "google_alloydb_instance" "read_pool" {
  cluster       = google_alloydb_cluster.main.name
  instance_id   = "${var.project}-alloydb-reader"
  instance_type = "READ_POOL"

  read_pool_config {
    node_count = 2
  }

  machine_config {
    cpu_count = 4
  }
}
```

---

## Networking & Security

### VPC Architecture

```
┌─────────────────────────────────────────────────┐
│                    VPC                            │
│  ┌──────────────────────────────────────────┐   │
│  │    App Subnet (GKE / Cloud Run)          │   │
│  │    Firewall: Allow egress to DB subnet   │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │    Database Subnet (Private Services)     │   │
│  │    - Private Service Access enabled       │   │
│  │    - No external IP addresses             │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │    Private Service Connect (for Cloud SQL)│   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Secret Manager

```hcl
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project}-db-password"
  project   = var.gcp_project

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}
```

Application access:
```typescript
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const client = new SecretManagerServiceClient();
const [version] = await client.accessSecretVersion({
  name: `projects/${projectId}/secrets/${secretId}/versions/latest`,
});
const password = version.payload?.data?.toString();
```

### IAM Database Authentication

Cloud SQL supports IAM-based authentication (passwordless):

```hcl
resource "google_sql_user" "iam_user" {
  name     = "app-sa@${var.gcp_project}.iam"
  instance = google_sql_database_instance.main.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = var.gcp_project
}
```

---

## Monitoring & Alerting

### Cloud Monitoring Alerts

```hcl
resource "google_monitoring_alert_policy" "db_cpu" {
  display_name = "${var.project} - Cloud SQL High CPU"
  project      = var.gcp_project
  combiner     = "OR"

  conditions {
    display_name = "CPU > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [var.notification_channel_id]

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "db_connections" {
  display_name = "${var.project} - Cloud SQL High Connections"
  project      = var.gcp_project
  combiner     = "OR"

  conditions {
    display_name = "Connections > 80% of max"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/network/connections\""
      comparison      = "COMPARISON_GT"
      threshold_value = 160  # 80% of 200 max_connections
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [var.notification_channel_id]
}
```

### Query Insights

Cloud SQL Query Insights is built-in and free. Enable it in the instance settings to get:
- Top queries by total execution time
- Query plans and explain output
- Wait event analysis
- Tag-based filtering (by application or user)

### Recommended Monitoring

- **Cloud Monitoring dashboards**: Pre-built Cloud SQL dashboard + custom panels
- **Query Insights**: Built into Cloud SQL console
- **Cloud Logging**: PostgreSQL slow query logs, audit logs
- **Uptime checks**: External connectivity monitoring
- **Custom metrics**: Push application-level database metrics via OpenTelemetry
