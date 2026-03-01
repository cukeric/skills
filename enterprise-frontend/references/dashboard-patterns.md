# Dashboard & Admin Panel Patterns

## Layout Architecture

### Dashboard Shell

Every dashboard has the same structural elements:
1. **Sidebar** (left, 256px) — navigation, user info, collapsible on mobile
2. **Top bar** (full width minus sidebar) — breadcrumbs, search, notifications, user menu
3. **Main content area** — scrollable, padded, contains the page content
4. **Optional: Command palette** (⌘K) — quick search/navigation

```
┌──────────┬─────────────────────────────────┐
│          │  Top Bar (breadcrumbs, search)   │
│ Sidebar  ├─────────────────────────────────┤
│  (nav)   │                                 │
│          │  Main Content (scrollable)       │
│          │                                 │
│          │                                 │
└──────────┴─────────────────────────────────┘
```

### Responsive Behavior

| Viewport | Sidebar | Top Bar | Content |
|---|---|---|---|
| Desktop (≥1024px) | Fixed, expanded (256px) | Full minus sidebar | Padded 24px |
| Tablet (768-1023px) | Collapsed icons only (64px) | Full minus sidebar | Padded 16px |
| Mobile (<768px) | Hidden, toggle via hamburger | Full width | Padded 16px |

### Collapsible Sidebar Pattern

```html
<!-- Sidebar container: toggle between w-64 and w-16 -->
<aside :class="collapsed ? 'w-16' : 'w-64'" class="glass fixed left-0 top-0 bottom-0 border-r transition-all duration-300 z-[var(--z-sticky)]">
  <!-- Nav items show icon always, text only when expanded -->
  <a class="flex items-center gap-3 px-3 py-2.5 rounded-md">
    <Icon class="w-5 h-5 shrink-0" />
    <span :class="collapsed ? 'sr-only' : ''">Dashboard</span>
  </a>
</aside>
```

---

## Widget / Card Grid System

Dashboards are composed of **widgets** — self-contained cards that display a single piece of information or visualization.

### Grid Layout

```html
<!-- Responsive grid: 1 col mobile, 2 tablet, 3-4 desktop -->
<div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4 lg:gap-6">
  <!-- Stat cards (small) -->
  <StatCard title="Total Revenue" value="$48,293" change="+12.5%" trend="up" />
  <StatCard title="Active Users" value="2,847" change="+3.2%" trend="up" />
  <StatCard title="Conversion" value="3.24%" change="-0.8%" trend="down" />
  <StatCard title="Avg. Order" value="$67.50" change="+5.1%" trend="up" />
</div>

<!-- Large widgets: span multiple columns -->
<div class="grid grid-cols-1 lg:grid-cols-3 gap-4 lg:gap-6 mt-6">
  <div class="lg:col-span-2">
    <RevenueChart />     <!-- Takes 2/3 on desktop -->
  </div>
  <div>
    <RecentActivity />   <!-- Takes 1/3 on desktop -->
  </div>
</div>
```

### Stat Card Pattern

```html
<div class="glass rounded-lg p-5">
  <div class="flex items-center justify-between">
    <p class="text-xs font-medium text-[var(--text-tertiary)] uppercase tracking-wider">Total Revenue</p>
    <div class="w-8 h-8 rounded-md bg-[var(--accent-primary-subtle)] flex items-center justify-center">
      <DollarSign class="w-4 h-4 text-[var(--accent-primary)]" />
    </div>
  </div>
  <p class="mt-3 text-2xl font-bold text-[var(--text-primary)] font-display">$48,293</p>
  <div class="mt-2 flex items-center gap-1.5">
    <span class="flex items-center text-xs font-medium text-[var(--color-success)]">
      <TrendingUp class="w-3.5 h-3.5 mr-0.5" /> +12.5%
    </span>
    <span class="text-xs text-[var(--text-tertiary)]">vs last month</span>
  </div>
</div>
```

---

## Data Table Patterns

