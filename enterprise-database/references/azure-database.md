# Azure Database Deployment Guide

## Table of Contents
1. [Service Selection](#service-selection)
2. [Azure Database for PostgreSQL](#azure-database-for-postgresql)
3. [Azure Cosmos DB](#azure-cosmos-db)
4. [Azure Cache for Redis](#azure-cache-for-redis)
5. [Networking & Security](#networking--security)
6. [Infrastructure as Code (Terraform & Bicep)](#infrastructure-as-code)
7. [Monitoring & Alerting](#monitoring--alerting)

---

## Service Selection

| Use Case | Azure Service | Notes |
|----------|--------------|-------|
| Relational (default) | **Azure Database for PostgreSQL - Flexible Server** | Always use Flexible Server (Single Server is deprecated) |
| Relational (MySQL) | **Azure Database for MySQL - Flexible Server** | Only when MySQL is required |
| Relational (SQL Server) | **Azure SQL Database** | For .NET ecosystems or SQL Server requirements |
| Multi-model NoSQL | **Cosmos DB** | Global distribution, multiple APIs (MongoDB, PostgreSQL, Cassandra, Table, NoSQL) |
| Caching | **Azure Cache for Redis** | Managed Redis |
| Search | **Azure AI Search** | Full-text and vector search |

---

## Azure Database for PostgreSQL

Always use **Flexible Server** — it's the current generation with better performance, more control, and lower cost than the deprecated Single Server.

### Terraform: Production Flexible Server

```hcl
# Resource Group
resource "azurerm_resource_group" "db" {
  name     = "${var.project}-db-rg"
  location = var.location
}

# Private DNS Zone (required for private access)
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.project}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.db.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.project}-pg-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = azurerm_resource_group.db.name
  virtual_network_id    = var.vnet_id
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${var.project}-pg"
  resource_group_name = azurerm_resource_group.db.name
  location            = var.location

  version                = "16"
  sku_name               = "GP_Standard_D4ds_v5"  # General Purpose, 4 vCores
  storage_mb             = 131072                   # 128 GB
  storage_tier           = "P30"
  auto_grow_enabled      = true

  delegated_subnet_id = var.db_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password  # Use Key Vault

  backup_retention_days  = 35
  geo_redundant_backup_enabled = true

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  maintenance_window {
    day_of_week  = 0  # Sunday
    start_hour   = 3
    start_minute = 0
  }
}

# Server Configuration
resource "azurerm_postgresql_flexible_server_configuration" "shared_preload" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "pg_stat_statements,pgaudit"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_slow" {
  name      = "log_min_duration_statement"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "1000"
}

# Database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Read Replica
resource "azurerm_postgresql_flexible_server" "replica" {
  name                = "${var.project}-pg-replica"
  resource_group_name = azurerm_resource_group.db.name
  location            = var.location

  create_mode      = "Replica"
  source_server_id = azurerm_postgresql_flexible_server.main.id
  sku_name         = "GP_Standard_D4ds_v5"
  storage_mb       = 131072
}

# Diagnostic Settings (send logs to Log Analytics)
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  name                       = "${var.project}-pg-diag"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "PostgreSQLLogs"
  }
  enabled_log {
    category = "PostgreSQLFlexSessions"
  }
  metric {
    category = "AllMetrics"
  }
}
```

### Bicep Alternative

```bicep
// main.bicep
param projectName string
param location string = resourceGroup().location
param adminLogin string
@secure()
param adminPassword string

resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: '${projectName}-pg'
  location: location
  sku: {
    name: 'Standard_D4ds_v5'
    tier: 'GeneralPurpose'
  }
  properties: {
    version: '16'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 128
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: 'Enabled'
    }
    highAvailability: {
      mode: 'ZoneRedundant'
    }
  }
}
```

---

## Azure Cosmos DB

Cosmos DB supports multiple APIs. Choose based on your needs:

- **NoSQL API**: Native Cosmos, best performance and features
- **MongoDB API**: Drop-in replacement for MongoDB apps (with limitations)
- **PostgreSQL API** (Citus): Distributed PostgreSQL
- **Apache Cassandra API**: For Cassandra workloads
- **Table API**: Simple key-value (Azure Table Storage replacement)

### Terraform: Cosmos DB with MongoDB API

```hcl
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.project}-cosmos"
  resource_group_name = azurerm_resource_group.db.name
  location            = var.location
  offer_type          = "Standard"
  kind                = "MongoDB"

  # Enable server-side features
  mongo_server_version = "7.0"

  # Consistency level
  consistency_policy {
    consistency_level = "Session"  # Good default for most apps
    # Options: Strong, BoundedStaleness, Session, ConsistentPrefix, Eventual
  }

  # Multi-region (if needed)
  geo_location {
    location          = var.location
    failover_priority = 0
  }

  # Network
  is_virtual_network_filter_enabled = true
  virtual_network_rule {
    id = var.app_subnet_id
  }

  # Security
  public_network_access_enabled = false  # Private endpoint only

  # Backup
  backup {
    type                = "Continuous"
    tier                = "Continuous7Days"  # Or Continuous30Days
  }

  capabilities {
    name = "EnableServerless"  # For variable workloads; remove for provisioned
  }
}

# Private Endpoint
resource "azurerm_private_endpoint" "cosmos" {
  name                = "${var.project}-cosmos-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.db.name
  subnet_id           = var.db_subnet_id

  private_service_connection {
    name                           = "${var.project}-cosmos-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["MongoDB"]
    is_manual_connection           = false
  }
}
```

### Cosmos DB Pricing Models

- **Serverless**: Pay per operation. Best for dev/test and intermittent workloads.
- **Provisioned throughput**: Pre-allocated RU/s. Best for predictable workloads.
- **Autoscale**: Automatically scales between 10% and 100% of max RU/s. Best for variable but continuous workloads.

---

## Azure Cache for Redis

```hcl
resource "azurerm_redis_cache" "main" {
  name                = "${var.project}-redis"
  resource_group_name = azurerm_resource_group.db.name
  location            = var.location

  capacity            = 2          # Cache size (C2 = 6GB for Premium)
  family              = "P"        # P = Premium (supports clustering, persistence, VNet)
  sku_name            = "Premium"  # Basic, Standard, or Premium

  enable_non_ssl_port = false      # TLS only
  minimum_tls_version = "1.2"

  shard_count         = 2          # For Premium with clustering (0 = no clustering)

  redis_configuration {
    maxmemory_policy = "allkeys-lru"
    
    # AOF persistence
    aof_backup_enabled = true

    # RDB backup
    rdb_backup_enabled            = true
    rdb_backup_frequency          = 60       # Minutes
    rdb_storage_connection_string = var.backup_storage_connection_string
  }

  subnet_id = var.db_subnet_id  # Private VNet access

  zones = ["1", "2"]  # Zone redundancy
}
```

---

## Networking & Security

### Virtual Network Architecture

```
┌─────────────────────────────────────────────────┐
│                    VNet                           │
│  ┌──────────────────────────────────────────┐   │
│  │    App Subnet (App Service / AKS)        │   │
│  │    NSG: Allow outbound to DB subnet      │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │    Database Subnet (Delegated)            │   │
│  │    NSG: Allow inbound from App subnet    │   │
│  │    - PostgreSQL: Subnet delegation       │   │
│  │    - Cosmos/Redis: Private Endpoints     │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Azure Key Vault for Secrets

```hcl
# Store database credentials in Key Vault
resource "azurerm_key_vault_secret" "db_connection" {
  name         = "db-connection-string"
  value        = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.db_name}?sslmode=require"
  key_vault_id = var.key_vault_id
}
```

Application retrieval:
```typescript
import { DefaultAzureCredential } from '@azure/identity';
import { SecretClient } from '@azure/keyvault-secrets';

const client = new SecretClient(
  `https://${vaultName}.vault.azure.net`,
  new DefaultAzureCredential()
);
const secret = await client.getSecret('db-connection-string');
const connectionString = secret.value;
```

### Microsoft Entra Authentication (Passwordless)

Prefer managed identity over password-based auth when possible:

```hcl
# Enable Microsoft Entra admin on PostgreSQL
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "main" {
  server_name         = azurerm_postgresql_flexible_server.main.name
  resource_group_name = azurerm_resource_group.db.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.app_managed_identity_object_id
  principal_name      = var.app_managed_identity_name
  principal_type      = "ServicePrincipal"
}
```

---

## Monitoring & Alerting

### Azure Monitor Alerts

```hcl
# High CPU alert
resource "azurerm_monitor_metric_alert" "db_cpu" {
  name                = "${var.project}-db-high-cpu"
  resource_group_name = azurerm_resource_group.db.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  window_size = "PT15M"
  frequency   = "PT5M"

  action {
    action_group_id = var.action_group_id
  }
}

# Storage alert
resource "azurerm_monitor_metric_alert" "db_storage" {
  name                = "${var.project}-db-high-storage"
  resource_group_name = azurerm_resource_group.db.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }
}
```

### Recommended Dashboards

Use Azure Workbooks or Grafana with Azure Monitor data source. Key metrics to track:
- CPU utilization, memory utilization, storage percentage
- Active connections vs max connections
- Read/write IOPS
- Replication lag (for replicas)
- Slow query count (from PostgreSQL logs in Log Analytics)
