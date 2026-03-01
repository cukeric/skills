# Kafka, RabbitMQ & BullMQ Reference

## BullMQ (Recommended Default for Node.js)

### Setup

```bash
npm install bullmq ioredis
npm install -D @bull-board/api @bull-board/express  # Dashboard
```

### Queue Configuration

```typescript
// src/lib/queue.ts
import { Queue, Worker, QueueEvents } from 'bullmq'
import IORedis from 'ioredis'

const connection = new IORedis(process.env.REDIS_URL!, { maxRetriesPerRequest: null })

// Define queues
export const emailQueue = new Queue('emails', {
  connection,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 1000 },
    removeOnComplete: { age: 24 * 3600, count: 1000 },
    removeOnFail: { age: 7 * 24 * 3600 },
  },
})

export const orderQueue = new Queue('orders', {
  connection,
  defaultJobOptions: {
    attempts: 5,
    backoff: { type: 'exponential', delay: 2000 },
    removeOnComplete: { age: 48 * 3600 },
    removeOnFail: false,
  },
})

export const reportQueue = new Queue('reports', {
  connection,
  defaultJobOptions: {
    attempts: 2,
    timeout: 5 * 60 * 1000,  // 5 min timeout for long reports
  },
})
```

### Workers

```typescript
// src/workers/email.worker.ts
import { Worker, Job } from 'bullmq'
import { connection } from '@/lib/queue'

interface SendEmailJob {
  to: string
  subject: string
  template: string
  data: Record<string, unknown>
}

const emailWorker = new Worker<SendEmailJob>(
  'emails',
  async (job: Job<SendEmailJob>) => {
    const { to, subject, template, data } = job.data

    // Update progress
    await job.updateProgress(10)

    const html = await renderTemplate(template, data)
    await job.updateProgress(50)

    await emailProvider.send({ to, subject, html })
    await job.updateProgress(100)

    return { sent: true, messageId: 'msg_123' }
  },
  {
    connection,
    concurrency: 5,         // Process 5 emails at a time
    limiter: {
      max: 100,             // Max 100 emails
      duration: 60_000,     // per minute (rate limit)
    },
  }
)

emailWorker.on('completed', (job) => {
  logger.info({ jobId: job.id, to: job.data.to }, 'Email sent')
})

emailWorker.on('failed', (job, error) => {
  logger.error({ jobId: job?.id, error: error.message }, 'Email failed')
})
```

### Job Scheduling

```typescript
// Delayed jobs
await emailQueue.add('welcome-email', { to: 'user@example.com', ... }, {
  delay: 5 * 60 * 1000,  // Send in 5 minutes
})

// Repeatable jobs (cron)
await reportQueue.add('daily-report', { type: 'daily' }, {
  repeat: { pattern: '0 9 * * *' },  // Every day at 9 AM
  jobId: 'daily-report',             // Prevent duplicates
})

await reportQueue.add('weekly-digest', { type: 'weekly' }, {
  repeat: { pattern: '0 10 * * 1' }, // Every Monday at 10 AM
})

// Priority jobs (lower number = higher priority)
await orderQueue.add('urgent-order', { orderId: '123' }, { priority: 1 })
await orderQueue.add('normal-order', { orderId: '456' }, { priority: 5 })
```

### Bull Board Dashboard

```typescript
import { createBullBoard } from '@bull-board/api'
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter'
import { ExpressAdapter } from '@bull-board/express'

const serverAdapter = new ExpressAdapter()
serverAdapter.setBasePath('/admin/queues')

createBullBoard({
  queues: [
    new BullMQAdapter(emailQueue),
    new BullMQAdapter(orderQueue),
    new BullMQAdapter(reportQueue),
  ],
  serverAdapter,
})

app.use('/admin/queues', authMiddleware, serverAdapter.getRouter())
```

### Graceful Shutdown

```typescript
async function gracefulShutdown() {
  logger.info('Shutting down workers...')

  // Stop accepting new jobs, finish current ones
  await Promise.all([
    emailWorker.close(),
    orderWorker.close(),
  ])

  // Close queue connections
  await Promise.all([
    emailQueue.close(),
    orderQueue.close(),
  ])

  await connection.quit()
  logger.info('All workers shut down')
  process.exit(0)
}

process.on('SIGTERM', gracefulShutdown)
process.on('SIGINT', gracefulShutdown)
```

---

## Kafka (High-Throughput Event Streaming)

### Setup

```bash
npm install kafkajs
```

```yaml
# docker-compose.yml
services:
  kafka:
    image: confluentinc/cp-kafka:7.5.0
    ports:
      - 9092:9092
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://localhost:9092'
      KAFKA_PROCESS_ROLES: 'broker,controller'
      KAFKA_CONTROLLER_QUORUM_VOTERS: '1@kafka:29093'
      KAFKA_CONTROLLER_LISTENER_NAMES: 'CONTROLLER'
      CLUSTER_ID: 'MkU3OEVBNTcwNTJENDM2Qk'
```

