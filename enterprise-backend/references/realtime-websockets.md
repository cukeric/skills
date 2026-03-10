# Real-Time Communication & Background Jobs Reference

## Technology Selection

| Need | Best Choice | Why |
|---|---|---|
| Bidirectional real-time (chat, collaboration) | **WebSockets** | Full duplex, low latency, both client and server push |
| Server → client updates (dashboards, feeds) | **SSE (Server-Sent Events)** | Simpler than WS, auto-reconnect, works through proxies |
| High-frequency data (stocks, metrics, IoT) | **WebSockets** | Lower overhead per message than SSE |
| Occasional updates (notifications) | **SSE** or **polling** | SSE is simple; polling acceptable if < 1 req/min |
| Inter-service messaging | **Redis Pub/Sub** or **Message Queue** | Decouple services, reliable delivery |
| Background processing | **BullMQ** (Node) / **Celery** (Python) | Retry, scheduling, concurrency control |

---

## WebSocket Server (Node.js)

### Setup with ws library (works with any HTTP framework)

```bash
pnpm add ws
pnpm add -D @types/ws
```

```typescript
// src/lib/websocket.ts
import { WebSocketServer, WebSocket } from 'ws'
import type { Server } from 'http'
import { validateSession } from './auth'
import { redis } from './redis'
import { logger } from './logger'

interface AuthenticatedWebSocket extends WebSocket {
  userId: string
  role: string
  isAlive: boolean
}

export function createWebSocketServer(server: Server) {
  const wss = new WebSocketServer({ server, path: '/ws' })

  // Connection authentication
  wss.on('connection', async (ws: AuthenticatedWebSocket, req) => {
    // Extract session from cookie
    const cookies = parseCookies(req.headers.cookie || '')
    const session = await validateSession(cookies.session)

    if (!session) {
      ws.close(4001, 'Unauthorized')
      return
    }

    ws.userId = session.userId
    ws.role = session.role
    ws.isAlive = true

    logger.info({ userId: ws.userId }, 'WebSocket connected')

    // Subscribe to user-specific Redis channel
    const subscriber = redis.duplicate()
    await subscriber.subscribe(`user:${ws.userId}`)
    subscriber.on('message', (channel, message) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(message)
    })

    // Subscribe to broadcast channel
    const broadcastSub = redis.duplicate()
    await broadcastSub.subscribe('broadcast')
    broadcastSub.on('message', (channel, message) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(message)
    })

    // Handle incoming messages
    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString())
        handleClientMessage(ws, msg)
      } catch {
        ws.send(JSON.stringify({ type: 'error', message: 'Invalid message format' }))
      }
    })

    // Pong for heartbeat
    ws.on('pong', () => { ws.isAlive = true })

    // Cleanup on disconnect
    ws.on('close', () => {
      logger.info({ userId: ws.userId }, 'WebSocket disconnected')
      subscriber.unsubscribe()
      subscriber.quit()
      broadcastSub.unsubscribe()
      broadcastSub.quit()
    })

    // Send initial state
    ws.send(JSON.stringify({ type: 'connected', userId: ws.userId }))
  })

  // Heartbeat — detect stale connections
  const heartbeat = setInterval(() => {
    wss.clients.forEach((ws: AuthenticatedWebSocket) => {
      if (!ws.isAlive) return ws.terminate()
      ws.isAlive = false
      ws.ping()
    })
  }, 30_000)

  wss.on('close', () => clearInterval(heartbeat))

  return wss
}

// Route client messages to handlers
function handleClientMessage(ws: AuthenticatedWebSocket, msg: { type: string; payload?: unknown }) {
  switch (msg.type) {
    case 'subscribe':
      // Subscribe to additional channels (e.g., project updates)
      break
    case 'ping':
      ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }))
      break
    default:
      ws.send(JSON.stringify({ type: 'error', message: `Unknown message type: ${msg.type}` }))
  }
}

function parseCookies(header: string): Record<string, string> {
  return Object.fromEntries(header.split(';').map(c => { const [k, ...v] = c.trim().split('='); return [k, v.join('=')] }))
}
```

### Sending Messages from Backend Services

