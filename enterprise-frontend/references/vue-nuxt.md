# Vue & Nuxt 3 Enterprise Reference

## Project Initialization

### Nuxt 3 — default for most Vue projects

```bash
pnpm dlx nuxi@latest init my-app
cd my-app
pnpm add zod @tanstack/vue-query class-variance-authority clsx tailwind-merge lucide-vue-next @pinia/nuxt
pnpm add -D @nuxtjs/tailwindcss vitest @vue/test-utils @testing-library/vue playwright
```

### Vue + Vite — SPAs, dashboards

```bash
pnpm create vite my-app --template vue-ts
cd my-app
pnpm add vue-router pinia zod @tanstack/vue-query class-variance-authority clsx tailwind-merge lucide-vue-next
pnpm add -D tailwindcss @tailwindcss/vite vitest @vue/test-utils playwright
```

---

## Nuxt 3 Architecture

### Directory Structure

```
├── app.vue                  # Root component
├── pages/
│   ├── index.vue            # Home page
│   ├── login.vue
│   ├── dashboard/
│   │   ├── index.vue
│   │   ├── analytics.vue
│   │   └── users/
│   │       ├── index.vue
│   │       └── [id].vue
├── layouts/
│   ├── default.vue          # Public layout
│   ├── auth.vue             # Centered card layout for auth pages
│   └── dashboard.vue        # Sidebar + header layout
├── components/
│   ├── ui/                  # Design system primitives
│   ├── layout/              # Shell, Sidebar, Navbar
│   ├── features/            # Feature-specific components
│   └── shared/              # Cross-feature reusable
├── composables/
│   ├── useAuth.ts
│   ├── useWebSocket.ts
│   └── useApiClient.ts
├── stores/                  # Pinia stores
│   └── auth.ts
├── server/
│   ├── api/                 # Server routes (API)
│   └── middleware/           # Server middleware
├── middleware/               # Route middleware (client)
│   └── auth.ts
├── types/
│   └── index.ts
├── utils/
│   └── cn.ts
└── nuxt.config.ts
```

### Nuxt Config

```typescript
// nuxt.config.ts
export default defineNuxtConfig({
  devtools: { enabled: true },
  modules: ['@nuxtjs/tailwindcss', '@pinia/nuxt', '@vueuse/nuxt'],
  typescript: { strict: true },
  runtimeConfig: {
    apiSecret: '',
    public: { apiBase: '/api' },
  },
  app: {
    head: {
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Plus+Jakarta+Sans:wght@600;700&display=swap' },
      ],
    },
  },
})
```

### Route Middleware (Auth Guard)

```typescript
// middleware/auth.ts
export default defineNuxtRouteMiddleware((to) => {
  const auth = useAuthStore()
  const publicPages = ['/login', '/register', '/forgot-password']

  if (!auth.isAuthenticated && !publicPages.includes(to.path)) {
    return navigateTo('/login')
  }
  if (auth.isAuthenticated && publicPages.includes(to.path)) {
    return navigateTo('/dashboard')
  }
})
```

### Dashboard Layout

```vue
<!-- layouts/dashboard.vue -->
<template>
  <div class="flex h-screen bg-base">
    <Sidebar />
    <div class="flex-1 flex flex-col overflow-hidden">
      <Navbar />
      <main class="flex-1 overflow-y-auto p-6">
        <slot />
      </main>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ middleware: 'auth' })
</script>
```

---

## Vue Component Patterns

### Composable: API Client

```typescript
// composables/useApiClient.ts
import { z } from 'zod'

class ApiError extends Error {
  constructor(public status: number, message: string, public data?: unknown) {
    super(message); this.name = 'ApiError'
  }
}

export function useApiClient() {
  const config = useRuntimeConfig()
  const base = config.public.apiBase

  async function request<T>(path: string, options: RequestInit = {}, schema?: z.ZodType<T>): Promise<T> {
    const res = await $fetch.raw(`${base}${path}`, {
      credentials: 'include',
      ...options,
    })
    const data = res._data
    return schema ? schema.parse(data) : data as T
  }

  return {
    get: <T>(path: string, schema?: z.ZodType<T>) => request<T>(path, { method: 'GET' }, schema),
    post: <T>(path: string, body: unknown, schema?: z.ZodType<T>) => request<T>(path, { method: 'POST', body: JSON.stringify(body) }, schema),
    put: <T>(path: string, body: unknown, schema?: z.ZodType<T>) => request<T>(path, { method: 'PUT', body: JSON.stringify(body) }, schema),
    delete: <T>(path: string, schema?: z.ZodType<T>) => request<T>(path, { method: 'DELETE' }, schema),
  }
}
```

