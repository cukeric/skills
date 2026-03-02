# React & Next.js Enterprise Reference

## Project Initialization

### Next.js (App Router) — default for most projects

```bash
pnpm create next-app@latest my-app --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"
cd my-app
pnpm add zod @tanstack/react-query class-variance-authority clsx tailwind-merge lucide-react
pnpm add -D @types/node vitest @testing-library/react @testing-library/jest-dom playwright
```

### React + Vite — SPAs, dashboards, internal tools

```bash
pnpm create vite my-app --template react-ts
cd my-app
pnpm add react-router-dom zod @tanstack/react-query class-variance-authority clsx tailwind-merge lucide-react
pnpm add -D tailwindcss @tailwindcss/vite vitest @testing-library/react playwright
```

---

## Next.js App Router Patterns

### Route Structure

```
src/app/
├── (auth)/                    # Route group — shared auth layout
│   ├── login/page.tsx
│   ├── register/page.tsx
│   └── layout.tsx             # Centered card layout
├── (dashboard)/               # Route group — authenticated area
│   ├── layout.tsx             # Dashboard shell (sidebar + header)
│   ├── page.tsx               # Dashboard home
│   ├── analytics/page.tsx
│   ├── settings/
│   │   ├── page.tsx
│   │   └── [tab]/page.tsx     # Dynamic settings tab
│   └── users/
│       ├── page.tsx           # Users list
│       └── [id]/page.tsx      # User detail
├── api/
│   └── webhooks/stripe/route.ts
├── layout.tsx                 # Root layout (providers, fonts, metadata)
├── loading.tsx                # Root loading UI
├── error.tsx                  # Root error boundary
├── not-found.tsx
└── globals.css
```

### Root Layout with Providers

```tsx
// src/app/layout.tsx
import type { Metadata } from 'next'
import { inter, jakarta, jetbrains } from '@/lib/fonts'
import { Providers } from '@/components/providers'
import './globals.css'

export const metadata: Metadata = {
  title: { default: 'App Name', template: '%s | App Name' },
  description: 'Enterprise application',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${jakarta.variable} ${jetbrains.variable}`} suppressHydrationWarning>
      <body className="font-sans antialiased bg-base text-[var(--text-primary)]">
        <Providers>{children}</Providers>
      </body>
    </html>
  )
}
```

### Provider Stack

```tsx
// src/components/providers.tsx
'use client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ThemeProvider } from '@/components/theme-provider'
import { useState } from 'react'

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 60_000,
        gcTime: 300_000,
        retry: 2,
        refetchOnWindowFocus: false,
      },
    },
  }))

  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider defaultTheme="light" storageKey="app-theme">
        {children}
      </ThemeProvider>
    </QueryClientProvider>
  )
}
```

### Server vs Client Components

**Default to Server Components.** Only add `'use client'` when you need event handlers, hooks, or browser APIs.

**Pattern: Server component wraps client component with data**
```tsx
// page.tsx (SERVER) — fetches data
export default async function AnalyticsPage() {
  const data = await getAnalytics()
  return <AnalyticsDashboard initialData={data} />
}

// analytics-dashboard.tsx (CLIENT) — interactive
'use client'
export function AnalyticsDashboard({ initialData }: { initialData: AnalyticsData }) {
  const { data } = useQuery({
    queryKey: ['analytics'],
    queryFn: getAnalytics,
    initialData,
    refetchInterval: 30_000,
  })
  return (/* render */)
}
```

### Middleware (Auth Guard)

```tsx
// src/middleware.ts
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

const publicPaths = ['/login', '/register', '/forgot-password']

export function middleware(request: NextRequest) {
  const token = request.cookies.get('session')?.value
  const isPublic = publicPaths.some(p => request.nextUrl.pathname.startsWith(p))
  if (!token && !isPublic) return NextResponse.redirect(new URL('/login', request.url))
  if (token && isPublic) return NextResponse.redirect(new URL('/', request.url))
  return NextResponse.next()
}

