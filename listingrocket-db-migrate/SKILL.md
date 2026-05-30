---
name: listingrocket-db-migrate
description: ListingRocket-specific — run PostgreSQL migrations on the ListingRocket VPS via the saas_admin role. Credentials come from env (SAAS_ADMIN_PASSWORD), never hardcoded. ONLY for ListingRocket. Invoke via /listingrocket-db-migrate.
---

# Database Migration for ListingRocket

Run SQL migrations safely on the production PostgreSQL database using the `saas_admin` superuser.

## Critical Rules

1. **NEVER use `listinglaunch_app`** for DDL operations — it only has CRUD permissions
2. **ALWAYS use `saas_admin`** — it owns the tables and can run ALTER/CREATE/DROP
3. **ALWAYS review the SQL** with the user before executing
4. **ALWAYS back up affected tables** before destructive operations (ALTER DROP COLUMN, DROP TABLE)

## User Separation

| User | Permissions | Use For |
|------|-------------|---------|
| `saas_admin` / `${SAAS_ADMIN_PASSWORD}` | Superuser, owns all tables | Migrations, DDL, backups |
| `listinglaunch_app` / `${APP_DB_PASSWORD}` | SELECT/INSERT/UPDATE/DELETE only | App runtime queries |

## Migration Workflow

### Step 1: Generate SQL

If using Prisma schema changes:
```bash
cd /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/ListingRocket/frontend && npx prisma migrate diff --from-schema-datasource prisma/schema.prisma --to-schema-datamodel prisma/schema.prisma --script
```

Or write raw SQL for the migration.

### Step 2: Review with User

Present the exact SQL that will be executed. Wait for user approval.

### Step 3: Execute on VPS

```bash
ssh -i /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/vps_deploy_key root@77.42.18.40 \
  "docker exec saas-postgres psql 'postgresql://saas_admin:${SAAS_ADMIN_PASSWORD}@localhost:5432/listinglaunch' -c \"YOUR_SQL_HERE\""
```

For multi-statement migrations, use a heredoc:
```bash
ssh -i /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/vps_deploy_key root@77.42.18.40 \
  "docker exec saas-postgres psql 'postgresql://saas_admin:${SAAS_ADMIN_PASSWORD}@localhost:5432/listinglaunch' <<'SQL'
BEGIN;
-- migration statements here
COMMIT;
SQL"
```

### Step 4: Verify

After migration, verify the changes:
```bash
ssh -i /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/vps_deploy_key root@77.42.18.40 \
  "docker exec saas-postgres psql 'postgresql://saas_admin:${SAAS_ADMIN_PASSWORD}@localhost:5432/listinglaunch' -c \"\\dt\""
```

### Step 5: Regenerate Prisma Client

If schema.prisma was updated:
```bash
cd /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/ListingRocket/frontend && npx prisma generate
```

Then rebuild and deploy the app (use `/deploy`).

## Backup Before Destructive Changes

```bash
ssh -i /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/vps_deploy_key root@77.42.18.40 \
  "docker exec saas-postgres pg_dump -U saas_admin -d listinglaunch -t TABLE_NAME --data-only > /tmp/backup_TABLE_NAME_$(date +%Y%m%d).sql"
```

## Common Patterns

### Add a column
```sql
ALTER TABLE "TableName" ADD COLUMN "columnName" TEXT;
```

### Add a column with default + backfill
```sql
ALTER TABLE "TableName" ADD COLUMN "columnName" INTEGER DEFAULT 0;
UPDATE "TableName" SET "columnName" = 0 WHERE "columnName" IS NULL;
ALTER TABLE "TableName" ALTER COLUMN "columnName" SET NOT NULL;
```

### Create an index
```sql
CREATE INDEX CONCURRENTLY idx_name ON "TableName" ("columnName");
```

### Grant permissions to app user after new table
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON "NewTable" TO listinglaunch_app;
```
