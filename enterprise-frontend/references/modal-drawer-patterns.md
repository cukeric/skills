# Modal / Drawer / Overlay Patterns — Native <dialog>, Focus, Touch, SSR

Hard-won patterns from AIGIST M17 sprint (2026-05-13). Five HIGH-severity bugs caught in code-review when these were implemented wrong. Read before building any modal, drawer, side panel, off-canvas menu, command palette, or focus-trapping overlay.

---

## 1. Use Native `<dialog>` with `showModal()` — Never `<dialog open>`

The single most common modal mistake: rendering `<dialog open>` instead of calling `dialogRef.current.showModal()`. They look identical at first but differ on every dimension that matters.

| Behaviour | `<dialog open>` (non-modal) | `dialog.showModal()` (modal) |
|---|---|---|
| Native focus trap | ❌ Must hand-roll | ✅ Browser handles |
| `::backdrop` pseudo-element | ❌ Not rendered | ✅ Available for CSS |
| `aria-modal="true"` implied | ❌ No | ✅ Yes (still add explicitly) |
| Escape key closes | ❌ Manual `onKeyDown` only | ✅ Native, dispatches `cancel` event |
| Background inert | ❌ Tab order leaks out | ✅ Rest of page is inert |
| Click outside backdrop dismisses | ❌ Must hand-roll | ✅ Wire via `onClick` checking `event.target === dialogRef.current` |
| Focus return on close | ❌ Must call `triggerRef.focus()` | ✅ Browser returns focus to the invoking element |

### Correct pattern

```tsx
function MyDrawer({ open, onClose }: { open: boolean; onClose: () => void }) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  // Drive open/close imperatively — do NOT use the `open` attribute
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open) {
      if (!dialog.open) dialog.showModal();
    } else {
      if (dialog.open) dialog.close();
    }
  }, [open]);

  // Escape key dispatches a cancel event. preventDefault keeps React state
  // authoritative (we drive close via the effect, not the browser).
  const handleCancel = (e: React.SyntheticEvent<HTMLDialogElement>) => {
    e.preventDefault();
    onClose();
  };

  // Backdrop click: event.target === dialog itself (clicked the ::backdrop area)
  const handleClick = (e: React.MouseEvent<HTMLDialogElement>) => {
    if (e.target === dialogRef.current) onClose();
  };

  return (
    // biome-ignore lint/a11y/useKeyWithClickEvents: onClick handles backdrop dismiss; keyboard dismiss is wired via onCancel (native Escape on modal <dialog>)
    <dialog
      ref={dialogRef}
      aria-label="My drawer"
      aria-modal="true"
      onCancel={handleCancel}
      onClick={handleClick}
    >
      {/* content */}
    </dialog>
  );
}
```

### Companion CSS — `::backdrop`

```css
dialog::backdrop {
  background: rgba(26, 29, 42, 0.48);
  backdrop-filter: blur(2px);
}

@media (prefers-reduced-motion: no-preference) {
  dialog::backdrop {
    animation: backdrop-fade-in 200ms ease-out;
  }
}

@keyframes backdrop-fade-in {
  from { opacity: 0; }
  to   { opacity: 1; }
}
```

### Why this matters

`<dialog open>` is a footgun that satisfies Biome's `useSemanticElements` lint without giving you any of the actual modal semantics. Reviewers and screen-reader users will flag this. The fix is one `useEffect`; there is no reason to ship the non-modal version.

---

## 2. The "Focus Trap Steals on Mount" Anti-Pattern

If you hand-roll a focus trap (and sometimes you must, e.g. for non-`<dialog>` overlays), the naive version fires on initial render and steals focus to the trigger element — typically a mobile hamburger button hidden on desktop.

### Broken

```tsx
function useFocusTrap(open: boolean, triggerRef: RefObject<HTMLButtonElement>) {
  useEffect(() => {
    if (!open) {
      triggerRef.current?.focus();   // ← fires on every initial mount (open=false)
      return;
    }
    // trap setup
  }, [open]);
}
```

On every page load, focus jumps to `triggerRef`. Desktop users see a stray ring on the hidden mobile hamburger. Mobile users land focus on the wrong element after navigation.

### Correct — track open→closed transitions

```tsx
function useFocusTrap(open: boolean, triggerRef: RefObject<HTMLButtonElement>) {
  const wasOpenRef = useRef(false);

  useEffect(() => {
    if (!open) {
      // Only restore focus on a genuine open→closed transition,
      // not on initial mount where wasOpenRef is still false.
      if (wasOpenRef.current) {
        triggerRef.current?.focus();
        wasOpenRef.current = false;
      }
      return;
    }
    wasOpenRef.current = true;
    // trap setup …
  }, [open, triggerRef]);
}
```

### Better — delete the hand-rolled trap

If you can use `<dialog>` + `showModal()`, you get this for free. Delete `useFocusTrap`. The dead-code risk (unused symbol, unused ref, unused prop pass-through) is real — Biome's `noUnusedVariables` will catch most of it, but the cleanup is yours to do.

---

## 3. Hover on Touch Devices — CSS Pointer-Type Guard, Not React State

JS `onMouseEnter` / `onMouseLeave` handlers fire on iOS Safari and Android Chrome **on the first tap** (the browser synthesises mouse events for touch). If you use them to expand a sidebar / show a tooltip / reveal a control, touch users see the affordance animate mid-tap.

### Broken

