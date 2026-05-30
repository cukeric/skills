---
name: i18n-translate
description: Internationalize a page or component in any next-intl project. Detects the project's configured locales and message-file location, extracts hardcoded English strings, adds translation keys to every locale file, and wires up useTranslations(). Use when translating pages or when the user says "translate", "i18n", "internationalize", or invokes /i18n-translate.
---

# Internationalize a Page (next-intl)

Standardized workflow for converting hardcoded English strings to next-intl translations across all of a project's locales. Project-agnostic — it discovers the locale set and message-file path from the codebase.

## Step 0: Discover the i18n Setup (do this first, every time)

Do not assume locales or paths — read them from the project:

1. **Locales**: read the next-intl routing/config (`src/i18n/routing.ts`, `src/i18n/request.ts`, `i18n.ts`, or `next.config.*`) for the `locales` array. The first / `defaultLocale` is the source of truth.
2. **Message files**: locate the per-locale JSON. Common layouts: `src/i18n/messages/{locale}.json`, `messages/{locale}.json`, `src/messages/{locale}.json`. Confirm by checking which path the next-intl config loads.
3. Note the default locale (usually `en`) — that's where you add keys first.

## Workflow

### Step 1: Audit the Target Page

Read the target file. Identify ALL hardcoded user-facing strings in JSX — labels, headings, descriptions, button text, error messages, placeholder text, aria labels, alt text.

Categorize them:
- **Static text**: Direct string literals in JSX (`<h2>Dashboard</h2>`)
- **Template literals**: Strings with variables (`Expires in ${days}d`)
- **Conditional text**: Ternaries with string outputs
- **Array items**: Mapped arrays with label strings

### Step 2: Design Key Structure

Use a flat namespace matching the page name. Example for a dashboard:

```json
{
  "dashboard": {
    "title": "Your Items",
    "empty": "No items yet",
    "expiresIn": "Expires in {days}d",
    "status": { "complete": "Complete", "processing": "Processing", "failed": "Failed" }
  }
}
```

Rules:
- camelCase keys; group related strings under sub-objects
- `{variable}` syntax for interpolation (next-intl ICU format)
- Keep keys descriptive but concise
- **Brand names and product/plan names stay in English across all locales**
- Currency amounts stay in the project's base currency across all locales

### Step 3: Add Keys to the Default Locale First

Add the keys to the default-locale file (e.g. `en.json`) — the source of truth.

### Step 4: Translate to Every Other Locale

For each non-default locale file discovered in Step 0:
1. Add the same key structure
2. Translate naturally — not word-for-word
3. Keep brand names, technical terms, and currency in English / base form
4. Match the tone of existing translations in that locale
5. Preserve all `{variable}` placeholders exactly

### Step 5: Wire Up the Component

1. `import { useTranslations } from 'next-intl'`
2. `const t = useTranslations('namespace')`
3. Replace every hardcoded string with `t('key')` or `t('key', { variable: value })`
4. Raw values (numbers, arrays): `t.raw('key')`
5. Rich text with HTML: `t.rich('key', { bold: (chunks) => <strong>{chunks}</strong> })`

### Step 6: Verify

- No hardcoded English strings remain in JSX (grep for common English words)
- **Every** locale file has identical key structures (key parity)
- Component renders without errors; TypeScript compiles cleanly

## Common Patterns

### Pluralization
```json
{ "items": "{count, plural, one {# item} other {# items}}" }
```
```tsx
t('items', { count: 5 })
```

### Conditional with variable
```json
{ "expiresIn": "Expires in {days}d" }
```
```tsx
t('expiresIn', { days: daysLeft })
```

### Nested access
```tsx
const t = useTranslations('dashboard')
t('status.complete') // "Complete"
```

## Quality Checklist

- [ ] Locale set + message path discovered from the project (not assumed)
- [ ] All hardcoded strings extracted
- [ ] Keys added to **all** locale files (key parity verified)
- [ ] Translations are natural, not machine-literal
- [ ] Brand names kept in English
- [ ] Variables/placeholders preserved
- [ ] `useTranslations()` wired in component
- [ ] No TypeScript errors
- [ ] No remaining English strings in JSX (except brand names)
