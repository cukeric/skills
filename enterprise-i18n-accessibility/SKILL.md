---
name: enterprise-i18n-accessibility
description: Explains how to implement internationalization, localization, and accessibility with enterprise standards. Trigger on ANY mention of i18n, internationalization, l10n, localization, translation, locale, language, RTL, right-to-left, pluralization, date format, number format, intl, react-intl, next-intl, i18next, ICU message format, accessibility, a11y, WCAG, WAI-ARIA, aria, screen reader, keyboard navigation, focus management, color contrast, alt text, semantic HTML, skip link, live region, aria-label, aria-describedby, role, tab order, focus trap, accessible form, or any request requiring multi-language support, locale-aware formatting, or accessibility compliance.
---

# Enterprise i18n & Accessibility Skill

Internationalization (i18n) and accessibility (a11y) are not afterthoughts — they expand your addressable market and are legal requirements in many jurisdictions. This skill covers multi-language support, locale-aware formatting, and WCAG 2.1 AA compliance.

## Reference Files

### Internationalization

- `references/i18n-setup.md` — next-intl/react-intl/i18next setup, locale routing, message extraction, ICU format, pluralization, RTL support

### Locale-Aware Formatting

- `references/locale-formatting.md` — Intl API (dates, numbers, currencies, relative time), timezone handling, locale detection

### Accessibility Fundamentals

- `references/accessibility-wcag.md` — WCAG 2.1 AA checklist, semantic HTML, ARIA patterns, keyboard navigation, forms, color contrast, testing

### Screen Reader & Keyboard

- `references/keyboard-screenreader.md` — Focus management, skip links, live regions, focus traps, announcement patterns

### Testing i18n & a11y

- `references/testing-i18n-a11y.md` — axe-core, jest-axe, Lighthouse a11y audit, pseudo-localization, visual regression for RTL

---

## Decision Framework

### i18n Library Selection

| Requirement | Best Choice | Why |
|---|---|---|
| Next.js app | **next-intl** | Built for App Router, type-safe, server components |
| React (non-Next) | **react-intl (FormatJS)** | ICU standard, powerful formatting |
| Any JS framework | **i18next** | Framework-agnostic, largest ecosystem |
| React Native | **i18next + react-i18next** | Works cross-platform |
| Server-only | **Intl + custom** | Native Intl API, no library needed |

**Default: next-intl** for Next.js, i18next for other frameworks.

### Accessibility Targets

| Level | Requirements | When |
|---|---|---|
| **WCAG 2.1 A** | Basic accessibility | Minimum for any app |
| **WCAG 2.1 AA** | Standard compliance | **Default target** |
| **WCAG 2.1 AAA** | Enhanced accessibility | Government, healthcare |
| **Section 508** | US federal standard | Government contracts |
| **EN 301 549** | EU standard | EU market |

**Default: WCAG 2.1 AA** for all applications.

---

## i18n Architecture

```
src/
├── messages/
│   ├── en.json              # Source language
│   ├── fr.json              # French
│   ├── de.json              # German
│   ├── ja.json              # Japanese
│   └── ar.json              # Arabic (RTL)
├── lib/
│   └── i18n.ts              # Configuration
└── app/
    └── [locale]/            # Locale-based routing
        ├── layout.tsx
        └── page.tsx
```

### Message Format (ICU)

```json
{
  "greeting": "Hello, {name}!",
  "items": "{count, plural, =0 {No items} one {1 item} other {{count} items}}",
  "price": "Total: {amount, number, currency}",
  "lastSeen": "Last seen {date, date, medium}",
  "gender": "{gender, select, male {He} female {She} other {They}} liked your post"
}
```

### next-intl Setup

```typescript
// src/lib/i18n.ts
import { getRequestConfig } from 'next-intl/server'
import { notFound } from 'next/navigation'

export const locales = ['en', 'fr', 'de', 'ja', 'ar'] as const
export const defaultLocale = 'en' as const
export type Locale = (typeof locales)[number]

export default getRequestConfig(async ({ locale }) => {
  if (!locales.includes(locale as Locale)) notFound()

  return {
    messages: (await import(`../messages/${locale}.json`)).default,
    timeZone: 'UTC',
    now: new Date(),
  }
})
```

