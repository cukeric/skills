---
name: enterprise-search-messaging
description: Explains how to implement full-text search, event-driven architecture, message queues, CQRS patterns, and background job processing with enterprise standards. Trigger on ANY mention of search, full-text search, Elasticsearch, Meilisearch, Algolia, Typesense, message queue, Kafka, RabbitMQ, BullMQ, event-driven, CQRS, event sourcing, pub/sub, publish subscribe, webhook, webhook management, background job, worker, cron job, scheduled task, dead letter queue, idempotent, eventual consistency, event bus, saga pattern, domain event, command query, queue, consumer, producer, broker, or any request requiring search functionality, event processing, asynchronous messaging, or background task orchestration.
---

# Enterprise Search & Messaging Skill

Every search or messaging system created or modified using this skill must meet enterprise-grade standards for reliability, data consistency, observability, and performance — in that priority order. These systems are the nervous system of modern applications: search makes data discoverable, messaging makes systems decoupled and resilient. Failures here cascade. Even for MVPs, idempotency and dead letter handling must be production-ready from day one.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) based on the project's requirements:

### Search Engines

- `references/elasticsearch-meilisearch.md` — Engine selection, index design, mapping, analyzers, faceted search, autocomplete, relevance tuning

### Message Brokers & Queues

- `references/kafka-rabbitmq-bullmq.md` — Broker selection, Kafka topics/partitions/consumer groups, RabbitMQ exchanges, BullMQ Redis-backed queues, dead letter patterns

### CQRS & Event Sourcing

- `references/cqrs-patterns.md` — Command/query separation, event sourcing, projections, eventual consistency, domain events, saga orchestration

### Webhook Management

- `references/webhook-management.md` — Outgoing webhooks, signature verification, retry with backoff, delivery guarantees, webhook testing, event catalog

### Background Jobs

- `references/background-jobs.md` — Job scheduling, cron patterns, prioritization, rate limiting, monitoring, graceful shutdown, idempotent workers

Read this SKILL.md first for architecture decisions and standards, then consult the relevant reference files for implementation specifics.

---

## Decision Framework: Choosing the Right Components

### Search Engine Selection

| Requirement | Best Choice | Why |
|---|---|---|
| Full-text search, complex queries | **Elasticsearch** | Most powerful, aggregations, geo, ML ranking |
| Simple search, fast setup | **Meilisearch** | Typo-tolerant, instant results, minimal config |
| Real-time search, low latency | **Typesense** | Sub-10ms, easy clustering |
| Hosted, zero-ops | **Algolia** | Managed service, instant search widgets |
| Already using PostgreSQL | **pg_trgm + tsvector** | No extra infra, good for < 1M docs |

**Default: Meilisearch** for most applications. Switch to Elasticsearch when you need aggregations, geo-queries, or handle 10M+ documents.

### Message Broker Selection

| Requirement | Best Choice | Why |
|---|---|---|
| High-throughput event streaming | **Kafka** | Millions/sec, replay, partitioning, log compaction |
| Complex routing, RPC patterns | **RabbitMQ** | Exchange types, routing keys, request-reply |
| Node.js job queue, Redis-backed | **BullMQ** | Simple, Redis-based, dashboard (Bull Board), delays |
| Serverless / cloud-native | **AWS SQS + SNS** | Zero-ops, auto-scaling, FIFO support |
| Simple pub/sub, already using Redis | **Redis Streams/Pub-Sub** | No extra infra, lightweight |

**Default: BullMQ** for Node.js applications. Scale to Kafka when throughput exceeds 10K events/sec or you need event replay.

### When to Use CQRS

| Signal | Use CQRS | Don't Use CQRS |
|---|---|---|
| Read/write patterns differ significantly | ✅ | |
| Read model needs denormalized views | ✅ | |
| Simple CRUD with balanced reads/writes | | ✅ |
| Need event audit trail / replay | ✅ | |
| Small team, simple domain | | ✅ |
| Multiple read projections needed | ✅ | |

**Default: Don't use CQRS.** Use it only when reads and writes have genuinely different scaling needs or data shapes.

---

## Architecture Patterns

### Event-Driven Architecture (EDA)

