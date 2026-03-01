# Enterprise Data & Analytics Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | ~220 | Decision frameworks (analytics platform, export format, ETL vs ELT), event schema design, data export patterns, verification checklist |
| `references/etl-pipelines.md` | ~150 | Node.js stream ETL, batch processing, scheduling, error handling |
| `references/reporting-dashboards.md` | ~130 | Recharts, scheduled reports with email delivery, materialized views |
| `references/data-exports.md` | ~130 | CSV/Excel streaming, background export jobs, signed download URLs |
| `references/analytics-tracking.md` | ~130 | PostHog server/client, event taxonomy, funnel analysis |
| `references/data-warehouse.md` | ~130 | Star schema, dimensional modeling, materialized views, ClickHouse, retention |

**Total: ~900+ lines of enterprise data & analytics patterns.**

---

## Installation

```bash
mkdir -p ~/.claude/skills/enterprise-data-analytics/references
cp SKILL.md ~/.claude/skills/enterprise-data-analytics/
cp references/* ~/.claude/skills/enterprise-data-analytics/references/
```

---

## Trigger Keywords

> ETL, data pipeline, reporting, dashboard, analytics, data export, CSV, Excel, PDF report, PostHog, Segment, funnel, cohort, KPI, chart, Recharts, data warehouse, materialized view, ClickHouse

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-backend` | API endpoints for reports and exports |
| `enterprise-database` | Materialized views, query optimization |
| `enterprise-search-messaging` | Background job queues for exports and ETL |
| `enterprise-frontend` | Dashboard UI with chart components |
