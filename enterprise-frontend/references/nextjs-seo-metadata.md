# Next.js SEO & Metadata (App Router)

Complete, current (Next 14/15/16) playbook for technical SEO on the App Router. Covers
the Metadata API, the `viewport` export, canonicals, file-based social images, JSON-LD
structured data, and the **client-component metadata gotcha**. Derived from a full SEO
rework of a Next 16 portfolio (2026-05-31).

> Priority order holds: this is performance/discoverability work — never let an SEO
> change weaken security headers, leak data in OG tags, or inject unsanitized JSON-LD.

---

## 1. Root metadata: template + defaults (one source of truth)

In the root `app/layout.tsx`. Use a **title template** so child pages get a brand suffix
for free, and set `metadataBase` so all relative URLs (canonical, OG) resolve absolutely.

```ts
import type { Metadata, Viewport } from "next";

const SITE_URL = "https://example.com";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),          // REQUIRED for relative canonical/OG to resolve
  title: {
    default: "Brand — Tagline",             // used on pages that set no title
    template: "%s · Brand",                 // child `title: "X"` → "X · Brand"
  },
  description: "…",
  applicationName: "Brand",
  authors: [{ name: "…", url: SITE_URL }],
  creator: "…",
  publisher: "…",
  keywords: ["…"],                          // low ranking value, but harmless; keep current
  alternates: { canonical: "/" },           // self-canonical; relative resolves via metadataBase
  category: "technology",
  formatDetection: { email: false, telephone: false, address: false },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",         // rich image results
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  openGraph: {
    title: "Brand — Tagline",
    description: "…",
    url: SITE_URL,
    siteName: "Brand",
    locale: "en_US",
    type: "website",
  },
  twitter: { card: "summary_large_image", title: "…", description: "…", creator: "@handle" },
};

// viewport + themeColor are a SEPARATE export since Next 14 (do NOT put them in `metadata`)
export const viewport: Viewport = {
  themeColor: "#ffffff",
  colorScheme: "light",
  width: "device-width",
  initialScale: 1,
};
```

**Gotchas**
- `themeColor`, `colorScheme`, `width`, `initialScale` moved OUT of `metadata` into the
  `viewport` export (Next 14+). Leaving them in `metadata` logs a build warning and is ignored.
- `metadataBase` missing → Next warns and falls back to `localhost`, producing broken
  absolute OG/canonical URLs in production.

---

## 2. Per-page metadata + canonicals

Static pages: `export const metadata`. Dynamic routes: `export async function generateMetadata`.

```ts
export async function generateMetadata({ params }): Promise<Metadata> {
  const { slug } = await params;            // params is a Promise in Next 15+
  const item = getBySlug(slug);
  if (!item) return {};
  const canonical = `/items/${slug}`;
  return {
    title: { absolute: item.metaTitle },    // `absolute` BYPASSES the template (no "· Brand" suffix)
    description: item.metaDescription,
    alternates: { canonical },              // every indexable page needs ONE self-canonical
    openGraph: { title: item.metaTitle, description: item.metaDescription,
                 url: `${SITE_URL}${canonical}`, siteName: "Brand", type: "article" },
    twitter: { card: "summary_large_image", title: item.metaTitle, description: item.metaDescription },
  };
}
```

- Use `title.absolute` when the page's title is already a full, crafted title and you do
  NOT want the brand-suffix template appended (avoids overlong / doubled titles).
- A page that manually wrote `title: "Privacy — Brand"` will become `"Privacy — Brand · Brand"`
  once you add a template. Fix: change it to `title: "Privacy"` and let the template add the suffix.
- Every indexable route should declare exactly one canonical. Pagination/filters → canonical
  to the clean URL.

---

## 3. The client-component metadata gotcha (important)

**A `"use client"` page cannot `export const metadata` / `generateMetadata`** — metadata is a
server-only contract. The page silently inherits only the root metadata (wrong title, no
canonical). This is easy to miss because there's no error.

**Fix: add a server-component segment `layout.tsx` next to the client page** — a layout can
export metadata for the whole route segment even when its page is a client component:

```ts
// app/resume/layout.tsx  (server component — no "use client")
import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "Resume",
  description: "…",
  alternates: { canonical: "/resume" },
};
export default function ResumeLayout({ children }: { children: React.ReactNode }) {
  return children;
}
```

The client `app/resume/page.tsx` stays as-is. This is the canonical pattern for giving an
interactive (client) page proper SEO.

---

## 4. Social images — prefer the file convention

Don't hand-maintain `openGraph.images`. Drop a file in the route segment and Next auto-adds
the correct `<meta og:image>` (with width/height/type) to that segment and its children:

