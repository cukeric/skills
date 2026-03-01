---
name: enterprise-deployment
description: Explains how to deploy, host, configure, monitor, or manage infrastructure for applications with enterprise standards. Trigger on ANY mention of deploy, deployment, hosting, server, VPS, cloud, Azure, AWS, GCP, Docker, container, Kubernetes, AKS, nginx, reverse proxy, SSL, TLS, HTTPS, certificate, Let's Encrypt, CI/CD, pipeline, GitHub Actions, Azure DevOps, DevOps, build, release, staging, production, environment, secrets, Key Vault, monitoring, logging, App Insights, Application Insights, Sentry, Grafana, Prometheus, uptime, health check, load balancer, CDN, WAF, firewall, backup, rollback, blue-green, deployment slot, infrastructure, IaC, Bicep, Terraform, ARM template, domain, DNS, or any request to get an application running in production. Also trigger when the user asks about server setup, going live, publishing an app, making something accessible on the internet, or when a project clearly requires deployment infrastructure even if the word deploy is never used. This skill applies to new deployments AND modifications to existing infrastructure.
---

# Enterprise Deployment Skill

Every deployment created or modified using this skill must meet enterprise-grade standards for security, reliability, observability, and scalability — in that priority order. A well-built application is worthless if it's deployed insecurely, goes down without alerting anyone, or can't be updated without downtime. There are no shortcuts in production infrastructure.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) based on the deployment target and requirements:

### Environment A: Azure / Enterprise Cloud
- `references/azure-cloud-deployment.md` — Azure App Service, Container Apps, AKS, Front Door, Application Gateway, VNets, Private Endpoints, Key Vault, Managed Identity
- `references/azure-devops-cicd.md` — Azure DevOps Pipelines, build/release YAML, deployment slots, environment approvals, Bicep IaC, Azure Repos + GitHub integration

### Environment B: VPS / Self-Hosted
- `references/vps-setup.md` — Ubuntu server hardening, SSH, firewall, fail2ban, user permissions, initial provisioning
- `references/nginx-ssl.md` — Reverse proxy, SSL/TLS via Let's Encrypt, HTTP/2, WebSocket proxy, static asset caching

### Both Environments
- `references/docker-containerization.md` — Dockerfiles (Node.js + Python), multi-stage builds, docker-compose, Azure Container Registry, image security
- `references/github-actions-cicd.md` — GitHub Actions pipelines, environment promotion, deploy to Azure / VPS, rollback, secrets management
- `references/monitoring-logging.md` — Azure Monitor + App Insights (enterprise), Grafana + Prometheus + Sentry (VPS), structured logging, alerting, uptime
- `references/environment-management.md` — Secrets strategy (Key Vault vs .env), database migrations in CI, blue-green / deployment slots, backup & restore, geo-redundancy

Read this SKILL.md first for architecture decisions and standards, then consult the relevant reference files for implementation specifics.

---

## Decision Framework: Choosing the Right Deployment Target

### Environment Selection Matrix

| Question | Azure / Enterprise (Env A) | VPS / Self-Hosted (Env B) |
|---|---|---|
| Who manages infrastructure? | Cloud platform (PaaS/managed) | You (full control, full responsibility) |
| Budget | Higher baseline, scales with usage | Fixed monthly cost, predictable |
| Team size | Medium-large, dedicated DevOps | Small team, developers wear ops hat |
| Compliance requirements | SOC 2, HIPAA, ISO 27001 built-in | You implement and audit yourself |
| Scaling needs | Auto-scale to thousands of instances | Manual scaling, vertical first |
| SSO / Azure AD integration | Native, seamless | Works but requires more configuration |
| Deployment complexity | Higher initial setup, lower ongoing | Lower initial, higher ongoing maintenance |
| Best for | Enterprise SaaS, corporate apps, B2B | Side projects, startups, cost-sensitive, learning |

### Azure Service Selection

| Need | Azure Service | Why |
|---|---|---|
| Simple web app / API (default) | **App Service** | Managed, deployment slots, auto-scale, custom domains, easy |
| Containerized app, event-driven | **Container Apps** | Serverless containers, KEDA scaling, Dapr integration |
| Full Kubernetes control | **AKS** | Complex microservices, multi-team, need k8s ecosystem |
| Static frontend + API | **Static Web Apps** | Free tier, built-in auth, API via Functions |
| Background jobs / event processing | **Functions** | Serverless, consumption billing, event triggers |
| Global CDN + WAF | **Front Door** | Edge caching, DDoS protection, SSL termination, global routing |
| Internal load balancing | **Application Gateway** | L7 load balancer, WAF, SSL offload, within VNet |