export const config = { matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'] }
```

---

## Shared Layout Components (Header, Footer, Shell)

Next.js App Router layouts compose hierarchically. A shared component (e.g., footer) can't simply go in the root layout if some pages already have their own version (landing page with custom footer, microsites with no footer). Choose the right strategy:

### Strategy Decision

| Scenario | Approach |
|---|---|
| Footer/header identical on every page | Put in root `layout.tsx` |
| Some pages have custom footer (landing page) | Add per-layout or per-page — NOT root layout |
| Auth pages share a layout, dashboard pages share a different one | Use route group layouts: `(auth)/layout.tsx`, `(dashboard)/layout.tsx` |
| One-off pages (contact, privacy, terms) | Import and render directly in the page component |

### Shared Footer Component

```tsx
// src/components/SiteFooter.tsx
import Link from "next/link"

export default function SiteFooter() {
  return (
    <footer className="w-full border-t border-border/40 bg-background/80 backdrop-blur-sm">
      <div className="mx-auto max-w-6xl px-6 py-8">
        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          <span className="text-xs font-medium text-muted-foreground">AppName</span>
          <nav className="flex items-center gap-6" aria-label="Footer">
            <Link href="/contact" className="text-xs text-muted-foreground hover:text-foreground transition-colors">Contact</Link>
            <Link href="/privacy" className="text-xs text-muted-foreground hover:text-foreground transition-colors">Privacy</Link>
            <Link href="/terms" className="text-xs text-muted-foreground hover:text-foreground transition-colors">Terms</Link>
          </nav>
          <p className="text-[11px] text-muted-foreground/60">&copy; {new Date().getFullYear()} AppName</p>
        </div>
      </div>
    </footer>
  )
}
```

### Route Group Layout Pattern

Use route groups to wrap related pages with shared chrome without affecting the URL structure:

```tsx
// src/app/(auth)/layout.tsx — wraps /login, /register, /forgot-password
import SiteFooter from "@/components/SiteFooter"

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen flex flex-col">
      <div className="flex-1">{children}</div>
      <SiteFooter />
    </div>
  )
}
```

```tsx
// src/app/(dashboard)/layout.tsx — wraps authenticated pages
import { SessionProvider } from "next-auth/react"
import SiteFooter from "@/components/SiteFooter"

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <SessionProvider>
      {children}
      <SiteFooter />
    </SessionProvider>
  )
}
```

### Avoiding Double Footers

> **Common mistake:** Adding a footer to the root layout AND having pages/route-groups that render their own footer. This causes double footers.
>
> **Rule:** If ANY page under a layout has its own footer (e.g., a landing page with a custom branded footer), do NOT put a shared footer in the parent layout. Instead, add the footer to each route group or page individually.

### Dashboard Shell Pattern

For authenticated areas with sidebar + header + content area:

```tsx
// src/components/DashboardShell.tsx
export function DashboardShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen flex flex-col">
      <header className="sticky top-0 z-40 border-b bg-background/80 backdrop-blur-sm">
        {/* Logo, nav, user menu */}
      </header>
      <div className="flex flex-1">
        <aside className="hidden lg:block w-60 border-r p-4">
          {/* Sidebar navigation */}
        </aside>
        <main className="flex-1 p-6">{children}</main>
      </div>
      <SiteFooter />
    </div>
  )
}
```

---

## React Component Patterns

### cn() utility for Tailwind class merging

```typescript
// src/lib/utils.ts
import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'
export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)) }
```

### API Client with Zod Validation

```typescript
// src/services/api-client.ts
import { z } from 'zod'

const API_BASE = process.env.NEXT_PUBLIC_API_URL || '/api'

class ApiError extends Error {
  constructor(public status: number, message: string, public data?: unknown) {
    super(message); this.name = 'ApiError'
  }
}

async function request<T>(path: string, options: RequestInit = {}, schema?: z.ZodType<T>): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...options.headers },
    ...options,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => null)
    throw new ApiError(res.status, err?.message || res.statusText, err)
  }
  const data = await res.json()
  return schema ? schema.parse(data) : data as T
}

export const api = {
  get: <T>(path: string, schema?: z.ZodType<T>) => request<T>(path, { method: 'GET' }, schema),
  post: <T>(path: string, body: unknown, schema?: z.ZodType<T>) => request<T>(path, { method: 'POST', body: JSON.stringify(body) }, schema),
  put: <T>(path: string, body: unknown, schema?: z.ZodType<T>) => request<T>(path, { method: 'PUT', body: JSON.stringify(body) }, schema),
  patch: <T>(path: string, body: unknown, schema?: z.ZodType<T>) => request<T>(path, { method: 'PATCH', body: JSON.stringify(body) }, schema),
  delete: <T>(path: string, schema?: z.ZodType<T>) => request<T>(path, { method: 'DELETE' }, schema),
}
```

### TanStack Query Hook Pattern

```typescript
// src/hooks/use-users.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/services/api-client'
import { z } from 'zod'

const UserSchema = z.object({
  id: z.string(), email: z.string().email(), name: z.string(),
  role: z.enum(['admin', 'user', 'viewer']), createdAt: z.string().datetime(),
})
type User = z.infer<typeof UserSchema>

