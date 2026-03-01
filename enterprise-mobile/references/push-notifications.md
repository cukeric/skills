# Push Notifications Reference

## Architecture Overview

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Your App   │────▶│  Your Server │────▶│  APNs / FCM │
│  (Client)   │     │  (Backend)   │     │  (Provider)  │
└─────────────┘     └──────────────┘     └──────┬───────┘
       ▲                                         │
       └─────────────────────────────────────────┘
                    Push Delivered
```

1. **Client** registers for push → receives device token
2. **Client** sends token to **your backend**
3. **Backend** stores token per user
4. **Backend** sends push via APNs (iOS) / FCM (Android)
5. **Provider** delivers to device

---

## Expo Notifications Setup

### Installation

```bash
npx expo install expo-notifications expo-device expo-constants
```

### app.config.ts Additions

```typescript
plugins: [
  [
    'expo-notifications',
    {
      icon: './assets/notification-icon.png',   // Android only, 96x96 white on transparent
      color: '#6366F1',                          // Android accent color
      sounds: ['./assets/sounds/alert.wav'],     // Custom sounds
      defaultChannel: 'default',                 // Android channel
    },
  ],
],
```

### Token Registration

```typescript
// src/lib/notifications.ts
import * as Notifications from 'expo-notifications'
import * as Device from 'expo-device'
import Constants from 'expo-constants'
import { Platform } from 'react-native'
import { api } from './api'

// Configure notification behavior
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
})

export async function registerForPushNotifications(): Promise<string | null> {
  // Physical device check (push doesn't work in simulator)
  if (!Device.isDevice) {
    console.warn('Push notifications only work on physical devices')
    return null
  }

  // Check/request permissions
  const { status: existingStatus } = await Notifications.getPermissionsAsync()
  let finalStatus = existingStatus

  if (existingStatus !== 'granted') {
    const { status } = await Notifications.requestPermissionsAsync()
    finalStatus = status
  }

  if (finalStatus !== 'granted') {
    console.warn('Push notification permission denied')
    return null
  }

  // Get Expo push token
  const projectId = Constants.expoConfig?.extra?.eas?.projectId
  const tokenData = await Notifications.getExpoPushTokenAsync({
    projectId,
  })

  // Android: create notification channel
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Default',
      importance: Notifications.AndroidImportance.MAX,
      vibrationPattern: [0, 250, 250, 250],
      lightColor: '#6366F1',
    })

    await Notifications.setNotificationChannelAsync('orders', {
      name: 'Order Updates',
      importance: Notifications.AndroidImportance.HIGH,
      description: 'Notifications about order status changes',
    })

    await Notifications.setNotificationChannelAsync('messages', {
      name: 'Messages',
      importance: Notifications.AndroidImportance.HIGH,
      description: 'New message notifications',
      sound: 'alert.wav',
    })
  }

  return tokenData.data
}

// Send token to backend
export async function syncPushToken(token: string): Promise<void> {
  await api.post('/api/v1/push-tokens', {
    token,
    platform: Platform.OS,
    deviceName: Device.deviceName,
  })
}
```

### Notification Listeners

```typescript
// src/hooks/useNotifications.ts
import { useEffect, useRef, useState } from 'react'
import * as Notifications from 'expo-notifications'
import { useRouter } from 'expo-router'

export function useNotifications() {
  const router = useRouter()
  const notificationListener = useRef<Notifications.Subscription>()
  const responseListener = useRef<Notifications.Subscription>()
  const [notification, setNotification] = useState<Notifications.Notification>()

  useEffect(() => {
    // Foreground notification received
    notificationListener.current = Notifications.addNotificationReceivedListener(
      (notification) => {
        setNotification(notification)
        // Handle in-app notification display (toast, banner, etc.)
      }
    )

    // User tapped notification
    responseListener.current = Notifications.addNotificationResponseReceivedListener(
      (response) => {
        const data = response.notification.request.content.data

        // Route based on notification type
        switch (data.type) {
          case 'order_update':
            router.push(`/orders/${data.orderId}`)
            break
          case 'new_message':
            router.push(`/messages/${data.conversationId}`)
            break
          case 'payment_received':
            router.push('/payments')
            break
          default:
            router.push('/')
        }
      }
    )

    return () => {
      notificationListener.current?.remove()
      responseListener.current?.remove()
    }
  }, [router])

  return { notification }
}

