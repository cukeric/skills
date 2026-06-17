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

---

## Locale Variants — When to Use Which

Default `fr` is France French. If the audience is Canadian, Quebec, federal Canadian government, IRAP-track, or any French-speaking jurisdiction outside France, use `fr-CA` and treat it as a **distinct locale**, not a synonym for `fr`. The vocabulary, idioms, and (especially) UI verbs differ.

### Quebec French (fr-CA) UI conventions

Translation traps that hit the AIGIST project (2026-05):

| English UI verb | France `fr` | Quebec `fr-CA` |
|---|---|---|
| Expand sidebar | Étendre la barre latérale | **Déployer** la barre latérale (preferred) — "Étendre" reads as "extend its size" |
| Collapse sidebar | Réduire la barre latérale | Réduire / Replier la barre latérale |
| Sign in | Se connecter | Se connecter (same) |
| Sign out | Se déconnecter | Se déconnecter (same) |
| Email | E-mail | **Courriel** (mandatory in GoC / federal Quebec content) |
| Submit | Soumettre | Soumettre / Envoyer |
| Cancel | Annuler | Annuler (same) |
| Click here | Cliquez ici | Cliquez ici (same) — but avoid in body copy, both locales prefer descriptive link text |
| File (noun) | Fichier | Fichier (same) |
| Download | Télécharger | Télécharger (same) |
| Toggle | Basculer | Basculer / Activer |
| Settings | Paramètres | **Paramètres** (preferred) or "Réglages" |

### Government of Canada (GoC) terminology

If the project targets federal Canadian deployment:

- "Government of Canada" → **"Gouvernement du Canada"** (always capitalised)
- "Service Canada" stays untranslated (it's a proper noun).
- AIDA → **"LIAD"** (Loi sur l'intelligence artificielle et les données) when expanded; AIDA as the acronym is acceptable.
- PIPEDA → **"LPRPDE"** (Loi sur la protection des renseignements personnels et les documents électroniques); citation form "PIPEDA / LPRPDE" is acceptable.
- "Federal" → "fédéral / fédérale" (gendered agreement matters).
- Always use the [Termium Plus](https://www.btb.termiumplus.gc.ca/) terminology database for any federal-government-specific term — it is the authoritative GoC glossary.

### Native-speaker review

Quebec French has enough surface-level overlap with France French that machine translation and AI translation pass at first glance — but UI verbs, idioms, and the choice between "tu" and "vous" addressing modes diverge. Budget for at least one native-speaker review pass per release for any fr-CA surface, especially if the audience includes government / regulated industry.

### Code: locale negotiation

```ts
// next-intl with fr-CA as a distinct locale
export const locales = ["en", "fr-CA"] as const;
export const defaultLocale = "en" as const;

// In your getRequestConfig — fall back fr → fr-CA, never the other way
function negotiateLocale(requested: string): typeof locales[number] {
  if (requested === "fr-CA" || requested === "fr") return "fr-CA";
  return "en";
}
```

Do NOT label your French file as just `fr.json` if it contains Quebec usage — name it `fr-CA.json`. Future translators will assume `fr.json` is France French and "fix" your Quebec idioms.

## Localizing DATA, not just UI chrome (single-source pattern)

Message files (`en.json`/`fr.json`) cover UI chrome. But when the *content* is data produced by
a backend/engine (legal citations, rule rationales, audit records, AI-generated text), translating
the chrome around English data is a half-job — a bilingual audience (e.g. Government of Canada,
constitutionally bilingual) sees French labels wrapping English content. Two ways to make the data
bilingual, and the trade-off that matters:

- **❌ Re-derive translations in the render layer** (map an id → localized string in the frontend
  i18n) duplicates the producer's branch logic in a second place → the two **drift**. Avoid.
- **✅ Single bilingual source** — the producer emits both languages as **additive optional sibling
  fields** and the render layer just picks by locale with a source-language fallback:
  - Producer (resolver/engine): `RuleApplied { citation, citationFr?, relevance, relevanceFr?, … }`
    — the canonical (e.g. English) field stays authoritative for the audit record; FR is additive.
    Make the internal resolution type's FR fields **required** so the compiler forces every branch
    to emit them (no branch can silently leak the source language).
  - Render: one helper `localize(obj, locale)` → `(locale==='fr' && obj.fieldFr) || obj.field`,
    routed through **every** render site (don't inline per-field ternaries — that's how drift starts).
    The `|| field` fallback is REQUIRED so records written before the bilingual change still render.
  - Net: one source of truth (no drift — the #1 i18n-data trust risk), audit record stays canonical,
    exports get the other language for free, and a missing translation degrades to the source string.
  - Verify legal/official strings against the **official-language primary source** (statute names,
    control catalogues have authoritative FR names); never machine-guess a legal citation.
  Proven on Eloryn's Rule-Application Standard (2026-06): bilingual resolver + `lib/rule-localize.ts`
  at 5 register sites; data + chrome both FR, zero drift, EN fallback for old events.

Also: outcome/status labels used as the `{decision}` word in a sentence must be the **adjective**
form ("Permis"/"Interdit"/"Terminé"), not the infinitive verb ("Permettre"/"Interdire") — a verb
keyed `.short` reads wrong when interpolated as a noun-label. Audit `tml.*`/outcome label keys.
