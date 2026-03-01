# Locale-Aware Formatting Reference

## Intl API (Built-in)

### Date Formatting

```typescript
// Basic
new Intl.DateTimeFormat('en-US').format(date)  // "3/15/2024"
new Intl.DateTimeFormat('de-DE').format(date)  // "15.3.2024"
new Intl.DateTimeFormat('ja-JP').format(date)  // "2024/3/15"

// With options
new Intl.DateTimeFormat('en-US', {
  dateStyle: 'long',
  timeStyle: 'short',
}).format(date) // "March 15, 2024, 2:30 PM"

// Relative time
const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })
rtf.format(-1, 'day')    // "yesterday"
rtf.format(-3, 'hour')   // "3 hours ago"
rtf.format(2, 'week')    // "in 2 weeks"
```

### Number Formatting

```typescript
// Currency
new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(1234.56)
// "$1,234.56"

new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' }).format(1234.56)
// "1.234,56 €"

// Compact
new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 }).format(1500000)
// "1.5M"

// Percentage
new Intl.NumberFormat('en', { style: 'percent', maximumFractionDigits: 1 }).format(0.854)
// "85.4%"

// Units
new Intl.NumberFormat('en', { style: 'unit', unit: 'kilometer-per-hour' }).format(120)
// "120 km/h"
```

### List Formatting

```typescript
const list = new Intl.ListFormat('en', { style: 'long', type: 'conjunction' })
list.format(['Apple', 'Banana', 'Cherry']) // "Apple, Banana, and Cherry"

const listFr = new Intl.ListFormat('fr', { style: 'long', type: 'conjunction' })
listFr.format(['Pomme', 'Banane', 'Cerise']) // "Pomme, Banane et Cerise"
```

---

## Timezone Handling

```typescript
// Display in user's timezone
function formatInUserTimezone(date: Date, timezone: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, {
    dateStyle: 'long',
    timeStyle: 'short',
    timeZone: timezone,
  }).format(date)
}

// Store everything in UTC on the server
// Convert to user timezone only for display
const userTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone
```

---

## Locale Detection

```typescript
// Client-side
const browserLocale = navigator.language || 'en'  // "en-US", "fr-FR"

// Server-side (from Accept-Language header)
function getPreferredLocale(acceptLanguage: string, supported: string[]): string {
  const preferred = acceptLanguage
    .split(',')
    .map((l) => l.split(';')[0].trim())
    .map((l) => l.split('-')[0])

  return preferred.find((l) => supported.includes(l)) || 'en'
}
```

---

## Formatting Helpers

```typescript
// src/lib/format.ts
export function formatCurrency(cents: number, currency: string, locale: string): string {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
  }).format(cents / 100)
}

export function formatRelativeTime(date: Date, locale: string): string {
  const diff = Date.now() - date.getTime()
  const seconds = Math.floor(diff / 1000)
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' })

  if (seconds < 60) return rtf.format(-seconds, 'second')
  if (seconds < 3600) return rtf.format(-Math.floor(seconds / 60), 'minute')
  if (seconds < 86400) return rtf.format(-Math.floor(seconds / 3600), 'hour')
  return rtf.format(-Math.floor(seconds / 86400), 'day')
}
```
