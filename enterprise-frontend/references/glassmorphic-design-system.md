# Glassmorphic Design System Reference

This is the default design system for all enterprise frontend projects. It produces warm, layered, modern interfaces with glass-effect containers, soft color palettes, and functional elegance.

## Design Philosophy

Glassmorphism creates depth through translucent layers with backdrop blur, simulating frosted glass. When done right, it produces UIs that feel premium without sacrificing readability or accessibility. The key is restraint — glass effects enhance hierarchy, they don't replace it.

**Rules:**
1. Glass is for containers, not text. Text must always be crisp and readable.
2. Maximum two glass layers deep. More creates visual mud.
3. Every glass panel needs a visible background behind it to blur — glass on white is just white.
4. Blur intensity correlates with hierarchy: more blur = more prominent/elevated element.
5. Borders are structural, not decorative — they define where glass panels begin and end.

---

## Color Tokens

### CSS Custom Properties (put in globals.css)

```css
:root {
  /* ── Background Layers ── */
  --bg-base: #f8f6f3;              /* Warm off-white — the canvas */
  --bg-surface: rgba(255, 255, 255, 0.6);   /* Primary glass surface */
  --bg-surface-hover: rgba(255, 255, 255, 0.75);
  --bg-elevated: rgba(255, 255, 255, 0.8);  /* Cards, modals, dropdowns */
  --bg-elevated-hover: rgba(255, 255, 255, 0.9);
  --bg-overlay: rgba(0, 0, 0, 0.3);         /* Modal backdrop */
  --bg-inset: rgba(0, 0, 0, 0.03);          /* Recessed areas, input backgrounds */

  /* ── Text ── */
  --text-primary: #2d2a26;          /* Warm near-black */
  --text-secondary: #6b6560;        /* Warm gray for secondary content */
  --text-tertiary: #9e9790;         /* Muted — captions, timestamps */
  --text-inverse: #faf8f6;          /* Text on dark backgrounds */
  --text-link: #c07a45;             /* Warm amber for links */
  --text-link-hover: #a8653a;

  /* ── Brand / Accent ── */
  --accent-primary: #c07a45;        /* Warm amber — primary actions */
  --accent-primary-hover: #a8653a;
  --accent-primary-subtle: rgba(192, 122, 69, 0.12);
  --accent-secondary: #7b9e87;      /* Sage green — success/secondary */
  --accent-secondary-hover: #6a8a74;
  --accent-secondary-subtle: rgba(123, 158, 135, 0.12);

  /* ── Semantic ── */
  --color-success: #7b9e87;         /* Sage green */
  --color-success-subtle: rgba(123, 158, 135, 0.12);
  --color-warning: #d4a053;         /* Golden amber */
  --color-warning-subtle: rgba(212, 160, 83, 0.12);
  --color-error: #c47068;           /* Warm coral */
  --color-error-subtle: rgba(196, 112, 104, 0.12);
  --color-info: #7a9bb5;            /* Muted blue */
  --color-info-subtle: rgba(122, 155, 181, 0.12);

  /* ── Glass Effects ── */
  --glass-blur: 16px;
  --glass-blur-heavy: 24px;
  --glass-border: rgba(255, 255, 255, 0.3);
  --glass-border-subtle: rgba(255, 255, 255, 0.15);
  --glass-shadow: 0 4px 24px rgba(0, 0, 0, 0.06);
  --glass-shadow-elevated: 0 8px 40px rgba(0, 0, 0, 0.1);

  /* ── Borders & Dividers ── */
  --border-default: rgba(0, 0, 0, 0.08);
  --border-strong: rgba(0, 0, 0, 0.15);
  --border-focus: var(--accent-primary);
  --border-radius-sm: 8px;
  --border-radius-md: 12px;
  --border-radius-lg: 16px;
  --border-radius-xl: 24px;
  --border-radius-full: 9999px;

  /* ── Spacing Scale (4px base) ── */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 20px;
  --space-6: 24px;
  --space-8: 32px;
  --space-10: 40px;
  --space-12: 48px;
  --space-16: 64px;
  --space-20: 80px;

  /* ── Typography ── */
  --font-sans: 'Inter', system-ui, -apple-system, sans-serif;
  --font-mono: 'JetBrains Mono', 'Fira Code', monospace;
  --font-display: 'Plus Jakarta Sans', var(--font-sans);

  --text-xs: 0.75rem;     /* 12px */
  --text-sm: 0.875rem;    /* 14px */
  --text-base: 1rem;      /* 16px */
  --text-lg: 1.125rem;    /* 18px */
  --text-xl: 1.25rem;     /* 20px */
  --text-2xl: 1.5rem;     /* 24px */
  --text-3xl: 1.875rem;   /* 30px */
  --text-4xl: 2.25rem;    /* 36px */

  --leading-tight: 1.25;
  --leading-normal: 1.5;
  --leading-relaxed: 1.75;

  /* ── Transitions ── */
  --transition-fast: 150ms ease;
  --transition-base: 200ms ease;
  --transition-slow: 300ms ease;
  --transition-spring: 300ms cubic-bezier(0.34, 1.56, 0.64, 1);

  /* ── Z-Index Scale ── */
  --z-base: 0;
  --z-dropdown: 100;
  --z-sticky: 200;
  --z-overlay: 300;
  --z-modal: 400;
  --z-toast: 500;
  --z-tooltip: 600;
}

/* ── Dark Mode ── */
.dark {
  --bg-base: #1a1816;
  --bg-surface: rgba(40, 36, 32, 0.7);
  --bg-surface-hover: rgba(50, 46, 42, 0.8);
  --bg-elevated: rgba(55, 50, 45, 0.85);
  --bg-elevated-hover: rgba(65, 60, 55, 0.9);
  --bg-overlay: rgba(0, 0, 0, 0.6);
  --bg-inset: rgba(255, 255, 255, 0.04);

  --text-primary: #ede9e4;
  --text-secondary: #a09890;
  --text-tertiary: #787068;
  --text-inverse: #2d2a26;

  --glass-border: rgba(255, 255, 255, 0.1);
  --glass-border-subtle: rgba(255, 255, 255, 0.06);
  --glass-shadow: 0 4px 24px rgba(0, 0, 0, 0.2);
  --glass-shadow-elevated: 0 8px 40px rgba(0, 0, 0, 0.3);

  --border-default: rgba(255, 255, 255, 0.08);
  --border-strong: rgba(255, 255, 255, 0.15);
}
```