### Enterprise Data Table Requirements
- Sortable columns (click header)
- Filterable / searchable
- Pagination (server-side for large datasets)
- Row selection (checkbox)
- Column visibility toggle
- Responsive: horizontal scroll on mobile, or card view
- Loading skeleton rows
- Empty state

### Recommended Libraries
- **React**: TanStack Table (headless, full control)
- **Vue**: TanStack Table for Vue, or PrimeVue DataTable
- **Svelte**: TanStack Table for Svelte

### Table Structure

```html
<div class="glass rounded-lg overflow-hidden">
  <!-- Header: search + filters + actions -->
  <div class="flex items-center justify-between px-4 py-3 border-b border-[var(--border-default)]">
    <div class="flex items-center gap-3">
      <div class="relative">
        <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-tertiary)]" />
        <input placeholder="Search..." class="input-base pl-9 w-64" />
      </div>
      <button class="/* ghost button */">Filters <ChevronDown class="w-4 h-4" /></button>
    </div>
    <button class="/* primary button */">Add User</button>
  </div>

  <!-- Table -->
  <div class="overflow-x-auto">
    <table class="w-full">
      <thead>
        <tr class="border-b border-[var(--border-default)]">
          <th class="px-4 py-3 text-left text-xs font-medium text-[var(--text-tertiary)] uppercase tracking-wider">
            <!-- Checkbox -->
          </th>
          <th class="px-4 py-3 text-left text-xs font-medium text-[var(--text-tertiary)] uppercase tracking-wider cursor-pointer hover:text-[var(--text-primary)]">
            Name <ArrowUpDown class="inline w-3 h-3 ml-1" />
          </th>
          <!-- More columns -->
        </tr>
      </thead>
      <tbody class="divide-y divide-[var(--border-default)]">
        <tr class="hover:bg-[var(--bg-inset)] transition-colors">
          <td class="px-4 py-3"><!-- Checkbox --></td>
          <td class="px-4 py-3">
            <div class="flex items-center gap-3">
              <div class="w-8 h-8 rounded-full bg-[var(--accent-primary-subtle)]"><!-- Avatar --></div>
              <div>
                <p class="text-sm font-medium text-[var(--text-primary)]">Jane Doe</p>
                <p class="text-xs text-[var(--text-tertiary)]">jane@company.com</p>
              </div>
            </div>
          </td>
          <!-- More cells -->
        </tr>
      </tbody>
    </table>
  </div>

  <!-- Pagination -->
  <div class="flex items-center justify-between px-4 py-3 border-t border-[var(--border-default)]">
    <p class="text-sm text-[var(--text-tertiary)]">Showing 1-10 of 248</p>
    <div class="flex items-center gap-2">
      <button class="/* ghost icon button */">Previous</button>
      <button class="/* ghost icon button */">Next</button>
    </div>
  </div>
</div>
```

---

## Real-Time Dashboard Patterns

### Live Metric Updates

```typescript
// Pattern: Throttled store updates for high-frequency data
const THROTTLE_MS = 250

let buffer: MetricUpdate[] = []
let timer: ReturnType<typeof setTimeout> | null = null

function handleMetricUpdate(update: MetricUpdate) {
  buffer.push(update)

  if (!timer) {
    timer = setTimeout(() => {
      // Batch apply all buffered updates
      metricsStore.batchUpdate(buffer)
      buffer = []
      timer = null
    }, THROTTLE_MS)
  }
}
```

### Connection Status Indicator

```html
<!-- Always visible in top bar when using real-time data -->
<div class="flex items-center gap-2 text-xs">
  <!-- Connected -->
  <span class="flex items-center gap-1.5 text-[var(--color-success)]">
    <span class="w-2 h-2 rounded-full bg-[var(--color-success)] animate-pulse" />
    Live
  </span>

  <!-- Reconnecting -->
  <span class="flex items-center gap-1.5 text-[var(--color-warning)]">
    <span class="w-2 h-2 rounded-full bg-[var(--color-warning)] animate-pulse" />
    Reconnecting...
  </span>

  <!-- Disconnected -->
  <span class="flex items-center gap-1.5 text-[var(--color-error)]">
    <span class="w-2 h-2 rounded-full bg-[var(--color-error)]" />
    Offline
  </span>
</div>
```

