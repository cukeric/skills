# Enterprise i18n & Accessibility Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | ~280 | Decision frameworks (i18n library, a11y targets), i18n architecture, ICU messages, next-intl setup, semantic HTML, ARIA patterns, keyboard navigation, verification checklist |
| `references/i18n-setup.md` | ~180 | next-intl middleware/layout/usage, i18next setup, ICU format, RTL CSS, translation workflow |
| `references/locale-formatting.md` | ~150 | Intl API (dates, numbers, currencies, lists, relative time), timezone handling, locale detection |
| `references/accessibility-wcag.md` | ~180 | WCAG 2.1 AA checklist (perceivable, operable, understandable, robust), semantic HTML, forms, skip link, sr-only |
| `references/keyboard-screenreader.md` | ~170 | Focus management, focus traps, live regions, keyboard shortcuts, roving tabindex |
| `references/testing-i18n-a11y.md` | ~140 | axe-core, jest-axe, Lighthouse CI, missing translations test, pseudo-localization, manual checklists |

**Total: ~1,100+ lines of i18n & accessibility patterns.**

---

## Installation

```bash
mkdir -p ~/.claude/skills/enterprise-i18n-accessibility/references
cp SKILL.md ~/.claude/skills/enterprise-i18n-accessibility/
cp references/* ~/.claude/skills/enterprise-i18n-accessibility/references/
```

---

## Trigger Keywords

> i18n, internationalization, localization, translation, locale, RTL, pluralization, next-intl, i18next, accessibility, a11y, WCAG, ARIA, screen reader, keyboard navigation, focus management, color contrast, alt text, semantic HTML

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-frontend` | UI components must be accessible; design tokens for contrast |
| `enterprise-mobile` | React Native accessibility props, platform-specific patterns |
| `enterprise-testing` | axe-core integration, a11y test automation |
| `enterprise-devx-monorepo` | Shared i18n config across apps |
