# Offline-First Architecture Reference

## Strategy Selection

| Data Type | Strategy | Technology | When |
|---|---|---|---|
| API response cache | Cache-first | TanStack Query + MMKV | Read-heavy, network optional |
| Key-value settings | Local-first | MMKV | User preferences, flags |
| Relational data | Offline-first DB | WatermelonDB | Complex queries, large datasets |
| File/media assets | Download + cache | expo-file-system | Images, PDFs, media |
| Form submissions | Queue-and-retry | Custom MMKV queue | Write operations offline |

---

## MMKV (Fast Key-Value Storage)

MMKV is a high-performance, synchronous key-value store backed by memory-mapped files — 30x faster than AsyncStorage.

### Setup

```bash
npx expo install react-native-mmkv
```

```typescript
// src/lib/storage.ts
import { MMKV } from 'react-native-mmkv'

export const storage = new MMKV()

export const encryptedStorage = new MMKV({
  id: 'encrypted-storage',
  encryptionKey: 'device-derived-key',
})

// Zustand persistence adapter
export const mmkvStorage = {
  getItem: (key: string) => storage.getString(key) ?? null,
  setItem: (key: string, value: string) => storage.set(key, value),
  removeItem: (key: string) => storage.delete(key),
}
```

### Zustand + MMKV Persistence

```typescript
import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { mmkvStorage } from '@/lib/storage'

interface AppSettings {
  theme: 'light' | 'dark' | 'system'
  language: string
  onboardingComplete: boolean
  setTheme: (theme: AppSettings['theme']) => void
}

export const useAppSettings = create<AppSettings>()(
  persist(
    (set) => ({
      theme: 'system',
      language: 'en',
      onboardingComplete: false,
      setTheme: (theme) => set({ theme }),
    }),
    { name: 'app-settings', storage: createJSONStorage(() => mmkvStorage) }
  )
)
```

---

## TanStack Query Offline Persistence

```typescript
// src/lib/query-client.ts
import { QueryClient } from '@tanstack/react-query'
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister'
import { persistQueryClient } from '@tanstack/react-query-persist-client'
import { mmkvStorage } from './storage'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,
      gcTime: 24 * 60 * 60 * 1000,
      retry: 2,
      networkMode: 'offlineFirst',
    },
    mutations: { retry: 3, networkMode: 'offlineFirst' },
  },
})

const persister = createSyncStoragePersister({
  storage: mmkvStorage,
  key: 'REACT_QUERY_CACHE',
  throttleTime: 1000,
})

persistQueryClient({ queryClient, persister, maxAge: 24 * 60 * 60 * 1000 })
```

---

## WatermelonDB (Offline-First Database)

For apps with complex relational data that must work fully offline.

### Schema

```typescript
import { appSchema, tableSchema } from '@nozbe/watermelondb'

export const schema = appSchema({
  version: 1,
  tables: [
    tableSchema({
      name: 'orders',
      columns: [
        { name: 'server_id', type: 'string', isIndexed: true },
        { name: 'title', type: 'string' },
        { name: 'status', type: 'string', isIndexed: true },
        { name: 'customer_id', type: 'string', isIndexed: true },
        { name: 'total_cents', type: 'number' },
        { name: 'is_dirty', type: 'boolean' },
        { name: 'created_at', type: 'number' },
        { name: 'updated_at', type: 'number' },
      ],
    }),
  ],
})
```

### Sync Strategy (Pull-Push)

```typescript
import { synchronize } from '@nozbe/watermelondb/sync'
import { database } from '@/db'
import { api } from './api'

export async function syncDatabase(): Promise<void> {
  await synchronize({
    database,
    pullChanges: async ({ lastPulledAt }) => {
      const response = await api.get<SyncResponse>(
        `/api/v1/sync?last_pulled_at=${lastPulledAt || 0}`
      )
      return { changes: response.changes, timestamp: response.timestamp }
    },
    pushChanges: async ({ changes, lastPulledAt }) => {
      await api.post('/api/v1/sync', { changes, lastPulledAt })
    },
    migrationsEnabledAtVersion: 1,
  })
}
```

### Conflict Resolution Strategies

| Strategy | When | How |
|---|---|---|
| **Server wins** | Most CRUD apps | Server overwrites local |
| **Client wins** | Offline-heavy field apps | Local overwrites server |
| **Last-write-wins** | Simple comparison | Newest `updatedAt` wins |
| **Manual resolution** | Critical data | Present both to user |

---

## Offline Queue (Write Operations)

```typescript
// src/lib/offline-queue.ts
import { storage } from './storage'

interface QueuedAction {
  id: string
  type: 'POST' | 'PATCH' | 'DELETE'
  endpoint: string
  body?: unknown
  retryCount: number
  maxRetries: number
}

const QUEUE_KEY = 'offline_action_queue'

export const offlineQueue = {
  getQueue(): QueuedAction[] {
    const raw = storage.getString(QUEUE_KEY)
    return raw ? JSON.parse(raw) : []
  },

  enqueue(action: Omit<QueuedAction, 'id' | 'retryCount' | 'maxRetries'>) {
    const queue = this.getQueue()
    queue.push({ ...action, id: `${Date.now()}`, retryCount: 0, maxRetries: 5 })
    storage.set(QUEUE_KEY, JSON.stringify(queue))
  },

  dequeue(id: string) {
    const queue = this.getQueue().filter((a) => a.id !== id)
    storage.set(QUEUE_KEY, JSON.stringify(queue))
  },

  async processQueue(): Promise<void> {
    for (const action of this.getQueue()) {
      if (action.retryCount >= action.maxRetries) {
        this.dequeue(action.id)
        continue
      }
      try {
        const response = await fetch(action.endpoint, {
          method: action.type,
          headers: { 'Content-Type': 'application/json' },
          body: action.body ? JSON.stringify(action.body) : undefined,
        })
        if (response.ok) this.dequeue(action.id)
      } catch {
        // Network error — retry later
      }
    }
  },
}
```

### Auto-Sync on Reconnect

```typescript
import NetInfo from '@react-native-community/netinfo'

NetInfo.addEventListener(async (state) => {
  if (state.isConnected) {
    await offlineQueue.processQueue()
    await syncDatabase()
  }
})
```

---

## Network Status Banner

```typescript
import { View, Text, StyleSheet } from 'react-native'
import Animated, { FadeInDown, FadeOutUp } from 'react-native-reanimated'
import { useNetworkStore } from '@/stores/network'

export function OfflineBanner() {
  const isConnected = useNetworkStore((s) => s.isConnected)
  if (isConnected) return null

  return (
    <Animated.View entering={FadeInDown} exiting={FadeOutUp} style={styles.banner}>
      <Text style={styles.text}>You're offline. Changes will sync when connected.</Text>
    </Animated.View>
  )
}
```

---

## Offline-First Checklist

- [ ] Network state monitored globally (NetInfo)
- [ ] Critical data cached locally (MMKV or WatermelonDB)
- [ ] TanStack Query configured with `offlineFirst` network mode
- [ ] Query cache persisted to MMKV
- [ ] Write operations queued when offline
- [ ] Optimistic UI updates for immediate feedback
- [ ] Sync triggered on connectivity restored
- [ ] Conflict resolution strategy defined per data type
- [ ] Offline banner shown to user
- [ ] Dead letter handling for failed operations
