# Svelte & SvelteKit Enterprise Reference

## Project Initialization

```bash
pnpm create svelte@latest my-app  # Choose: Skeleton, TypeScript, ESLint, Prettier, Playwright, Vitest
cd my-app
pnpm add zod @tanstack/svelte-query class-variance-authority clsx tailwind-merge lucide-svelte
pnpm add -D tailwindcss @tailwindcss/vite
```

---

## SvelteKit Architecture

### Directory Structure

```
src/
├── routes/
│   ├── +layout.svelte         # Root layout (providers, fonts)
│   ├── +layout.server.ts      # Root server load (auth check)
│   ├── +page.svelte            # Home page
│   ├── +error.svelte           # Error page
│   ├── (auth)/
│   │   ├── login/+page.svelte
│   │   ├── register/+page.svelte
│   │   └── +layout.svelte      # Centered auth layout
│   ├── (dashboard)/
│   │   ├── +layout.svelte      # Dashboard shell
│   │   ├── +layout.server.ts   # Auth guard
│   │   ├── +page.svelte        # Dashboard home
│   │   ├── analytics/+page.svelte
│   │   └── users/
│   │       ├── +page.svelte
│   │       └── [id]/+page.svelte
│   └── api/
│       └── webhooks/stripe/+server.ts
├── lib/
│   ├── components/
│   │   ├── ui/                 # Design system
│   │   ├── layout/
│   │   ├── features/
│   │   └── shared/
│   ├── stores/
│   │   ├── auth.ts
│   │   └── websocket.ts
│   ├── services/
│   │   └── api-client.ts
│   ├── types/
│   │   └── index.ts
│   └── utils/
│       └── cn.ts
├── hooks.server.ts              # Server hooks (auth middleware)
└── app.d.ts                     # Type declarations
```

### Server Hooks (Auth Middleware)

```typescript
// src/hooks.server.ts
import type { Handle } from '@sveltejs/kit'
import { redirect } from '@sveltejs/kit'

const publicPaths = ['/login', '/register', '/forgot-password']

export const handle: Handle = async ({ event, resolve }) => {
  const session = event.cookies.get('session')
  event.locals.user = session ? await validateSession(session) : null

  const isPublic = publicPaths.some(p => event.url.pathname.startsWith(p))
  if (!event.locals.user && !isPublic) throw redirect(303, '/login')
  if (event.locals.user && isPublic) throw redirect(303, '/dashboard')

  return resolve(event)
}
```

### Load Functions

```typescript
// src/routes/(dashboard)/+layout.server.ts
import type { LayoutServerLoad } from './$types'

export const load: LayoutServerLoad = async ({ locals }) => {
  return { user: locals.user }
}
```

```typescript
// src/routes/(dashboard)/users/+page.server.ts
import type { PageServerLoad } from './$types'

export const load: PageServerLoad = async ({ fetch, url }) => {
  const page = Number(url.searchParams.get('page')) || 1
  const res = await fetch(`/api/users?page=${page}`)
  return { users: await res.json() }
}
```

---

## Svelte Component Patterns

### Store-Based State

```typescript
// src/lib/stores/auth.ts
import { writable, derived } from 'svelte/store'

interface User { id: string; email: string; name: string; role: string }

export const user = writable<User | null>(null)
export const isAuthenticated = derived(user, $user => !!$user)
export const isAdmin = derived(user, $user => $user?.role === 'admin')
```

### WebSocket Store

```typescript
// src/lib/stores/websocket.ts
import { writable, get } from 'svelte/store'

type State = 'connecting' | 'connected' | 'disconnected' | 'reconnecting'

export function createWebSocketStore(url: string) {
  const state = writable<State>('disconnected')
  const messages = writable<unknown[]>([])
  let ws: WebSocket | null = null
  let attempts = 0

  function connect() {
    state.set('connecting')
    ws = new WebSocket(url)
    ws.onopen = () => { state.set('connected'); attempts = 0 }
    ws.onmessage = (e) => {
      try { messages.update(m => [...m.slice(-99), JSON.parse(e.data)]) }
      catch { messages.update(m => [...m.slice(-99), e.data]) }
    }
    ws.onclose = () => {
      state.set('disconnected')
      if (attempts < 10) {
        state.set('reconnecting')
        setTimeout(() => { attempts++; connect() }, Math.min(1000 * 2 ** attempts, 30000))
      }
    }
  }

  function send(data: unknown) { ws?.readyState === WebSocket.OPEN && ws.send(JSON.stringify(data)) }
  function disconnect() { attempts = 10; ws?.close() }

  return { state, messages, connect, send, disconnect }
}
```

