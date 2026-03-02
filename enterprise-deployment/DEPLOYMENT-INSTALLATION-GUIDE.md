# Enterprise Deployment Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | 238 | Main skill: deployment target decision framework (Azure vs VPS), security/reliability/observability/scalability priority stack, IaC project structure, integration points, verification checklist |
| **Azure / Enterprise Cloud** | | |
| `references/azure-cloud-deployment.md` | 496 | Azure App Service, Container Apps, AKS, Front Door (CDN+WAF), Application Gateway, VNets, Private Endpoints, NSGs, Key Vault + Managed Identity, Bicep IaC templates, auto-scale rules |
| `references/azure-devops-cicd.md` | 386 | Azure DevOps YAML Pipelines: build→test→staging→approval→production swap, infrastructure pipelines (Bicep validate/what-if/deploy), ACR push, deployment slots, Key Vault variable groups, migration safety, GitHub Repos integration |
| **VPS / Self-Hosted** | | |
| `references/vps-setup.md` | 311 | Ubuntu 24.04 hardening: deploy user, SSH key-only with strong ciphers, UFW firewall (22/80/443 only), fail2ban, automatic security updates, swap space, Docker install, deploy script with rollback |
| `references/nginx-ssl.md` | 325 | Reverse proxy config, SSL/TLS via Let's Encrypt (Certbot), HTTP/2, security headers (HSTS, CSP, X-Frame), WebSocket proxy, SSE proxy (buffering disabled), rate limiting at proxy level, gzip, static asset caching, multi-app config, performance tuning |
| **Both Environments** | | |
| `references/docker-containerization.md` | 358 | Multi-stage Dockerfiles (Node.js + Python), non-root user, health checks, docker-compose production config (Postgres + Redis), dev overrides, ACR + GHCR push, Trivy image scanning, .dockerignore, container management commands |
| `references/github-actions-cicd.md` | 380 | Full CI/CD: lint→test→build→scan→deploy with service containers (Postgres/Redis), deploy to Azure (slot swap + auto-rollback) AND VPS (SSH), Python pipeline variant, environment protection rules, reusable workflows |
| `references/monitoring-logging.md` | 373 | **Azure path:** App Insights APM, Log Analytics (KQL queries), Azure Monitor alerts, availability tests. **VPS path:** pino/structlog structured logging, Sentry errors, Prometheus+Grafana+Loki stack (docker-compose), Node Exporter. Both: alert thresholds table, external uptime monitoring |
| `references/environment-management.md` | 387 | Key Vault secret management + rotation, .env strategy with file permissions, Doppler/Infisical alternatives, database migration safety (backward-compatible patterns), blue-green deployment (Azure slots + nginx switching), automated backup scripts (PostgreSQL → S3), restore procedures, disaster recovery runbook, DNS configuration |

**Total: ~3,254 lines of enterprise deployment patterns and infrastructure code.**

---

## Two-Environment Architecture

### Environment A — Azure / Enterprise Cloud
- App Service or Container Apps (default) / AKS (complex)
- Azure Front Door for CDN + WAF + global load balancing
- Virtual Networks + Private Endpoints (DB/Redis never public)
- Key Vault + Managed Identity (zero stored credentials)
- Azure DevOps Pipelines with deployment slots (staging→swap→production)
- App Insights + Log Analytics for full APM and logging
- Bicep infrastructure-as-code

### Environment B — VPS / Self-Hosted
- Hardened Ubuntu server (SSH keys, UFW, fail2ban)
- Docker Compose (app + Postgres + Redis)
- Nginx reverse proxy + Let's Encrypt SSL
- GitHub Actions CI/CD (SSH deploy with health check gates)
- Sentry + Prometheus + Grafana monitoring stack
- Automated pg_dump backups to S3

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-deployment/references
cp SKILL.md ~/.claude/skills/enterprise-deployment/
cp references/* ~/.claude/skills/enterprise-deployment/references/
ls -R ~/.claude/skills/enterprise-deployment/
```

### Option B: From .skill Package

```bash
mkdir -p ~/.claude/skills
tar -xzf enterprise-deployment.skill -C ~/.claude/skills/
ls -R ~/.claude/skills/enterprise-deployment/
```

### Option C: Project-Level

```bash
mkdir -p .claude/skills/enterprise-deployment/references
cp SKILL.md .claude/skills/enterprise-deployment/
cp references/* .claude/skills/enterprise-deployment/references/
```

---

## Trigger Keywords

> deploy, deployment, hosting, server, VPS, cloud, Azure, AWS, Docker, container, Kubernetes, AKS, nginx, reverse proxy, SSL, TLS, HTTPS, certificate, Let's Encrypt, CI/CD, pipeline, GitHub Actions, Azure DevOps, build, release, staging, production, environment, secrets, Key Vault, monitoring, logging, App Insights, Sentry, Grafana, Prometheus, uptime, health check, load balancer, CDN, WAF, firewall, backup, rollback, blue-green, deployment slot, Bicep, Terraform, DNS, go live

---

## Complete Skill Library

| Skill | Files | Lines | Covers |
|---|---|---|---|
| `enterprise-database` | 10 | ~3,000 | PostgreSQL, MongoDB, Redis, DynamoDB, ORMs, AWS/Azure/GCP deployment |
| `enterprise-frontend` | 8 | ~2,800 | React/Next.js, Vue/Nuxt, Svelte/SvelteKit, glassmorphic design, dashboards, accessibility |
| `enterprise-backend` | 8 | ~3,350 | APIs, auth (Azure AD SSO vs OAuth/MFA), Stripe, WebSockets, email, API design |
| `enterprise-deployment` | 9 | ~3,250 | Azure cloud + VPS, Docker, CI/CD (Azure DevOps + GitHub Actions), monitoring, secrets, backups |
| **Total** | **35** | **~12,400** | **Full-stack enterprise application lifecycle** |