**Default for most projects: App Service** (web app) + **Azure Front Door** (CDN/WAF) + **Key Vault** (secrets) + **Azure Monitor** (observability).

### VPS Provider Selection

| Provider | Strength | Starting Price |
|---|---|---|
| **Hetzner** | Best price/performance in EU | €4/mo (2 vCPU, 4GB) |
| **DigitalOcean** | Simple UX, good docs | $6/mo (1 vCPU, 1GB) |
| **Linode (Akamai)** | Reliable, good networking | $5/mo (1 vCPU, 1GB) |
| **Vultr** | Many regions, bare metal options | $6/mo (1 vCPU, 1GB) |
| **OVH** | Cheapest high-spec in EU | €6/mo (2 vCPU, 4GB) |

**Default VPS stack:** Docker Compose + nginx + Certbot + GitHub Actions deploy.

---

## Priority 1: Security

### Network Security
- **Azure:** Virtual Networks with subnets, Network Security Groups (NSGs), Private Endpoints for databases/Redis/storage. No public IPs on backend resources.
- **VPS:** UFW firewall allowing only 22 (SSH), 80 (HTTP→redirect), 443 (HTTPS). Block everything else.
- **Both:** No management ports exposed to the internet. SSH via key only, no password auth.

### Secrets Management
- **Azure:** Azure Key Vault with Managed Identity. Applications authenticate to Key Vault without stored credentials.
- **VPS:** `.env` files with strict permissions (600), or Doppler/Infisical for managed secrets.
- **Both:** Never commit secrets to git. Different secrets per environment. Rotate regularly.

### SSL / TLS
- **Azure:** Managed certificates on App Service / Front Door (free, auto-renewing). Or bring your own from Key Vault.
- **VPS:** Let's Encrypt via Certbot with auto-renewal cron. Force HTTPS redirect.
- **Both:** TLS 1.2 minimum. HSTS header enabled. A+ rating on SSL Labs.

### Container Security
- **Minimal base images** — `node:22-alpine`, `python:3.12-slim`, not full distros.
- **Non-root user** inside containers. Never run as root.
- **Scan images** with Trivy, Snyk, or Azure Defender for containers.
- **Pin image digests** in production (not just tags).
- **No secrets in Dockerfiles or image layers.**

---

## Priority 2: Reliability

### Zero-Downtime Deployments
- **Azure:** Deployment slots (staging → swap → production). Test in staging slot, swap instantly.
- **VPS:** Blue-green with nginx upstream switching, or rolling restart with health check gates.
- **Both:** Health check endpoint must return 200 before traffic routes to new version.

### Health Checks
Every application must expose:
- `/health` — full dependency check (DB, Redis, external services). Returns 200 if healthy, 503 if degraded.
- `/healthz` — liveness probe (process is running). Always 200.
- `/readyz` — readiness probe (can serve traffic). 200 only when all dependencies connected.

### Rollback Strategy
- **Azure:** Swap back to previous deployment slot (instant). Or redeploy previous container image tag.
- **VPS:** Keep previous Docker image. Rollback = `docker compose up -d` with previous image tag.
- **Both:** Database migrations must be forward-compatible. Never deploy a migration that breaks the previous app version.

### Backup & Recovery
- **Azure:** Azure Backup for App Service, automated database backups (point-in-time restore), geo-redundant storage.
- **VPS:** Automated database dumps (pg_dump) to object storage (S3/Backblaze B2). Test restores monthly.
- **Both:** Documented disaster recovery procedure. RTO and RPO defined per environment.

---

## Priority 3: Observability

### Logging
- **Structured JSON logs** from application (pino for Node.js, structlog for Python).
- **Azure:** Logs flow to Azure Monitor / Log Analytics workspace. Query with KQL.
- **VPS:** Logs flow to file → collected by Promtail/Fluentd → aggregated in Grafana Loki or shipped to a SaaS (Datadog, Logtail).
- **Both:** Log levels: ERROR (alert), WARN (investigate), INFO (business events), DEBUG (dev only, never in prod).

