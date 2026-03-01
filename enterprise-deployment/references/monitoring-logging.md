# Monitoring, Logging & Alerting Reference

## Two Paths

| Concern | Azure / Enterprise (Env A) | VPS / Self-Hosted (Env B) |
|---|---|---|
| APM (Application Performance) | **Azure Application Insights** | **Sentry** (errors) + **Prometheus** (metrics) |
| Log aggregation | **Azure Log Analytics** (KQL queries) | **Grafana Loki** or **Logtail** (SaaS) |
| Dashboards | **Azure Monitor Workbooks** | **Grafana** |
| Alerting | **Azure Monitor Alerts** → email/SMS/Teams | **Alertmanager** or **Better Stack** → Slack/PagerDuty |
| Uptime monitoring | **Azure Availability Tests** | **UptimeRobot** or **Better Stack** |
| Infrastructure metrics | Built into Azure Monitor | **Prometheus Node Exporter** |

---

# ENVIRONMENT A: Azure Monitor + Application Insights

## Application Insights Setup

```bash
# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --resource-group $RG --workspace-name myapp-logs --location $LOCATION

# Create Application Insights
az monitor app-insights component create \
  --app myapp-insights \
  --resource-group $RG \
  --location $LOCATION \
  --workspace $(az monitor log-analytics workspace show --resource-group $RG --workspace-name myapp-logs --query id -o tsv)

# Get connection string
az monitor app-insights component show --app myapp-insights --resource-group $RG --query connectionString -o tsv
```

### Node.js Integration

```bash
pnpm add applicationinsights
```

```typescript
// src/lib/telemetry.ts — import FIRST in your entry point
import * as appInsights from 'applicationinsights'

if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights.setup()
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true, true)
    .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C)
    .start()
}

export const telemetryClient = appInsights.defaultClient

// Custom event tracking
export function trackEvent(name: string, properties?: Record<string, string>) {
  telemetryClient?.trackEvent({ name, properties })
}

// Custom metric
export function trackMetric(name: string, value: number) {
  telemetryClient?.trackMetric({ name, value })
}
```

```typescript
// src/server.ts
import './lib/telemetry'  // Must be first import
import { buildApp } from './app'
// ...
```

### Python Integration

```bash
pip install opencensus-ext-azure
```

```python
from opencensus.ext.azure.log_exporter import AzureLogHandler
from opencensus.ext.azure.trace_exporter import AzureExporter
import logging

logger = logging.getLogger(__name__)
logger.addHandler(AzureLogHandler(connection_string=settings.APPINSIGHTS_CONNECTION_STRING))
```

### KQL Queries (Log Analytics)

```kusto
// Failed requests in last hour
requests
| where timestamp > ago(1h)
| where resultCode >= 400
| summarize count() by resultCode, name
| order by count_ desc

// Slow API endpoints (p95 > 500ms)
requests
| where timestamp > ago(24h)
| summarize p95=percentile(duration, 95), count=count() by name
| where p95 > 500
| order by p95 desc

// Exception trends
exceptions
| where timestamp > ago(7d)
| summarize count() by bin(timestamp, 1h), type
| render timechart

// Dependency failures (DB, Redis, external APIs)
dependencies
| where timestamp > ago(1h)
| where success == false
| summarize count() by target, type, resultCode
```

### Azure Monitor Alerts

```bash
# Alert: Error rate > 5% in 5 minutes
az monitor metrics alert create \
  --name "high-error-rate" \
  --resource-group $RG \
  --scopes $(az monitor app-insights component show --app myapp-insights --resource-group $RG --query id -o tsv) \
  --condition "avg requests/failed > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action-group $ACTION_GROUP_ID \
  --severity 1

# Alert: Response time p95 > 2 seconds
az monitor metrics alert create \
  --name "high-latency" \
  --resource-group $RG \
  --scopes $(az monitor app-insights component show --app myapp-insights --resource-group $RG --query id -o tsv) \
  --condition "avg requests/duration > 2000" \
  --window-size 5m \
  --severity 2

# Action group (where alerts go)
az monitor action-group create \
  --name "ops-team" \
  --resource-group $RG \
  --short-name "ops" \
  --email-receiver name="oncall" email="oncall@company.com" \
  --webhook-receiver name="slack" uri="https://hooks.slack.com/..."
```

### Availability Tests (Uptime)

