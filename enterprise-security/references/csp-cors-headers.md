# CSP, CORS & Security Headers Reference

## Content Security Policy (CSP)

CSP prevents XSS by defining which sources are allowed to load content.

### Building a CSP

```typescript
function buildCSP(options: {
  apiOrigins: string[]
  cdnOrigins?: string[]
  analyticsOrigins?: string[]
}): string {
  const directives = [
    "default-src 'self'",
    `script-src 'self' ${options.cdnOrigins?.join(' ') || ''} 'strict-dynamic'`.trim(),
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    `img-src 'self' data: blob: ${options.cdnOrigins?.join(' ') || ''} https:`.trim(),
    "font-src 'self' https://fonts.gstatic.com",
    `connect-src 'self' ${[...options.apiOrigins, ...(options.analyticsOrigins || [])].join(' ')}`,
    "media-src 'self'",
    "object-src 'none'",
    "frame-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "upgrade-insecure-requests",
  ]
  return directives.join('; ')
}
```

### CSP with Nonces (Strictest)

```typescript
// Generate nonce per request
app.addHook('onRequest', (req, reply, done) => {
  req.cspNonce = crypto.randomBytes(16).toString('base64')
  done()
})

app.addHook('onSend', (req, reply, payload, done) => {
  reply.header('Content-Security-Policy',
    `script-src 'nonce-${req.cspNonce}' 'strict-dynamic'; ` +
    `style-src 'self' 'nonce-${req.cspNonce}'; ` +
    "default-src 'self'; object-src 'none'; base-uri 'self'"
  )
  done()
})
```

### Report-Only Mode (Testing)

```typescript
// Deploy in report-only first, fix violations, then enforce
reply.header('Content-Security-Policy-Report-Only',
  `${buildCSP(options)}; report-uri /api/v1/csp-reports`
)

// CSP violation report endpoint
app.post('/api/v1/csp-reports', (req) => {
  logger.warn({ violation: req.body }, 'CSP violation reported')
})
```

---

## CORS Deep Dive

### How CORS Works

```
1. Browser sends preflight OPTIONS request (for non-simple requests)
2. Server responds with allowed origins, methods, headers
3. Browser checks response headers
4. If allowed, browser sends actual request
5. If denied, browser blocks the request (JavaScript gets no response)
```

### Strict Configuration

```typescript
import cors from '@fastify/cors'

await app.register(cors, {
  origin: (origin, callback) => {
    const allowed = [
      'https://app.company.com',
      'https://admin.company.com',
    ]

    // Allow requests with no origin (mobile apps, curl)
    if (!origin) return callback(null, true)

    if (allowed.includes(origin)) {
      return callback(null, true)
    }

    // Development: also allow localhost
    if (process.env.NODE_ENV === 'development' && origin?.startsWith('http://localhost')) {
      return callback(null, true)
    }

    callback(new Error('Not allowed by CORS'), false)
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
  exposedHeaders: ['X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-Request-ID'],
  maxAge: 86400,          // Preflight cache: 24 hours
  preflight: true,
  strictPreflight: true,
})
```

### Common CORS Mistakes

| Mistake | Risk | Fix |
|---|---|---|
| `origin: '*'` with credentials | Browser blocks it (won't work) | Use explicit origins |
| `origin: '*'` without credentials | Any site can read responses | Use allowlist |
| Reflecting Origin header | Equivalent to `*` | Use static allowlist |
| Allowing all methods | Broader attack surface | List only needed methods |
| No `maxAge` | Preflight on every request | Set to 86400 (24h) |

---

## Security Headers

### Complete Headers Setup

```typescript
// All headers — set on every response
function securityHeaders(req, reply, done) {
  // HTTPS enforcement (1 year, include subdomains, allow preload list)
  reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload')

  // Prevent MIME type sniffing
  reply.header('X-Content-Type-Options', 'nosniff')

  // Prevent clickjacking
  reply.header('X-Frame-Options', 'DENY')

  // Disable browser XSS filter (CSP is the modern replacement)
  reply.header('X-XSS-Protection', '0')

  // Control referrer information
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin')

  // Restrict browser features
  reply.header('Permissions-Policy', [
    'camera=()',
    'microphone=()',
    'geolocation=()',
    'interest-cohort=()',
    'browsing-topics=()',
  ].join(', '))

  // Prevent DNS prefetching to external domains
  reply.header('X-DNS-Prefetch-Control', 'off')

  // Prevent page from being embedded (CSP supplement)
  reply.header('Cross-Origin-Embedder-Policy', 'require-corp')
  reply.header('Cross-Origin-Opener-Policy', 'same-origin')
  reply.header('Cross-Origin-Resource-Policy', 'same-origin')

  done()
}

app.addHook('onSend', securityHeaders)
```

### Header Verification

```bash
# Test headers with curl
curl -I https://app.company.com

# Expected headers in response:
# strict-transport-security: max-age=31536000; includeSubDomains; preload
# x-content-type-options: nosniff
# x-frame-options: DENY
# content-security-policy: default-src 'self'; ...
# referrer-policy: strict-origin-when-cross-origin
# permissions-policy: camera=(), microphone=(), geolocation=()
```

### Online Verification Tools

- **SecurityHeaders.com** — Grades your headers A-F
- **Mozilla Observatory** — Comprehensive security scan
- **CSP Evaluator** (Google) — Validates CSP effectiveness

---

## Security Headers Checklist

- [ ] HSTS enabled with preload (max-age ≥ 1 year)
- [ ] X-Content-Type-Options: nosniff
- [ ] X-Frame-Options: DENY (or SAMEORIGIN if iframes needed)
- [ ] CSP configured and tested (start with report-only)
- [ ] Referrer-Policy: strict-origin-when-cross-origin
- [ ] Permissions-Policy: restrict unused browser features
- [ ] CORS: explicit origin allowlist, credentials: true only when needed
- [ ] Cross-Origin-*-Policy headers set for isolation
- [ ] Headers verified with SecurityHeaders.com (A+ grade target)
- [ ] CSP violations monitored via report-uri
