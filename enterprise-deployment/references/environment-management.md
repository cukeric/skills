# Environment & Secrets Management Reference

## Environment Strategy

### Three Standard Environments

| Environment | Purpose | Data | Deployment | Access |
|---|---|---|---|---|
| **Development** | Local coding, feature branches | Seed data, fake data | Automatic on push | All developers |
| **Staging** | Pre-production testing, QA | Copy of production (anonymized) | Auto on main merge | Dev team + QA |
| **Production** | Live user traffic | Real user data | Manual approval required | Restricted |

### Environment Parity Rule
Staging must mirror production as closely as possible: same Docker images, same infrastructure type (just smaller scale), same environment variable names (different values).

---

## Remote .env Protection (SCP/SSH Deployments)

When deploying via SCP to a VPS, **never overwrite the remote `.env` file**. The remote server has its own environment configuration with production secrets, database URLs, and API keys that differ from local development.

### Safe SCP Deployment Pattern

```bash
# CORRECT: Transfer only build artifacts, never .env
scp -i $KEY build.tar.gz user@server:/app/
ssh -i $KEY user@server "cd /app && tar -xzf build.tar.gz && rm build.tar.gz && systemctl restart myapp"

# WRONG: Transferring entire project directory (includes .env)
scp -r -i $KEY ./ user@server:/app/    # NEVER DO THIS

# WRONG: Explicitly sending .env
scp -i $KEY .env user@server:/app/.env  # NEVER DO THIS
```

### Rules
- **Build artifacts only**: Transfer compiled output (`.next/standalone`, `dist/`, etc.), not source or config
- **Schema separately**: If DB schema changed, transfer `schema.prisma` alone and run migrations on server
- **Verify exclusion**: Before any `scp` command, mentally confirm `.env` is not in the transfer set
- **If schema changes**: Transfer schema file alone, then run `prisma db push` on the server

---

## Secrets Management

### Azure: Key Vault (Enterprise)

```bash
# Create Key Vault
az keyvault create --name myapp-prod-kv --resource-group $RG --location $LOCATION

# Add secrets
az keyvault secret set --vault-name myapp-prod-kv --name database-url --value "postgresql://..."
az keyvault secret set --vault-name myapp-prod-kv --name redis-url --value "rediss://..."
az keyvault secret set --vault-name myapp-prod-kv --name stripe-secret-key --value "sk_live_..."
az keyvault secret set --vault-name myapp-prod-kv --name resend-api-key --value "re_..."
az keyvault secret set --vault-name myapp-prod-kv --name azure-ad-client-secret --value "..."

# Separate Key Vaults per environment
# myapp-dev-kv, myapp-staging-kv, myapp-prod-kv

# App Service reads via Key Vault references (zero code changes)
# App Setting: DATABASE_URL = @Microsoft.KeyVault(SecretUri=https://myapp-prod-kv.vault.azure.net/secrets/database-url/)
```

### Secret Rotation

```bash
# Rotate a secret in Key Vault
az keyvault secret set --vault-name myapp-prod-kv --name database-url --value "postgresql://new-connection-string"

# App Service picks up new value within minutes (or force restart)
az webapp restart --name myapp-prod-api --resource-group $RG

# For secrets that need coordinated rotation (e.g., database password):
# 1. Create new credential in DB
# 2. Update Key Vault secret with new credential
# 3. Restart app to pick up new secret
# 4. Remove old credential from DB
```

### VPS: .env Files

```bash
# .env.example (committed to git — template only, no real values)
NODE_ENV=production
PORT=3000

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/myapp
DB_POOL_SIZE=20

# Redis
REDIS_URL=redis://:password@localhost:6379

# Auth
SESSION_SECRET=generate-random-64-char-string
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
AZURE_TENANT_ID=

# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Email
RESEND_API_KEY=re_...
EMAIL_DOMAIN=myapp.com

# App
APP_URL=https://myapp.com
FRONTEND_URL=https://myapp.com
COOKIE_DOMAIN=myapp.com
CORS_ORIGINS=https://myapp.com,https://admin.myapp.com
```

```bash
# Production .env file on server (strict permissions)
chmod 600 /home/deploy/apps/myapp/.env
chown deploy:deploy /home/deploy/apps/myapp/.env

# Never commit .env to git
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore
echo "!.env.example" >> .gitignore
```

### Managed Secrets Services (VPS Alternative to Key Vault)

