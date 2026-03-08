---
name: enterprise-frontend
description: Explains how to create, design, modify, style, or optimize frontend applications with enterprise standards. Trigger on ANY mention of UI, UX, component, dashboard, layout, visualization, chart, graph, responsive, styling, CSS, Tailwind, glassmorphic, glassmorphism, frontend, front-end, React, Next.js, Vue, Nuxt, Svelte, SvelteKit, widget, sidebar, navbar, modal, form, table, data grid, theme, dark mode, animation, page, view, screen, design system, accessibility, a11y, or any request to build user-facing interfaces. Also trigger when the user asks to display data visually, build admin panels, create landing pages, or when a project clearly requires a UI layer even if the word frontend is never used. This skill applies to new projects AND modifications to existing frontends.
---

# Enterprise Frontend Development Skill

Every frontend created or modified using this skill must meet enterprise-grade standards for security, performance, responsiveness, and scalability — in that priority order. Even for prototypes or MVPs, the foundations must be production-ready because retrofitting architecture, accessibility, and security into a mature UI codebase is brutal.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) based on the project's framework and requirements:

### Framework-Specific Implementation
- `references/react-nextjs.md` — Any project using React or Next.js
- `references/vue-nuxt.md` — Any project using Vue or Nuxt
- `references/svelte-sveltekit.md` — Any project using Svelte or SvelteKit

### Design System & UI
- `references/glassmorphic-design-system.md` — Default design system: glassmorphic components, color tokens, typography, spacing, warm-toned soft palette
- `references/dashboard-patterns.md` — Real-time dashboards, admin panels, data grids, modular widget layouts

### Data Visualization & Maps
- `references/data-visualization.md` — Charts, graphs, maps, real-time streaming visualization, library selection
- `references/google-maps-integration.md` — Google Maps Places Autocomplete, Static Maps, Geocoding, address input components

### Responsive Design & Accessibility
- `references/responsive-accessibility.md` — Responsive breakpoints, mobile-first patterns, WCAG 2.1 AA compliance, keyboard navigation, screen readers

Read this SKILL.md first for architecture decisions and standards, then consult the relevant reference files for implementation specifics.

---

## Decision Framework: Choosing the Right Frontend Stack

Before writing any component code, evaluate the project requirements and select the appropriate framework. Do not default to a stack out of familiarity — match the stack to the problem.

### Framework Selection Matrix

| Requirement | Best Choice | Why |
|---|---|---|
| SEO-critical public pages (marketing, blog, e-commerce) | **Next.js** (App Router) | Server-side rendering, static generation, metadata API, image optimization |
| Internal dashboard / admin panel | **React + Vite** or **Next.js** | SPA is fine for authenticated apps; Next.js if SSR needed for performance |
| Content-heavy site with forms and interactivity | **Nuxt 3** | Vue's template syntax excels at form-heavy UIs, Nuxt adds SSR/SSG |
| Performance-critical with minimal JS | **SvelteKit** | Smallest bundle sizes, compile-time optimization, no virtual DOM overhead |
| Rapid prototyping / small team | **SvelteKit** or **Nuxt 3** | Less boilerplate, faster iteration, built-in routing and state |
| Enterprise with existing React ecosystem | **Next.js** (App Router) | Largest ecosystem, most hiring pool, best tooling support |
| Real-time heavy (live data, websockets) | **React + Vite** or **SvelteKit** | SPA avoids SSR hydration complexity for socket-connected UIs |
| Mobile + Web from one codebase | **Next.js + React Native** (or Expo) | Shared business logic, separate UI layers |

### When to Use SSR vs SPA vs SSG

**Server-Side Rendering (SSR):** Public-facing pages that need SEO, social sharing previews, or fast initial paint. Use Next.js App Router, Nuxt 3, or SvelteKit in SSR mode.

**Single Page Application (SPA):** Authenticated dashboards, admin panels, internal tools where SEO doesn't matter and the user is already logged in. Use React+Vite, Vue+Vite, or SvelteKit in SPA mode.

**Static Site Generation (SSG):** Marketing pages, documentation, blogs with infrequent content changes. Use Next.js static export, Nuxt generate, or SvelteKit prerender.

**Hybrid:** Most enterprise apps need a combination. Next.js App Router and SvelteKit both support per-route rendering strategies — use SSG for marketing, SSR for dynamic public pages, and client-side for authenticated sections.

### Meta-Framework vs Bare Framework

Always prefer a meta-framework (Next.js, Nuxt, SvelteKit) over bare React/Vue/Svelte unless the project is a widget, embeddable component, or micro-frontend. Meta-frameworks provide routing, data fetching, build optimization, and deployment integration out of the box.

---

## Priority 1: Security

### Content Security
- **Sanitize all user-generated content** before rendering. Use DOMPurify or equivalent.
- **Never use `dangerouslySetInnerHTML`** (React), `v-html` (Vue), or `{@html}` (Svelte) with untrusted data.
- **Implement Content Security Policy (CSP) headers** via the meta-framework's middleware or server config.
- **Validate all inputs client-side AND server-side.** Client validation is UX; server validation is security.

