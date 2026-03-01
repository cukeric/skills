# GitHub Actions CI/CD Reference

## Pipeline Architecture

```
┌──────────────┐    ┌───────────────┐    ┌──────────────┐    ┌──────────────┐
│  Push / PR   │───▶│ Lint + Test   │───▶│ Build Image  │───▶│   Deploy     │
│              │    │               │    │ Push to Reg  │    │ (Staging/    │
│              │    │               │    │              │    │  Production) │
└──────────────┘    └───────────────┘    └──────────────┘    └──────────────┘
```

---

## Full Pipeline: Node.js Application

```yaml
# .github/workflows/ci-cd.yml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read
  packages: write

jobs:
  # ═══════════════════════════════════════
  # Job 1: Lint & Test
  # ═══════════════════════════════════════
  test:
    name: Lint & Test
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: testuser
          POSTGRES_PASSWORD: testpass
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U testuser -d testdb"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with:
          version: 9

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Lint
        run: pnpm lint

      - name: Type check
        run: pnpm typecheck

      - name: Run tests
        run: pnpm test -- --coverage
        env:
          DATABASE_URL: postgresql://testuser:testpass@localhost:5432/testdb
          REDIS_URL: redis://localhost:6379

      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  # ═══════════════════════════════════════
  # Job 2: Build & Push Docker Image
  # ═══════════════════════════════════════
  build:
    name: Build & Push Image
    runs-on: ubuntu-latest
    needs: test
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
      image-digest: ${{ steps.build.outputs.digest }}

    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scan image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          severity: 'CRITICAL,HIGH'
          exit-code: '1'

  # ═══════════════════════════════════════
  # Job 3A: Deploy to Azure (Enterprise)
  # ═══════════════════════════════════════
  deploy-azure:
    name: Deploy to Azure
    runs-on: ubuntu-latest
    needs: build
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    environment: production    # Requires manual approval (configure in GitHub Settings)

    steps:
      - name: Login to Azure
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Deploy to staging slot
        uses: azure/webapps-deploy@v3
        with:
          app-name: myapp-prod-api
          slot-name: staging
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

      - name: Wait for staging health
        run: |
          for i in $(seq 1 30); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://myapp-prod-api-staging.azurewebsites.net/health)
            if [ "$STATUS" = "200" ]; then echo "✅ Staging healthy"; exit 0; fi
            echo "Attempt $i: $STATUS"; sleep 10
          done
          echo "❌ Staging unhealthy"; exit 1

      - name: Swap staging to production
        run: |
          az webapp deployment slot swap \
            --name myapp-prod-api \
            --resource-group myapp-prod-rg \
            --slot staging --target-slot production

      - name: Verify production
        run: |
          sleep 15
          STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://myapp-prod-api.azurewebsites.net/health)
          if [ "$STATUS" != "200" ]; then
            echo "❌ Production unhealthy — rolling back"
            az webapp deployment slot swap \
              --name myapp-prod-api --resource-group myapp-prod-rg \
              --slot production --target-slot staging
            exit 1
          fi
          echo "✅ Production healthy"

  # ═══════════════════════════════════════
  # Job 3B: Deploy to VPS (Non-Enterprise)
  # ═══════════════════════════════════════
  deploy-vps:
    name: Deploy to VPS
    runs-on: ubuntu-latest
    needs: build
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    environment: production

    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: deploy
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /home/deploy/apps/myapp

            # Pull new image
            echo "${{ secrets.GHCR_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            docker compose pull

            # Run migrations
            docker compose run --rm api npx prisma migrate deploy

            # Deploy with health check
            docker compose up -d --remove-orphans

            # Verify
            sleep 10
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)
            if [ "$STATUS" != "200" ]; then
              echo "❌ Deploy failed — check logs"
              docker compose logs --tail=50 api
              exit 1
            fi
            echo "✅ Deployed successfully"

            # Cleanup
            docker image prune -f
```

---

## Python Pipeline

```yaml
# .github/workflows/ci-cd-python.yml
name: Python CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env: { POSTGRES_DB: testdb, POSTGRES_USER: testuser, POSTGRES_PASSWORD: testpass }
        ports: ['5432:5432']
        options: --health-cmd "pg_isready" --health-interval 10s --health-timeout 5s --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'

      - name: Install dependencies
        run: pip install -r requirements.txt -r requirements-dev.txt

      - name: Lint
        run: |
          ruff check .
          ruff format --check .

      - name: Type check
        run: mypy src/

      - name: Run tests
        run: pytest --cov=src --cov-report=xml -v
        env:
          DATABASE_URL: postgresql://testuser:testpass@localhost:5432/testdb

  # build and deploy jobs follow same pattern as Node.js above
```

---

## Secrets Management in GitHub Actions

### Required Secrets (Settings → Secrets and variables → Actions)

**Azure deployment:**
```
AZURE_CREDENTIALS    # JSON output from: az ad sp create-for-rbac --name "github-deploy" --role contributor --scopes /subscriptions/{sub-id}
```

**VPS deployment:**
```
VPS_HOST             # Server IP address
VPS_SSH_KEY          # Private SSH key for deploy user
GHCR_TOKEN           # GitHub token with packages:read
```

### Environment Protection Rules

Configure in Settings → Environments:

1. **staging** — auto-deploy, no approval required
2. **production** — require approval from 1-2 reviewers, 5 min wait timer, limit to `main` branch

---

## Reusable Workflow (for Multi-Service Repos)

```yaml
# .github/workflows/deploy-service.yml (reusable)
on:
  workflow_call:
    inputs:
      service-name:
        required: true
        type: string
      dockerfile-path:
        required: true
        type: string

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build ${{ inputs.service-name }}
        run: docker build -f ${{ inputs.dockerfile-path }} -t ghcr.io/${{ github.repository }}/${{ inputs.service-name }}:${{ github.sha }} .
      # ... push, deploy

# .github/workflows/ci.yml (caller)
jobs:
  deploy-api:
    uses: ./.github/workflows/deploy-service.yml
    with:
      service-name: api
      dockerfile-path: services/api/Dockerfile
  deploy-worker:
    uses: ./.github/workflows/deploy-service.yml
    with:
      service-name: worker
      dockerfile-path: services/worker/Dockerfile
```

---

## Checklist

- [ ] PR builds run lint + test (no deploy)
- [ ] Main branch pushes trigger full pipeline (test → build → deploy)
- [ ] Docker images tagged with commit SHA (not just `latest`)
- [ ] Image scanned for vulnerabilities before deploy
- [ ] Production environment requires manual approval
- [ ] Health check gates: staging must be healthy before production swap
- [ ] Auto-rollback on production health check failure
- [ ] Secrets stored in GitHub Secrets (never in workflow files)
- [ ] Dependency caching enabled (pnpm, pip, Docker layers)
- [ ] Database migrations run before app deploy