### Tailwind Configuration

```typescript
// tailwind.config.ts
import type { Config } from 'tailwindcss'

export default {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx,svelte,vue}'],
  theme: {
    extend: {
      colors: {
        base: 'var(--bg-base)',
        surface: 'var(--bg-surface)',
        elevated: 'var(--bg-elevated)',
        inset: 'var(--bg-inset)',
        accent: {
          DEFAULT: 'var(--accent-primary)',
          hover: 'var(--accent-primary-hover)',
          subtle: 'var(--accent-primary-subtle)',
        },
        success: { DEFAULT: 'var(--color-success)', subtle: 'var(--color-success-subtle)' },
        warning: { DEFAULT: 'var(--color-warning)', subtle: 'var(--color-warning-subtle)' },
        error: { DEFAULT: 'var(--color-error)', subtle: 'var(--color-error-subtle)' },
        info: { DEFAULT: 'var(--color-info)', subtle: 'var(--color-info-subtle)' },
      },
      fontFamily: {
        sans: ['var(--font-sans)'],
        mono: ['var(--font-mono)'],
        display: ['var(--font-display)'],
      },
      borderRadius: {
        sm: 'var(--border-radius-sm)',
        md: 'var(--border-radius-md)',
        lg: 'var(--border-radius-lg)',
        xl: 'var(--border-radius-xl)',
      },
      backdropBlur: {
        glass: 'var(--glass-blur)',
        'glass-heavy': 'var(--glass-blur-heavy)',
      },
      boxShadow: {
        glass: 'var(--glass-shadow)',
        'glass-elevated': 'var(--glass-shadow-elevated)',
      },
    },
  },
} satisfies Config
```

---

## Core Glass Component Patterns

### Glass Card (the building block)

```css
/* Utility class — apply to any container */
.glass {
  background: var(--bg-surface);
  backdrop-filter: blur(var(--glass-blur));
  -webkit-backdrop-filter: blur(var(--glass-blur));
  border: 1px solid var(--glass-border);
  border-radius: var(--border-radius-lg);
  box-shadow: var(--glass-shadow);
}

.glass-elevated {
  background: var(--bg-elevated);
  backdrop-filter: blur(var(--glass-blur-heavy));
  -webkit-backdrop-filter: blur(var(--glass-blur-heavy));
  border: 1px solid var(--glass-border);
  border-radius: var(--border-radius-lg);
  box-shadow: var(--glass-shadow-elevated);
}
```

