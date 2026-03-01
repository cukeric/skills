# Payments & Stripe Integration Reference

## Architecture Principles

1. **Stripe is the source of truth** for all payment data. Your database mirrors Stripe, not the other way around.
2. **Never trust the client.** Prices, quantities, and discounts are set server-side. The client only selects products.
3. **Webhooks are mandatory.** Payment confirmations come via webhooks, not API responses. The checkout redirect alone is not proof of payment.
4. **PCI compliance** — never touch raw card numbers. Use Stripe Elements (frontend) or Checkout Sessions (hosted).
5. **Idempotency keys** on all mutating Stripe API calls to prevent double charges.

---

## Stripe Setup

```bash
pnpm add stripe
```

```typescript
// src/lib/stripe.ts
import Stripe from 'stripe'
import { env } from '../config/env'

export const stripe = new Stripe(env.STRIPE_SECRET_KEY, {
  apiVersion: '2024-12-18.acacia',  // Pin API version
  typescript: true,
})
```

### Environment Variables

```env
STRIPE_SECRET_KEY=sk_test_...          # sk_live_... in production
STRIPE_PUBLISHABLE_KEY=pk_test_...     # Sent to frontend
STRIPE_WEBHOOK_SECRET=whsec_...        # From Stripe Dashboard → Webhooks
STRIPE_PRICE_BASIC=price_...           # Price IDs for subscription plans
STRIPE_PRICE_PRO=price_...
STRIPE_PRICE_ENTERPRISE=price_...
```

---

## One-Time Payments (Checkout Session)

### Flow
```
1. User clicks "Buy" → frontend calls POST /api/payments/checkout
2. Backend creates Stripe Checkout Session → returns session URL
3. Frontend redirects to Stripe-hosted checkout page
4. User pays → Stripe redirects to your success URL
5. Stripe sends checkout.session.completed webhook → your app fulfills order
```

### Implementation

```typescript
// POST /api/payments/checkout — create checkout session
app.post('/api/payments/checkout', { preHandler: [authGuard] }, async (req, reply) => {
  const { items } = CheckoutSchema.parse(req.body)

  // Look up prices server-side — never trust client-provided prices
  const lineItems = await Promise.all(items.map(async (item) => {
    const product = await db.product.findUnique({ where: { id: item.productId } })
    if (!product) throw errors.notFound('Product')
    return { price: product.stripePriceId, quantity: item.quantity }
  }))

  // Get or create Stripe customer
  const stripeCustomerId = await getOrCreateStripeCustomer(req.user)

  const session = await stripe.checkout.sessions.create({
    customer: stripeCustomerId,
    mode: 'payment',
    line_items: lineItems,
    success_url: `${env.FRONTEND_URL}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${env.FRONTEND_URL}/checkout/cancel`,
    metadata: { userId: req.user.id, orderId: generateOrderId() },
    payment_intent_data: {
      metadata: { userId: req.user.id },
    },
  }, {
    idempotencyKey: `checkout-${req.user.id}-${Date.now()}`,
  })

  return reply.send({ url: session.url })
})

async function getOrCreateStripeCustomer(user: { id: string; email: string; name: string }) {
  let customer = await db.user.findUnique({ where: { id: user.id }, select: { stripeCustomerId: true } })

  if (!customer?.stripeCustomerId) {
    const stripeCustomer = await stripe.customers.create({
      email: user.email,
      name: user.name,
      metadata: { userId: user.id },
    })
    await db.user.update({ where: { id: user.id }, data: { stripeCustomerId: stripeCustomer.id } })
    return stripeCustomer.id
  }

  return customer.stripeCustomerId
}
```

---

## Subscriptions

### Creating Subscriptions

