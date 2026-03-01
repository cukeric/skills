# Docker & Containerization Reference

## Dockerfile: Node.js (Multi-Stage Build)

```dockerfile
# ── Stage 1: Dependencies ──
FROM node:22-alpine AS deps
WORKDIR /app

# Enable corepack for pnpm
RUN corepack enable

# Copy lockfile first (cache layer)
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod=false

# ── Stage 2: Build ──
FROM node:22-alpine AS builder
WORKDIR /app

RUN corepack enable

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Generate Prisma client (if using Prisma)
RUN npx prisma generate 2>/dev/null || true

# Build application
RUN pnpm build

# Remove dev dependencies
RUN pnpm prune --prod

# ── Stage 3: Production ──
FROM node:22-alpine AS runner
WORKDIR /app

# Security: non-root user
RUN addgroup --system --gid 1001 appgroup && \
    adduser --system --uid 1001 appuser

# Install security updates
RUN apk update && apk upgrade --no-cache && apk add --no-cache dumb-init

# Copy production files
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package.json ./
COPY --from=builder --chown=appuser:appgroup /app/prisma ./prisma

# Environment
ENV NODE_ENV=production
ENV PORT=3000

# Switch to non-root user
USER appuser

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
```

---

## Dockerfile: Python (Multi-Stage Build)

```dockerfile
# ── Stage 1: Build ──
FROM python:3.12-slim AS builder
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Production ──
FROM python:3.12-slim AS runner
WORKDIR /app

# Security: non-root user
RUN groupadd --system --gid 1001 appgroup && \
    useradd --system --uid 1001 --gid appgroup appuser

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl && \
    rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application
COPY --chown=appuser:appgroup . .

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PORT=8000

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["gunicorn", "src.main:app", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8000"]
```

---

## Docker Compose: Production

```yaml
# docker-compose.yml
services:
  api:
    image: ghcr.io/your-org/myapp-api:${TAG:-latest}
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"    # Only expose to localhost (nginx proxies)
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"    # Localhost only
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 2G
    shm_size: 256m

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"    # Localhost only
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
```

### Docker Compose: Dev Overrides

```yaml
# docker-compose.dev.yml
# Usage: docker compose -f docker-compose.yml -f docker-compose.dev.yml up
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
      target: deps    # Stop at deps stage for dev
    command: pnpm dev
    volumes:
      - .:/app
      - /app/node_modules
    ports:
      - "3000:3000"
      - "9229:9229"   # Node.js debugger

  postgres:
    ports:
      - "5432:5432"   # Expose to host for DB tools

  redis:
    ports:
      - "6379:6379"   # Expose to host for redis-cli
```

---

## Azure Container Registry (ACR)

### Build & Push

```bash
# Login to ACR
az acr login --name myappregistry

# Build and push (from CI or local)
docker build -t myappregistry.azurecr.io/myapp-api:1.0.0 .
docker push myappregistry.azurecr.io/myapp-api:1.0.0

# Or build remotely on ACR (no local Docker needed)
az acr build --registry myappregistry --image myapp-api:1.0.0 --file Dockerfile .
```

### GitHub Container Registry (GHCR)

```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Build and push
docker build -t ghcr.io/your-org/myapp-api:1.0.0 .
docker push ghcr.io/your-org/myapp-api:1.0.0
```

---

## Image Security

### Scanning

```bash
# Trivy (local scanning)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp-api:latest

# In CI (GitHub Actions)
# - name: Scan image
#   uses: aquasecurity/trivy-action@master
#   with:
#     image-ref: ghcr.io/your-org/myapp-api:${{ github.sha }}
#     severity: 'CRITICAL,HIGH'
#     exit-code: '1'
```

### Best Practices

```dockerfile
# ✅ Use specific tags, not :latest
FROM node:22.12-alpine3.21

# ✅ Pin with digest for reproducibility in production
FROM node:22-alpine@sha256:abc123...

# ✅ Don't copy unnecessary files
# .dockerignore:
# node_modules, .git, .env, *.md, tests/, .github/

# ✅ Minimize layers — combine RUN commands
RUN apk update && apk upgrade --no-cache && apk add --no-cache dumb-init && rm -rf /var/cache/apk/*

# ✅ Never store secrets in images
# No: ENV DATABASE_URL=postgresql://...
# Yes: Use env_file or secrets management at runtime

# ✅ Use COPY not ADD (ADD has implicit tar extraction and URL fetching)
COPY . .
```

### .dockerignore

```
node_modules
.git
.github
.env
.env.*
*.md
tests/
coverage/
.vscode/
.idea/
Dockerfile
docker-compose*.yml
```

---

## Container Management Commands

```bash
# View running containers
docker compose ps

# View logs (follow)
docker compose logs -f api

# View resource usage
docker stats --no-stream

# Restart a specific service
docker compose restart api

# Pull latest and redeploy
docker compose pull && docker compose up -d

# Clean up unused images, volumes, networks
docker system prune -af --volumes

# Exec into running container
docker compose exec api sh

# Run one-off command (e.g., migration)
docker compose run --rm api npx prisma migrate deploy
```

---

## Checklist

- [ ] Multi-stage Dockerfile (separate build and runtime)
- [ ] Non-root user in production image
- [ ] HEALTHCHECK directive in Dockerfile
- [ ] .dockerignore excludes node_modules, .git, .env, tests
- [ ] Ports bound to 127.0.0.1 (not 0.0.0.0) in compose
- [ ] Resource limits set in compose deploy section
- [ ] Log rotation configured (json-file driver with max-size)
- [ ] Image scanned for vulnerabilities before deploy
- [ ] Secrets passed at runtime via env_file, never baked into image
- [ ] Persistent data in named volumes (not bind mounts in production)
