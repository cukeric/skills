# Webhook Management Reference

## Outgoing Webhooks (Your App Sends)

### Webhook Dispatch Service

```typescript
// src/services/webhook.service.ts
import crypto from 'crypto'

interface WebhookSubscription {
  id: string
  url: string
  secret: string
  events: string[]       // ['order.created', 'order.updated']
  active: boolean
  createdAt: Date
  metadata?: Record<string, string>
}

interface WebhookDelivery {
  id: string
  subscriptionId: string
  eventType: string
  payload: unknown
  status: 'pending' | 'delivered' | 'failed'
  statusCode?: number
  attempts: number
  maxAttempts: number
  lastAttemptAt?: Date
  nextRetryAt?: Date
  response?: string
}

export class WebhookService {
  // Sign payload with HMAC-SHA256
  private sign(payload: string, secret: string): string {
    return crypto
      .createHmac('sha256', secret)
      .update(payload, 'utf8')
      .digest('hex')
  }

  async dispatch(subscription: WebhookSubscription, event: DomainEvent): Promise<void> {
    const payload = JSON.stringify({
      id: event.id,
      type: event.type,
      timestamp: event.timestamp,
      data: event.data,
    })

    const signature = this.sign(payload, subscription.secret)
    const deliveryId = generateId()

    // Queue the delivery
    await webhookQueue.add('deliver', {
      deliveryId,
      subscriptionId: subscription.id,
      url: subscription.url,
      payload,
      signature,
      eventType: event.type,
    }, {
      attempts: 5,
      backoff: { type: 'exponential', delay: 60_000 }, // 1m, 2m, 4m, 8m, 16m
    })
  }

  async deliver(params: {
    url: string
    payload: string
    signature: string
    deliveryId: string
  }): Promise<void> {
    const response = await fetch(params.url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Webhook-Signature': `sha256=${params.signature}`,
        'X-Webhook-ID': params.deliveryId,
        'X-Webhook-Timestamp': new Date().toISOString(),
        'User-Agent': 'MyApp-Webhooks/1.0',
      },
      body: params.payload,
      signal: AbortSignal.timeout(30_000), // 30s timeout
    })

    if (!response.ok) {
      throw new Error(`Webhook delivery failed: ${response.status}`)
    }
  }
}
```

### Webhook Registration API

```typescript
// POST /api/v1/webhooks
app.post('/api/v1/webhooks', authGuard, async (req, reply) => {
  const body = WebhookCreateSchema.parse(req.body)
  const secret = crypto.randomBytes(32).toString('hex')

  const webhook = await db.webhookSubscription.create({
    data: {
      url: body.url,
      events: body.events,
      secret,
      active: true,
      tenantId: req.user.tenantId,
    },
  })

  // Return secret ONCE — user must save it
  return reply.status(201).send({
    id: webhook.id,
    url: webhook.url,
    events: webhook.events,
    secret,  // Only shown on creation
    active: webhook.active,
  })
})

// GET /api/v1/webhooks/:id/deliveries
app.get('/api/v1/webhooks/:id/deliveries', authGuard, async (req) => {
  return db.webhookDelivery.findMany({
    where: { subscriptionId: req.params.id },
    orderBy: { createdAt: 'desc' },
    take: 50,
  })
})

// POST /api/v1/webhooks/:id/test
app.post('/api/v1/webhooks/:id/test', authGuard, async (req) => {
  const webhook = await db.webhookSubscription.findUnique({
    where: { id: req.params.id },
  })

  await webhookService.dispatch(webhook, {
    id: 'test_event',
    type: 'webhook.test',
    timestamp: new Date().toISOString(),
    data: { message: 'This is a test webhook delivery' },
  })

  return { status: 'Test webhook queued' }
})
```

---

## Incoming Webhooks (Your App Receives)

### Signature Verification (Non-Negotiable)

```typescript
// Verify webhook signature before processing
function verifyWebhookSignature(
  payload: string | Buffer,
  signature: string,
  secret: string
): boolean {
  const expected = crypto
    .createHmac('sha256', secret)
    .update(payload, 'utf8')
    .digest('hex')

  // Timing-safe comparison to prevent timing attacks
  const sig = signature.replace('sha256=', '')
  return crypto.timingSafeEqual(
    Buffer.from(sig, 'hex'),
    Buffer.from(expected, 'hex')
  )
}

// Webhook endpoint
app.post('/api/v1/webhooks/stripe', {
  config: { rawBody: true },  // Need raw body for signature
}, async (req, reply) => {
  const signature = req.headers['stripe-signature'] as string
  const rawBody = req.rawBody

  try {
    const event = stripe.webhooks.constructEvent(
      rawBody, signature, process.env.STRIPE_WEBHOOK_SECRET!
    )

    // Idempotent processing
    const processed = await db.processedWebhooks.findUnique({
      where: { eventId: event.id },
    })
    if (processed) return reply.status(200).send({ received: true })

    // Process event
    await processStripeEvent(event)

    // Mark as processed
    await db.processedWebhooks.create({
      data: { eventId: event.id, type: event.type, processedAt: new Date() },
    })

    return reply.status(200).send({ received: true })
  } catch (error) {
    logger.error({ error }, 'Webhook verification failed')
    return reply.status(400).send({ error: 'Invalid signature' })
  }
})
```

---

## Event Catalog

Document all webhook events your system sends:

```typescript
// src/webhook-events.ts
export const WEBHOOK_EVENTS = {
  'order.created': {
    description: 'Fired when a new order is placed',
    schema: {
      orderId: 'string',
      customerId: 'string',
      items: 'OrderItem[]',
      totalCents: 'number',
      currency: 'string',
    },
  },
  'order.updated': {
    description: 'Fired when order status changes',
    schema: {
      orderId: 'string',
      previousStatus: 'string',
      newStatus: 'string',
    },
  },
  'payment.completed': {
    description: 'Fired when payment is successfully processed',
    schema: {
      paymentId: 'string',
      orderId: 'string',
      amountCents: 'number',
      method: 'string',
    },
  },
} as const
```

---

## Webhook Checklist

- [ ] Outgoing: HMAC-SHA256 signature on every delivery
- [ ] Outgoing: Retry with exponential backoff (5 attempts)
- [ ] Outgoing: Delivery logs with status codes and response bodies
- [ ] Outgoing: Test endpoint for each subscription
- [ ] Outgoing: Automatic deactivation after N consecutive failures
- [ ] Incoming: Signature verification before processing
- [ ] Incoming: Idempotent processing (track processed event IDs)
- [ ] Incoming: Respond with 200 quickly, process async
- [ ] Incoming: Raw body preserved for signature verification
- [ ] Event catalog documented for all webhook event types
