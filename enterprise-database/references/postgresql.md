# PostgreSQL Reference Guide

## Table of Contents
1. [Installation & Version Policy](#installation--version-policy)
2. [Configuration Tuning](#configuration-tuning)
3. [Essential Extensions](#essential-extensions)
4. [Replication Setup](#replication-setup)
5. [Partitioning](#partitioning)
6. [Advanced Security](#advanced-security)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Backup & Recovery Details](#backup--recovery-details)

---

## Installation & Version Policy

Always use the latest stable major version of PostgreSQL (currently PostgreSQL 17 as of early 2025). Use the official PostgreSQL repository for installation, not OS-provided packages, which are often outdated.

```bash
# Ubuntu/Debian — official PostgreSQL repo
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install postgresql-17
```

For Docker-based development:
```yaml
services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    command:
      - "postgres"
      - "-c" 
      - "shared_preload_libraries=pg_stat_statements,pgaudit"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./sql/init:/docker-entrypoint-initdb.d
```

---

## Configuration Tuning

PostgreSQL ships with very conservative defaults designed to run on minimal hardware. For any real workload, these must be tuned.

### Memory Settings

| Parameter | Recommended Value | Notes |
|-----------|------------------|-------|
| `shared_buffers` | 25% of total RAM | Main shared memory cache. 8GB on a 32GB machine. |
| `effective_cache_size` | 75% of total RAM | Hint to planner about OS cache. Does not allocate memory. |
| `work_mem` | 64MB–256MB | Per-sort/hash operation. Be careful — a complex query can use multiples of this. Start conservative. |
| `maintenance_work_mem` | 1GB–2GB | For VACUUM, CREATE INDEX, ALTER TABLE. Can be larger since these run less frequently. |
| `wal_buffers` | 64MB | WAL write buffer. 64MB is a safe default for most workloads. |
| `huge_pages` | `try` | Use huge pages if OS supports them. Reduces TLB misses for large shared_buffers. |

### Write-Ahead Log (WAL) Settings

```ini
# For production workloads
wal_level = replica                    # Enables replication and PITR
max_wal_senders = 10                   # Max concurrent replication connections
wal_keep_size = 1GB                    # Keep WAL segments for replication catch-up
archive_mode = on                      # Enable WAL archiving for PITR
archive_command = 'cp %p /backup/wal/%f'  # Customize for your backup solution
```

### Connection Settings

```ini
max_connections = 200                  # Tune based on expected load + pool size
superuser_reserved_connections = 3     # Keep emergency connections available
```

Use PgBouncer in front of PostgreSQL for connection pooling. Application-level pooling (from ORMs) is acceptable but PgBouncer is more efficient for high-concurrency scenarios.

```ini
# pgbouncer.ini essentials
[databases]
mydb = host=127.0.0.1 port=5432 dbname=mydb

[pgbouncer]
listen_port = 6432
pool_mode = transaction          # Best for most web applications
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
server_idle_timeout = 600
```

### Query Planner Settings

```ini
random_page_cost = 1.1               # Lower for SSDs (default 4.0 is for spinning disks)
effective_io_concurrency = 200        # For SSDs. Default 1 is for spinning disks.
default_statistics_target = 500       # More accurate planner stats (default 100)
```

### Autovacuum Tuning

Autovacuum must be enabled (it is by default). For high-write workloads, make it more aggressive:

```ini
autovacuum_max_workers = 6                    # Default 3 is too low for busy systems
autovacuum_naptime = 30s                      # Check more frequently
autovacuum_vacuum_threshold = 50              # Default 50 is fine
autovacuum_vacuum_scale_factor = 0.05         # Vacuum when 5% of rows changed (default 20%)
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.025       # Analyze when 2.5% changed (default 10%)
autovacuum_vacuum_cost_delay = 2ms            # Less throttling for faster vacuums
```

---

## Essential Extensions

Install these extensions by default for enterprise projects:

```sql
-- Performance monitoring (CRITICAL — enable in shared_preload_libraries)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Security auditing
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Cryptographic functions for column-level encryption
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Or use the newer gen_random_uuid() built into PostgreSQL 13+

-- Full text search (if needed)
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- Trigram similarity for fuzzy search

-- Table maintenance without locks
-- (install pg_repack separately — not bundled)
```

### pg_stat_statements Usage

This is the single most important tool for identifying slow queries:

```sql
-- Top 10 queries by total execution time
SELECT
  calls,
  round(total_exec_time::numeric, 2) AS total_ms,
  round(mean_exec_time::numeric, 2) AS avg_ms,
  round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS pct,
  substring(query, 1, 100) AS query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

---

## Replication Setup

### Streaming Replication (Primary-Replica)

**On the primary:**
```ini
# postgresql.conf
wal_level = replica
max_wal_senders = 10
wal_keep_size = 1GB
synchronous_commit = on           # Set to 'remote_apply' for synchronous replication
```

```sql
-- Create replication user
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '...';
```

```
# pg_hba.conf — allow replication connections from replica IP
host replication replicator REPLICA_IP/32 scram-sha-256
```

**On the replica:**
```bash
# Initial base backup
pg_basebackup -h PRIMARY_HOST -U replicator -D /var/lib/postgresql/17/main -Fp -Xs -P -R
# The -R flag creates standby.signal and sets primary_conninfo automatically
```

### Connection Routing

Use your application's read/write splitting or a proxy like PgPool-II:
- Write queries → primary
- Read queries → replicas
- Be aware of replication lag for reads after writes

---

## Partitioning

Use native declarative partitioning for tables expected to grow beyond ~10 million rows or where you need efficient data lifecycle management.

### Range Partitioning (Most Common — Time-Based Data)

```sql
-- Create partitioned table
CREATE TABLE events (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    event_type  TEXT NOT NULL,
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create partitions (automate this with pg_partman or a cron job)
CREATE TABLE events_2025_q1 PARTITION OF events
    FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');
CREATE TABLE events_2025_q2 PARTITION OF events
    FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');

-- Create a default partition to catch anything that doesn't match
CREATE TABLE events_default PARTITION OF events DEFAULT;

-- Indexes are created per partition
CREATE INDEX idx_events_2025_q1_type ON events_2025_q1 (event_type);
```

### Automating Partition Management

Use `pg_partman` extension to automate partition creation and retention:

```sql
CREATE EXTENSION pg_partman;

SELECT partman.create_parent(
    p_parent_table := 'public.events',
    p_control := 'created_at',
    p_type := 'native',
    p_interval := '1 month',
    p_premake := 3               -- Create 3 months ahead
);

-- Set retention (auto-drop old partitions)
UPDATE partman.part_config
SET retention = '12 months',
    retention_keep_table = false
WHERE parent_table = 'public.events';
```

---

## Advanced Security

### Row-Level Security (RLS) in Detail

```sql
-- Enable RLS on a multi-tenant table
ALTER TABLE customer_data ENABLE ROW LEVEL SECURITY;

-- Policy: users can only see their own tenant's data
CREATE POLICY tenant_isolation ON customer_data
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Force RLS even for table owners (important!)
ALTER TABLE customer_data FORCE ROW LEVEL SECURITY;

-- In your application, set the tenant context per request:
-- SET LOCAL app.current_tenant = 'tenant-uuid-here';
-- (SET LOCAL scopes to the current transaction)
```

### Column-Level Encryption

```sql
-- Encrypt sensitive data using pgcrypto
INSERT INTO users (email, ssn_encrypted)
VALUES (
    'user@example.com',
    pgp_sym_encrypt('123-45-6789', current_setting('app.encryption_key'))
);

-- Decrypt when reading
SELECT email,
       pgp_sym_decrypt(ssn_encrypted::bytea, current_setting('app.encryption_key')) AS ssn
FROM users
WHERE id = 1;
```

Store the encryption key in a secret manager, not in the database or application config.

### Audit Logging with pgaudit

```ini
# postgresql.conf
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'write, ddl'        # Log data changes and schema changes
pgaudit.log_catalog = off          # Don't log catalog queries (noisy)
pgaudit.log_parameter = on         # Include parameter values in logs
```

---

## Monitoring & Maintenance

### Key Metrics to Monitor

| Metric | Alert Threshold | Query/Method |
|--------|----------------|--------------|
| Active connections | > 80% of max_connections | `SELECT count(*) FROM pg_stat_activity WHERE state = 'active';` |
| Replication lag | > 30 seconds | `SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));` |
| Dead tuple ratio | > 10% of live tuples | `SELECT relname, n_dead_tup, n_live_tup FROM pg_stat_user_tables;` |
| Cache hit ratio | < 99% | `SELECT sum(blks_hit) / (sum(blks_hit) + sum(blks_read)) FROM pg_stat_database;` |
| Disk usage growth | > 80% of volume | OS-level monitoring |
| Long-running queries | > 5 minutes | `SELECT * FROM pg_stat_activity WHERE state = 'active' AND query_start < NOW() - INTERVAL '5 min';` |
| Unused indexes | Any | `SELECT * FROM pg_stat_user_indexes WHERE idx_scan = 0;` |

### Recommended Monitoring Stack

- **Prometheus** + **postgres_exporter** for metrics collection
- **Grafana** for dashboards (use the PostgreSQL dashboard template ID 9628)
- **pgwatch2** as an alternative all-in-one monitoring tool
- Cloud-managed: use the provider's built-in monitoring (CloudWatch for RDS, Azure Monitor, Cloud Monitoring)

---

## Backup & Recovery Details

### Continuous Archiving with Point-in-Time Recovery (PITR)

This is the gold standard for PostgreSQL backups:

```bash
# 1. Configure WAL archiving (postgresql.conf)
archive_mode = on
archive_command = 'aws s3 cp %p s3://my-backup-bucket/wal/%f'  # Example for S3

# 2. Take a base backup
pg_basebackup -h localhost -U backup_user -D /backup/base -Ft -z -P

# 3. To restore to a specific point in time:
# - Restore the base backup
# - Set recovery_target_time in postgresql.conf:
recovery_target_time = '2025-03-15 14:30:00 UTC'
restore_command = 'aws s3 cp s3://my-backup-bucket/wal/%f %p'
```

### Logical Backups

For smaller databases or when you need portable SQL dumps:

```bash
# Full database dump (compressed, custom format)
pg_dump -Fc -f /backup/mydb.dump mydb

# Schema only (for version control)
pg_dump --schema-only -f schema.sql mydb

# Specific tables
pg_dump -t users -t orders -Fc -f /backup/partial.dump mydb

# Restore
pg_restore -d mydb /backup/mydb.dump
```

### Automated Backup Script Example

```bash
#!/bin/bash
# /opt/scripts/pg_backup.sh — run via cron
set -euo pipefail

BACKUP_DIR="/backup/postgresql"
RETENTION_DAYS=30
DB_NAME="mydb"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup
pg_dump -Fc -f "${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump" "$DB_NAME"

# Verify backup is not empty
if [ ! -s "${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump" ]; then
    echo "ERROR: Backup file is empty!" >&2
    exit 1
fi

# Clean up old backups
find "$BACKUP_DIR" -name "*.dump" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: ${DB_NAME}_${TIMESTAMP}.dump"
```

---

## Row-Level Locking & TOCTOU Prevention

### The Problem: TOCTOU Race Conditions

Time-of-Check-to-Time-of-Use (TOCTOU) bugs occur when you read a value, make a decision, then write — but another concurrent request changes the value between your read and write. Common in credit/token/balance systems.

```
Request A: SELECT balance → 5 tokens
Request B: SELECT balance → 5 tokens (same stale read)
Request A: UPDATE balance SET balance = balance - 3 → 2 tokens ✓
Request B: UPDATE balance SET balance = balance - 3 → -1 tokens ✗ (overdraft!)
```

### Solution: SELECT FOR UPDATE in a Transaction

```sql
-- Lock rows before reading, preventing concurrent reads until transaction completes
BEGIN;
  SELECT id, "remainingTokens"
  FROM "TokenBatch"
  WHERE "userId" = $1
    AND "remainingTokens" > 0
    AND "expiresAt" > NOW()
  ORDER BY "createdAt" ASC
  FOR UPDATE;  -- Row-level lock: other transactions block here

  -- Now safe to check totals and deduct
  UPDATE "TokenBatch" SET "remainingTokens" = "remainingTokens" - $2 WHERE id = $3;
COMMIT;
```

### Prisma Interactive Transaction Pattern

Prisma doesn't support `FOR UPDATE` natively. Use `$queryRaw` inside an interactive transaction:

```typescript
export async function deductTokens(userId: string, amount: number): Promise<boolean> {
  return await prisma.$transaction(async (tx) => {
    // Lock rows with FOR UPDATE via raw SQL
    const batches = await tx.$queryRaw<
      { id: string; remainingTokens: number }[]
    >`SELECT id, "remainingTokens"
      FROM "TokenBatch"
      WHERE "userId" = ${userId}
        AND "remainingTokens" > 0
        AND "expiresAt" > ${new Date()}
      ORDER BY "createdAt" ASC
      FOR UPDATE`

    const total = batches.reduce((sum, b) => sum + b.remainingTokens, 0)
    if (total < amount) return false

    // FIFO deduction — oldest batch first
    let remaining = amount
    for (const batch of batches) {
      if (remaining <= 0) break
      const deduct = Math.min(batch.remainingTokens, remaining)
      await tx.tokenBatch.update({
        where: { id: batch.id },
        data: { remainingTokens: { decrement: deduct } },
      })
      remaining -= deduct
    }

    return true
  }, {
    isolationLevel: 'Serializable',
    timeout: 10000,
  })
}
```

### Key Guidelines

- **Always use `FOR UPDATE`** when reading data that determines a write decision (balances, quotas, inventory)
- **Use `Serializable` isolation** for financial operations (token deduction, payments, transfers)
- **Set a timeout** on transactions (10s is reasonable) to prevent deadlocks from hanging
- **FIFO ordering**: Use `ORDER BY "createdAt" ASC` when consuming from batches (oldest first)
- **Refund cap**: When refunding, cap at `totalTokens - remainingTokens` to prevent over-credit
- **Prisma `$queryRaw`**: Use template literals (not string concatenation) for parameterized raw queries