| Service | Pricing | Best For |
|---|---|---|
| **Doppler** | Free for 5 projects | Multi-environment, team sync |
| **Infisical** | Free self-hosted, $6/user SaaS | Open-source, self-hostable |
| **AWS Secrets Manager** | $0.40/secret/month | AWS ecosystem |
| **1Password Secrets** | Part of Teams plan | Teams already using 1Password |

```bash
# Doppler example: inject secrets at runtime
doppler run --project myapp --config production -- node dist/server.js

# Or export to .env file
doppler secrets download --project myapp --config production --no-file --format env > .env
```

---

## Database Migrations in CI/CD

### Migration Strategy

```
1. Developer creates migration locally
2. Migration committed to git with application code
3. CI pipeline runs migration on staging DB during deploy
4. After manual approval, CI runs migration on production DB
5. New application version deploys (works with both old and new schema)
```

### Backward-Compatible Migrations (Critical)

Migrations must work with BOTH the current and new application version during deployment:

```
✅ SAFE:
- Add nullable column
- Add new table
- Add index
- Add column with default value

❌ UNSAFE (needs two-step deploy):
- Drop column (Step 1: remove code usage → Step 2: drop column)
- Rename column (Step 1: add new column, backfill → Step 2: drop old column)
- Change column type
- Add NOT NULL without default
```

### Running Migrations in Pipeline

```yaml
# GitHub Actions
- name: Run migrations
  run: |
    docker compose run --rm api npx prisma migrate deploy
  env:
    DATABASE_URL: ${{ secrets.STAGING_DATABASE_URL }}

# Azure DevOps
- script: |
    az webapp ssh --name $APP --resource-group $RG --slot staging \
      --command "npx prisma migrate deploy"
  displayName: 'Run database migrations'
```

### Migration Verification

```bash
# Before deploying to production, verify:

# 1. Migration has been tested on staging
# 2. Migration is backward-compatible
# 3. Migration has a rollback plan

# Prisma: check pending migrations
npx prisma migrate status

# Check migration drift
npx prisma migrate diff --from-schema-datamodel prisma/schema.prisma --to-migrations prisma/migrations
```

---

## Blue-Green / Zero-Downtime Deployment

### Azure: Deployment Slots

```bash
# Slot swap is instant and zero-downtime
# Slots share the App Service Plan but have independent:
# - App settings (environment variables)
# - Connection strings
# - Custom domains (optional)
# - Deployment sources

# Sticky settings (stay with the slot, not swapped)
az webapp config appsettings set --name $APP --resource-group $RG \
  --slot-settings SLOT_NAME=staging   # This stays in staging even after swap
```

### VPS: Blue-Green with nginx

```bash
#!/bin/bash
# deploy-blue-green.sh
# Two containers: myapp-blue and myapp-green
# nginx points to one; deploy to the other, then switch

ACTIVE=$(docker ps --format '{{.Names}}' | grep myapp | head -1)

if [[ "$ACTIVE" == *"blue"* ]]; then
  DEPLOY_TO="green"
  DEPLOY_PORT=3001
else
  DEPLOY_TO="blue"
  DEPLOY_PORT=3000
fi

echo "Active: $ACTIVE → Deploying to: myapp-$DEPLOY_TO (port $DEPLOY_PORT)"

# Start new version on inactive port
docker compose up -d "myapp-$DEPLOY_TO"

# Wait for health check
for i in $(seq 1 30); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$DEPLOY_PORT/health")
  if [ "$STATUS" = "200" ]; then
    echo "✅ myapp-$DEPLOY_TO is healthy"
    break
  fi
  sleep 5
done

# Switch nginx upstream to new container
sed -i "s/proxy_pass http:\/\/127.0.0.1:[0-9]*/proxy_pass http:\/\/127.0.0.1:$DEPLOY_PORT/" /etc/nginx/sites-available/myapp.conf
nginx -t && systemctl reload nginx

# Stop old container (after a drain period)
sleep 30
docker compose stop "$ACTIVE"

echo "✅ Deployed to myapp-$DEPLOY_TO"
```

---

## Backup & Disaster Recovery

### Azure Backups