```typescript
// Any service can push to WebSocket clients via Redis pub/sub
// This works across multiple server instances (horizontal scaling)

export async function sendToUser(userId: string, type: string, data: unknown) {
  const message = JSON.stringify({ type, data, timestamp: Date.now() })
  await redis.publish(`user:${userId}`, message)
}

export async function broadcast(type: string, data: unknown) {
  const message = JSON.stringify({ type, data, timestamp: Date.now() })
  await redis.publish('broadcast', message)
}

// Usage in any service:
await sendToUser(user.id, 'notification', { title: 'Payment received', amount: '$49.99' })
await broadcast('system', { message: 'Scheduled maintenance in 30 minutes' })
```

---

## Server-Sent Events (SSE)

Simpler than WebSockets for server → client only. Great for dashboards and notification feeds.

### Fastify SSE

```typescript
app.get('/api/events', { preHandler: [authGuard] }, async (req, reply) => {
  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',  // Disable nginx buffering
  })

  // Subscribe to user events via Redis
  const subscriber = redis.duplicate()
  await subscriber.subscribe(`user:${req.user.id}`, 'broadcast')

  subscriber.on('message', (channel, message) => {
    reply.raw.write(`data: ${message}\n\n`)
  })

  // Heartbeat every 15s to keep connection alive
  const heartbeat = setInterval(() => {
    reply.raw.write(`: heartbeat\n\n`)
  }, 15_000)

  // Cleanup
  req.raw.on('close', () => {
    clearInterval(heartbeat)
    subscriber.unsubscribe()
    subscriber.quit()
  })
})
```

### FastAPI SSE (Python)

```python
from fastapi.responses import StreamingResponse
import asyncio

@router.get("/events")
async def events(user=Depends(require_auth)):
    async def event_stream():
        pubsub = redis_client.pubsub()
        await pubsub.subscribe(f"user:{user.id}", "broadcast")

        try:
            while True:
                msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                if msg and msg["type"] == "message":
                    yield f"data: {msg['data'].decode()}\n\n"
                else:
                    yield f": heartbeat\n\n"
                await asyncio.sleep(0.1)
        finally:
            await pubsub.unsubscribe()

    return StreamingResponse(event_stream(), media_type="text/event-stream")
```

---

## Message Queues & Background Jobs

### BullMQ (Node.js — Redis-based)

```bash
pnpm add bullmq
```

```typescript
// src/lib/queue.ts
import { Queue, Worker, QueueEvents } from 'bullmq'
import { redis } from './redis'
import { logger } from './logger'

// Define queues
export const emailQueue = new Queue('email', { connection: redis })
export const paymentQueue = new Queue('payment', { connection: redis })
export const reportQueue = new Queue('report', { connection: redis })

// Email worker
const emailWorker = new Worker('email', async (job) => {
  const { to, template, data } = job.data
  logger.info({ jobId: job.id, to, template }, 'Processing email job')

  await sendEmail(to, template, data)
}, {
  connection: redis,
  concurrency: 5,            // Process 5 emails in parallel
  limiter: { max: 50, duration: 1000 },  // Max 50/sec (Resend/SendGrid limits)
})

emailWorker.on('failed', (job, err) => {
  logger.error({ jobId: job?.id, err }, 'Email job failed')
})

// Adding jobs from anywhere in the app
export async function queueEmail(to: string, template: string, data: Record<string, unknown>) {
  await emailQueue.add('send', { to, template, data }, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: { age: 86400 },   // Clean up after 24h
    removeOnFail: { age: 604800 },      // Keep failed for 7 days
  })
}

// Scheduled / recurring jobs
export async function setupRecurringJobs() {
  // Daily report at 6 AM UTC
  await reportQueue.add('daily-report', {}, {
    repeat: { pattern: '0 6 * * *' },  // Cron syntax
  })

  // Subscription renewal check every hour
  await paymentQueue.add('check-renewals', {}, {
    repeat: { every: 3600_000 },
  })
}
```

### Celery (Python)

```python
# src/tasks/email_tasks.py
from celery import Celery
from src.config import settings

celery_app = Celery('tasks', broker=settings.REDIS_URL, backend=settings.REDIS_URL)
celery_app.conf.task_serializer = 'json'
celery_app.conf.result_expires = 86400

@celery_app.task(bind=True, max_retries=3, default_retry_delay=30)
def send_email_task(self, to: str, template: str, data: dict):
    try:
        send_email(to, template, data)
    except Exception as exc:
        self.retry(exc=exc)

@celery_app.task
def generate_daily_report():
    # Heavy computation, runs in background
    pass

# Scheduled tasks (celery beat)
celery_app.conf.beat_schedule = {
    'daily-report': {
        'task': 'src.tasks.email_tasks.generate_daily_report',
        'schedule': crontab(hour=6, minute=0),
    },
}
```

