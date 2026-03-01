# Background Jobs Reference

## Job Types

| Type | Pattern | Example |
|---|---|---|
| **Fire-and-forget** | Enqueue, process async | Send email, generate thumbnail |
| **Delayed** | Process after delay | Send reminder 24h later |
| **Scheduled (cron)** | Recurring on schedule | Daily report, hourly cleanup |
| **Priority** | Process by importance | Urgent vs normal notifications |
| **Batch** | Process group together | Bulk email, data export |
| **Rate-limited** | Throttle processing | API calls to external services |

---

## BullMQ Job Patterns

### Job Producer Service

```typescript
// src/services/job.service.ts
import { Queue, FlowProducer } from 'bullmq'
import { connection } from '@/lib/redis'

// Queue definitions
const queues = {
  emails: new Queue('emails', { connection }),
  reports: new Queue('reports', { connection }),
  cleanup: new Queue('cleanup', { connection }),
  sync: new Queue('sync', { connection }),
}

export const jobService = {
  // Fire-and-forget
  async sendEmail(data: EmailJobData) {
    return queues.emails.add('send', data, {
      attempts: 3,
      backoff: { type: 'exponential', delay: 1000 },
    })
  },

  // Delayed job
  async sendReminder(data: ReminderData, delayMs: number) {
    return queues.emails.add('reminder', data, { delay: delayMs })
  },

  // Priority job
  async sendUrgentNotification(data: NotificationData) {
    return queues.emails.add('urgent', data, { priority: 1 })
  },

  // Bulk jobs
  async sendBulkEmails(recipients: EmailJobData[]) {
    const jobs = recipients.map((data) => ({
      name: 'send',
      data,
      opts: { attempts: 3, backoff: { type: 'exponential' as const, delay: 1000 } },
    }))
    return queues.emails.addBulk(jobs)
  },
}
```

### Worker with Rate Limiting

```typescript
// src/workers/sync.worker.ts
import { Worker } from 'bullmq'

const syncWorker = new Worker(
  'sync',
  async (job) => {
    switch (job.name) {
      case 'sync-crm':
        await syncToCRM(job.data)
        break
      case 'sync-analytics':
        await syncToAnalytics(job.data)
        break
    }
  },
  {
    connection,
    concurrency: 3,
    limiter: {
      max: 30,          // Max 30 API calls
      duration: 60_000, // per minute
    },
  }
)
```

### Cron / Scheduled Jobs

```typescript
// src/jobs/scheduled.ts
import { Queue } from 'bullmq'

const scheduledQueue = new Queue('scheduled', { connection })

export async function registerScheduledJobs() {
  // Daily report at 9 AM UTC
  await scheduledQueue.add('daily-report', { type: 'daily' }, {
    repeat: { pattern: '0 9 * * *' },
    jobId: 'daily-report', // Prevents duplicate registrations
  })

  // Hourly data cleanup
  await scheduledQueue.add('cleanup-expired', {}, {
    repeat: { pattern: '0 * * * *' },
    jobId: 'cleanup-expired',
  })

  // Every 5 minutes: health check
  await scheduledQueue.add('health-check', {}, {
    repeat: { pattern: '*/5 * * * *' },
    jobId: 'health-check',
  })

  // Weekly: full database backup
  await scheduledQueue.add('weekly-backup', {}, {
    repeat: { pattern: '0 2 * * 0' }, // Sunday 2 AM
    jobId: 'weekly-backup',
  })

  // Monthly: generate invoices
  await scheduledQueue.add('monthly-invoices', {}, {
    repeat: { pattern: '0 6 1 * *' }, // 1st of month, 6 AM
    jobId: 'monthly-invoices',
  })
}
```

### Job Progress & Events

```typescript
// Worker reports progress
const reportWorker = new Worker('reports', async (job) => {
  const users = await db.user.findMany()
  const total = users.length

  for (let i = 0; i < total; i++) {
    await processUser(users[i])
    await job.updateProgress(Math.round(((i + 1) / total) * 100))
    await job.log(`Processed user ${i + 1}/${total}`)
  }

  return { processedCount: total }
}, { connection })

// API to check job status
app.get('/api/v1/jobs/:id/status', async (req) => {
  const job = await Queue.fromId(reportQueue, req.params.id)
  if (!job) return reply.status(404).send({ error: 'Job not found' })

  const state = await job.getState()
  const progress = job.progress

  return {
    id: job.id,
    state,          // 'waiting', 'active', 'completed', 'failed', 'delayed'
    progress,
    data: job.data,
    result: job.returnvalue,
    failedReason: job.failedReason,
    attempts: job.attemptsMade,
    createdAt: job.timestamp,
  }
})
```