### Tailwind utility classes (add to globals.css)

```css
@layer components {
  .glass {
    @apply bg-surface backdrop-blur-glass border border-white/20 shadow-glass;
  }
  .glass-elevated {
    @apply bg-elevated backdrop-blur-[24px] border border-white/20 shadow-glass-elevated;
  }
  .glass-inset {
    @apply bg-inset rounded-md border border-black/5;
  }
}
```

---

## Component Library Patterns

### Button Variants (CVA)

```typescript
import { cva, type VariantProps } from 'class-variance-authority'

export const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-md font-medium transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--border-focus)] focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        primary: 'bg-[var(--accent-primary)] text-[var(--text-inverse)] hover:bg-[var(--accent-primary-hover)] shadow-sm',
        secondary: 'glass hover:bg-[var(--bg-surface-hover)] text-[var(--text-primary)]',
        ghost: 'hover:bg-[var(--bg-inset)] text-[var(--text-secondary)] hover:text-[var(--text-primary)]',
        danger: 'bg-[var(--color-error)] text-[var(--text-inverse)] hover:opacity-90 shadow-sm',
        success: 'bg-[var(--color-success)] text-[var(--text-inverse)] hover:opacity-90 shadow-sm',
        link: 'text-[var(--text-link)] hover:text-[var(--text-link-hover)] underline-offset-4 hover:underline p-0 h-auto',
      },
      size: {
        sm: 'h-8 px-3 text-sm',
        md: 'h-10 px-4 text-sm',
        lg: 'h-12 px-6 text-base',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  }
)
export type ButtonVariants = VariantProps<typeof buttonVariants>
```

### Input Styles

```css
.input-base {
  width: 100%;
  padding: var(--space-2) var(--space-3);
  background: var(--bg-inset);
  border: 1px solid var(--border-default);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  font-size: var(--text-sm);
  line-height: var(--leading-normal);
  transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
}
.input-base:focus {
  outline: none;
  border-color: var(--border-focus);
  box-shadow: 0 0 0 3px var(--accent-primary-subtle);
}
.input-base::placeholder { color: var(--text-tertiary); }
.input-base:disabled { opacity: 0.5; cursor: not-allowed; }
.input-error { border-color: var(--color-error); }
.input-error:focus { box-shadow: 0 0 0 3px var(--color-error-subtle); }
```

### Glass Card with Header

```html
<div class="glass rounded-lg overflow-hidden">
  <div class="flex items-center justify-between px-6 py-4 border-b border-[var(--border-default)]">
    <div>
      <h3 class="text-sm font-semibold text-[var(--text-primary)]">Card Title</h3>
      <p class="text-xs text-[var(--text-tertiary)] mt-0.5">Description text</p>
    </div>
    <div class="flex items-center gap-2"><!-- Action buttons --></div>
  </div>
  <div class="p-6"><!-- Card body --></div>
</div>
```

### Modal / Dialog

```html
<div class="fixed inset-0 z-[var(--z-modal)] flex items-center justify-center">
  <div class="absolute inset-0 bg-[var(--bg-overlay)] backdrop-blur-sm"></div>
  <div class="glass-elevated relative w-full max-w-lg mx-4 rounded-xl overflow-hidden">
    <div class="flex items-center justify-between px-6 py-4 border-b border-[var(--border-default)]">
      <h2 class="text-lg font-semibold text-[var(--text-primary)]">Modal Title</h2>
      <button class="text-[var(--text-tertiary)] hover:text-[var(--text-primary)] transition-colors"><!-- Close --></button>
    </div>
    <div class="px-6 py-4 max-h-[60vh] overflow-y-auto"><!-- Content --></div>
    <div class="flex items-center justify-end gap-3 px-6 py-4 border-t border-[var(--border-default)]">
      <button>Cancel</button>
      <button>Confirm</button>
    </div>
  </div>
</div>
```

### Sidebar Navigation

