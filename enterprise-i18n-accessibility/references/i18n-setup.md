# i18n Setup Reference

## next-intl (Next.js App Router)

### Installation

```bash
npm install next-intl
```

### Middleware

```typescript
// middleware.ts
import createMiddleware from 'next-intl/middleware'

export default createMiddleware({
  locales: ['en', 'fr', 'de', 'ja', 'ar'],
  defaultLocale: 'en',
  localeDetection: true,
  localePrefix: 'as-needed', // No prefix for default locale
})

export const config = {
  matcher: ['/', '/(en|fr|de|ja|ar)/:path*'],
}
```

### Message Files

```json
// messages/en.json
{
  "Navigation": {
    "home": "Home",
    "dashboard": "Dashboard",
    "settings": "Settings"
  },
  "Auth": {
    "login": "Log in",
    "logout": "Log out",
    "welcome": "Welcome back, {name}!"
  },
  "Orders": {
    "title": "Orders",
    "count": "{count, plural, =0 {No orders} one {1 order} other {{count} orders}}",
    "total": "Total: {amount, number, ::currency/USD}",
    "status": "{status, select, pending {Pending} shipped {Shipped} delivered {Delivered} other {Unknown}}"
  }
}
```

### Layout

```typescript
// app/[locale]/layout.tsx
import { NextIntlClientProvider } from 'next-intl'
import { getMessages, setRequestLocale } from 'next-intl/server'

export default async function LocaleLayout({
  children, params: { locale },
}: { children: React.ReactNode; params: { locale: string } }) {
  setRequestLocale(locale)
  const messages = await getMessages()

  return (
    <html lang={locale} dir={locale === 'ar' ? 'rtl' : 'ltr'}>
      <body>
        <NextIntlClientProvider messages={messages}>
          {children}
        </NextIntlClientProvider>
      </body>
    </html>
  )
}
```

### Usage

```typescript
// Server component
import { getTranslations } from 'next-intl/server'

export default async function OrdersPage() {
  const t = await getTranslations('Orders')
  return <h1>{t('title')}</h1>
}

// Client component
'use client'
import { useTranslations, useFormatter } from 'next-intl'

function OrderSummary({ orders }) {
  const t = useTranslations('Orders')
  const format = useFormatter()

  return (
    <div>
      <p>{t('count', { count: orders.length })}</p>
      <p>{format.number(totalCents / 100, { style: 'currency', currency: 'USD' })}</p>
      <p>{format.dateTime(new Date(), { dateStyle: 'long' })}</p>
    </div>
  )
}
```

### Typing `t` as a Component Prop

When passing the `t` function to sub-components, use `ReturnType<typeof useTranslations>`:

```typescript
import { useTranslations } from 'next-intl'

// CORRECT — preserves full type safety
function SubComponent({ t }: { t: ReturnType<typeof useTranslations> }) {
  return <p>{t('someKey')}</p>
}

// WRONG — loses namespace type safety, breaks t.rich() and other methods
function SubComponent({ t }: { t: (key: string) => string }) { ... }
```

### Rich Text (HTML in Translations)

Use `t.rich()` for translations that contain HTML tags:

```json
{
  "description": "Save <strong>up to 40%</strong> with a subscription"
}
```

```tsx
{t.rich('description', {
  strong: (chunks) => <strong>{chunks}</strong>,
  code: (chunks) => <code className="font-mono">{chunks}</code>,
})}
```

### Cookie-Based Locale (No URL Prefix)

For apps that use cookie-based locale detection without `/[locale]/` URL prefixes:

```typescript
// routing.ts
import { defineRouting } from 'next-intl/routing'
export const routing = defineRouting({
  locales: ['en', 'es', 'fr', 'pt', 'de', 'it', 'nl'],
  defaultLocale: 'en',
})

// middleware.ts — create but DON'T call intlMiddleware until URL-prefix routing is ready
const intlMiddleware = createIntlMiddleware(routing)
// Locale is set via NEXT_LOCALE cookie by LanguageSwitcher component
```

### Bulk i18n Wiring Strategy

When translating many pages at once with parallel agents:
1. **Wave 1**: Pages that DON'T share locale file namespaces (avoids merge conflicts)
2. **Wave 2**: Remaining pages
3. Run a verification pass: check key parity across all locales, placeholder integrity
4. Use `labelKey`/`descKey` pattern for data arrays (dropdowns, option lists) instead of hardcoded labels

---

## i18next (Framework-Agnostic)

```bash
npm install i18next react-i18next i18next-browser-languagedetector
```

```typescript
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: { translation: { /* ... */ } },
      fr: { translation: { /* ... */ } },
    },
    fallbackLng: 'en',
    interpolation: { escapeValue: false },
  })
```

---

## RTL Support

```css
/* Logical properties for automatic RTL */
.container {
  padding-inline-start: 1rem;  /* left in LTR, right in RTL */
  padding-inline-end: 2rem;
  margin-inline-start: auto;
  border-inline-start: 2px solid;
  text-align: start;           /* left in LTR, right in RTL */
}

/* Direction-specific overrides */
[dir='rtl'] .icon-arrow { transform: scaleX(-1); }
```

---

## Translation Workflow

1. Developers write English strings in `en.json`
2. Run extraction script to find new keys
3. Send new keys to translation service (Crowdin, Lokalise, Phrase)
4. Translators provide translations
5. Import translated files back to `messages/`
6. CI checks for missing translations
