# Data Visualization Reference

## Library Selection

| Need | Library | Why |
|---|---|---|
| Standard charts (line, bar, pie, area) | **Recharts** (React) / **Chart.js** (all) | Simple API, good defaults, responsive |
| Complex / custom visualizations | **D3.js** | Full control, any visualization possible |
| Real-time streaming charts | **uPlot** or **Lightweight Charts** | Extremely fast rendering, handles 100k+ points |
| Maps / geospatial | **Mapbox GL JS** or **Leaflet** | Interactive maps, custom layers |
| Data grids with mini charts | **AG Grid** (enterprise) or **TanStack Table** + sparklines | Heavy data tables with inline viz |
| Simple sparklines | **@visx/sparkline** or custom SVG | Tiny inline charts for stat cards |

### Framework-Specific Wrappers
- **React**: Recharts, @visx, nivo, react-chartjs-2
- **Vue**: vue-chartjs, Vue ECharts
- **Svelte**: LayerCake, svelte-chartjs, pancake (deprecated → LayerCake)

---

## Chart Design Standards (Glassmorphic Theme)

### Color Palette for Charts

```typescript
// Chart colors — warm, distinguishable, accessible
export const chartColors = {
  primary: '#c07a45',     // Warm amber
  secondary: '#7b9e87',   // Sage green
  tertiary: '#7a9bb5',    // Muted blue
  quaternary: '#d4a053',  // Golden amber
  quinary: '#c47068',     // Warm coral
  senary: '#9b8bb4',      // Muted purple

  // Sequential scale (for heatmaps, gradients)
  sequential: ['#fef0e0', '#fdd5a5', '#f0b06a', '#c07a45', '#8a5530'],

  // Diverging scale (for positive/negative)
  diverging: ['#c47068', '#e8a098', '#f5f0ec', '#a3c5ad', '#7b9e87'],
}

// Dark mode variants
export const chartColorsDark = {
  primary: '#d4944f',
  secondary: '#8fb69b',
  tertiary: '#8fb0c8',
  quaternary: '#e0b460',
  quinary: '#d4847c',
  senary: '#b0a0c8',
}
```

### Standard Chart Styling

```typescript
// Recharts example — consistent styling
const chartConfig = {
  // Grid
  grid: { strokeDasharray: '3 3', stroke: 'var(--border-default)' },

  // Axes
  axis: {
    tick: { fill: 'var(--text-tertiary)', fontSize: 12 },
    line: { stroke: 'var(--border-default)' },
  },

  // Tooltip
  tooltip: {
    contentStyle: {
      background: 'var(--bg-elevated)',
      backdropFilter: 'blur(16px)',
      border: '1px solid var(--glass-border)',
      borderRadius: 'var(--border-radius-md)',
      boxShadow: 'var(--glass-shadow-elevated)',
      fontSize: '13px',
      color: 'var(--text-primary)',
    },
    cursor: { fill: 'var(--accent-primary-subtle)' },
  },

  // Legend
  legend: { fontSize: 12, color: 'var(--text-secondary)' },
}
```

### Chart Container Pattern

```html
<!-- All charts wrapped in glass card with header -->
<div class="glass rounded-lg overflow-hidden">
  <div class="flex items-center justify-between px-5 py-4 border-b border-[var(--border-default)]">
    <div>
      <h3 class="text-sm font-semibold text-[var(--text-primary)]">Revenue Over Time</h3>
      <p class="text-xs text-[var(--text-tertiary)] mt-0.5">Last 12 months</p>
    </div>
    <div class="flex items-center gap-2">
      <!-- Time range buttons: 7d, 30d, 90d, 12m -->
      <div class="flex rounded-md overflow-hidden border border-[var(--border-default)]">
        <button class="px-2.5 py-1 text-xs bg-[var(--accent-primary-subtle)] text-[var(--accent-primary)] font-medium">12m</button>
        <button class="px-2.5 py-1 text-xs text-[var(--text-tertiary)] hover:text-[var(--text-primary)]">90d</button>
        <button class="px-2.5 py-1 text-xs text-[var(--text-tertiary)] hover:text-[var(--text-primary)]">30d</button>
      </div>
    </div>
  </div>
  <div class="p-5">
    <div class="h-64">
      <!-- Chart renders here — ALWAYS set explicit height -->
    </div>
  </div>
</div>
```

