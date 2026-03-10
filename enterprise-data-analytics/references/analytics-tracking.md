# Analytics Event Tracking Reference

## Server-Side Tracking (Recommended)

```typescript
// src/lib/analytics.ts
import { PostHog } from 'posthog-node'

const posthog = new PostHog(process.env.POSTHOG_API_KEY!, {
  host: process.env.POSTHOG_HOST || 'https://app.posthog.com',
})

export const analytics = {
  track(userId: string, event: string, properties?: Record<string, unknown>) {
    posthog.capture({
      distinctId: userId,
      event,
      properties: { ...properties, $lib: 'server' },
    })
  },

  identify(userId: string, traits: Record<string, unknown>) {
    posthog.identify({ distinctId: userId, properties: traits })
  },

  // Flush on shutdown
  async shutdown() {
    await posthog.shutdown()
  },
}

// Track in route handlers
app.post('/api/v1/orders', async (req) => {
  const order = await createOrder(req.body)

  analytics.track(req.user.id, 'order_completed', {
    orderId: order.id,
    totalCents: order.totalCents,
    itemCount: order.items.length,
    paymentMethod: order.paymentMethod,
  })

  return order
})
```

## Event Taxonomy

```typescript
// Define all events in one place for consistency
export const ANALYTICS_EVENTS = {
  // User lifecycle
  USER_SIGNED_UP: 'user_signed_up',
  USER_LOGGED_IN: 'user_logged_in',
  USER_ONBOARDING_COMPLETED: 'user_onboarding_completed',
  USER_PROFILE_UPDATED: 'user_profile_updated',

  // Engagement
  PAGE_VIEWED: 'page_viewed',
  FEATURE_USED: 'feature_used',
  SEARCH_PERFORMED: 'search_performed',

  // Revenue
  ORDER_COMPLETED: 'order_completed',
  SUBSCRIPTION_STARTED: 'subscription_started',
  SUBSCRIPTION_CANCELLED: 'subscription_cancelled',

  // Errors
  ERROR_OCCURRED: 'error_occurred',
} as const
```

## Funnel Analysis Setup

```typescript
// Track each step of a conversion funnel
// Funnel: Landing → Sign Up → Onboarding → First Order

analytics.track(userId, 'funnel_step', {
  funnel: 'new_user_activation',
  step: 1,
  stepName: 'landing_page_visited',
})

analytics.track(userId, 'funnel_step', {
  funnel: 'new_user_activation',
  step: 2,
  stepName: 'signup_completed',
})

// PostHog/Mixpanel can build funnel visualizations from these events
```

## Client-Side Tracking (React)

```typescript
// src/lib/analytics-client.ts
import posthog from 'posthog-js'

export function initAnalytics() {
  if (typeof window === 'undefined') return

  posthog.init(process.env.NEXT_PUBLIC_POSTHOG_KEY!, {
    api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST,
    capture_pageview: false, // Manual page tracking
    capture_pageleave: true,
    persistence: 'localStorage',
  })
}

// React hook
export function useTrack() {
  return useCallback((event: string, properties?: Record<string, unknown>) => {
    posthog.capture(event, properties)
  }, [])
}
```

---

## Zero-Cost PostgreSQL-Native Analytics

When budget constraints prevent using PostHog/Mixpanel/Amplitude, PostgreSQL itself can serve as a lightweight analytics store. Suitable for early-stage SaaS with < 100K events/day.

### Schema

```sql
CREATE TABLE "AnalyticsEvent" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid(),
  "event" TEXT NOT NULL,          -- e.g., 'page_view', 'generate_start', 'purchase_complete'
  "properties" JSONB DEFAULT '{}',
  "ipHash" TEXT,                  -- Privacy-compliant hashed IP (NOT raw IP)
  "userAgent" TEXT,
  "userId" TEXT,                  -- Nullable for anonymous events
  "createdAt" TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_analytics_event ON "AnalyticsEvent" ("event");
CREATE INDEX idx_analytics_created ON "AnalyticsEvent" ("createdAt");
```

### Privacy-Compliant IP Hashing

Never store raw IP addresses. Use SHA-256 with a daily rotating salt so IPs can't be reversed but same-day uniqueness is preserved:

```typescript
import crypto from 'crypto'

function hashIP(ip: string): string {
  const dailySalt = new Date().toISOString().slice(0, 10) // YYYY-MM-DD
  return crypto
    .createHash('sha256')
    .update(`${ip}:${dailySalt}:${process.env.NEXTAUTH_SECRET}`)
    .digest('hex')
    .slice(0, 16) // First 16 hex chars — sufficient for uniqueness
}
```

### Client-Side: `navigator.sendBeacon`

Use `sendBeacon` for fire-and-forget analytics — it survives page unloads (unlike `fetch`):

```typescript
// src/hooks/useAnalytics.ts
'use client'
import { useCallback } from 'react'

export function useAnalytics() {
  const track = useCallback((event: string, properties?: Record<string, unknown>) => {
    const payload = JSON.stringify({ event, properties })
    // sendBeacon is fire-and-forget, survives page navigation
    navigator.sendBeacon('/api/analytics', payload)
  }, [])

  return { track }
}
```

### API Endpoint

```typescript
// POST /api/analytics — accepts sendBeacon payloads
export async function POST(request: Request) {
  const body = await request.json()
  const ip = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown'

  await prisma.analyticsEvent.create({
    data: {
      event: body.event,
      properties: body.properties || {},
      ipHash: hashIP(ip),
      userAgent: request.headers.get('user-agent') || undefined,
      userId: session?.user?.id, // Optional: from auth
    },
  })

  return new Response(null, { status: 204 })
}
```

### Cron Compaction

Delete old analytics events to prevent table bloat (90 days is a reasonable retention):

```typescript
// In your cron cleanup job
await prisma.analyticsEvent.deleteMany({
  where: { createdAt: { lt: new Date(Date.now() - 90 * 24 * 60 * 60 * 1000) } },
})
```

### When to Upgrade to a Dedicated Service

Move to PostHog/Mixpanel when:
- Events exceed ~100K/day (PostgreSQL becomes a bottleneck)
- You need funnels, cohorts, or session replay
- You need real-time dashboards with complex aggregations
- Multiple team members need self-serve analytics access
