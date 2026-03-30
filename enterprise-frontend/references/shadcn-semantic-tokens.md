# shadcn/ui + Tailwind v4 Semantic Token Rules

Critical patterns for using shadcn/ui CSS custom properties correctly. Violating these causes invisible text (1:1 contrast) on light backgrounds.

---

## The Core Rule: Base Tokens vs. Foreground Tokens

shadcn/ui status tokens come in pairs. They have DIFFERENT purposes:

| Token pair | Base token purpose | Foreground token purpose |
|---|---|---|
| `--destructive` / `--destructive-foreground` | Background for SOLID elements (Button bg) | Text on solid `bg-destructive` backgrounds |
| `--warning` / `--warning-foreground` | Background tint, accent color | Text on ANY surface |
| `--success` / `--success-foreground` | Background tint, accent color | Text on ANY surface |
| `--info` / `--info-foreground` | Background tint, accent color | Text on ANY surface |

**The trap:** Base tokens like `--warning` (`oklch(0.769 ...)`) have high lightness — they look great as backgrounds but fail WCAG contrast (~2.5:1) when used as text color on white/light surfaces.

---

## Wash Background Badge Rule

Wash backgrounds = `bg-warning/10`, `bg-success/10`, `bg-destructive/10` etc.

```tsx
// ❌ WRONG — text-warning fails 3:1 contrast on light mode
<span className="bg-warning/10 border-warning/25 text-warning">HIGH</span>

// ✅ CORRECT — text-warning-foreground passes in both light and dark
<span className="bg-warning/10 border-warning/25 text-warning-foreground">HIGH</span>
```

**Rule:** On ANY wash background (`/10`, `/15`, `/20` opacity backgrounds), always use the `-foreground` token for text color.

---

## The Destructive Foreground Split Problem

`--destructive-foreground` in shadcn is near-white (`oklch(0.985 0 0)`) — designed for text on SOLID destructive buttons. On `bg-destructive/10` in light mode: ~1.04:1 contrast. Completely invisible.

**Solution: Separate badge foreground token**

```css
/* globals.css */
:root {
  --destructive-badge-foreground: oklch(0.45 0.20 25);   /* dark red for light mode */
}
.dark {
  --destructive-badge-foreground: oklch(0.78 0.18 25);   /* bright red for dark mode */
}

/* @theme inline */
--color-destructive-badge-foreground: var(--destructive-badge-foreground);
```

```tsx
// ❌ WRONG — invisible on light mode wash backgrounds
<span className="bg-destructive/10 text-destructive-foreground">CRITICAL</span>

// ✅ CORRECT
<span className="bg-destructive/10 text-destructive-badge-foreground">CRITICAL</span>

// ✅ shadcn Button still works — uses solid bg
<Button variant="destructive">Delete</Button>  // bg-destructive + text-destructive-foreground = fine
```

Do NOT consolidate these tokens. The split is intentional and preserves shadcn component compatibility.

---

## Dark Mode Foreground Token Values

When defining foreground tokens in `.dark`, set lightness HIGH (L ≥ 0.78) so text is readable on dark surfaces:

```css
.dark {
  --warning-foreground: oklch(0.82 0.12 70);    /* ✅ ~9:1 on dark card */
  --success-foreground: oklch(0.82 0.12 162);   /* ✅ ~9:1 on dark card */
  /* ❌ oklch(0.15 ...) = near-black = invisible on dark backgrounds */
}
```

---

## Light Mode Root Token Values

In `:root`, surface/brand tokens must be LIGHT (L ≥ 0.90):

```css
:root {
  --brand-surface: oklch(0.97 0.005 270);   /* ✅ light */
  --surface-inset: oklch(0.94 0.004 270);   /* ✅ light */
  /* ❌ oklch(0.16 ...) = near-black = identical to .dark = broken light mode */
}
```

Always diff `:root` vs `.dark` surface tokens. If they're the same value, light mode is broken.

---

## Quick Audit Checklist

Before shipping any badge/pill/status component:

```bash
# Find any base tokens used as text color on wash backgrounds:
grep -rn "text-warning\b\|text-success\b\|text-destructive-foreground" src/ --include="*.tsx"
# All results on wash (bg-*/10) backgrounds are WRONG — change to -foreground variants

# Verify root vs dark surface tokens are distinct:
grep -A2 "brand-surface\|surface-inset" src/app/globals.css
# :root values should be L >= 0.90; .dark values should be L <= 0.25
```