### Authentication UI
- **Never store tokens in localStorage.** Use httpOnly cookies set by the backend.
- **Implement CSRF protection** on all state-changing forms.
- **Auto-redirect expired sessions** with a global auth guard / middleware.
- **Never expose sensitive data in client-side state.** API keys, secrets, and internal IDs stay server-side.
- **Use `<input type="password">` with autocomplete attributes** for credential forms.

### Dependency Security
- **Audit dependencies regularly** with `npm audit` or `pnpm audit`.
- **Pin dependency versions** in production. Use lockfiles.
- **Minimize third-party scripts.** Every external script is an attack surface.

---

## Priority 2: Performance

### Core Web Vitals Targets
Every page must target:
- **LCP (Largest Contentful Paint):** < 2.5s
- **FID/INP (Interaction to Next Paint):** < 200ms
- **CLS (Cumulative Layout Shift):** < 0.1

### Bundle Optimization
- **Code split aggressively.** Route-based splitting is the baseline; component-level splitting for heavy modules (charts, editors, maps).
- **Lazy load below-the-fold content.** Use `React.lazy()`, Vue `defineAsyncComponent()`, or Svelte dynamic imports.
- **Tree-shake everything.** Import only what's needed: `import { Button } from 'lib'` not `import lib from 'lib'`.
- **Analyze bundle size** with `@next/bundle-analyzer`, `rollup-plugin-visualizer`, or `vite-plugin-inspect`.
- **Set performance budgets:** < 200KB initial JS (compressed), < 100KB CSS.

### Image & Asset Optimization
- **Use next/image, nuxt-image, or equivalent** for automatic format conversion (WebP/AVIF), responsive srcsets, and lazy loading.
- **Serve static assets from a CDN.** Configure cache headers (immutable for hashed assets, short TTL for HTML).
- **Inline critical CSS** and defer non-critical stylesheets.

### Rendering Performance
- **Memoize expensive computations.** `useMemo`/`useCallback` (React), `computed` (Vue), reactive declarations (Svelte).
- **Virtualize long lists.** Use `@tanstack/react-virtual`, `vue-virtual-scroller`, or `svelte-virtual-list` for lists > 100 items.
- **Debounce rapid-fire events** (scroll, resize, input) — 150-300ms for UI, 300-500ms for API calls.
- **Avoid layout thrashing.** Batch DOM reads before writes. Use `requestAnimationFrame` for visual updates.

---

## Priority 3: Responsiveness & UX

### Mobile-First Design
- **Design mobile-first, enhance for desktop.** Start with the smallest viewport and add complexity.
- **Breakpoints (Tailwind defaults):**
  - `sm`: 640px — large phones landscape
  - `md`: 768px — tablets
  - `lg`: 1024px — small laptops
  - `xl`: 1280px — desktops
  - `2xl`: 1536px — large screens
- **Touch targets minimum 44x44px** (WCAG 2.5.8).
- **No horizontal scroll on any viewport.** Test at 320px minimum width.

### Component Architecture
- **Atomic design hierarchy:** Atoms → Molecules → Organisms → Templates → Pages.
- **Every component must be:**
  - Self-contained (no implicit dependencies on parent state)
  - Typed (TypeScript interfaces for all props)
  - Accessible (keyboard navigable, ARIA labels where needed)
  - Testable (pure rendering logic, side effects in hooks/composables)
- **Composition over configuration.** Prefer composable primitives over monolithic components with dozens of props.

### State Management
Choose the simplest solution that works:

| Scope | Solution |
|---|---|
| Component-local | `useState` / `ref()` / `let` binding |
| Shared between siblings | Lift state to nearest common parent |
| Feature-wide | Context (React), `provide/inject` (Vue), stores (Svelte) |
| App-wide client state | Zustand (React), Pinia (Vue), built-in stores (Svelte) |
| Server state / caching | TanStack Query (all frameworks) or SWR (React) |
| Complex forms | React Hook Form, VeeValidate (Vue), Superforms (SvelteKit) |
| Real-time / WebSocket state | Dedicated store connected to socket, TanStack Query with refetch |

**Never put server state in client state stores.** Use TanStack Query or equivalent for all API data — it handles caching, revalidation, loading states, and error states.

---

## Priority 4: Scalability & Maintainability

### Project Structure
Enforce a consistent structure regardless of framework:

```
src/
├── app/                  # Routes/pages (framework-specific)
├── components/
│   ├── ui/               # Design system primitives (Button, Input, Card, etc.)
│   ├── layout/           # Shell, Sidebar, Navbar, Footer
│   ├── features/         # Feature-specific components (UserProfile, InvoiceTable)
│   └── shared/           # Cross-feature reusable components
├── hooks/ (or composables/ or lib/)
│   ├── use-auth.ts       # Auth state and guards
│   ├── use-websocket.ts  # WebSocket connection management
│   └── use-debounce.ts   # Utility hooks
├── services/
│   ├── api-client.ts     # Configured HTTP client (axios/fetch wrapper)
│   └── websocket.ts      # WebSocket service
├── stores/               # Global state (if needed beyond server state)
├── types/                # Shared TypeScript interfaces and types
├── utils/                # Pure utility functions
├── styles/
│   ├── globals.css        # Tailwind directives, CSS custom properties
│   └── design-tokens.ts   # Color, spacing, typography tokens
├── config/
│   ├── env.ts            # Typed environment variables
│   └── constants.ts      # App-wide constants
└── tests/
    ├── unit/
    ├── integration/
    └── e2e/
```

