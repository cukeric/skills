# Enterprise Search & Messaging Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | ~340 | Decision frameworks (search engine, broker, CQRS), EDA patterns, event schema, reliability/consistency/performance/observability priorities, outbox pattern, verification checklist |
| `references/elasticsearch-meilisearch.md` | ~300 | Meilisearch (index config, batch indexing, search, autocomplete, facets, multi-index), Elasticsearch (mapping, queries, aggregations, geo-search), search service pattern, index sync strategies |
| `references/kafka-rabbitmq-bullmq.md` | ~310 | BullMQ (queues, workers, scheduling, dashboard, shutdown), Kafka (producer, consumer, partitions), RabbitMQ (exchanges, DLQ, routing), broker comparison |
| `references/cqrs-patterns.md` | ~250 | Command pattern, read projections, event sourcing, aggregate rebuild, saga/process manager, eventual consistency UI handling |
| `references/webhook-management.md` | ~230 | Outgoing (signing, dispatch, delivery logs, test endpoint), incoming (signature verification, idempotent processing), event catalog |
| `references/background-jobs.md` | ~260 | Job types, BullMQ patterns (scheduling, rate limiting, flows, progress), idempotent workers, monitoring, graceful shutdown |

**Total: ~1,700+ lines of enterprise search & messaging patterns.**

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-search-messaging/references
cp SKILL.md ~/.claude/skills/enterprise-search-messaging/
cp references/* ~/.claude/skills/enterprise-search-messaging/references/
```

### Option B: Project-Level

```bash
mkdir -p .claude/skills/enterprise-search-messaging/references
cp SKILL.md .claude/skills/enterprise-search-messaging/
cp references/* .claude/skills/enterprise-search-messaging/references/
```

---

## Trigger Keywords

> search, full-text search, Elasticsearch, Meilisearch, Algolia, message queue, Kafka, RabbitMQ, BullMQ, event-driven, CQRS, event sourcing, pub/sub, webhook, background job, worker, cron, dead letter queue, idempotent, eventual consistency, saga

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-backend` | Message consumers are backend services; queue setup in backend layer |
| `enterprise-database` | Write store uses database patterns; projections may use different storage |
| `enterprise-deployment` | Broker infrastructure (Redis, Kafka) as Docker services |
| `enterprise-security` | Webhook HMAC signatures, event payload encryption |