```typescript
// Usage in components
import { useTranslations } from 'next-intl'

function ProductCard({ product }) {
  const t = useTranslations('Product')

  return (
    <article aria-label={t('cardLabel', { name: product.name })}>
      <h2>{product.name}</h2>
      <p>{t('price', { amount: product.price })}</p>
      <p>{t('inStock', { count: product.stock })}</p>
    </article>
  )
}
```

---

## Accessibility Essentials

### Semantic HTML

```tsx
// ✅ Correct
<nav aria-label="Main navigation">
  <ul>
    <li><a href="/home">Home</a></li>
  </ul>
</nav>
<main>
  <article>
    <h1>Page Title</h1>
    <section aria-labelledby="features-heading">
      <h2 id="features-heading">Features</h2>
    </section>
  </article>
</main>
<footer>...</footer>

// ❌ Incorrect (div soup)
<div class="nav">
  <div class="nav-item" onclick="goto('/home')">Home</div>
</div>
<div class="content">
  <div class="title">Page Title</div>
</div>
```

### ARIA Patterns

```tsx
// Alert/notification
<div role="alert" aria-live="assertive">
  {errorMessage}
</div>

// Dialog/modal
<div role="dialog" aria-modal="true" aria-labelledby="dialog-title">
  <h2 id="dialog-title">Confirm Delete</h2>
  <p>Are you sure you want to delete this item?</p>
  <button onClick={onConfirm}>Delete</button>
  <button onClick={onCancel} autoFocus>Cancel</button>
</div>

// Toggle button
<button
  aria-pressed={isActive}
  onClick={() => setActive(!isActive)}
>
  Dark Mode
</button>

// Loading state
<button disabled={isLoading} aria-busy={isLoading}>
  {isLoading ? 'Saving...' : 'Save'}
</button>
```

### Color Contrast

| Text Size | Minimum Ratio (AA) | Enhanced (AAA) |
|---|---|---|
| Normal text (< 18pt) | 4.5:1 | 7:1 |
| Large text (≥ 18pt bold or ≥ 24pt) | 3:1 | 4.5:1 |
| UI components, graphical objects | 3:1 | — |

### Keyboard Navigation

```tsx
// Focus trap for modals
function Modal({ isOpen, onClose, children }) {
  const modalRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!isOpen) return

    const focusableElements = modalRef.current?.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    const first = focusableElements?.[0] as HTMLElement
    const last = focusableElements?.[focusableElements.length - 1] as HTMLElement

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
      if (e.key === 'Tab') {
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault(); last?.focus()
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault(); first?.focus()
        }
      }
    }

    first?.focus()
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen])

  if (!isOpen) return null

  return (
    <div role="dialog" aria-modal="true" ref={modalRef}>
      {children}
    </div>
  )
}
```

---

## Verification Checklist

### i18n

- [ ] All user-visible strings externalized to message files
- [ ] ICU message format used for pluralization and formatting
- [ ] Locale-based routing configured
- [ ] RTL layout support (if applicable languages included)
- [ ] Dates, numbers, and currencies use Intl API
- [ ] Fallback locale configured for missing translations

### Accessibility

- [ ] Semantic HTML used (nav, main, article, section, button)
- [ ] All images have alt text (or aria-hidden for decorative)
- [ ] All forms have labels (visible or aria-label)
- [ ] Color contrast meets WCAG AA (4.5:1 normal, 3:1 large)
- [ ] Keyboard navigation works for all interactive elements
- [ ] Focus management handles modals, menus, dynamic content
- [ ] Skip link provided for main content
- [ ] Error messages associated with form fields (aria-describedby)
- [ ] No content conveyed by color alone
- [ ] Lighthouse accessibility audit score ≥ 90
