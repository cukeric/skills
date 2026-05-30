# Client/Server Boundary Pitfalls — Next.js + React

Common bugs that ship green in tests but crash in the browser. Each one passes
typecheck and Vitest (jsdom-based, Node-runtime-by-default) and surfaces only
in a real browser session.

---

## 1. `Buffer is not defined` in client components

Node's `Buffer` is **not** a defined-but-undefined value in browsers — the
identifier is **not declared at all**, so any reference at runtime throws
`ReferenceError: Buffer is not defined`. A guard like `Buffer.from !==
undefined` evaluates `Buffer.from` first, which crashes before the comparison.

```typescript
// ❌ CRASHES in browser — Buffer is not declared at all
const json =
  Buffer.from !== undefined
    ? Buffer.from(b64, "base64").toString("utf8")
    : atob(b64)
```

**Fix:** `typeof` is the only safe form because it returns `"undefined"` for
declared-but-undefined AND for not-declared:

```typescript
// ✅ SAFE — typeof handles "not declared" without throwing
const json =
  typeof Buffer !== "undefined"
    ? Buffer.from(b64, "base64").toString("utf8")
    : new TextDecoder("utf-8").decode(
        Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)),
      )
```

**Why `atob` alone is not enough:** `atob()` returns a Latin-1 byte string —
characters above U+00FF are lost. A base64-encoded UTF-8 JSON payload
containing non-ASCII (e.g. French translations, emojis, accented usernames)
will decode to garbled bytes. The `atob → Uint8Array → TextDecoder` chain
recovers proper UTF-8.

**Where this hits in practice:** custom HTTP headers carrying base64-encoded
JSON (signed manifests, JWTs printed by hand), `window.atob` in download
flows, IndexedDB serialisation, cryptographic verification on the client.

---

## 2. `process` and `process.env.*` in client components

Same failure mode as `Buffer` — the `process` global doesn't exist in browsers.
Next.js inlines `process.env.NEXT_PUBLIC_*` at build time, but any other
`process.*` reference crashes at runtime.

```typescript
// ❌ CRASHES in client component
if (process.env.NODE_ENV === "production") { … }

// ✅ Next.js inlines this at build time, browser-safe
if (process.env.NEXT_PUBLIC_ENV === "production") { … }

// ✅ Or use the typeof guard for non-inlined process refs
if (typeof process !== "undefined" && process.env.SOME_VAR) { … }
```

**Rule:** in a `"use client"` file, only reference `process.env.NEXT_PUBLIC_*`.
Anything else belongs in a server component, an API route, or a server action.

---

## 3. React keys for position-stable tables

Biome's `lint/suspicious/noArrayIndexKey` flags `key={i}` on the assumption
that array items can reorder. For **position-stable** rendering (table columns
in a fixed-schema table, fixed-order tabs), the index IS the canonical
identity — but biome still complains. Two paths:

### Path A — pre-compute key tuples outside the JSX-level map

```tsx
{rows.map((row) => {
  const rowKey = String(row[0] ?? "")
  // Compute (key, value) tuples once. The JSX-level map no longer references
  // the index, so biome's heuristic doesn't fire.
  const cells = headers.map((h, i) => ({
    key: `${rowKey}__${h}__${i}`,
    value: row[i],
  }))
  return (
    <tr key={rowKey}>
      {cells.map((cell) => (
        <td key={cell.key}>{cell.value}</td>
      ))}
    </tr>
  )
})}
```

### Path B — `biome-ignore` with rationale

When the table genuinely has duplicate header labels (e.g. two columns
labelled the same) and Path A's composite key still feels artificial:

```tsx
{/* biome-ignore lint/suspicious/noArrayIndexKey: table columns are position-stable; headers can duplicate */}
{headers.map((_h, i) => (
  <td key={i}>{row[i]}</td>
))}
```

**Biome suppression placement gotcha:** the comment must be on the line
**immediately before** the AST node the rule flags. For JSX maps, the rule
flags the index parameter in `.map((_h, i) => …)`, so the suppression goes on
the line above the `.map()` call. Multi-line `// biome-ignore` comments do
not work — keep it single-line.

**Antipattern to avoid:** `key={String(row[i])}` — cell contents can repeat
or be empty across rows, producing duplicate keys with React warnings AND
broken reconciliation.