---

## Real-Time Chart Patterns

### Streaming Line Chart

For data that updates every few seconds (metrics, stock prices, sensor data):

```typescript
// Pattern: Sliding window of N data points
const MAX_POINTS = 60  // 1 minute at 1 update/sec

function addDataPoint(newPoint: DataPoint) {
  setData(prev => {
    const updated = [...prev, newPoint]
    return updated.length > MAX_POINTS ? updated.slice(-MAX_POINTS) : updated
  })
}

// Smooth transitions: use CSS transitions on SVG paths
// or animationDuration prop in chart libraries
```

### Throttled Updates for High-Frequency Data

```typescript
// Buffer updates and render at 4 FPS (250ms) for smooth UX
const RENDER_INTERVAL = 250
let pendingData: DataPoint[] = []

wsConnection.onMessage((data) => {
  pendingData.push(data)
})

setInterval(() => {
  if (pendingData.length > 0) {
    // Take latest value (for gauges) or all values (for line charts)
    batchUpdateChart(pendingData)
    pendingData = []
  }
}, RENDER_INTERVAL)
```

---

## Specific Chart Patterns

### Sparklines (inline mini charts)

```html
<!-- Inside stat cards or table cells -->
<svg viewBox="0 0 100 30" class="w-20 h-8" preserveAspectRatio="none">
  <polyline
    fill="none"
    stroke="var(--color-success)"
    stroke-width="1.5"
    stroke-linecap="round"
    stroke-linejoin="round"
    points="0,25 15,20 30,22 45,10 60,15 75,8 100,5"
  />
</svg>
```

### Donut / Pie with Center Label

```html
<!-- Center label overlay pattern -->
<div class="relative">
  <!-- Chart -->
  <div class="h-48 w-48"><!-- PieChart component --></div>
  <!-- Center label -->
  <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
    <span class="text-2xl font-bold text-[var(--text-primary)]">78%</span>
    <span class="text-xs text-[var(--text-tertiary)]">Completion</span>
  </div>
</div>
```

### Progress / Gauge

```html
<!-- Simple progress bar with glass styling -->
<div class="w-full">
  <div class="flex items-center justify-between mb-1.5">
    <span class="text-xs font-medium text-[var(--text-secondary)]">Storage Used</span>
    <span class="text-xs font-medium text-[var(--text-primary)]">78%</span>
  </div>
  <div class="h-2 rounded-full bg-[var(--bg-inset)] overflow-hidden">
    <div class="h-full rounded-full bg-[var(--accent-primary)] transition-all duration-500" style="width: 78%"></div>
  </div>
</div>
```

---

## Accessibility for Charts

1. **Always provide text alternatives.** Screen readers can't interpret SVG charts.
   - Add `aria-label` describing the chart's key takeaway
   - Provide a data table toggle for every chart
2. **Don't rely on color alone.** Use patterns, shapes, or labels in addition to color.
3. **Ensure sufficient contrast.** Chart elements against backgrounds must meet 3:1 minimum.
4. **Keyboard navigation** for interactive charts (tooltips, data point focus).
5. **Announce live data changes** with `aria-live="polite"` for real-time updates.

```html
<div role="img" aria-label="Revenue increased 12.5% over the last 12 months, from $42,800 to $48,293">
  <!-- Chart SVG -->
</div>
<button class="text-xs text-[var(--text-link)]">View as table</button>
```

---

## Performance Tips

1. **Use canvas for 1000+ data points.** SVG slows down; switch to canvas-based renderers (uPlot, Chart.js).
2. **Downsample for display.** Show 200 points on screen, even if the dataset has 10,000. Use LTTB (Largest Triangle Three Buckets) algorithm.
3. **Lazy load chart libraries.** Charts are heavy — dynamic import them.
4. **Memoize chart data transformations.** Don't recompute on every render.
5. **Debounce window resize** handlers for responsive charts (300ms).