### Component with CVA

```svelte
<!-- src/lib/components/ui/Button.svelte -->
<script lang="ts">
  import { cn } from '$lib/utils/cn'
  import { buttonVariants, type ButtonVariants } from '$lib/styles/button-variants'

  export let variant: ButtonVariants['variant'] = 'primary'
  export let size: ButtonVariants['size'] = 'md'
  export let loading = false
  export let disabled = false
  let className = ''
  export { className as class }
</script>

<button
  class={cn(buttonVariants({ variant, size }), className)}
  disabled={disabled || loading}
  on:click
  {...$$restProps}
>
  {#if loading}
    <span class="animate-spin w-4 h-4 border-2 border-current border-t-transparent rounded-full" />
  {/if}
  <slot />
</button>
```

### API Client

```typescript
// src/lib/services/api-client.ts
import { z } from 'zod'

class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); this.name = 'ApiError' }
}

async function request<T>(path: string, options: RequestInit = {}, schema?: z.ZodType<T>): Promise<T> {
  const res = await fetch(`/api${path}`, {
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...options.headers },
    ...options,
  })
  if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => ({ message: res.statusText }))).message)
  const data = await res.json()
  return schema ? schema.parse(data) : data as T
}

export const api = {
  get: <T>(p: string, s?: z.ZodType<T>) => request<T>(p, { method: 'GET' }, s),
  post: <T>(p: string, b: unknown, s?: z.ZodType<T>) => request<T>(p, { method: 'POST', body: JSON.stringify(b) }, s),
  put: <T>(p: string, b: unknown, s?: z.ZodType<T>) => request<T>(p, { method: 'PUT', body: JSON.stringify(b) }, s),
  delete: <T>(p: string, s?: z.ZodType<T>) => request<T>(p, { method: 'DELETE' }, s),
}
```

### Form Handling with Superforms

```bash
pnpm add sveltekit-superforms
```

```typescript
// src/routes/(dashboard)/users/create/+page.server.ts
import { superValidate, fail, message } from 'sveltekit-superforms'
import { zod } from 'sveltekit-superforms/adapters'
import { z } from 'zod'

const schema = z.object({
  email: z.string().email(),
  name: z.string().min(2),
  role: z.enum(['admin', 'user', 'viewer']),
})

export const load = async () => ({ form: await superValidate(zod(schema)) })

export const actions = {
  default: async ({ request }) => {
    const form = await superValidate(request, zod(schema))
    if (!form.valid) return fail(400, { form })
    // Create user...
    return message(form, 'User created')
  },
}
```

```svelte
<!-- src/routes/(dashboard)/users/create/+page.svelte -->
<script lang="ts">
  import { superForm } from 'sveltekit-superforms'
  export let data
  const { form, errors, enhance, submitting } = superForm(data.form)
</script>

<form method="POST" use:enhance>
  <input bind:value={$form.email} class="input-base" />
  {#if $errors.email}<span class="text-[var(--color-error)] text-xs">{$errors.email}</span>{/if}
  <button type="submit" disabled={$submitting}>Create</button>
</form>
```

---

## SvelteKit-Specific Performance

- **Prerender static pages**: `export const prerender = true` in `+page.ts`
- **Stream data**: Use `event.platform` and streaming load functions
- **Prefetch links**: SvelteKit prefetches on hover by default — no config needed
- **Adapter selection**: `@sveltejs/adapter-node` for VPS, `@sveltejs/adapter-auto` for Vercel/Cloudflare

---

## Testing

```typescript
// src/lib/components/ui/__tests__/Button.test.ts
import { render, fireEvent } from '@testing-library/svelte'
import Button from '../Button.svelte'

describe('Button', () => {
  it('renders slot content', () => {
    const { getByRole } = render(Button, { props: {}, slots: { default: 'Click me' } })
    expect(getByRole('button')).toHaveTextContent('Click me')
  })
})
```