```bash
# App Service Backup (automatic)
az webapp config backup create \
  --webapp-name $APP --resource-group $RG \
  --backup-name "daily-backup" \
  --container-url "$STORAGE_SAS_URL" \
  --db-connection-string "$DATABASE_URL" \
  --db-name myapp \
  --db-type PostgreSql \
  --frequency 1d \
  --retain-one true \
  --retention 30

# Azure Database for PostgreSQL — Point-in-Time Restore
# Automatic backups retained for 7-35 days (configurable)
az postgres flexible-server restore \
  --resource-group $RG \
  --name myapp-db-restored \
  --source-server myapp-db \
  --restore-point-in-time "2024-06-15T10:30:00Z"

# Geo-Redundant Storage
az storage account create \
  --name myappbackups \
  --resource-group $RG \
  --sku Standard_GRS \
  --kind StorageV2
```

### VPS Backups

```bash
#!/bin/bash
# /home/deploy/scripts/backup.sh
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/deploy/backups"
S3_BUCKET="s3://myapp-backups"

# PostgreSQL dump
docker compose exec -T postgres pg_dump -U $DB_USER $DB_NAME | gzip > "$BACKUP_DIR/db_$TIMESTAMP.sql.gz"

# Upload to S3 (or Backblaze B2, Wasabi, etc.)
aws s3 cp "$BACKUP_DIR/db_$TIMESTAMP.sql.gz" "$S3_BUCKET/postgres/"

# Clean local backups older than 7 days
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

# Clean remote backups older than 30 days
aws s3 ls "$S3_BUCKET/postgres/" | awk '{print $4}' | while read file; do
  DATE=$(echo "$file" | grep -oP '\d{8}')
  if [[ $(date -d "$DATE" +%s) -lt $(date -d "30 days ago" +%s) ]]; then
    aws s3 rm "$S3_BUCKET/postgres/$file"
  fi
done

echo "✅ Backup completed: db_$TIMESTAMP.sql.gz"
```

```bash
# Schedule via cron (daily at 2 AM UTC)
crontab -e
# 0 2 * * * /home/deploy/scripts/backup.sh >> /var/log/backup.log 2>&1
```

### Restore Procedure

```bash
# VPS: Restore PostgreSQL from backup
gunzip -c db_20240615_020000.sql.gz | docker compose exec -T postgres psql -U $DB_USER $DB_NAME

# Verify restore
docker compose exec postgres psql -U $DB_USER -d $DB_NAME -c "SELECT count(*) FROM users;"
```

### Disaster Recovery Runbook

```markdown
## DR Procedure

### Severity 1: Complete Infrastructure Loss
1. Provision new VPS / Azure resources (using IaC: Bicep or setup scripts)
2. Restore database from latest backup
3. Deploy latest Docker image
4. Update DNS to point to new infrastructure
5. Verify health checks pass
6. RTO target: 2 hours (VPS), 30 minutes (Azure with geo-redundancy)

### Severity 2: Application Failure
1. Check health endpoints and logs
2. If deployment-related: rollback to previous version (slot swap or Docker image)
3. If data-related: restore from point-in-time backup
4. RTO target: 15 minutes

### Severity 3: Degraded Performance
1. Check monitoring dashboards for bottleneck
2. Scale up/out if resource constrained
3. Check for slow queries, connection pool exhaustion, or external service issues
4. RTO target: 30 minutes
```

---

## DNS & Domain Configuration

```bash
# Typical DNS records
# A record:       myapp.com → server IP (or Azure Front Door IP)
# CNAME record:   www.myapp.com → myapp.com
# CNAME record:   api.myapp.com → myapp-prod-api.azurewebsites.net (Azure)
# MX record:      myapp.com → mail provider
# TXT record:     SPF, DKIM, DMARC for email deliverability

# Recommended TTL:
# Production A/CNAME: 300 seconds (5 min) — allows fast failover
# MX/TXT: 3600 seconds (1 hour) — rarely changes
# During migration: temporarily lower TTL to 60 seconds
```

---

## Checklist

- [ ] Secrets in Key Vault (Azure) or .env with 600 permissions (VPS), never in git
- [ ] Separate secrets per environment (dev, staging, prod)
- [ ] Secret rotation procedure documented and tested
- [ ] Database migrations run in CI before app deploy
- [ ] Migrations are backward-compatible (no breaking changes in single deploy)
- [ ] Zero-downtime deployment verified (slot swap or blue-green)
- [ ] Automated database backups (daily minimum)
- [ ] Backup restoration tested (at least monthly)
- [ ] Disaster recovery runbook written and accessible
- [ ] DNS configured with appropriate TTL
- [ ] Geo-redundant backups for production data