### Composable: WebSocket

```typescript
// composables/useWebSocket.ts
export function useWebSocket(url: string, onMessage: (data: unknown) => void) {
  const state = ref<'connecting' | 'connected' | 'disconnected' | 'reconnecting'>('disconnected')
  let ws: WebSocket | null = null
  let attempts = 0
  const maxRetries = 10

  function connect() {
    state.value = 'connecting'
    ws = new WebSocket(url)
    ws.onopen = () => { state.value = 'connected'; attempts = 0 }
    ws.onmessage = (e) => { try { onMessage(JSON.parse(e.data)) } catch { onMessage(e.data) } }
    ws.onclose = () => {
      state.value = 'disconnected'
      if (attempts < maxRetries) {
        state.value = 'reconnecting'
        setTimeout(() => { attempts++; connect() }, Math.min(1000 * 2 ** attempts, 30000))
      }
    }
  }

  function send(data: unknown) { ws?.readyState === WebSocket.OPEN && ws.send(JSON.stringify(data)) }

  onMounted(connect)
  onUnmounted(() => { attempts = maxRetries; ws?.close() })

  return { state: readonly(state), send }
}
```

### Pinia Store Pattern

```typescript
// stores/auth.ts
import { defineStore } from 'pinia'
import { z } from 'zod'

const UserSchema = z.object({
  id: z.string(), email: z.string().email(), name: z.string(),
  role: z.enum(['admin', 'user', 'viewer']),
})
type User = z.infer<typeof UserSchema>

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const isAuthenticated = computed(() => !!user.value)
  const isAdmin = computed(() => user.value?.role === 'admin')

  async function login(email: string, password: string) {
    const api = useApiClient()
    const data = await api.post<{ user: User }>('/auth/login', { email, password })
    user.value = data.user
  }

  async function logout() {
    const api = useApiClient()
    await api.post('/auth/logout', {})
    user.value = null
    navigateTo('/login')
  }

  async function fetchUser() {
    try {
      const api = useApiClient()
      const data = await api.get('/auth/me', z.object({ user: UserSchema }))
      user.value = data.user
    } catch { user.value = null }
  }

  return { user, isAuthenticated, isAdmin, login, logout, fetchUser }
})
```

### Component with CVA

```vue
<!-- components/ui/Button.vue -->
<template>
  <component :is="asChild ? Slot : 'button'" :class="cn(buttonVariants({ variant, size }), $attrs.class)" :disabled="disabled || loading" v-bind="$attrs">
    <span v-if="loading" class="animate-spin w-4 h-4 border-2 border-current border-t-transparent rounded-full" />
    <slot />
  </component>
</template>

<script setup lang="ts">
import { buttonVariants, type ButtonVariants } from '@/styles/button-variants'
import { cn } from '@/utils/cn'

interface Props extends ButtonVariants {
  asChild?: boolean
  loading?: boolean
  disabled?: boolean
}

withDefaults(defineProps<Props>(), { variant: 'primary', size: 'md' })
</script>
```

### TanStack Vue Query

```typescript
// composables/useUsers.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import { z } from 'zod'

const UserSchema = z.object({ id: z.string(), email: z.string(), name: z.string(), role: z.string() })

export function useUsers(page: Ref<number>) {
  const api = useApiClient()
  return useQuery({
    queryKey: ['users', page],
    queryFn: () => api.get(`/users?page=${page.value}`, z.object({ users: z.array(UserSchema), total: z.number() })),
  })
}

export function useCreateUser() {
  const api = useApiClient()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data: { email: string; name: string; role: string }) => api.post('/users', data, UserSchema),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['users'] }),
  })
}
```

---

## Testing

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  test: { environment: 'jsdom', globals: true },
})
```

```typescript
// components/ui/__tests__/Button.test.ts
import { render, fireEvent } from '@testing-library/vue'
import Button from '../Button.vue'

describe('Button', () => {
  it('emits click event', async () => {
    const { getByRole, emitted } = render(Button, { slots: { default: 'Click' } })
    await fireEvent.click(getByRole('button'))
    expect(emitted()).toHaveProperty('click')
  })
})
```
