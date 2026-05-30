---
name: listingrocket-deploy
description: ListingRocket-specific — deploy the ListingRocket frontend to its Hetzner VPS (build verification, rsync, Docker rebuild, smoke tests). ONLY for the ListingRocket project. Invoke via /listingrocket-deploy.
---

# Deploy ListingRocket to Production

Standardized deployment workflow for the ListingRocket VPS (Hetzner, Docker Compose, Nginx + Cloudflare).

## Pre-Deployment Checks

Before deploying, verify:

1. `npm run build` succeeds locally (in `frontend/`)
2. No uncommitted changes that should be included
3. All new env vars have been set on VPS (rsync excludes `.env.local`)

## Deployment Steps

Execute these steps in order:

### Step 1: Build Verification

```bash
cd /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/ListingRocket/frontend && npm run build
```

If build fails, fix errors before proceeding. Do NOT skip this step.

### Step 2: Rsync to VPS

```bash
rsync -avz -e "ssh -i /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/vps_deploy_key" \
  --exclude node_modules \
  --exclude .next \
  --exclude .env.local \
  --exclude .git \
  /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/ListingRocket/frontend/ \
  root@77.42.18.40:/root/saas/listinglaunch/frontend/
```

### Step 3: Docker Rebuild & Restart

```bash
ssh -i /Users/cikacule/Desktop/GEMS/dev/Projects/SAAS/vps_deploy_key root@77.42.18.40 \
  "cd /root/saas/listinglaunch && docker compose build && docker compose up -d"
```

### Step 4: Post-Deploy Smoke Tests

Run these curl checks against production:

```bash
# Landing page
curl -s -o /dev/null -w "%{http_code}" https://listingrocket.app

# Auth guard (should redirect 307)
curl -s -o /dev/null -w "%{http_code}" https://listingrocket.app/dashboard

# API health (should 401 without auth)
curl -s -o /dev/null -w "%{http_code}" https://listingrocket.app/api/billing/credits

# Admin login page (should 200)
curl -s -o /dev/null -w "%{http_code}" https://listingrocket.app/admin

# Analytics endpoint (should 405 for GET)
curl -s -o /dev/null -w "%{http_code}" https://listingrocket.app/api/analytics/track
```

Expected results: 200, 307, 401, 200, 405

### Step 5: Report

Report the results of each step to the user. If any smoke test fails, investigate immediately.

## Important Notes

- **rsync excludes `.env.local`** — new env vars must be set manually on VPS via SSH
- **NEXTAUTH_URL on VPS** must be `https://listingrocket.app` (not localhost)
- **DB migrations** are separate — use `/db-migrate` skill for schema changes
- **Docker build cache**: Use `docker compose build --no-cache` if env changes aren't picked up
