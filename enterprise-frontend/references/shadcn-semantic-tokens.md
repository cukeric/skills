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

---

## Two dark-mode contrast traps (any token system, not just shadcn)

Both shipped invisible-in-dark text on eloryn 2026-06-19d; a green build never catches either — only an eyeball in the dark theme does.

### Trap 1 — an OVERLOADED token (used as BOTH text and fill) breaks when the theme flips it

If one token serves two roles — e.g. `--brand-ink` as heading TEXT *and* as a primary-button FILL — flipping it for dark mode (ink goes light so headings stay readable) silently inverts the button: a now-LIGHT fill with text that was hardcoded `#fff`/`--text-on-sec` → light-on-light, invisible.

```css
/* ❌ button text reuses a token that is the OPPOSITE side of its own fill in dark */
.button-primary { background: var(--brand-ink); color: var(--text-on-sec); } /* both light in dark */

/* ✅ a fill needs a PAIRED contrast token that flips WITH the fill */
:root        { --text-on-brand: #fcfbfa; } /* brand-ink dark  → light text */
:root[data-theme="dark"] { --text-on-brand: #1a1613; } /* brand-ink light → dark text */
.button-primary { background: var(--brand-ink); color: var(--text-on-brand); }
```
Rule: **every filled element gets a `--text-on-<fill>` token defined in BOTH themes.** Never put the raw inverted ink as text on its own fill.

### Trap 2 — an UNDEFINED CSS var with a hardcoded LIGHT fallback never flips

`var(--surface-2, #f6f8fa)` looks token-driven but `--surface-2` was never defined → the hardcoded light `#f6f8fa` applies in BOTH themes → light page shell with light text in dark mode.

```bash
# Audit for undefined-token references whose fallback is a hardcoded LIGHT colour:
grep -rn 'var(--[a-z-]*,[[:space:]]*#' src/   # every hit either: define the token, or drop the literal
```
Fix = define the missing token as a **flipping alias** of a real one (`--surface-2: var(--background-warm)`) so it inherits the dark override automatically — one edit fixes every stale usage. Also: a global affordance (theme toggle, sign-out) must be added to **every** `app/**/layout.tsx` route-group, not just the main shell — sibling groups (e.g. a `(control)` surface) have their own layout.
