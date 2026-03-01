# Testing i18n & Accessibility Reference

## Accessibility Testing

### axe-core (Automated)

```bash
npm install -D @axe-core/react axe-core jest-axe
```

```typescript
// Jest + jest-axe
import { axe, toHaveNoViolations } from 'jest-axe'
import { render } from '@testing-library/react'

expect.extend(toHaveNoViolations)

test('form is accessible', async () => {
  const { container } = render(<ContactForm />)
  const results = await axe(container)
  expect(results).toHaveNoViolations()
})

// Test specific rules
test('images have alt text', async () => {
  const { container } = render(<ProductCard product={mockProduct} />)
  const results = await axe(container, {
    rules: { 'image-alt': { enabled: true } },
  })
  expect(results).toHaveNoViolations()
})
```

### React Dev Tools

```typescript
// Enable axe in development
if (process.env.NODE_ENV === 'development') {
  import('@axe-core/react').then((axe) => {
    axe.default(React, ReactDOM, 1000)
    // Logs violations to console
  })
}
```

### Lighthouse CI

```yaml
# CI accessibility audit
jobs:
  a11y:
    steps:
      - run: npm ci && npm run build
      - name: Lighthouse
        uses: treosh/lighthouse-ci-action@v11
        with:
          urls: |
            http://localhost:3000
            http://localhost:3000/login
          budgetPath: .lighthouserc.json
```

```json
// .lighthouserc.json
{
  "ci": {
    "assert": {
      "assertions": {
        "categories:accessibility": ["error", { "minScore": 0.9 }]
      }
    }
  }
}
```

---

## i18n Testing

### Missing Translation Detection

```typescript
// Test all locales have all keys
import en from '../messages/en.json'
import fr from '../messages/fr.json'
import de from '../messages/de.json'

function getAllKeys(obj: object, prefix = ''): string[] {
  return Object.entries(obj).flatMap(([key, value]) => {
    const path = prefix ? `${prefix}.${key}` : key
    return typeof value === 'object' ? getAllKeys(value, path) : [path]
  })
}

test('all locales have all translation keys', () => {
  const enKeys = getAllKeys(en)
  const frKeys = getAllKeys(fr)
  const deKeys = getAllKeys(de)

  const missingFr = enKeys.filter((k) => !frKeys.includes(k))
  const missingDe = enKeys.filter((k) => !deKeys.includes(k))

  expect(missingFr).toEqual([])
  expect(missingDe).toEqual([])
})
```

### Pseudo-Localization

```typescript
// Expand text to test layout with longer strings
function pseudoLocalize(text: string): string {
  const map: Record<string, string> = {
    a: 'ä', e: 'ë', i: 'ï', o: 'ö', u: 'ü',
    A: 'Ä', E: 'Ë', I: 'Ï', O: 'Ö', U: 'Ü',
  }

  const accented = text.replace(/[aeiouAEIOU]/g, (c) => map[c] || c)
  const padded = `[${accented}]` // Add ~30% length + brackets for visual marker
  return padded
}
```

---

## Manual Testing Checklist

### Keyboard

- [ ] Tab through entire page — everything reachable
- [ ] Enter/Space activates all buttons and links
- [ ] Escape closes modals, dropdowns, menus
- [ ] Arrow keys navigate menus and tab groups
- [ ] No keyboard traps (can always Tab away)

### Screen Reader

- [ ] Test with VoiceOver (macOS: Cmd+F5)
- [ ] Test with NVDA (Windows, free)
- [ ] All content read in correct order
- [ ] Dynamic updates announced (live regions)
- [ ] Form errors announced when they appear

### Visual

- [ ] Zoom to 200% — no content cut off
- [ ] High contrast mode — all text readable
- [ ] Reduced motion — no animations
- [ ] Dark mode — contrast still meets AA
