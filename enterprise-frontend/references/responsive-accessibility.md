# Responsive Design & Accessibility Reference

## Mobile-First Responsive Strategy

### Breakpoint System (Tailwind defaults)

| Token | Width | Target Devices | Design Approach |
|---|---|---|---|
| (base) | 0-639px | Phones portrait | Single column, stacked, full-width |
| `sm` | ≥640px | Phones landscape, small tablets | Minor adjustments |
| `md` | ≥768px | Tablets | 2-column layouts, sidebar appears |
| `lg` | ≥1024px | Laptops | Full dashboard layout, sidebar expanded |
| `xl` | ≥1280px | Desktops | Wider content, more columns |
| `2xl` | ≥1536px | Large monitors | Max-width containers, extra spacing |

### Writing Mobile-First CSS

```html
<!-- CORRECT: mobile-first (add complexity as viewport grows) -->
<div class="flex flex-col md:flex-row gap-4 md:gap-6">
  <div class="w-full md:w-1/3">Sidebar</div>
  <div class="w-full md:w-2/3">Content</div>
</div>

<!-- WRONG: desktop-first (subtracting on mobile) -->
<div class="flex flex-row md:flex-col gap-6 md:gap-4">...</div>
```

### Container Strategy

```html
<!-- Max-width container for content-heavy pages -->
<div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
  <!-- Content -->
</div>

<!-- Full-bleed for dashboards (no max-width) -->
<div class="px-4 sm:px-6 lg:px-8">
  <!-- Dashboard content uses full width -->
</div>
```

---

## Responsive Component Patterns

### Navigation: Desktop Sidebar → Mobile Drawer

```html
<!-- Desktop: always visible sidebar -->
<aside class="hidden lg:flex lg:w-64 lg:flex-col fixed inset-y-0">
  <!-- Sidebar content -->
</aside>

<!-- Mobile: hamburger + slide-out drawer -->
<button class="lg:hidden" aria-label="Open menu" aria-expanded="false">
  <Menu class="w-6 h-6" />
</button>

<!-- Mobile drawer (shown on toggle) -->
<div class="lg:hidden fixed inset-0 z-[var(--z-overlay)]">
  <div class="absolute inset-0 bg-[var(--bg-overlay)]" />
  <aside class="relative w-64 h-full glass-elevated">
    <!-- Same sidebar content -->
  </aside>
</div>
```

### Data Tables → Card View on Mobile

```html
<!-- Desktop: standard table -->
<table class="hidden md:table w-full">
  <!-- Full table with columns -->
</table>

<!-- Mobile: card stack -->
<div class="md:hidden space-y-3">
  <div class="glass rounded-lg p-4">
    <div class="flex items-center justify-between">
      <span class="font-medium text-sm">Jane Doe</span>
      <span class="text-xs px-2 py-0.5 rounded-full bg-[var(--color-success-subtle)] text-[var(--color-success)]">Active</span>
    </div>
    <p class="text-xs text-[var(--text-tertiary)] mt-1">jane@company.com</p>
    <p class="text-xs text-[var(--text-tertiary)]">Admin · Joined Jan 2024</p>
  </div>
</div>
```

### Dashboard Grid Responsive Collapse

```html
<!-- 4 cols desktop → 2 tablet → 1 mobile -->
<div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
  <!-- Stat cards -->
</div>

<!-- Chart: full width on mobile, 2/3 on desktop -->
<div class="grid grid-cols-1 lg:grid-cols-3 gap-4 mt-6">
  <div class="lg:col-span-2"><!-- Main chart --></div>
  <div><!-- Side panel --></div>
</div>
```

---

## Touch & Interaction Design

### Touch Targets (WCAG 2.5.8)
- **Minimum 44x44px** for all interactive elements
- **Minimum 24px spacing** between adjacent touch targets
- Inputs, buttons, links, checkboxes all apply

```html
<!-- CORRECT: adequate touch target -->
<button class="h-11 px-4 min-w-[44px]">Click</button>

<!-- WRONG: too small -->
<button class="h-6 px-2">Click</button>
```

### Swipe & Gesture Awareness
- Don't override native browser gestures (swipe-back, pull-to-refresh)
- If using custom gestures, provide button alternatives
- Test with thumb reachability (bottom navigation preferred on mobile)

---

## WCAG 2.1 AA Compliance Checklist

### Perceivable

**1.1 Text Alternatives**
- [ ] All `<img>` have descriptive `alt` text (or `alt=""` for decorative)
- [ ] Icon-only buttons have `aria-label`
- [ ] Charts/graphs have text descriptions or data table alternatives

**1.3 Adaptable**
- [ ] Content order in DOM matches visual order
- [ ] Headings follow logical hierarchy (h1 → h2 → h3, no skipping)
- [ ] Form inputs have associated `<label>` elements
- [ ] Use semantic HTML: `<nav>`, `<main>`, `<aside>`, `<section>`, `<article>`