### Metrics & Alerting
- **Azure:** Application Insights for APM (request rates, response times, exceptions, dependencies). Azure Monitor alerts.
- **VPS:** Prometheus for metrics collection, Grafana for dashboards, Alertmanager or PagerDuty for alerts.
- **Both:** Alert on: error rate > 1%, p95 latency > 1s, health check failures, disk > 80%, memory > 85%.

### Uptime Monitoring
- External uptime monitor (UptimeRobot, Better Stack, Checkly) pinging `/health` every 1-5 minutes.
- Alert via SMS/Slack/PagerDuty within 2 minutes of downtime detection.

---

## Priority 4: Scalability

### Azure Scaling
- **App Service:** Auto-scale rules based on CPU, memory, or HTTP queue length. Scale out (more instances) not up.
- **Container Apps:** KEDA-based scaling (HTTP concurrent requests, queue depth, custom metrics). Scale to zero for cost savings.
- **AKS:** Horizontal Pod Autoscaler (HPA) + Cluster Autoscaler.

### VPS Scaling
- **Vertical first:** Upgrade VPS tier (more CPU/RAM) — simplest, no architecture changes.
- **Horizontal:** Add VPS instances behind a load balancer (DigitalOcean LB, Hetzner LB, or self-managed HAProxy/nginx).
- **Offload static assets** to a CDN (Cloudflare, BunnyCDN) to reduce server load.
- **Database scaling:** Move from local PostgreSQL to managed (Supabase, Neon, or cloud-provider managed DB).

### Caching Layers
- **CDN** for static assets and cacheable API responses (Cloudflare, Azure Front Door, CloudFront).
- **Redis** for application-level caching, sessions, rate limiting.
- **HTTP cache headers** (Cache-Control, ETag) on API responses where appropriate.

---

## Project Structure: Infrastructure as Code

### Azure (Bicep)

```
infra/
├── main.bicep                # Entry point — orchestrates modules
├── modules/
│   ├── app-service.bicep     # App Service + plan
│   ├── container-registry.bicep
│   ├── key-vault.bicep
│   ├── database.bicep        # Azure Database for PostgreSQL Flexible Server
│   ├── redis.bicep            # Azure Cache for Redis
│   ├── front-door.bicep       # CDN + WAF
│   ├── monitoring.bicep       # App Insights + Log Analytics
│   └── networking.bicep       # VNet + subnets + NSGs + Private Endpoints
├── parameters/
│   ├── dev.bicepparam
│   ├── staging.bicepparam
│   └── prod.bicepparam
└── scripts/
    └── deploy.sh
```

### VPS (Docker Compose)

```
deploy/
├── docker-compose.yml         # Production compose file
├── docker-compose.dev.yml     # Dev overrides
├── Dockerfile                 # Application Dockerfile
├── nginx/
│   ├── nginx.conf
│   └── sites/
│       └── app.conf           # Reverse proxy config
├── scripts/
│   ├── setup-server.sh        # Initial VPS provisioning
│   ├── deploy.sh              # Pull + restart
│   └── backup.sh              # Database backup to S3
├── .env.example               # Template (no real values)
└── monitoring/
    ├── prometheus.yml
    └── grafana/
        └── dashboards/
```

---

## Integration with Other Enterprise Skills

- **enterprise-database**: Deployment provisions the database infrastructure (Azure Flexible Server / VPS PostgreSQL) and runs migrations in the CI/CD pipeline.
- **enterprise-backend**: Deployment containerizes and deploys the backend API, configures environment variables, and connects to Key Vault or secrets management.
- **enterprise-frontend**: Deployment builds the frontend (static export or SSR server), deploys to CDN or App Service, and configures caching headers.

---

## Verification Checklist

Before considering any deployment complete, verify:

- [ ] HTTPS enforced on all endpoints (no plain HTTP)
- [ ] SSL Labs rating A or A+
- [ ] Health check endpoint returns 200 and checks all dependencies
- [ ] Secrets loaded from Key Vault / secret manager (none in code or env files in git)
- [ ] Firewall rules allow only necessary ports
- [ ] SSH key-only authentication (VPS) or Managed Identity (Azure)
- [ ] CI/CD pipeline runs: lint → test → build → deploy with rollback capability
- [ ] Structured logs flowing to aggregation service
- [ ] Alerts configured for error rate, latency, health check failures
- [ ] External uptime monitor active
- [ ] Database backups automated and tested
- [ ] Zero-downtime deployment verified (deployment slots or blue-green)
- [ ] Container images scanned for vulnerabilities
- [ ] DNS and domain configured with appropriate TTL