---

## Job Flows (Dependencies)

```typescript
import { FlowProducer } from 'bullmq'

const flowProducer = new FlowProducer({ connection })

// Order processing flow: parent waits for all children
await flowProducer.add({
  name: 'complete-order',
  queueName: 'orders',
  data: { orderId: '123' },
  children: [
    {
      name: 'charge-payment',
      queueName: 'payments',
      data: { orderId: '123', amount: 9999 },
    },
    {
      name: 'reserve-inventory',
      queueName: 'inventory',
      data: { orderId: '123', items: [...] },
    },
    {
      name: 'send-confirmation',
      queueName: 'emails',
      data: { orderId: '123', to: 'user@example.com' },
    },
  ],
})
// Parent job runs AFTER all children complete
```

---

## Idempotent Workers

```typescript
// Every worker must handle duplicate execution safely
const emailWorker = new Worker('emails', async (job) => {
  // Check if already processed
  const idempotencyKey = `email:${job.data.to}:${job.data.template}:${job.data.uniqueId}`
  const alreadySent = await redis.get(idempotencyKey)

  if (alreadySent) {
    logger.info({ jobId: job.id }, 'Email already sent, skipping')
    return { skipped: true }
  }

  // Process
  const result = await emailProvider.send(job.data)

  // Mark as processed (TTL: 24 hours)
  await redis.set(idempotencyKey, '1', 'EX', 86400)

  return result
}, { connection })
```

---

## Monitoring

### Health Check

```typescript
async function getQueueHealth(): Promise<Record<string, QueueStats>> {
  const stats: Record<string, QueueStats> = {}

  for (const [name, queue] of Object.entries(queues)) {
    const counts = await queue.getJobCounts()
    stats[name] = {
      waiting: counts.waiting,
      active: counts.active,
      completed: counts.completed,
      failed: counts.failed,
      delayed: counts.delayed,
      paused: counts.paused,
    }
  }

  return stats
}

// Alert if queue depth exceeds threshold
async function checkQueueAlerts() {
  const health = await getQueueHealth()

  for (const [name, stats] of Object.entries(health)) {
    if (stats.waiting > 10_000) {
      logger.warn({ queue: name, waiting: stats.waiting }, 'Queue depth critical')
      await alertService.send(`Queue ${name} has ${stats.waiting} waiting jobs`)
    }
    if (stats.failed > 100) {
      logger.warn({ queue: name, failed: stats.failed }, 'High failure rate')
    }
  }
}
```

---

## Graceful Shutdown

```typescript
const workers: Worker[] = [emailWorker, reportWorker, syncWorker]

async function shutdown() {
  logger.info('Graceful shutdown initiated')

  // Close workers (finishes in-flight jobs)
  await Promise.allSettled(workers.map((w) => w.close()))

  // Close queues
  await Promise.allSettled(Object.values(queues).map((q) => q.close()))

  // Close Redis
  await connection.quit()

  logger.info('All workers stopped')
  process.exit(0)
}

process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)

// Force kill after 30 seconds
process.on('SIGTERM', () => {
  setTimeout(() => {
    logger.error('Forced shutdown after timeout')
    process.exit(1)
  }, 30_000)
})
```

---

## Background Jobs Checklist

- [ ] All heavy operations moved off request path
- [ ] Workers are idempotent (safe to replay)
- [ ] Retry strategy with exponential backoff
- [ ] Dead letter handling for permanently failed jobs
- [ ] Job progress reporting for long-running tasks
- [ ] Rate limiting for external API calls
- [ ] Cron jobs registered with unique IDs (no duplicates)
- [ ] Queue depth monitoring with alerts
- [ ] Graceful shutdown completes in-flight jobs
- [ ] Job results retrievable via API (for polling)
- [ ] Bull Board or equivalent dashboard deployed
- [ ] Structured logging on start/complete/fail