```
┌──────────┐     ┌─────────────┐     ┌──────────────┐
│ Producer  │────▶│   Broker    │────▶│   Consumer   │
│ (Service) │     │ (Kafka/RMQ) │     │  (Workers)   │
└──────────┘     └─────────────┘     └──────────────┘
                       │
                       ├────▶ Consumer Group A (Order Processing)
                       ├────▶ Consumer Group B (Notifications)
                       ├────▶ Consumer Group C (Analytics)
                       └────▶ Dead Letter Queue
```

### Event Design Principles

1. **Events are facts** — they describe something that happened, past tense: `OrderCreated`, `PaymentProcessed`, `UserRegistered`.
2. **Events are immutable** — once published, never modified.
3. **Events carry sufficient data** — include enough context so consumers don't need to call back to the producer.
4. **Events have a schema** — version all events, use a schema registry for Kafka.
5. **Events are ordered within a partition** — use entity ID as partition key.

### Event Schema

```typescript
interface DomainEvent<T = unknown> {
  id: string                  // UUID v4
  type: string                // 'order.created', 'payment.processed'
  version: number             // Schema version (1, 2, 3...)
  timestamp: string           // ISO 8601
  source: string              // 'order-service', 'payment-service'
  correlationId: string       // Trace across services
  causationId: string         // ID of event that caused this
  data: T                     // Event-specific payload
  metadata: {
    userId?: string           // Who triggered it
    tenantId?: string         // Multi-tenant isolation
    environment: string       // 'production', 'staging'
  }
}

// Example
const orderCreatedEvent: DomainEvent<OrderCreatedPayload> = {
  id: 'evt_abc123',
  type: 'order.created',
  version: 1,
  timestamp: '2024-06-20T14:22:00Z',
  source: 'order-service',
  correlationId: 'req_xyz789',
  causationId: 'cmd_create_order_456',
  data: {
    orderId: 'ord_001',
    customerId: 'cust_042',
    items: [{ productId: 'prod_01', quantity: 2, priceCents: 2999 }],
    totalCents: 5998,
    currency: 'USD',
  },
  metadata: {
    userId: 'user_admin_01',
    tenantId: 'tenant_acme',
    environment: 'production',
  },
}
```

---

## Priority 1: Reliability

### Idempotent Consumers (Non-Negotiable)

Every consumer must handle duplicate messages safely. Messages WILL be delivered more than once.

```typescript
// Idempotent consumer pattern
async function handleOrderCreated(event: DomainEvent<OrderCreatedPayload>) {
  // Check if already processed
  const existing = await db.processedEvents.findUnique({
    where: { eventId: event.id },
  })

  if (existing) {
    logger.info({ eventId: event.id }, 'Event already processed, skipping')
    return
  }

  // Process in transaction
  await db.$transaction(async (tx) => {
    // Business logic
    await tx.order.create({ data: mapToOrder(event.data) })

    // Mark as processed (idempotency key)
    await tx.processedEvents.create({
      data: { eventId: event.id, processedAt: new Date() },
    })
  })
}
```

### Dead Letter Queues (Non-Negotiable)

Messages that fail processing after max retries go to a dead letter queue for investigation.

```typescript
// BullMQ dead letter pattern
const orderQueue = new Queue('orders', {
  connection: redis,
  defaultJobOptions: {
    attempts: 5,
    backoff: { type: 'exponential', delay: 1000 }, // 1s, 2s, 4s, 8s, 16s
    removeOnComplete: { age: 24 * 3600 },           // Keep 24h
    removeOnFail: false,                              // Keep failed for inspection
  },
})

// Failed jobs automatically go to the failed set
// Monitor with Bull Board or custom dashboard
```

### Retry Strategy

| Attempt | Delay | Total Elapsed |
|---|---|---|
| 1 | 1 second | 1s |
| 2 | 2 seconds | 3s |
| 3 | 4 seconds | 7s |
| 4 | 8 seconds | 15s |
| 5 | 16 seconds | 31s |
| Dead Letter | — | Investigation |

---

## Priority 2: Data Consistency

### Outbox Pattern (Transactional Messaging)

Ensures database writes and event publishing are atomic — prevents ghost events or lost events.