```typescript
app.post('/api/subscriptions/create', { preHandler: [authGuard] }, async (req, reply) => {
  const { planId } = SubscriptionSchema.parse(req.body)

  const PLAN_PRICES: Record<string, string> = {
    basic: env.STRIPE_PRICE_BASIC,
    pro: env.STRIPE_PRICE_PRO,
    enterprise: env.STRIPE_PRICE_ENTERPRISE,
  }

  const priceId = PLAN_PRICES[planId]
  if (!priceId) throw errors.validation('Invalid plan')

  const stripeCustomerId = await getOrCreateStripeCustomer(req.user)

  // Check for existing active subscription
  const existing = await db.subscription.findFirst({
    where: { userId: req.user.id, status: { in: ['active', 'trialing'] } },
  })
  if (existing) throw errors.conflict('Already has an active subscription. Use upgrade endpoint.')

  const session = await stripe.checkout.sessions.create({
    customer: stripeCustomerId,
    mode: 'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${env.FRONTEND_URL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${env.FRONTEND_URL}/billing/plans`,
    subscription_data: {
      trial_period_days: 14,
      metadata: { userId: req.user.id, plan: planId },
    },
    metadata: { userId: req.user.id },
  })

  return reply.send({ url: session.url })
})
```

### Plan Changes (Upgrade / Downgrade)

```typescript
app.post('/api/subscriptions/change-plan', { preHandler: [authGuard] }, async (req, reply) => {
  const { newPlanId } = ChangePlanSchema.parse(req.body)

  const sub = await db.subscription.findFirst({
    where: { userId: req.user.id, status: 'active' },
  })
  if (!sub) throw errors.notFound('Active subscription')

  const PLAN_PRICES: Record<string, string> = {
    basic: env.STRIPE_PRICE_BASIC,
    pro: env.STRIPE_PRICE_PRO,
    enterprise: env.STRIPE_PRICE_ENTERPRISE,
  }

  const stripeSub = await stripe.subscriptions.retrieve(sub.stripeSubscriptionId)

  await stripe.subscriptions.update(sub.stripeSubscriptionId, {
    items: [{
      id: stripeSub.items.data[0].id,
      price: PLAN_PRICES[newPlanId],
    }],
    proration_behavior: 'create_prorations',  // Charge/credit difference immediately
    metadata: { plan: newPlanId },
  })

  return reply.send({ success: true, message: 'Plan updated. Prorated charges applied.' })
})
```

### Cancellation

```typescript
app.post('/api/subscriptions/cancel', { preHandler: [authGuard] }, async (req, reply) => {
  const sub = await db.subscription.findFirst({ where: { userId: req.user.id, status: 'active' } })
  if (!sub) throw errors.notFound('Active subscription')

  // Cancel at period end (user keeps access until billing cycle ends)
  await stripe.subscriptions.update(sub.stripeSubscriptionId, {
    cancel_at_period_end: true,
  })

  await db.subscription.update({
    where: { id: sub.id },
    data: { cancelAtPeriodEnd: true },
  })

  logger.info({ userId: req.user.id, subId: sub.id }, 'Subscription cancellation scheduled')
  return reply.send({ success: true, message: 'Subscription will cancel at end of billing period.' })
})
```

---

## Customer Portal (Billing Management)

Let Stripe handle payment method updates, invoice history, and plan management:

```typescript
app.post('/api/billing/portal', { preHandler: [authGuard] }, async (req, reply) => {
  const user = await db.user.findUnique({ where: { id: req.user.id } })
  if (!user?.stripeCustomerId) throw errors.notFound('No billing account')

  const session = await stripe.billingPortal.sessions.create({
    customer: user.stripeCustomerId,
    return_url: `${env.FRONTEND_URL}/billing`,
  })

  return reply.send({ url: session.url })
})
```

---

## Webhooks (Critical)

### Webhook Endpoint

```typescript
// POST /api/webhooks/stripe — receives ALL Stripe events
// IMPORTANT: Raw body required for signature verification
app.post('/api/webhooks/stripe', {
  config: { rawBody: true },  // Fastify: enable raw body for this route
}, async (req, reply) => {
  const signature = req.headers['stripe-signature']
  if (!signature) return reply.status(400).send({ error: 'Missing signature' })

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(req.rawBody!, signature, env.STRIPE_WEBHOOK_SECRET)
  } catch (err) {
    logger.error({ err }, 'Stripe webhook signature verification failed')
    return reply.status(400).send({ error: 'Invalid signature' })
  }

  logger.info({ eventType: event.type, eventId: event.id }, 'Stripe webhook received')

  // Idempotency: check if we already processed this event
  const processed = await redis.get(`stripe-event:${event.id}`)
  if (processed) return reply.send({ received: true, duplicate: true })

  try {
    await handleStripeEvent(event)
    await redis.setex(`stripe-event:${event.id}`, 86400 * 7, 'processed')  // 7 day dedup
  } catch (err) {
    logger.error({ err, eventType: event.type, eventId: event.id }, 'Stripe webhook handler error')
    return reply.status(500).send({ error: 'Handler failed' })
  }

  return reply.send({ received: true })
})
```

### Event Handlers

```typescript
async function handleStripeEvent(event: Stripe.Event) {
  switch (event.type) {
    // ── Checkout ──
    case 'checkout.session.completed': {
      const session = event.data.object as Stripe.Checkout.Session
      if (session.mode === 'payment') await fulfillOrder(session)
      if (session.mode === 'subscription') await activateSubscription(session)
      break
    }

    // ── Subscriptions ──
    case 'customer.subscription.created':
    case 'customer.subscription.updated': {
      const sub = event.data.object as Stripe.Subscription
      await syncSubscription(sub)
      break
    }

    case 'customer.subscription.deleted': {
      const sub = event.data.object as Stripe.Subscription
      await deactivateSubscription(sub)
      break
    }

    // ── Payments ──
    case 'invoice.payment_succeeded': {
      const invoice = event.data.object as Stripe.Invoice
      await recordPayment(invoice)
      break
    }

    case 'invoice.payment_failed': {
      const invoice = event.data.object as Stripe.Invoice
      await handleFailedPayment(invoice)
      break
    }

    // ── Disputes ──
    case 'charge.dispute.created': {
      const dispute = event.data.object as Stripe.Dispute
      logger.error({ disputeId: dispute.id, chargeId: dispute.charge }, 'PAYMENT DISPUTE — action required')
      await notifyAdmins('Payment dispute received', dispute)
      break
    }

    default:
      logger.debug({ eventType: event.type }, 'Unhandled Stripe event')
  }
}