**1.4 Distinguishable**
- [ ] Text contrast ≥ 4.5:1 against background (normal text)
- [ ] Large text (≥18px bold or ≥24px) contrast ≥ 3:1
- [ ] UI component boundaries contrast ≥ 3:1
- [ ] Text can be resized to 200% without loss of content
- [ ] No info conveyed by color alone (use icons/text + color)
- [ ] Content reflows at 320px width without horizontal scrolling

### Operable

**2.1 Keyboard Accessible**
- [ ] All interactive elements reachable via Tab key
- [ ] Tab order follows logical reading order
- [ ] No keyboard traps (user can always Tab away)
- [ ] Custom widgets have appropriate keyboard shortcuts (Enter/Space for buttons, Arrow keys for menus)
- [ ] Skip-to-content link as first focusable element

**2.4 Navigable**
- [ ] Page has descriptive `<title>`
- [ ] Focus indicator visible on all interactive elements
- [ ] At least two ways to reach each page (nav + search/sitemap)
- [ ] Links have descriptive text (not "click here")
- [ ] Current page indicated in navigation

**2.5 Input Modalities**
- [ ] Touch targets ≥ 44x44px
- [ ] No functionality requires multi-point or path-based gestures without alternative

### Understandable

**3.1 Readable**
- [ ] `<html lang="en">` set correctly
- [ ] Abbreviations explained on first use

**3.2 Predictable**
- [ ] No unexpected context changes on focus or input
- [ ] Navigation consistent across pages
- [ ] Labels consistent (same thing always called the same name)

**3.3 Input Assistance**
- [ ] Error messages identify the field and describe the error
- [ ] Required fields marked (asterisk + `aria-required="true"`)
- [ ] Suggestions provided when input errors are detected
- [ ] Confirmation step for irreversible actions

### Robust

**4.1 Compatible**
- [ ] Valid HTML (no duplicate IDs, proper nesting)
- [ ] Custom components have appropriate ARIA roles
- [ ] Dynamic content changes announced to screen readers

---

## ARIA Patterns for Common Components

### Modal Dialog

```html
<div role="dialog" aria-modal="true" aria-labelledby="modal-title" aria-describedby="modal-desc">
  <h2 id="modal-title">Confirm Delete</h2>
  <p id="modal-desc">Are you sure you want to delete this item?</p>
  <!-- Focus trapped inside modal -->
  <!-- Esc key closes modal -->
  <!-- Focus returns to trigger element on close -->
</div>
```

### Tabs

```html
<div role="tablist" aria-label="Settings sections">
  <button role="tab" aria-selected="true" aria-controls="panel-general" id="tab-general">General</button>
  <button role="tab" aria-selected="false" aria-controls="panel-security" id="tab-security">Security</button>
</div>
<div role="tabpanel" id="panel-general" aria-labelledby="tab-general">
  <!-- General settings -->
</div>
```

### Dropdown Menu

```html
<div class="relative">
  <button aria-haspopup="true" aria-expanded="false" id="menu-button">Options</button>
  <div role="menu" aria-labelledby="menu-button" hidden>
    <button role="menuitem">Edit</button>
    <button role="menuitem">Duplicate</button>
    <button role="menuitem">Delete</button>
  </div>
</div>
<!-- Arrow keys navigate items, Esc closes, Enter/Space activates -->
```

### Toast / Alert

```html
<!-- Container for dynamic notifications -->
<div aria-live="polite" aria-atomic="true" class="sr-only">
  <!-- Screen reader announces new toasts here -->
</div>
```

### Loading States

```html
<!-- Skeleton loading -->
<div aria-busy="true" aria-label="Loading content">
  <div class="skeleton h-4 w-3/4 mb-2" />
  <div class="skeleton h-4 w-1/2" />
</div>

<!-- Spinner -->
<div role="status" aria-label="Loading">
  <span class="animate-spin w-5 h-5 border-2 border-current border-t-transparent rounded-full" />
  <span class="sr-only">Loading...</span>
</div>
```

---

## Skip Navigation

```html
<!-- First element in body -->
<a href="#main-content" class="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-[var(--accent-primary)] focus:text-[var(--text-inverse)] focus:rounded-md">
  Skip to main content
</a>

<!-- Main content area -->
<main id="main-content" tabindex="-1">
  <!-- Page content -->
</main>
```

---

## Testing Accessibility

### Automated
- **axe-core**: Browser extension + CI integration
- **Lighthouse**: Accessibility audit score
- **eslint-plugin-jsx-a11y** (React) / **eslint-plugin-vuejs-accessibility** (Vue)

### Manual
- **Keyboard-only navigation**: Tab through entire page, activate all controls
- **Screen reader testing**: VoiceOver (Mac), NVDA (Windows), Orca (Linux)
- **Zoom to 200%**: Check content reflow
- **High contrast mode**: Verify visibility
- **Color blindness simulation**: Use browser DevTools color vision filters

### Playwright Accessibility Tests

```typescript
import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

test('dashboard has no a11y violations', async ({ page }) => {
  await page.goto('/dashboard')
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations).toEqual([])
})
```