- `app/opengraph-image.png` (or `.jpg`) → applies site-wide.
- `app/twitter-image.png` → Twitter card image.
- Dynamic: `app/opengraph-image.tsx` using `ImageResponse` (`next/og`) for templated cards.

A page that overrides `openGraph` *without* an `images` key still inherits the file-convention
image from its segment — so per-page OG text + a shared OG image works automatically. Manually
adding `images` on top of the file convention DUPLICATES the `og:image` tag — don't.

---

## 5. Structured data (JSON-LD)

Render a `<script type="application/ld+json">` in the component tree (works in body; Google
reads it). Centralize a tiny wrapper so escaping is uniform:

```tsx
function LdScript({ data }: { data: Record<string, unknown> }) {
  return <script type="application/ld+json"
    dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }} />;  // JSON.stringify IS the sanitizer
}
```

**The standard trio** (portfolio / marketing / docs):
- **Person** or **Organization** — identity. Give it a stable `@id` (`${SITE_URL}/#person`)
  and reference it elsewhere by `{ "@id": ... }` instead of repeating the object.
- **WebSite** — `name`, `url`, `inLanguage`, `author`/`publisher` → `@id`-ref the Person/Org.
- **BreadcrumbList** — on nested pages: `itemListElement` of `ListItem { position, name, item }`.
- Domain types as fits: `SoftwareApplication` (apps — `applicationCategory`, `operatingSystem`,
  `author`), `Article`/`BlogPosting`, `Product`, `FAQPage`.

**Rules**
- Only describe content actually on the page (Google flags mismatches).
- Keep `@id` references consistent across pages so entities de-duplicate in the graph.
- `dangerouslySetInnerHTML` with `JSON.stringify` is the *accepted* JSON-LD pattern — values
  come from your own data, and stringify escapes them. Don't interpolate raw strings.
- Validate with Google Rich Results Test / Schema.org validator before shipping.

---

## 6. sitemap.ts + robots.ts (file conventions)

```ts
// app/sitemap.ts — map data, don't hand-list
export default function sitemap(): MetadataRoute.Sitemap {
  return [{ url: SITE_URL, changeFrequency: "weekly", priority: 1 }, ...dynamicPages];
}
// app/robots.ts
export default function robots(): MetadataRoute.Robots {
  return { rules: { userAgent: "*", allow: "/" }, sitemap: `${SITE_URL}/sitemap.xml` };
}
```
- Generate sitemap entries from the same data source as the routes (slug rename → sitemap
  auto-updates; never hardcode slugs in two places).
- Renaming a route slug (e.g. rebrand `/projects/aigist` → `/projects/eloryn`): the old URL
  now 404s. If it had inbound links/SEO equity, add a `redirects()` 301 in `next.config`.

---

## 7. Run-and-observe (don't trust the build alone)

Green build ≠ correct SEO. After `next build`, run the server and **curl the rendered HTML**:

```bash
curl -s http://localhost:3000/         | grep -oE '<title>[^<]*</title>|rel="canonical"[^>]*|"@type":"[^"]*"'
curl -s http://localhost:3000/robots.txt
curl -s http://localhost:3000/sitemap.xml | grep -c '<loc>'
```
Confirm per route: correct `<title>` (template applied), exactly one `<link rel="canonical">`,
`robots` meta present, `og:image` resolves to an absolute URL, and the expected JSON-LD
`@type`s render. Then validate live (Rich Results Test) after deploy.

---

## Verification checklist

- [ ] `metadataBase` set in root layout (absolute OG/canonical resolution)
- [ ] Title template + `default`; per-page titles use `absolute` only when intentional
- [ ] Every indexable route declares exactly one `alternates.canonical`
- [ ] `viewport`/`themeColor` in the `viewport` export, NOT `metadata`
- [ ] `robots` + `googleBot` directives present (index/follow, max-image-preview:large)
- [ ] Client-component pages get metadata via a server segment `layout.tsx`
- [ ] OG/Twitter images via file convention (no duplicate `og:image`)
- [ ] JSON-LD: Person/Org + WebSite at minimum; BreadcrumbList on nested pages; stable `@id`s
- [ ] JSON-LD describes only on-page content; validated in Rich Results Test
- [ ] sitemap + robots generated from data, not hardcoded; old slugs 301'd on rename
- [ ] Rendered HTML curl-verified per route; not just a green build

---

## Integration with Other Enterprise Skills

- **enterprise-frontend / react-nextjs.md** — App Router fundamentals; this file is the SEO layer.
- **enterprise-frontend / client-server-boundary.md** — why `"use client"` blocks metadata export.
- **enterprise-i18n-accessibility** — `hreflang`/`alternates.languages` for multilingual SEO;
  semantic headings and `lang` attribute also feed SEO.
- **enterprise-deployment** — Vercel deploys on `git push` (no separate deploy step); verify
  live metadata post-deploy.