---

## Scaling Real-Time Across Multiple Servers

```
┌─────────┐    ┌─────────┐    ┌─────────┐
│ Server 1 │    │ Server 2 │    │ Server 3 │
│ (WS/SSE) │    │ (WS/SSE) │    │ (WS/SSE) │
└────┬─────┘    └────┬─────┘    └────┬─────┘
     │               │               │
     └───────────────┼───────────────┘
                     │
              ┌──────┴──────┐
              │  Redis Pub/  │
              │    Sub       │
              └─────────────┘
```

Any server can publish; all servers receive and forward to their connected clients. Redis Pub/Sub is the glue — no direct server-to-server communication needed.

---

## Security Considerations

- [ ] WebSocket connections authenticated via session cookie (not query params)
- [ ] Validate all incoming WS messages with a schema
- [ ] Rate limit incoming WS messages per client (prevent flooding)
- [ ] Heartbeat to detect and clean up stale connections
- [ ] Redis Pub/Sub channels scoped to user/tenant (no cross-tenant data leaks)
- [ ] Background jobs: no sensitive data in job payloads logged to console
- [ ] Queue admin UI (Bull Board) protected behind auth
- [ ] Dead letter queue monitored and alerted

---

## HTTP Range Requests (Video/File Streaming)

Required for `<video>` playback in Safari, Brave, and Edge. Without Range support, only Chrome plays the video.

### Implementation (Next.js API Route)

```typescript
export async function GET(request: Request) {
  const filePath = '/data/videos/example.mp4'
  const stat = await fs.stat(filePath)
  const fileSize = stat.size

  // Sanitize filename to prevent header injection
  const safeFilename = path.basename(filename).replace(/[^a-z0-9.\-]/gi, '_')

  const rangeHeader = request.headers.get('range')

  if (rangeHeader) {
    const match = rangeHeader.match(/bytes=(\d+)-(\d*)/)
    if (match) {
      const start = parseInt(match[1], 10)
      // Cap chunk to 2MB to prevent memory exhaustion
      const MAX_CHUNK = 2 * 1024 * 1024
      const end = match[2]
        ? Math.min(parseInt(match[2], 10), fileSize - 1)
        : Math.min(start + MAX_CHUNK - 1, fileSize - 1)

      if (start >= fileSize || start < 0 || end < start) {
        return new Response(null, {
          status: 416,
          headers: { 'Content-Range': `bytes */${fileSize}` },
        })
      }

      const chunkSize = end - start + 1
      const fileHandle = await fs.open(filePath, 'r')
      const buffer = Buffer.alloc(chunkSize)
      await fileHandle.read(buffer, 0, chunkSize, start)
      await fileHandle.close()

      return new Response(buffer, {
        status: 206,
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': String(chunkSize),
          'Content-Range': `bytes ${start}-${end}/${fileSize}`,
          'Accept-Ranges': 'bytes',
          'Content-Disposition': `inline; filename="${safeFilename}"`,
        },
      })
    }
  }

  // Full file response (non-Range)
  const fileBuffer = await fs.readFile(filePath)
  return new Response(fileBuffer, {
    headers: {
      'Content-Type': 'video/mp4',
      'Content-Length': String(fileSize),
      'Accept-Ranges': 'bytes', // MUST include — tells browsers Range is supported
      'Content-Disposition': `inline; filename="${safeFilename}"`,
    },
  })
}
```

### Key Requirements

- **Always include `Accept-Ranges: bytes`** in full-file responses — tells browsers Range requests are supported
- **Cap chunk size** (2MB recommended) to prevent large buffer allocations from malicious Range headers
- **Validate bounds**: Return `416 Range Not Satisfiable` for invalid start/end values
- **Sanitize filenames** in `Content-Disposition` to prevent header injection
- **HTML**: Use `<source type="video/mp4">` inside `<video>`, not bare `src` attribute