---

## 4. `res.text()` strips a leading UTF-8 BOM

The Fetch spec says UTF-8 decoders MUST strip a leading U+FEFF. If your CSV
export route returns a body starting with `\xEF\xBB\xBF`, browser code that
calls `res.text()` to inspect the BOM will see it gone.

```typescript
// ❌ res.text() strips the BOM before you can inspect it
const csv = await res.text()
expect(csv.charCodeAt(0)).toBe(0xfeff) // FAILS — BOM was stripped

// ✅ Read raw bytes when you need to verify byte-level encoding
const ab = await res.arrayBuffer()
const bytes = new Uint8Array(ab)
expect(bytes[0]).toBe(0xef)
expect(bytes[1]).toBe(0xbb)
expect(bytes[2]).toBe(0xbf)
```

Applies to test assertions, manifest verification, and any code that needs
to see the BOM exactly as the server wrote it.

---

## 5. Custom response headers require CORS exposure

A response carrying business-critical data in a custom header
(`X-Foo-Manifest`, `X-Rate-Limit-Remaining`) is **invisible to cross-origin
`fetch()`** by default. Same-origin works without ceremony; the moment the
dashboard moves behind a different origin (reverse proxy, subdomain split),
the client suddenly can't read the header.

```typescript
// Server (Next.js route handler)
return new Response(body, {
  headers: {
    "Content-Type": "application/pdf",
    "X-Custom-Manifest": manifestBase64,
    // Required: without this, cross-origin fetch sees the header as absent
    "Access-Control-Expose-Headers": "X-Custom-Manifest",
  },
})
```

**Rule:** set `Access-Control-Expose-Headers` defensively whenever you emit a
custom header that the client must read. Even for same-origin today —
cross-origin in 6 months is a single nginx config change away.

---

## 6. Server-component redirect destination matters

Operators landing on an auditor-only page must redirect to a destination the
operator actually has access to. Redirecting to `/` when `/` itself has a role
gate produces either a redirect loop or a 404, depending on which middleware
runs first.

```tsx
// ❌ Risky — depends on what / does when an operator hits it
if (role !== "admin" && role !== "auditor") redirect("/")

// ✅ Match the existing pattern — redirect to the role's actual landing page
if (role !== "admin" && role !== "auditor") redirect("/human-pause")
```

**Rule:** check the existing redirect pattern for adjacent role-gated routes
(e.g. `audit-log/page.tsx`) before choosing your destination. Don't invent a
new redirect target.

---

## 7. Module-level SDK-client init breaks `next build`

Instantiating an API client at module top level throws during `next build`'s
page-data collection when the key is absent in that environment (CI runner, a VPS
whose `.env` lacks the key) — `next build` evaluates every route module, and many SDKs
throw on construction without a key:

```ts
// ❌ Breaks the build wherever GROQ_API_KEY is absent — module is evaluated at build time
const groq = new Groq({ apiKey: process.env.GROQ_API_KEY })

// ✅ Lazy singleton — constructed on first request, never during build
let _groq: Groq | null = null
function getGroq(): Groq {
  if (!_groq) _groq = new Groq({ apiKey: process.env.GROQ_API_KEY })
  return _groq
}
```

Lazy-init has a bonus: the build needs **no runtime secrets**, so it runs identically
on any runner. Clients constructed *inside* the handler are already safe — only
module-scope instantiation is the trap. (iiSP `/api/chat`, 2026-05-29.)

## Quick checklist before shipping a new client-side feature

- [ ] No `Buffer`, `process`, `__dirname` references in `"use client"` files
- [ ] API/SDK clients (Groq, OpenAI, Stripe, …) are lazy-init'd, never constructed at module scope
- [ ] Base64 decode uses `atob → Uint8Array → TextDecoder` for UTF-8 safety
- [ ] Custom response headers have matching `Access-Control-Expose-Headers`
- [ ] Tests inspecting BOM / byte-level encoding use `arrayBuffer()`, not `text()`
- [ ] Role-gate redirects go to a destination the redirecting role can access
- [ ] React keys for tables don't pass biome's `noArrayIndexKey` heuristic by accident — use composite keys or a documented `biome-ignore`
