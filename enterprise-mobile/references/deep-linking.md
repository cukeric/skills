# Deep Linking Reference

## Overview

Deep links allow external sources (web, email, other apps) to open specific screens in your app.

| Type | Platform | Example |
|---|---|---|
| **Custom scheme** | Both | `myapp://orders/123` |
| **Universal Links** | iOS | `https://app.company.com/orders/123` |
| **App Links** | Android | `https://app.company.com/orders/123` |
| **Deferred deep links** | Both | Opens store if not installed, then routes after install |

**Best practice:** Use Universal Links / App Links (HTTPS-based) for production. Custom scheme for development.

---

## Expo Router Deep Links (Automatic)

Expo Router automatically generates deep link handling from your file structure.

```
app/
├── index.tsx              → /
├── settings.tsx           → /settings
├── orders/
│   ├── index.tsx          → /orders
│   └── [id].tsx           → /orders/123
├── (tabs)/
│   ├── index.tsx          → /
│   └── search.tsx         → /search
```

### Configuration

```typescript
// app.config.ts
export default {
  scheme: 'myapp',  // Custom scheme: myapp://
  ios: {
    associatedDomains: ['applinks:app.company.com'],
  },
  android: {
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [
          { scheme: 'https', host: 'app.company.com', pathPrefix: '/' },
        ],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
}
```

### Testing Deep Links

```bash
# iOS Simulator
npx uri-scheme open "myapp://orders/123" --ios

# Android Emulator
npx uri-scheme open "myapp://orders/123" --android

# Or via adb
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://app.company.com/orders/123" com.company.myapp

# Expo Go
npx uri-scheme open "exp://127.0.0.1:8081/--/orders/123"
```

---

## Universal Links (iOS)

### Apple App Site Association (AASA)

Host this file at `https://app.company.com/.well-known/apple-app-site-association` (no file extension, served as `application/json`).

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAM_ID.com.company.myapp"],
        "components": [
          { "/": "/orders/*", "comment": "Order detail pages" },
          { "/": "/products/*", "comment": "Product pages" },
          { "/": "/invite/*", "comment": "Invite links" },
          { "/": "/reset-password", "comment": "Password reset" },
          {
            "/": "/api/*",
            "exclude": true,
            "comment": "Exclude API routes"
          },
          {
            "/": "/admin/*",
            "exclude": true,
            "comment": "Exclude admin panel"
          }
        ]
      }
    ]
  }
}
```

### Verification

```bash
# Verify AASA is accessible
curl -I https://app.company.com/.well-known/apple-app-site-association

# Must return:
# Content-Type: application/json
# Status: 200
# Valid JSON with correct appIDs
```

---

## App Links (Android)

### Digital Asset Links

Host at `https://app.company.com/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.company.myapp",
      "sha256_cert_fingerprints": [
        "YOUR_SHA256_FINGERPRINT"
      ]
    }
  }
]
```

### Get SHA256 Fingerprint

```bash
# From EAS
eas credentials --platform android
# Look for "SHA-256 Fingerprint"

# From local keystore
keytool -list -v -keystore your-keystore.jks -alias your-alias
```

---

## Handling Deep Links in Code

### Reading Route Parameters

```typescript
// app/orders/[id].tsx
import { useLocalSearchParams } from 'expo-router'

export default function OrderDetail() {
  const { id } = useLocalSearchParams<{ id: string }>()

  const { data: order } = useQuery({
    queryKey: ['orders', id],
    queryFn: () => api.get(`/api/v1/orders/${id}`),
  })

  return <OrderDetailView order={order} />
}
```

### Deep Link with Query Parameters

```typescript
// URL: myapp://search?q=shoes&category=footwear
// File: app/search.tsx

import { useLocalSearchParams } from 'expo-router'

export default function Search() {
  const { q, category } = useLocalSearchParams<{
    q?: string
    category?: string
  }>()

  // Pre-fill search with deep link params
  const [query, setQuery] = useState(q || '')
  // ...
}
```

### Initial URL Handling (App Launch from Link)

```typescript
import * as Linking from 'expo-linking'
import { useEffect } from 'react'

export function useInitialURL() {
  useEffect(() => {
    // Handle URL that opened the app
    Linking.getInitialURL().then((url) => {
      if (url) {
        console.log('App opened with URL:', url)
        // Expo Router handles routing automatically
      }
    })

    // Handle URLs while app is running
    const subscription = Linking.addEventListener('url', ({ url }) => {
      console.log('Received URL while running:', url)
    })

    return () => subscription.remove()
  }, [])
}
```

---

## Deferred Deep Linking

When a user clicks a deep link but the app isn't installed: open the app store → install → open app → route to the intended screen.

### Implementation with Expo

```typescript
// src/lib/deferred-deep-link.ts
import * as Linking from 'expo-linking'
import { storage } from './storage'

const DEFERRED_LINK_KEY = 'deferred_deep_link'

// On first app open, check if there's a deferred link from the web
export async function checkDeferredDeepLink(): Promise<string | null> {
  // Check if server has a pending deep link for this device
  try {
    const deviceId = await getDeviceId()
    const response = await api.get<{ url: string | null }>(
      `/api/v1/deep-links/pending?device_id=${deviceId}`
    )
    return response.url
  } catch {
    return null
  }
}

// Web: Generate smart link that detects platform
// https://app.company.com/invite/abc123
// → If app installed: open app to /invite/abc123
// → If not installed: redirect to app store with deferred link stored
```

### Smart Banner (Web Fallback)

```html
<!-- Add to web pages that should open in app -->
<meta name="apple-itunes-app" content="app-id=YOUR_APP_ID, app-argument=https://app.company.com/orders/123">

<!-- Android -->
<link rel="alternate" href="android-app://com.company.myapp/https/app.company.com/orders/123">
```

---

## Creating Deep Links

```typescript
// src/lib/deep-links.ts
import * as Linking from 'expo-linking'

export function createDeepLink(path: string, params?: Record<string, string>): string {
  const url = Linking.createURL(path, { queryParams: params })
  return url
  // Development: exp://127.0.0.1:8081/--/orders/123
  // Production: myapp://orders/123
}

export function createWebLink(path: string): string {
  return `https://app.company.com${path}`
}

// Share a deep link
import { Share } from 'react-native'

async function shareOrder(orderId: string) {
  const url = createWebLink(`/orders/${orderId}`)
  await Share.share({
    message: `Check out this order: ${url}`,
    url, // iOS only
  })
}
```

---

## Deep Linking Checklist

- [ ] Custom scheme configured (`myapp://`)
- [ ] Universal Links: AASA file hosted and accessible
- [ ] App Links: assetlinks.json hosted with correct fingerprint
- [ ] Associated domains configured in app.config.ts
- [ ] All app routes handle deep link parameters gracefully
- [ ] Auth guard redirects to login, then back to intended screen
- [ ] Invalid/expired deep links show friendly error
- [ ] Deep links tested on physical iOS and Android devices
- [ ] Cold launch (app killed) deep linking works
- [ ] Warm launch (app backgrounded) deep linking works
- [ ] Web fallback page exists for when app isn't installed
- [ ] Analytics tracked for deep link opens (source, campaign)