### Stale Data Warning

```html
<!-- Show when data is older than threshold (e.g., 5 minutes) -->
<div class="flex items-center gap-2 px-3 py-2 rounded-md bg-[var(--color-warning-subtle)] text-[var(--color-warning)] text-xs">
  <AlertTriangle class="w-3.5 h-3.5" />
  Data last updated 7 minutes ago
  <button class="underline hover:no-underline">Refresh</button>
</div>
```

---

## Empty States

Every data view must have an empty state — never show a blank page.

```html
<div class="flex flex-col items-center justify-center py-16 px-4">
  <div class="w-12 h-12 rounded-full bg-[var(--bg-inset)] flex items-center justify-center mb-4">
    <Users class="w-6 h-6 text-[var(--text-tertiary)]" />
  </div>
  <h3 class="text-sm font-semibold text-[var(--text-primary)]">No users yet</h3>
  <p class="mt-1 text-sm text-[var(--text-tertiary)] text-center max-w-sm">
    Get started by inviting your first team member.
  </p>
  <button class="mt-4 /* primary button sm */">
    <Plus class="w-4 h-4" /> Add User
  </button>
</div>
```

---

## Notification / Toast System

```typescript
// Pattern: toast store
interface Toast {
  id: string
  type: 'success' | 'error' | 'warning' | 'info'
  title: string
  description?: string
  duration?: number  // ms, default 5000
}

// Position: bottom-right, stacked, auto-dismiss
// Max visible: 5 toasts
// Animation: slide in from right, fade out
```

### Toast Component Pattern

```html
<!-- Fixed position container -->
<div class="fixed bottom-4 right-4 z-[var(--z-toast)] flex flex-col gap-2 w-96 max-w-[calc(100vw-2rem)]">
  <!-- Individual toast -->
  <div class="glass-elevated rounded-lg p-4 flex items-start gap-3 animate-fade-in">
    <CheckCircle class="w-5 h-5 text-[var(--color-success)] shrink-0 mt-0.5" />
    <div class="flex-1 min-w-0">
      <p class="text-sm font-medium text-[var(--text-primary)]">User created</p>
      <p class="text-xs text-[var(--text-tertiary)] mt-0.5">Jane Doe has been added to the team.</p>
    </div>
    <button class="text-[var(--text-tertiary)] hover:text-[var(--text-primary)]">
      <X class="w-4 h-4" />
    </button>
  </div>
</div>
```

---

## Command Palette (⌘K)

For power users — quick search and navigation across the entire app.

**Recommended libraries:**
- React: `cmdk` (by Pacocoursey)
- Vue: `vue-command-palette`
- Svelte: Custom implementation with same pattern

```html
<!-- Trigger: Ctrl/Cmd + K -->
<div class="fixed inset-0 z-[var(--z-modal)]">
  <div class="absolute inset-0 bg-[var(--bg-overlay)]" />
  <div class="glass-elevated mx-auto mt-[20vh] w-full max-w-lg rounded-xl overflow-hidden">
    <div class="flex items-center gap-3 px-4 border-b border-[var(--border-default)]">
      <Search class="w-4 h-4 text-[var(--text-tertiary)]" />
      <input autofocus placeholder="Search or type a command..." class="flex-1 py-3 bg-transparent text-sm text-[var(--text-primary)] outline-none" />
      <kbd class="text-xs text-[var(--text-tertiary)] bg-[var(--bg-inset)] px-1.5 py-0.5 rounded">Esc</kbd>
    </div>
    <div class="max-h-72 overflow-y-auto p-2">
      <!-- Search results grouped by category -->
    </div>
  </div>
</div>
```