```html
<aside class="glass fixed left-0 top-0 bottom-0 w-64 border-r border-[var(--glass-border)] flex flex-col z-[var(--z-sticky)]">
  <div class="px-6 py-5 border-b border-[var(--border-default)]">
    <span class="font-display text-lg font-bold text-[var(--text-primary)]">AppName</span>
  </div>
  <nav class="flex-1 px-3 py-4 overflow-y-auto">
    <div class="space-y-1">
      <a class="flex items-center gap-3 px-3 py-2.5 rounded-md bg-[var(--accent-primary-subtle)] text-[var(--accent-primary)] font-medium text-sm">
        <!-- Icon --> Dashboard
      </a>
      <a class="flex items-center gap-3 px-3 py-2.5 rounded-md text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-inset)] transition-colors text-sm">
        <!-- Icon --> Analytics
      </a>
    </div>
  </nav>
  <div class="px-3 py-4 border-t border-[var(--border-default)]">
    <div class="flex items-center gap-3 px-3 py-2">
      <div class="w-8 h-8 rounded-full bg-[var(--accent-primary-subtle)] flex items-center justify-center text-sm font-medium text-[var(--accent-primary)]">JD</div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-[var(--text-primary)] truncate">Jane Doe</p>
        <p class="text-xs text-[var(--text-tertiary)] truncate">jane@company.com</p>
      </div>
    </div>
  </div>
</aside>
```

---

## Animation Standards

```css
.transition-interactive { transition: all var(--transition-base); }

.hover-lift { transition: transform var(--transition-base), box-shadow var(--transition-base); }
.hover-lift:hover { transform: translateY(-2px); box-shadow: var(--glass-shadow-elevated); }

.press-scale:active { transform: scale(0.98); }

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}
.animate-fade-in { animation: fadeIn var(--transition-slow) ease forwards; }

@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}
.skeleton {
  background: linear-gradient(90deg, var(--bg-inset) 25%, rgba(255,255,255,0.3) 50%, var(--bg-inset) 75%);
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
  border-radius: var(--border-radius-sm);
}
```

---

## Typography System

| Level | Font | Size | Weight | Usage |
|---|---|---|---|---|
| Display | Plus Jakarta Sans | 36px | 700 | Hero sections |
| H1 | Plus Jakarta Sans | 30px | 700 | Page titles |
| H2 | Inter | 24px | 600 | Section headers |
| H3 | Inter | 20px | 600 | Card titles |
| H4 | Inter | 16px | 600 | Group labels |
| Body | Inter | 16px | 400 | Primary content |
| Body Small | Inter | 14px | 400 | Secondary content, tables |
| Caption | Inter | 12px | 400 | Timestamps, metadata |
| Code | JetBrains Mono | 14px | 400 | Code blocks |

### Font Loading (Next.js)

```typescript
import { Inter, Plus_Jakarta_Sans, JetBrains_Mono } from 'next/font/google'
export const inter = Inter({ subsets: ['latin'], variable: '--font-sans' })
export const jakarta = Plus_Jakarta_Sans({ subsets: ['latin'], variable: '--font-display', weight: ['600', '700'] })
export const jetbrains = JetBrains_Mono({ subsets: ['latin'], variable: '--font-mono', weight: ['400', '500'] })
```

### Generic Font Loading (non-Next.js)

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Plus+Jakarta+Sans:wght@600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet" />
```

---

## Accessibility for Glassmorphism

### Contrast Rules
- Text on glass surfaces must meet **4.5:1 contrast ratio** (WCAG AA) against worst-case background
- Test with light AND dark content behind glass
- Never rely solely on glass border to define boundaries

### Reduced Motion & Transparency

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}

@media (prefers-reduced-transparency: reduce) {
  .glass, .glass-elevated {
    background: var(--bg-base);
    backdrop-filter: none;
  }
}
```

### Focus Indicators

```css
:focus-visible {
  outline: 2px solid var(--accent-primary);
  outline-offset: 2px;
}
```

---

## Icon System

Default: **Lucide** icons. Tree-shakeable, consistent, React/Vue/Svelte bindings.

```bash
pnpm add lucide-react   # or lucide-vue-next / lucide-svelte
```

| Context | Size | Tailwind |
|---|---|---|
| Navigation | 20px | w-5 h-5 |
| Inline text | 16px | w-4 h-4 |
| Feature icons | 24px | w-6 h-6 |
| Empty states | 48px | w-12 h-12 |

Always: `aria-hidden="true"` on decorative icons, `aria-label` on icon-only buttons.
