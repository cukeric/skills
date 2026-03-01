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
