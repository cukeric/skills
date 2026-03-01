---
name: enterprise-data-analytics
description: Explains how to implement ETL pipelines, reporting dashboards, data exports, analytics tracking, and data warehouse patterns with enterprise standards. Trigger on ANY mention of ETL, ELT, data pipeline, data transformation, reporting, report, dashboard, analytics, data export, CSV export, Excel export, PDF report, scheduled report, data warehouse, OLAP, star schema, dimensional modeling, materialized view, ClickHouse, BigQuery, data lake, Segment, PostHog, Plausible, Mixpanel, funnel analysis, cohort analysis, event tracking, analytics event, KPI, metrics, chart, visualization, Recharts, Chart.js, D3, data aggregation, batch processing, or any request requiring data processing, reporting, or analytics.
---

# Enterprise Data & Analytics Skill

Every data pipeline, report, and analytics implementation must meet enterprise-grade standards for accuracy, performance, and reliability. Bad data leads to bad decisions. Even for MVPs, data validation and idempotent processing must be production-ready from day one.

## Reference Files

### ETL Pipelines

- `references/etl-pipelines.md` — Pipeline architecture, Node.js/Python ETL, streaming transforms, scheduling, error handling, data validation

### Reporting & Dashboards

- `references/reporting-dashboards.md` — Chart.js/Recharts/D3, report builder patterns, scheduled reports, email delivery, dashboard design

### Data Exports

- `references/data-exports.md` — CSV/Excel generation, PDF reports, streaming large exports, signed download URLs, background export jobs

### Analytics Event Tracking

- `references/analytics-tracking.md` — Event schema design, Segment/PostHog/Plausible, server-side tracking, funnel analysis, cohort analysis

### Data Warehouse Patterns

- `references/data-warehouse.md` — Star schema, dimensional modeling, materialized views, ClickHouse/BigQuery, data retention policies

---

## Decision Framework

### Analytics Platform Selection

| Requirement | Best Choice | Why |
|---|---|---|
| Privacy-first, self-hosted | **PostHog** | Open source, feature flags, session replay |
| Privacy-first, no cookies | **Plausible** | Simple, lightweight, GDPR-compliant |
| Enterprise, customer data | **Segment** | Data routing, integrations, CDP |
| Product analytics | **Mixpanel / Amplitude** | Funnels, retention, behavioral analysis |
| Marketing analytics | **Google Analytics 4** | Free, attribution, audience |

**Default: PostHog** for product analytics. Plausible for simple page analytics.

### Data Export Technology

| Format | Library | Best For |
|---|---|---|
| CSV | papaparse / fast-csv | Simple tabular data, large datasets |
| Excel (.xlsx) | exceljs / xlsx | Formatted reports, multiple sheets |
| PDF | puppeteer / @react-pdf/renderer | Formatted documents, invoices |
| JSON | Native | API consumption, data interchange |

### ETL vs ELT

| Pattern | When | Tools |
|---|---|---|
| **ETL** | Transform before loading, data cleansing needed | Node.js streams, Python pandas |
| **ELT** | Warehouse does the transformation, raw data preserved | dbt, BigQuery, ClickHouse |

---

## Analytics Event Schema

```typescript
interface AnalyticsEvent {
  name: string                    // 'button_clicked', 'page_viewed', 'order_completed'
  properties: Record<string, unknown>  // Event-specific data
  timestamp: string               // ISO 8601
  userId?: string                 // Authenticated user
  anonymousId: string             // Device/session ID
  context: {
    page: { url: string; title: string; referrer: string }
    device: { type: string; os: string; browser: string }
    locale: string
    timezone: string
    campaign?: { source: string; medium: string; name: string }
  }
}

// Event naming convention: object_action
// ✅ 'order_completed', 'button_clicked', 'page_viewed'
// ❌ 'completed order', 'click', 'pageView'
```

### Core Events (Track These Minimum)

```typescript
// User lifecycle
track('user_signed_up', { method: 'email' | 'google' | 'github' })
track('user_logged_in', { method: 'email' | 'sso' })
track('user_onboarding_completed', { stepsCompleted: 5 })

// Product engagement
track('page_viewed', { pageName: 'Dashboard', url: '/dashboard' })
track('feature_used', { featureName: 'Search', context: 'header' })
track('button_clicked', { buttonName: 'Create Order', location: 'order-list' })

// Revenue
track('order_completed', { orderId: 'ord_123', totalCents: 9999, itemCount: 3 })
track('subscription_started', { plan: 'pro', interval: 'monthly', priceCents: 2999 })
track('subscription_cancelled', { plan: 'pro', reason: 'too-expensive' })
```

---

## Data Export Pattern

```typescript
// Background export job (for large datasets)
async function exportOrders(filters: OrderFilters, format: 'csv' | 'xlsx') {
  const jobId = generateId()

  await exportQueue.add('export-orders', {
    jobId,
    filters,
    format,
    userId: currentUser.id,
  })

  return { jobId, status: 'processing' }
}

// Worker
const exportWorker = new Worker('exports', async (job) => {
  const { filters, format, userId } = job.data

  // Stream from database
  const cursor = db.order.findMany({ where: filters, cursor: true })

  // Generate file
  const filePath = format === 'csv'
    ? await generateCSV(cursor)
    : await generateExcel(cursor)

  // Upload to S3
  const key = `exports/${userId}/${Date.now()}.${format}`
  const url = await uploadToS3(filePath, key)
  const signedUrl = await getSignedUrl(key, 24 * 3600) // 24h expiry

  // Notify user
  await notifyUser(userId, { type: 'export_ready', url: signedUrl })

  return { url: signedUrl }
})
```

---

## Verification Checklist

- [ ] Analytics events follow naming convention (object_action)
- [ ] Core lifecycle events tracked (signup, login, key actions)
- [ ] Event properties validated before sending
- [ ] Server-side tracking for revenue events (not client-only)
- [ ] Data exports work for large datasets (streaming, background jobs)
- [ ] Export files include proper headers and formatting
- [ ] Report scheduling works correctly (cron, timezone-aware)
- [ ] Dashboard queries optimized (materialized views, indexes)
- [ ] Data retention policy defined and automated
- [ ] PII handling compliant (anonymization, consent)