### Producer

```typescript
import { Kafka, Producer, Partitioners } from 'kafkajs'

const kafka = new Kafka({
  clientId: 'order-service',
  brokers: (process.env.KAFKA_BROKERS || 'localhost:9092').split(','),
})

const producer: Producer = kafka.producer({
  createPartitioner: Partitioners.DefaultPartitioner,
  idempotent: true,
})

await producer.connect()

// Publish event
async function publishEvent(topic: string, event: DomainEvent) {
  await producer.send({
    topic,
    messages: [
      {
        key: event.data.aggregateId, // Partition by entity ID (ordering guarantee)
        value: JSON.stringify(event),
        headers: {
          'event-type': event.type,
          'correlation-id': event.correlationId,
        },
      },
    ],
  })
}
```

### Consumer

```typescript
const consumer = kafka.consumer({
  groupId: 'order-processor',
  sessionTimeout: 30_000,
  heartbeatInterval: 3_000,
})

await consumer.connect()
await consumer.subscribe({ topics: ['orders', 'payments'], fromBeginning: false })

await consumer.run({
  autoCommit: false,
  eachMessage: async ({ topic, partition, message }) => {
    const event: DomainEvent = JSON.parse(message.value!.toString())

    try {
      await processEvent(event)
      // Manual commit after successful processing
      await consumer.commitOffsets([{
        topic, partition, offset: (BigInt(message.offset) + 1n).toString(),
      }])
    } catch (error) {
      logger.error({ topic, partition, offset: message.offset, error }, 'Processing failed')
      // Don't commit — message will be reprocessed
    }
  },
})
```

---

## RabbitMQ

### Setup

```bash
npm install amqplib
npm install -D @types/amqplib
```

### Connection & Channel

```typescript
import amqp, { Connection, Channel } from 'amqplib'

let connection: Connection
let channel: Channel

async function connectRabbitMQ() {
  connection = await amqp.connect(process.env.RABBITMQ_URL || 'amqp://localhost')
  channel = await connection.createChannel()
  await channel.prefetch(10)

  // Declare exchanges
  await channel.assertExchange('events', 'topic', { durable: true })
  await channel.assertExchange('dlx', 'direct', { durable: true })

  // Declare queues with dead letter exchange
  await channel.assertQueue('order-processing', {
    durable: true,
    deadLetterExchange: 'dlx',
    deadLetterRoutingKey: 'order-processing.dlq',
    messageTtl: 24 * 60 * 60 * 1000,
  })

  await channel.assertQueue('order-processing.dlq', { durable: true })

  // Bind queues to exchanges
  await channel.bindQueue('order-processing', 'events', 'order.*')
  await channel.bindQueue('order-processing.dlq', 'dlx', 'order-processing.dlq')
}
```

### Publisher

```typescript
async function publish(routingKey: string, event: DomainEvent) {
  channel.publish('events', routingKey, Buffer.from(JSON.stringify(event)), {
    persistent: true,
    contentType: 'application/json',
    messageId: event.id,
    timestamp: Date.now(),
    headers: { 'x-event-type': event.type },
  })
}
```

### Consumer

```typescript
channel.consume('order-processing', async (msg) => {
  if (!msg) return

  try {
    const event: DomainEvent = JSON.parse(msg.content.toString())
    await processEvent(event)
    channel.ack(msg)
  } catch (error) {
    const retryCount = (msg.properties.headers?.['x-retry-count'] || 0) + 1

    if (retryCount >= 5) {
      channel.reject(msg, false)  // Send to DLQ
    } else {
      // Requeue with retry count
      channel.publish('events', msg.fields.routingKey, msg.content, {
        ...msg.properties,
        headers: { ...msg.properties.headers, 'x-retry-count': retryCount },
      })
      channel.ack(msg)
    }
  }
}, { noAck: false })
```

---

## Broker Comparison

| Feature | BullMQ | Kafka | RabbitMQ |
|---|---|---|---|
| Backing store | Redis | Disk (log) | Erlang + disk |
| Ordering | Per queue | Per partition | Per queue |
| Throughput | ~10K/sec | Millions/sec | ~50K/sec |
| Message replay | No | Yes (offset reset) | No |
| Routing | Basic | Topic/partition | Flexible (exchanges) |
| Best for | Job queues | Event streaming | Complex routing |
| Ops complexity | Low (Redis) | High | Medium |

---

## Message Broker Checklist

- [ ] Broker selected with documented rationale
- [ ] Connection pooling/reuse configured
- [ ] Dead letter queue configured for each main queue
- [ ] Retry strategy with exponential backoff
- [ ] Graceful shutdown handles in-flight messages
- [ ] Consumer idempotency (duplicate message handling)
- [ ] Queue depth monitoring with alerts
- [ ] Consumer lag monitoring (Kafka)
- [ ] Message serialization: JSON with schema validation
- [ ] Structured logging on publish/consume/fail