// Check for notification that launched the app (killed state)
export async function getInitialNotification() {
  const response = await Notifications.getLastNotificationResponseAsync()
  return response?.notification.request.content.data
}
```

---

## Backend: Sending Push Notifications

### Using Expo Push API (Recommended)

```typescript
// Backend: send push notification via Expo's push service
import { Expo, ExpoPushMessage } from 'expo-server-sdk'

const expo = new Expo()

interface SendPushParams {
  tokens: string[]
  title: string
  body: string
  data?: Record<string, unknown>
  channelId?: string        // Android channel
  badge?: number            // iOS badge count
  sound?: 'default' | string
  priority?: 'default' | 'normal' | 'high'
  ttl?: number              // Time to live (seconds)
  categoryId?: string       // For actionable notifications
}

export async function sendPushNotifications(params: SendPushParams): Promise<void> {
  const { tokens, title, body, data, channelId, badge, sound, priority, ttl, categoryId } = params

  // Filter valid Expo push tokens
  const validTokens = tokens.filter((token) => Expo.isExpoPushToken(token))

  if (validTokens.length === 0) {
    console.warn('No valid Expo push tokens')
    return
  }

  // Build messages
  const messages: ExpoPushMessage[] = validTokens.map((to) => ({
    to,
    title,
    body,
    data,
    channelId: channelId || 'default',
    badge,
    sound: sound || 'default',
    priority: priority || 'high',
    ttl: ttl || 3600,
    categoryId,
  }))

  // Chunk messages (Expo recommends max 100 per request)
  const chunks = expo.chunkPushNotifications(messages)

  for (const chunk of chunks) {
    try {
      const receipts = await expo.sendPushNotificationsAsync(chunk)

      // Process receipts
      for (const receipt of receipts) {
        if (receipt.status === 'error') {
          console.error('Push notification error:', receipt.message)

          if (receipt.details?.error === 'DeviceNotRegistered') {
            // Remove invalid token from database
            await removeInvalidToken(receipt)
          }
        }
      }
    } catch (error) {
      console.error('Failed to send push chunk:', error)
    }
  }
}

// Check delivery receipts (call after ~15 minutes)
export async function checkPushReceipts(receiptIds: string[]): Promise<void> {
  const chunks = expo.chunkPushNotificationReceiptIds(receiptIds)

  for (const chunk of chunks) {
    const receipts = await expo.getPushNotificationReceiptsAsync(chunk)

    for (const [id, receipt] of Object.entries(receipts)) {
      if (receipt.status === 'error') {
        console.error(`Receipt ${id} error:`, receipt.message)

        if (receipt.details?.error === 'DeviceNotRegistered') {
          // Token is no longer valid — remove from DB
        }
      }
    }
  }
}
```

### Using FCM Directly (For Android-specific features)

```typescript
import admin from 'firebase-admin'

admin.initializeApp({
  credential: admin.credential.cert('./firebase-service-account.json'),
})

