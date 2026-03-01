# Keyboard & Screen Reader Reference

## Focus Management

### Focus on Route Change

```typescript
// Focus main content when navigating (SPA)
import { usePathname } from 'next/navigation'
import { useEffect, useRef } from 'react'

export function useFocusOnNavigate() {
  const pathname = usePathname()
  const mainRef = useRef<HTMLElement>(null)

  useEffect(() => {
    mainRef.current?.focus()
  }, [pathname])

  return mainRef
}

// Usage
function Layout({ children }) {
  const mainRef = useFocusOnNavigate()
  return <main ref={mainRef} tabIndex={-1}>{children}</main>
}
```

### Focus Trap (Modals)

```typescript
import { useRef, useEffect } from 'react'

export function useFocusTrap(isActive: boolean) {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!isActive || !containerRef.current) return

    const container = containerRef.current
    const focusable = container.querySelectorAll<HTMLElement>(
      'a[href], button:not([disabled]), input:not([disabled]), ' +
      'select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )
    const first = focusable[0]
    const last = focusable[focusable.length - 1]

    // Store previously focused element
    const previouslyFocused = document.activeElement as HTMLElement
    first?.focus()

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key !== 'Tab') return

      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault()
          last?.focus()
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault()
          first?.focus()
        }
      }
    }

    container.addEventListener('keydown', handleKeyDown)
    return () => {
      container.removeEventListener('keydown', handleKeyDown)
      previouslyFocused?.focus() // Restore focus on close
    }
  }, [isActive])

  return containerRef
}
```

---

## Live Regions

```tsx
// Announce dynamic content changes to screen readers
// aria-live="polite" — waits for user to finish current task
// aria-live="assertive" — interrupts immediately (use sparingly)

// Status updates
<div aria-live="polite" aria-atomic="true">
  {searchResults.length} results found
</div>

// Error notifications
<div role="alert" aria-live="assertive">
  Failed to save changes. Please try again.
</div>

// Progress updates
<div aria-live="polite" aria-busy={isLoading}>
  {isLoading ? 'Loading...' : `Loaded ${items.length} items`}
</div>
```

---

## Keyboard Shortcuts

```typescript
// Global keyboard shortcut handler
useEffect(() => {
  function handleKeyDown(e: KeyboardEvent) {
    // Ignore when typing in inputs
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes((e.target as HTMLElement).tagName)) return

    if (e.key === '/' && !e.metaKey) {
      e.preventDefault()
      document.getElementById('search-input')?.focus()
    }

    if (e.key === 'Escape') {
      closeModal()
    }
  }

  document.addEventListener('keydown', handleKeyDown)
  return () => document.removeEventListener('keydown', handleKeyDown)
}, [])
```

---

## Common Keyboard Patterns

| Component | Keys |
|---|---|
| **Button** | Enter, Space → activate |
| **Link** | Enter → follow |
| **Menu** | Arrow keys navigate, Enter selects, Escape closes |
| **Tab group** | Arrow keys switch tabs, Tab moves to panel |
| **Dialog** | Escape closes, Tab trapped inside |
| **Combobox** | Arrow keys navigate options, Enter selects |
| **Accordion** | Enter/Space toggles, Arrow keys between headers |

---

## Roving Tabindex (Menu/Toolbar)

```tsx
function Toolbar({ items }) {
  const [activeIndex, setActiveIndex] = useState(0)

  function handleKeyDown(e: React.KeyboardEvent) {
    switch (e.key) {
      case 'ArrowRight':
        setActiveIndex((i) => (i + 1) % items.length)
        break
      case 'ArrowLeft':
        setActiveIndex((i) => (i - 1 + items.length) % items.length)
        break
      case 'Home':
        setActiveIndex(0)
        break
      case 'End':
        setActiveIndex(items.length - 1)
        break
    }
  }

  return (
    <div role="toolbar" aria-label="Formatting" onKeyDown={handleKeyDown}>
      {items.map((item, i) => (
        <button
          key={item.id}
          tabIndex={i === activeIndex ? 0 : -1}
          ref={(el) => { if (i === activeIndex) el?.focus() }}
        >
          {item.label}
        </button>
      ))}
    </div>
  )
}
```