async function syncSubscription(sub: Stripe.Subscription) {
  const userId = sub.metadata.userId
  if (!userId) { logger.warn({ subId: sub.id }, 'Subscription missing userId metadata'); return }

  await db.subscription.upsert({
    where: { stripeSubscriptionId: sub.id },
    create: {
      userId,
      stripeSubscriptionId: sub.id,
      stripePriceId: sub.items.data[0].price.id,
      plan: sub.metadata.plan || 'unknown',
      status: sub.status,
      currentPeriodStart: new Date(sub.current_period_start * 1000),
      currentPeriodEnd: new Date(sub.current_period_end * 1000),
      cancelAtPeriodEnd: sub.cancel_at_period_end,
    },
    update: {
      status: sub.status,
      stripePriceId: sub.items.data[0].price.id,
      plan: sub.metadata.plan || 'unknown',
      currentPeriodStart: new Date(sub.current_period_start * 1000),
      currentPeriodEnd: new Date(sub.current_period_end * 1000),
      cancelAtPeriodEnd: sub.cancel_at_period_end,
    },
  })

  // Update user's access level
  await db.user.update({ where: { id: userId }, data: { plan: sub.metadata.plan || 'free' } })
}

async function handleFailedPayment(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string
  const user = await db.user.findFirst({ where: { stripeCustomerId: customerId } })
  if (!user) return

  logger.warn({ userId: user.id, invoiceId: invoice.id }, 'Payment failed')

  // Send email notification
  await sendEmail({
    to: user.email,
    template: 'payment-failed',
    data: { name: user.name, amount: (invoice.amount_due / 100).toFixed(2), currency: invoice.currency.toUpperCase() },
  })
}
```

### Required Webhook Events (Configure in Stripe Dashboard)

```
checkout.session.completed
customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
invoice.payment_succeeded
invoice.payment_failed
charge.dispute.created
charge.refunded
```

---

## Subscription Access Control Middleware

```typescript
// Middleware: require active subscription
export function requireSubscription(...allowedPlans: string[]) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const sub = await db.subscription.findFirst({
      where: { userId: req.user.id, status: { in: ['active', 'trialing'] } },
    })

    if (!sub) throw errors.forbidden('Active subscription required')

    if (allowedPlans.length > 0 && !allowedPlans.includes(sub.plan)) {
      throw errors.forbidden(`This feature requires: ${allowedPlans.join(' or ')}`)
    }
  }
}

// Usage
app.get('/api/analytics/advanced', {
  preHandler: [authGuard, requireSubscription('pro', 'enterprise')],
}, handler)
```

---

## Testing Payments

```typescript
// Use Stripe test mode + test card numbers
// 4242424242424242 → Success
// 4000000000009995 → Declined
// 4000000000003220 → Requires 3D Secure

// Webhook testing: use Stripe CLI
// stripe listen --forward-to localhost:3000/api/webhooks/stripe
// stripe trigger checkout.session.completed

describe('Payments', () => {
  it('creates checkout session for authenticated user', async () => {
    const res = await app.inject({
      method: 'POST', url: '/api/payments/checkout',
      payload: { items: [{ productId: 'prod_123', quantity: 1 }] },
      cookies: { session: testSession },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().url).toContain('checkout.stripe.com')
  })

  it('rejects unauthenticated checkout', async () => {
    const res = await app.inject({ method: 'POST', url: '/api/payments/checkout', payload: {} })
    expect(res.statusCode).toBe(401)
  })
})
```

---

## Security Checklist

- [ ] Stripe secret key in environment variable, never in code
- [ ] Webhook signature verified on every event (constructEvent)
- [ ] Webhook events deduplicated by event ID
- [ ] Prices set server-side — client only sends product/plan IDs
- [ ] Idempotency keys on all Stripe write operations
- [ ] Customer portal for self-service billing management
- [ ] Failed payment notifications sent to users
- [ ] Dispute alerts sent to admins
- [ ] No raw card data ever touches your servers (Stripe Elements / Checkout)
- [ ] Test mode in development, live mode behind environment variable switch