```bash
# Ping test from multiple Azure regions
az monitor app-insights web-test create \
  --resource-group $RG \
  --name "health-check" \
  --defined-web-test-name "health-check" \
  --location "us-va-ash-azr" \
  --frequency 300 \
  --timeout 30 \
  --kind "ping" \
  --locations '[{"Id":"us-va-ash-azr"},{"Id":"emea-nl-ams-azr"},{"Id":"apac-jp-kaw-edge"}]' \
  --web-test-url "https://myapp.com/health" \
  --expected-status-code 200
```

---

# ENVIRONMENT B: VPS Monitoring Stack

## Structured Application Logging

### Node.js (pino)

```typescript
// src/lib/logger.ts
import pino from 'pino'

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: process.env.NODE_ENV === 'development'
    ? { target: 'pino-pretty', options: { colorize: true } }
    : undefined,
  redact: ['req.headers.authorization', 'req.headers.cookie', 'password', 'token'],
  serializers: {
    req: (req) => ({
      method: req.method,
      url: req.url,
      remoteAddress: req.remoteAddress,
    }),
    err: pino.stdSerializers.err,
  },
})

// Usage
logger.info({ userId: user.id, action: 'login' }, 'User logged in')
logger.error({ err, orderId }, 'Payment processing failed')
```

### Python (structlog)

```python
import structlog

structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer(),
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
)

logger = structlog.get_logger()
logger.info("user_login", user_id=user.id, ip=request.client.host)
```

## Sentry (Error Tracking)

```bash
pnpm add @sentry/node
```

```typescript
import * as Sentry from '@sentry/node'

Sentry.init({
  dsn: env.SENTRY_DSN,
  environment: env.NODE_ENV,
  tracesSampleRate: env.NODE_ENV === 'production' ? 0.1 : 1.0,
  integrations: [
    Sentry.httpIntegration(),
    Sentry.expressIntegration(),
  ],
})

// Capture unhandled errors
process.on('unhandledRejection', (reason) => {
  Sentry.captureException(reason)
})
```

## Prometheus + Grafana (Docker Compose)

```yaml
# monitoring/docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "127.0.0.1:9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "127.0.0.1:3001:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: https://grafana.myapp.com

  node-exporter:
    image: prom/node-exporter:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'

  loki:
    image: grafana/loki:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:3100:3100"
    volumes:
      - loki_data:/loki

  promtail:
    image: grafana/promtail:latest
    restart: unless-stopped
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./promtail.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml

volumes:
  prometheus_data:
  grafana_data:
  loki_data:
```

### Prometheus Config

```yaml
# monitoring/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'app'
    static_configs:
      - targets: ['api:3000']
    metrics_path: /metrics
```

---

## External Uptime Monitoring (Both Environments)

Use an external service that pings from outside your infrastructure:

**Recommended:** UptimeRobot (free tier: 50 monitors, 5-min interval) or Better Stack (free tier: 10 monitors, 3-min interval)

Configure:
- URL: `https://myapp.com/health`
- Interval: 1-5 minutes
- Alert channels: Email + Slack + SMS (for critical)
- Expected response: HTTP 200 with body containing `"healthy"`

---

## Alert Thresholds (Both Environments)

| Metric | Warning | Critical | Action |
|---|---|---|---|
| Error rate (5xx) | > 1% over 5 min | > 5% over 5 min | Investigate → rollback if needed |
| Response time (p95) | > 1s | > 3s | Check DB queries, connections |
| CPU usage | > 70% for 10 min | > 90% for 5 min | Scale up / optimize |
| Memory usage | > 80% | > 90% | Investigate leaks, increase limits |
| Disk usage | > 70% | > 85% | Clean up, expand volume |
| Health check | 1 failure | 3 consecutive failures | Auto-restart or alert |
| SSL certificate | 30 days to expiry | 7 days to expiry | Renew immediately |

---

## Checklist

- [ ] Structured JSON logging from application (pino / structlog)
- [ ] Logs aggregated (Log Analytics / Loki / SaaS)
- [ ] Error tracking active (App Insights / Sentry)
- [ ] Application metrics exposed and collected
- [ ] Infrastructure metrics collected (CPU, memory, disk, network)
- [ ] Dashboards created for key metrics
- [ ] Alert rules configured with appropriate thresholds
- [ ] Alert channels connected (email, Slack, PagerDuty)
- [ ] External uptime monitoring active
- [ ] Log retention policy defined (30-90 days)
- [ ] Sensitive data redacted from logs (passwords, tokens, PII)