```typescript
// 1. Write data + event in same transaction
await db.$transaction(async (tx) => {
  const order = await tx.order.create({ data: orderData })

  await tx.outbox.create({
    data: {
      id: generateId(),
      aggregateType: 'Order',
      aggregateId: order.id,
      eventType: 'order.created',
      payload: JSON.stringify(order),
      createdAt: new Date(),
      published: false,
    },
  })
})

// 2. Separate process polls outbox and publishes
async function publishOutboxEvents() {
  const unpublished = await db.outbox.findMany({
    where: { published: false },
    orderBy: { createdAt: 'asc' },
    take: 100,
  })

  for (const event of unpublished) {
    try {
      await broker.publish(event.eventType, event.payload)
      await db.outbox.update({
        where: { id: event.id },
        data: { published: true, publishedAt: new Date() },
      })
    } catch (error) {
      logger.error({ eventId: event.id, error }, 'Failed to publish outbox event')
    }
  }
}
```

---

## Priority 3: Performance

### Search Performance Targets

| Metric | Target |
|---|---|
| Autocomplete/typeahead | < 50ms |
| Full-text search | < 200ms |
| Faceted search + aggregations | < 500ms |
| Search index update lag | < 5 seconds |
| Reindex full dataset (1M docs) | < 30 minutes |

### Messaging Performance Targets

| Metric | Target |
|---|---|
| Message publish latency | < 10ms |
| End-to-end processing (P99) | < 1 second |
| Consumer throughput | > 1000 msg/sec per worker |
| Queue depth alert threshold | > 10,000 messages |
| Dead letter rate | < 0.1% |

---

## Priority 4: Observability

### What to Monitor

- **Queue depth** — growing queues indicate consumers can't keep up
- **Processing latency** — time from enqueue to completion
- **Error rate** — percentage of failed message processing
- **Dead letter count** — requires investigation
- **Consumer lag** — Kafka consumer group lag
- **Search latency** — P50, P95, P99 response times
- **Index size** — storage growth rate

### Structured Event Logging

```typescript
logger.info({
  event: 'message_processed',
  queue: 'orders',
  jobId: job.id,
  eventType: 'order.created',
  processingTimeMs: Date.now() - startTime,
  attempt: job.attemptsMade,
  correlationId: event.correlationId,
}, 'Order event processed successfully')
```

---

## Testing Requirements

### What Must Be Tested

- [ ] Search: indexing, querying, facets, autocomplete return expected results
- [ ] Search: typo tolerance and relevance ranking
- [ ] Messages: producer publishes events with correct schema
- [ ] Messages: consumer processes events idempotently (send same event twice)
- [ ] Messages: failed messages land in dead letter queue
- [ ] Messages: retry backoff works correctly
- [ ] Webhooks: signature verification rejects tampered payloads
- [ ] Webhooks: retry logic handles server errors vs client errors
- [ ] CQRS: commands update write store, projections update read store
- [ ] Background jobs: scheduled jobs execute at correct intervals
- [ ] Background jobs: graceful shutdown completes in-flight jobs

---

## Integration with Other Enterprise Skills

- **enterprise-backend**: Message consumers are backend services. Queue setup and event publishing happen in the backend layer.
- **enterprise-database**: Write store uses database skill patterns (transactions, migrations). Read projections may use different storage (Redis, Elasticsearch).
- **enterprise-deployment**: Message brokers (Redis, Kafka) run as Docker containers alongside the app. Monitoring via the deployment skill's observability stack.
- **enterprise-security**: Webhook signatures use HMAC-SHA256. Event payloads may contain PII requiring encryption at rest.

---

## Verification Checklist

Before considering any search/messaging work complete, verify:

- [ ] Search engine selected with documented rationale
- [ ] Search index schema designed with appropriate analyzers
- [ ] Message broker selected with documented rationale
- [ ] All events follow the domain event schema (id, type, version, timestamp)
- [ ] All consumers are idempotent (duplicate message safe)
- [ ] Dead letter queue configured with alerting
- [ ] Retry strategy uses exponential backoff
- [ ] Outbox pattern used for transactional publishing (if applicable)
- [ ] Queue depth monitoring with alerts configured
- [ ] Structured logging on all event processing
- [ ] Consumer graceful shutdown handles in-flight messages
- [ ] Webhook signatures verified on all incoming webhooks
- [ ] Search latency within targets (< 200ms full-text)
- [ ] Message processing latency within targets (< 1s P99)