### TypeScript Standards
- **Strict mode always enabled.** `"strict": true` in tsconfig.
- **No `any` types.** Use `unknown` and narrow with type guards.
- **Interface for object shapes, type for unions/intersections.**
- **Zod for runtime validation** of API responses and form data.
- **Barrel exports (`index.ts`) for each directory** to enforce public APIs.

### Styling Architecture
**Default: Tailwind CSS** for all projects. It enforces consistency, eliminates naming debates, and tree-shakes unused styles.

- **Use design tokens via CSS custom properties** (see glassmorphic design system reference).
- **Component variants via CVA (Class Variance Authority)** or Tailwind's `@apply` in component-scoped styles.
- **Never use inline style objects** except for truly dynamic values (percentages, calculated positions).
- **Dark mode: `class` strategy** (not media query) for user-controlled theme switching.

### Testing Requirements
- **Unit tests** for utility functions and complex hooks/composables (Vitest).
- **Component tests** for interactive components (Testing Library + Vitest).
- **E2E tests** for critical user flows — auth, payments, data submission (Playwright).
- **Visual regression tests** for design system components (Chromatic or Percy, optional but recommended).
- **Minimum coverage:** 80% for utilities, 60% for components, 100% for auth flows.

### Error Handling
- **Global error boundary** at the app root (React `ErrorBoundary`, Vue `onErrorCaptured`, SvelteKit `+error.svelte`).
- **Per-feature error boundaries** for isolated failure (a broken chart shouldn't crash the whole dashboard).
- **User-friendly error states** for every async operation: loading, error, empty, and success states.
- **Log errors to a service** (Sentry, LogRocket, or custom endpoint). Never swallow errors silently.
- **Retry logic** for transient network failures (TanStack Query has built-in retry).

---

## Design System: Default Standards

Unless the user specifies otherwise, all UIs must follow the **glassmorphic design system** defined in `references/glassmorphic-design-system.md`. Key principles:

1. **Glass-effect containers** with backdrop blur and subtle borders
2. **Soft, warm color palette** — no harsh primaries, warm undertones on neutrals
3. **Generous whitespace** — content breathes, never cramped
4. **Subtle animations** — micro-interactions that feel natural (200-300ms transitions)
5. **Depth through layering** — not flat, not skeuomorphic, but layered glass panels
6. **Typography hierarchy** — clear visual hierarchy with weight and size, not color alone
7. **Functional first** — every design decision serves usability, beauty is the byproduct of good function

---

## Real-Time Data Patterns

For dashboards and live-updating UIs, follow these patterns:

### Connection Management
- **Single WebSocket connection per client** managed by a service/store, not per-component.
- **Automatic reconnection** with exponential backoff (1s, 2s, 4s, 8s, max 30s).
- **Connection state exposed to UI** — show connected/reconnecting/disconnected status.
- **Heartbeat/ping-pong** every 30s to detect stale connections.

### Data Flow
- **Server pushes updates → client store updates → components reactively re-render.**
- **Never poll when you can push.** Use WebSockets or SSE for live data.
- **Optimistic updates** for user actions — update UI immediately, roll back on server error.
- **Throttle render updates** for high-frequency data (stock tickers, metrics). Buffer and batch at 100-250ms intervals.

### Offline & Degraded Mode
- **Queue user actions when offline.** Replay when connection restores.
- **Show stale data with a timestamp** rather than showing nothing.
- **Degrade gracefully** — if WebSocket fails, fall back to polling at reduced frequency.

---

## Integration with Other Enterprise Skills

This frontend skill connects to:

- **enterprise-database**: Frontend doesn't connect to databases directly. All data flows through the backend API. The frontend's TanStack Query / data fetching layer maps to backend API endpoints.
- **enterprise-backend**: The API client and WebSocket service in the frontend must match the backend's API contracts. Use shared TypeScript types (monorepo) or OpenAPI-generated clients.
- **enterprise-deployment**: Frontend builds produce static assets or a Node.js server (SSR). The deployment skill handles CDN configuration, caching headers, and environment-specific builds.

---

## Verification Checklist

Before considering any frontend work complete, verify:

- [ ] TypeScript strict mode passes with zero errors
- [ ] All components render without console errors or warnings
- [ ] Lighthouse score > 90 for Performance, Accessibility, Best Practices, SEO
- [ ] No horizontal scroll at 320px viewport width
- [ ] Keyboard navigation works for all interactive elements
- [ ] Dark mode toggle works without flash of unstyled content
- [ ] Error boundaries catch and display failures gracefully
- [ ] Loading states shown for all async operations
- [ ] Bundle size within budget (< 200KB initial JS compressed)
- [ ] All environment variables typed and validated at build time