export async function sendFCMNotification(params: {
  tokens: string[]
  title: string
  body: string
  data?: Record<string, string>
  imageUrl?: string
}) {
  const message: admin.messaging.MulticastMessage = {
    tokens: params.tokens,
    notification: {
      title: params.title,
      body: params.body,
      imageUrl: params.imageUrl,
    },
    data: params.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'default',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
    apns: {
      payload: {
        aps: {
          badge: 1,
          sound: 'default',
          contentAvailable: true,
        },
      },
    },
  }

  const response = await admin.messaging().sendEachForMulticast(message)

  // Handle failures
  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      console.error(`FCM send failed for token ${idx}:`, resp.error)
    }
  })
}
```

---

## Rich Notifications

### Actionable Notifications (iOS & Android)

```typescript
// Define notification categories (actions)
Notifications.setNotificationCategoryAsync('order_update', [
  {
    identifier: 'view_order',
    buttonTitle: 'View Order',
    options: { opensAppToForeground: true },
  },
  {
    identifier: 'mark_received',
    buttonTitle: 'Mark Received',
    options: { opensAppToForeground: false },
  },
])

Notifications.setNotificationCategoryAsync('message', [
  {
    identifier: 'reply',
    buttonTitle: 'Reply',
    textInput: {
      submitButtonTitle: 'Send',
      placeholder: 'Type your reply...',
    },
  },
  {
    identifier: 'mark_read',
    buttonTitle: 'Mark Read',
    options: { opensAppToForeground: false },
  },
])
```

### Background Notifications (Silent Push)

```typescript
// Register background task for silent push
import * as TaskManager from 'expo-task-manager'

const BACKGROUND_NOTIFICATION_TASK = 'BACKGROUND_NOTIFICATION'

TaskManager.defineTask(BACKGROUND_NOTIFICATION_TASK, async ({ data, error }) => {
  if (error) {
    console.error('Background notification error:', error)
    return
  }

  // Process data silently (sync data, update badge, prefetch)
  const notificationData = data as { body: Record<string, unknown> }

  switch (notificationData.body.type) {
    case 'data_sync':
      await syncOfflineData()
      break
    case 'badge_update':
      await Notifications.setBadgeCountAsync(notificationData.body.count as number)
      break
  }
})

// Register in app initialization
Notifications.registerTaskAsync(BACKGROUND_NOTIFICATION_TASK)
```

---

## Notification Preferences

```typescript
// src/stores/notificationPreferences.ts
import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { mmkvStorage } from '@/lib/storage'

interface NotificationPreferences {
  orderUpdates: boolean
  messages: boolean
  promotions: boolean
  systemAlerts: boolean
  quietHoursEnabled: boolean
  quietHoursStart: string  // '22:00'
  quietHoursEnd: string    // '07:00'
  setPreference: (key: string, value: boolean) => void
  setQuietHours: (start: string, end: string) => void
}

export const useNotificationPreferences = create<NotificationPreferences>()(
  persist(
    (set) => ({
      orderUpdates: true,
      messages: true,
      promotions: false,
      systemAlerts: true,
      quietHoursEnabled: false,
      quietHoursStart: '22:00',
      quietHoursEnd: '07:00',
      setPreference: (key, value) => set({ [key]: value }),
      setQuietHours: (start, end) =>
        set({ quietHoursEnabled: true, quietHoursStart: start, quietHoursEnd: end }),
    }),
    {
      name: 'notification-preferences',
      storage: createJSONStorage(() => mmkvStorage),
    }
  )
)
```

---

## Push Notification Checklist

- [ ] Physical device testing (push doesn't work in simulators)
- [ ] Expo push token stored on backend, associated with user
- [ ] Token refresh handled (re-register on app start)
- [ ] Invalid/expired tokens removed from database
- [ ] Android notification channels configured (default, orders, messages, etc.)
- [ ] Foreground notification display handled (custom banner or system alert)
- [ ] Tap-to-open routes to correct screen based on notification data
- [ ] Cold launch from notification routes correctly (killed state)
- [ ] Background/silent push tested for data sync
- [ ] Actionable notification categories registered
- [ ] Permission denied state handled gracefully (show settings prompt)
- [ ] Badge count managed (increment on receive, clear on open)
- [ ] Rate limiting on backend (don't spam users)
- [ ] Notification preferences synced between app and backend
- [ ] Rich notifications with images tested (if applicable)