export function useUsers(page = 1) {
  return useQuery({
    queryKey: ['users', page],
    queryFn: () => api.get(`/users?page=${page}`, z.object({ users: z.array(UserSchema), total: z.number() })),
  })
}

export function useCreateUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data: Omit<User, 'id' | 'createdAt'>) => api.post('/users', data, UserSchema),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['users'] }),
  })
}
```

### WebSocket Hook

```typescript
// src/hooks/use-websocket.ts
'use client'
import { useEffect, useRef, useState, useCallback } from 'react'

type ConnectionState = 'connecting' | 'connected' | 'disconnected' | 'reconnecting'

export function useWebSocket({ url, onMessage, maxRetries = 10 }: {
  url: string; onMessage: (data: unknown) => void; maxRetries?: number
}) {
  const wsRef = useRef<WebSocket | null>(null)
  const [state, setState] = useState<ConnectionState>('disconnected')
  const attempts = useRef(0)

  const connect = useCallback(() => {
    setState('connecting')
    const ws = new WebSocket(url)
    ws.onopen = () => { setState('connected'); attempts.current = 0 }
    ws.onmessage = (e) => { try { onMessage(JSON.parse(e.data)) } catch { onMessage(e.data) } }
    ws.onclose = () => {
      setState('disconnected')
      if (attempts.current < maxRetries) {
        setState('reconnecting')
        setTimeout(() => { attempts.current++; connect() }, Math.min(1000 * 2 ** attempts.current, 30000))
      }
    }
    wsRef.current = ws
  }, [url, onMessage, maxRetries])

  const send = useCallback((data: unknown) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) wsRef.current.send(JSON.stringify(data))
  }, [])

  useEffect(() => { connect(); return () => { attempts.current = maxRetries; wsRef.current?.close() } }, [connect, maxRetries])

  return { state, send }
}
```

### Error Boundary

```tsx
// src/components/error-boundary.tsx
'use client'
import { Component, type ReactNode } from 'react'

export class ErrorBoundary extends Component<
  { children: ReactNode; fallback?: ReactNode | ((error: Error, reset: () => void) => ReactNode) },
  { hasError: boolean; error: Error | null }
> {
  state = { hasError: false, error: null as Error | null }
  static getDerivedStateFromError(error: Error) { return { hasError: true, error } }
  componentDidCatch(error: Error, info: React.ErrorInfo) { console.error('ErrorBoundary:', error, info.componentStack) }
  reset = () => this.setState({ hasError: false, error: null })

  render() {
    if (this.state.hasError && this.state.error) {
      if (typeof this.props.fallback === 'function') return this.props.fallback(this.state.error, this.reset)
      return this.props.fallback || (
        <div className="glass rounded-lg p-8 text-center">
          <p className="text-[var(--text-secondary)]">Something went wrong</p>
          <button onClick={this.reset} className="mt-4 text-sm text-[var(--text-link)] hover:underline">Try again</button>
        </div>
      )
    }
    return this.props.children
  }
}
```

---

## Performance Patterns

### Dynamic Imports
```tsx
import dynamic from 'next/dynamic'
const Chart = dynamic(() => import('@/components/features/chart'), { loading: () => <div className="skeleton h-64 w-full" />, ssr: false })
```

### Virtualized Lists
```tsx
import { useVirtualizer } from '@tanstack/react-virtual'
import { useRef } from 'react'

function VirtualList({ items }: { items: unknown[] }) {
  const parentRef = useRef<HTMLDivElement>(null)
  const virtualizer = useVirtualizer({ count: items.length, getScrollElement: () => parentRef.current, estimateSize: () => 56, overscan: 5 })

  return (
    <div ref={parentRef} className="h-[600px] overflow-auto">
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map((row) => (
          <div key={row.key} style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: `${row.size}px`, transform: `translateY(${row.start}px)` }}>
            {/* Render item */}
          </div>
        ))}
      </div>
    </div>
  )
}
```

---

## Testing Setup

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: { environment: 'jsdom', globals: true, setupFiles: ['./src/tests/setup.ts'] },
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
})
```

```tsx
// Example component test
import { render, screen, fireEvent } from '@testing-library/react'
import { Button } from '../button'

describe('Button', () => {
  it('renders and handles click', () => {
    const onClick = vi.fn()
    render(<Button onClick={onClick}>Click</Button>)
    fireEvent.click(screen.getByRole('button'))
    expect(onClick).toHaveBeenCalledOnce()
  })
  it('disables when loading', () => {
    render(<Button loading>Submit</Button>)
    expect(screen.getByRole('button')).toBeDisabled()
  })
})
```