```tsx
const [hoverExpanded, setHoverExpanded] = useState(false);

<aside
  onMouseEnter={() => setHoverExpanded(true)}
  onMouseLeave={() => setHoverExpanded(false)}
  style={{ width: hoverExpanded ? 220 : 56 }}
>
```

### Correct — CSS only, gated by pointer-type media query

```tsx
// Drop the React state entirely.
<aside data-sidebar-rail style={{ width: "var(--sidebar-width)" }} />
```

```css
:root { --sidebar-width: 56px; }
body[data-sidebar="expanded"] { --sidebar-width: 220px; }

@media (hover: hover) and (pointer: fine) {
  body[data-sidebar="collapsed"] aside[data-sidebar-rail]:hover {
    /* CSS-only hover-reveal — touch devices skip this rule */
    --sidebar-width: 220px;
  }
}
```

`(hover: hover) and (pointer: fine)` is the correct way to detect a mouse-like pointer. `(hover: hover)` alone matches some hybrid devices; pairing with `(pointer: fine)` excludes them.

### Why CSS-only

- One state branch, not three (`expanded` / `hoverExpanded` / `mobile`).
- No `useMediaQuery` hook + hydration mismatch risk.
- No JS event timing — instant hover response, no React re-render.
- Touch devices simply never match the media query, no extra guard needed.

---

## 4. SSR + localStorage = Hydration Mismatch + FOUC

Reading `localStorage` in initial render (or `useState` initialiser) breaks SSR — the server can't see localStorage, so its render uses defaults; the client immediately re-renders with the user's preference; React throws a hydration warning; the layout pops visibly.

### Acceptable — read in useEffect (hydration-safe, FOUC remains)

```tsx
const [expanded, setExpanded] = useState(false);  // deterministic default

useEffect(() => {
  try {
    const stored = localStorage.getItem("APP_SIDEBAR_EXPANDED");
    if (stored === "true") setExpanded(true);
  } catch {
    // localStorage blocked (Safari private mode, etc.) — silently fall back
  }
}, []);
```

This is hydration-safe but the user sees ~50ms of "collapsed" on hard reload before the effect runs. Acceptable for most cases.

### Better — pre-hydration script (no FOUC, next-themes pattern)

For layout-affecting preferences (theme, sidebar width, motion), apply via an inline `<script>` in `<head>` that runs **before** React hydrates. The script sets a `data-*` attribute on `<body>` (or `<html>`); your CSS keys off that attribute; the first paint matches user preference.

```tsx
// In app/layout.tsx (root layout) or via Next.js Script with strategy="beforeInteractive"
const themeScript = `
  try {
    var s = localStorage.getItem("APP_SIDEBAR_EXPANDED");
    if (s === "true") document.body.dataset.sidebar = "expanded";
    else document.body.dataset.sidebar = "collapsed";
  } catch (_) {
    document.body.dataset.sidebar = "collapsed";
  }
`;

<head>
  <script dangerouslySetInnerHTML={{ __html: themeScript }} />
</head>
```

```css
body[data-sidebar="collapsed"] { --sidebar-width: 56px; }
body[data-sidebar="expanded"]  { --sidebar-width: 220px; }
```

Five lines, kills the FOUC, no React state required for the initial paint. React effect still runs to keep state synchronised on subsequent changes.

---

## 5. `prefers-reduced-motion` Must Be Honoured

```css
@media (prefers-reduced-motion: no-preference) {
  .drawer-slide-in { animation: drawer-slide 200ms ease-out; }
  .sidebar-animate { transition: width 180ms ease-out; }
}
```

Wrap *all* layout-shifting animations in `(prefers-reduced-motion: no-preference)`. Users with vestibular disorders or motion sensitivity get instant snap. The inverse `(prefers-reduced-motion: reduce)` works too but the no-preference framing is positive — animations are opt-in, not opt-out — which matches the WCAG intent.

---

## Verification Checklist

When reviewing modal/drawer/overlay code, confirm:

- [ ] `<dialog>` is opened via `dialogRef.current.showModal()`, not `<dialog open>`
- [ ] `aria-modal="true"` is set explicitly
- [ ] `onCancel` is wired (Escape close)
- [ ] Backdrop click dismiss checks `event.target === dialogRef.current`
- [ ] If a hand-rolled focus trap exists: it tracks open→closed transitions via a ref (no focus steal on mount)
- [ ] Hover-reveal interactions are CSS-only behind `@media (hover: hover) and (pointer: fine)`
- [ ] No `onMouseEnter` / `onMouseLeave` for sidebar/tooltip/drawer expansion (touch synthesis hazard)
- [ ] localStorage reads happen in `useEffect`, never in `useState` initialiser
- [ ] For layout-affecting preferences: pre-hydration script in `<head>` sets a body data-attribute before React renders
- [ ] All layout-shifting animations wrapped in `@media (prefers-reduced-motion: no-preference)`
- [ ] Body scroll-lock on modal open is paired with release on close + unmount cleanup
- [ ] `aria-expanded` + `aria-controls` on the trigger button
- [ ] Active nav item in any associated navigation has `aria-current="page"`

---

## Integration with Other Skills

- **enterprise-i18n-accessibility** — `keyboard-screenreader.md` for full keyboard navigation requirements; `accessibility-wcag.md` §"aria-label for acronyms" for the screen-reader pronunciation pattern.
- **enterprise-testing** — recommend Vitest interaction tests for: open/close cycle, focus return, Escape dismiss, backdrop click. SSR/hydration safety should be asserted by rendering before useEffect runs and confirming default state.
