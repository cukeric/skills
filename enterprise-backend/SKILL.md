---
name: enterprise-backend
description: Explains how to create, design, modify, or optimize backend APIs and server-side logic with enterprise standards. Trigger on ANY mention of API, endpoint, route, REST, GraphQL, auth, authentication, authorization, SSO, SAML, OAuth, MFA, 2FA, TOTP, payment, Stripe, billing, subscription, webhook, middleware, rate limiting, logging, backend, back-end, server, Node.js, Express, Fastify, NestJS, Python, FastAPI, Django, Flask, Go, Gin, microservice, message queue, CORS, JWT, session, token, email, notification, SMS, or any request to build server-side logic. Also trigger when the user needs API design, data validation, background jobs, file uploads, search, caching strategy, or when a project clearly requires a backend even if the word backend is never used. This skill applies to new projects AND modifications to existing backends.
---

# Enterprise Backend Development Skill

Every backend created or modified using this skill must meet enterprise-grade standards for security, data integrity, performance, and scalability — in that priority order. Backends handle user data, financial transactions, and authentication. There are no shortcuts. Even for MVPs, the security and data integrity foundations must be production-ready from day one.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) based on the project's requirements:

### Framework-Specific Implementation
- `references/nodejs-frameworks.md` — Node.js backends: Express, Fastify, NestJS, Hono
- `references/python-frameworks.md` — Python backends: FastAPI, Django, Flask

### Authentication & Authorization
- `references/auth-sso-mfa.md` — Auth architecture, JWT vs sessions, SSO (SAML/OIDC), MFA/2FA, RBAC, OAuth social login

### Payments & Billing
- `references/payments-stripe.md` — Stripe integration: checkout, subscriptions, webhooks, invoicing, PCI compliance

### Real-Time & Messaging
- `references/realtime-websockets.md` — WebSockets, SSE, pub/sub, message queues, background jobs

### Email & Notifications
- `references/email-notifications.md` — Transactional email (Resend, SendGrid), SMS, push notifications, templates

### API Design
- `references/api-design.md` — REST conventions, GraphQL patterns, versioning, pagination, error handling, OpenAPI/Swagger

Read this SKILL.md first for architecture decisions and standards, then consult the relevant reference files for implementation specifics.

---

## Decision Framework: Choosing the Right Backend Stack

Before writing any server code, evaluate the project requirements and select the appropriate framework.

### Framework Selection Matrix

| Requirement | Best Choice | Why |
|---|---|---|
| TypeScript API with strong typing end-to-end | **Fastify** or **NestJS** | Fastify: fastest Node.js, great TS support. NestJS: structured, decorators, DI |
| Rapid API development, small team | **Fastify** or **Hono** | Minimal boilerplate, high performance, plugin ecosystem |
| Large team, strict architecture needed | **NestJS** | Enforced structure, modules, dependency injection, enterprise patterns |
| Data-heavy / ML / analytics backend | **FastAPI** (Python) | Async, automatic OpenAPI docs, Pydantic validation, Python data ecosystem |
| Full-featured web app with admin | **Django** (Python) | Batteries included: ORM, admin, auth, migrations, templating |
| Microservices | **Fastify** or **Hono** or **Go** | Lightweight, fast startup, low memory footprint |
| Edge / serverless functions | **Hono** | Runs everywhere: Cloudflare Workers, Vercel Edge, Deno, Bun, Node |
| Maximum raw performance | **Go (Gin/Echo)** | Compiled, concurrent by design, minimal overhead |
| Next.js project (fullstack) | **Next.js API Routes** + **tRPC** or server actions | Co-located with frontend, type-safe end-to-end |

### Monolith vs Microservices

**Start with a modular monolith.** Split into microservices only when:
- Different components need independent scaling
- Different teams own different services
- Different technology stacks are genuinely needed
- You have the infrastructure maturity to manage distributed systems

A well-structured monolith with clear module boundaries can be split later. Premature microservices add complexity without proportional benefit.

### REST vs GraphQL vs tRPC

| Pattern | Use When | Avoid When |
|---|---|---|
| **REST** | Public APIs, multi-client, simple CRUD, caching matters | Complex nested data requirements |
| **GraphQL** | Complex data relationships, multiple frontends need different data shapes | Simple CRUD, public API, caching critical |
| **tRPC** | TypeScript monorepo, frontend+backend same team, type safety end-to-end | Non-TypeScript clients, public API |

**Default: REST.** It's universally understood, cacheable, and works with every client.

---

## Priority 1: Security

### Input Validation (Non-Negotiable)
- **Validate every input at the API boundary** using Zod (TS), Pydantic (Python), or equivalent.
- **Validate types, ranges, lengths, and patterns.** An email field must be validated as an email, not just a non-empty string.
- **Reject unexpected fields.** Use strict schemas that strip or reject unknown properties.
- **Sanitize output** — escape HTML in any user-provided data that might be rendered.
- **Never trust the client.** Re-validate everything server-side, even if the frontend already validated.

### Authentication Architecture — Two Environments

The auth strategy depends on the deployment context. Read `references/auth-sso-mfa.md` for full implementation details.

**Environment A: Enterprise / Corporate (Azure AD, Okta, internal tools)**
- **SSO via SAML 2.0 or OIDC** as the primary auth method — users authenticate through the corporate identity provider.
- **Azure AD / Entra ID integration** for Microsoft-ecosystem organizations. Supports Conditional Access, device compliance, and group-based RBAC.
- **No local password storage** — the IdP handles credentials. Your app only receives and validates tokens/assertions.
- **SCIM provisioning** for automatic user sync (create/disable accounts from the IdP directory).
- **Session management** via httpOnly cookies after SSO callback. Session lifetime governed by IdP policy.
- **MFA enforced at the IdP level** — your app does not implement MFA directly; the IdP handles it.

**Environment B: Public / Consumer-Facing (SaaS, e-commerce, user-facing apps)**
- **Local auth (email + password)** with Argon2id hashing as the primary method.
- **OAuth 2.0 social login** (Google, GitHub, Apple, etc.) as an alternative/supplement.
- **Application-managed MFA/2FA (TOTP)** — your app generates secrets, verifies codes, manages recovery.
- **Short-lived access tokens** (15 min) + **long-lived refresh tokens** (7 days) in httpOnly cookies.
- **Rotate refresh tokens on use** (one-time use pattern).
- **Account lockout** after 5 failed attempts (progressive delay, not permanent lock).
- **Force re-authentication** for sensitive actions (password change, email change, payment).

**Both environments share:**
- **httpOnly, Secure, SameSite cookies** for session tokens. Never localStorage.
- **RBAC or ABAC** for authorization — enforced server-side, not UI-side.
- **Resource-level authorization** — User A cannot access User B's data even with valid auth.
- **Audit logging** on all auth events (login, logout, failures, permission changes).

### Authorization
- **Implement RBAC (Role-Based Access Control)** at minimum. ABAC for complex policies.
- **Enterprise SSO apps:** Map IdP groups/roles to application roles automatically.
- **Consumer apps:** Store roles in your database, enforce in middleware.
- **Check permissions in middleware** before route handlers execute.
- **Never rely on hiding UI elements** for security. Backend must enforce every permission.
- **Log all authorization failures** with user ID, resource, and attempted action.

### API Security
- **CORS: strict origin allowlist.** Never use `*` in production.
- **Rate limiting on all endpoints.** Stricter on auth endpoints (5/min login, 3/min password reset).
- **Helmet middleware** (Node.js) or equivalent security headers for every response.
- **CSRF protection** for cookie-based auth (double submit cookie or SameSite=Strict).
- **Request size limits** — reject payloads > 1MB unless explicitly needed (file uploads).
- **SQL injection prevention** — use parameterized queries exclusively. ORMs handle this.
- **Dependency scanning** — `npm audit` / `pip audit` in CI pipeline.

### Secrets Management
- **Environment variables** for all secrets. Never in code, config files, or git.
- **Use a secrets manager** in production (AWS Secrets Manager, HashiCorp Vault, Doppler).
- **Rotate secrets regularly.** Automate rotation where possible.
- **Different secrets per environment.** Dev, staging, and production must have separate credentials.

---

## Priority 2: Data Integrity

### Database Transactions
- **Wrap multi-step operations in transactions.** If step 3 fails, steps 1-2 must roll back.
- **Use optimistic concurrency control** for collaborative editing (version numbers / ETags).
- **Idempotent operations.** Retry-safe endpoints using idempotency keys.
- **Soft delete by default.** Add `deletedAt` column instead of destroying records.

### Data Validation Flow

```
Client Input → API Boundary Validation (Zod/Pydantic) → Business Logic Validation → Database Constraints
```

All three layers must enforce rules. API validation catches malformed data, business logic catches invalid state transitions, database constraints are the final safety net.

### Audit Logging
- **Log every write operation** with: who, what, when, from where (IP).
- **Immutable audit log.** Append-only, never delete audit records.
- **Structured logging** (JSON format) for machine parsing.
- **Log levels:** ERROR for failures, WARN for degraded, INFO for business events, DEBUG for development.

---

## Priority 3: Performance

### Response Time Targets
- **API responses:** < 200ms for simple CRUD, < 500ms for complex queries
- **Auth endpoints:** < 300ms (password hashing is intentionally slow)
- **File uploads:** Streaming, no timeout for large files
- **WebSocket messages:** < 50ms server-side processing

### Caching Strategy
- **HTTP caching headers** for cacheable GET responses (ETags, Cache-Control).
- **Redis for application caching** — session data, frequently accessed configs, rate limit counters.
- **Database query caching** via ORM or Redis with TTL.
- **Cache invalidation** on write — invalidate related cache keys when data changes.

### Database Performance
- **Index every column used in WHERE, JOIN, or ORDER BY.**
- **Use `EXPLAIN ANALYZE`** on slow queries.
- **Connection pooling** is mandatory (PgBouncer or ORM pool).
- **N+1 query prevention** — use eager loading / joins / DataLoader pattern.
- **Pagination** for all list endpoints (cursor-based preferred, offset for simple cases).

### Background Processing
- **Move heavy work off the request path.** Email sending, PDF generation, data aggregation → background jobs.
- **Use a proper job queue** (BullMQ for Node.js, Celery for Python, or cloud: AWS SQS + Lambda).
- **Implement retry with backoff** for failed jobs.
- **Dead letter queue** for permanently failed jobs.

---

## Priority 4: Scalability

### Horizontal Scaling Readiness
- **Stateless API servers.** No in-memory sessions (use Redis).
- **Shared-nothing architecture.** Any server instance can handle any request.
- **Database connection pooling** with limits per instance.
- **File storage on object storage** (S3, GCS), never local filesystem.

### API Structure (Modular Monolith)

```
src/
├── modules/
│   ├── auth/
│   │   ├── auth.controller.ts    # Route handlers
│   │   ├── auth.service.ts       # Business logic
│   │   ├── auth.schema.ts        # Zod validation schemas
│   │   ├── auth.middleware.ts     # Auth-specific middleware
│   │   └── auth.test.ts
│   ├── users/
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   ├── users.schema.ts
│   │   └── users.test.ts
│   ├── payments/
│   │   ├── payments.controller.ts
│   │   ├── payments.service.ts
│   │   ├── payments.webhook.ts   # Stripe webhook handler
│   │   └── payments.test.ts
│   └── notifications/
│       ├── notifications.service.ts
│       ├── email.provider.ts
│       └── notifications.test.ts
├── middleware/
│   ├── rate-limiter.ts
│   ├── cors.ts
│   ├── error-handler.ts
│   ├── request-logger.ts
│   └── auth-guard.ts
├── lib/
│   ├── database.ts              # DB connection setup
│   ├── redis.ts                 # Redis client
│   ├── logger.ts                # Structured logger (pino/winston)
│   ├── email.ts                 # Email service client
│   └── queue.ts                 # Job queue setup
├── types/
│   └── index.ts
├── config/
│   ├── env.ts                   # Typed environment variables
│   └── constants.ts
├── tests/
│   ├── setup.ts
│   ├── helpers/
│   └── integration/
└── index.ts                     # App entry point
```

### Environment Configuration

```typescript
// src/config/env.ts
import { z } from 'zod'

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  STRIPE_SECRET_KEY: z.string().startsWith('sk_'),
  STRIPE_WEBHOOK_SECRET: z.string().startsWith('whsec_'),
  RESEND_API_KEY: z.string(),
  CORS_ORIGINS: z.string().transform(s => s.split(',')),
})

export const env = envSchema.parse(process.env)
export type Env = z.infer<typeof envSchema>
```

### Error Handling Pattern

```typescript
// Typed application errors
class AppError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public code: string,
    public details?: unknown
  ) {
    super(message)
    this.name = 'AppError'
  }
}

// Specific error factories
export const errors = {
  notFound: (resource: string) => new AppError(404, `${resource} not found`, 'NOT_FOUND'),
  unauthorized: (msg = 'Unauthorized') => new AppError(401, msg, 'UNAUTHORIZED'),
  forbidden: (msg = 'Forbidden') => new AppError(403, msg, 'FORBIDDEN'),
  validation: (details: unknown) => new AppError(400, 'Validation failed', 'VALIDATION_ERROR', details),
  conflict: (msg: string) => new AppError(409, msg, 'CONFLICT'),
  rateLimit: () => new AppError(429, 'Too many requests', 'RATE_LIMITED'),
  internal: (msg = 'Internal server error') => new AppError(500, msg, 'INTERNAL_ERROR'),
}

// Global error handler middleware
function errorHandler(err: Error, req: Request, res: Response) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: { code: err.code, message: err.message, details: err.details },
    })
  }

  // Unknown error — log full details, return generic message
  logger.error({ err, req: { method: req.method, url: req.url } }, 'Unhandled error')
  return res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'An unexpected error occurred' },
  })
}
```

---

## Testing Requirements

### Test Pyramid
- **Unit tests** (70%): Service functions, validation schemas, utilities
- **Integration tests** (25%): API endpoints with real database (use test containers)
- **E2E tests** (5%): Critical paths (auth flow, payment flow)

### Test Database Strategy
- Use **Docker test containers** or **in-memory SQLite** for integration tests
- **Fresh database per test suite** — migrate, seed, test, tear down
- **Never test against production** or shared databases

### What Must Be Tested
- [ ] Every auth endpoint (login, register, refresh, logout, password reset)
- [ ] Every authorization rule (role checks, resource ownership)
- [ ] Payment webhook handling (all event types)
- [ ] Input validation rejection (malformed data returns 400)
- [ ] Rate limiting triggers correctly
- [ ] Error responses match expected format
- [ ] Database transactions roll back on failure

---

## Integration with Other Enterprise Skills

- **enterprise-database**: Backend connects to databases via ORMs/drivers configured in the database skill. Use connection pooling, migrations, and security patterns from that skill.
- **enterprise-frontend**: Backend provides the API that frontend consumes. Define clear contracts via OpenAPI spec or shared TypeScript types.
- **enterprise-deployment**: Backend runs as a Docker container or Node/Python process behind nginx. The deployment skill handles containerization, process management, and environment configuration.

---

## Verification Checklist

Before considering any backend work complete, verify:

- [ ] All inputs validated with typed schemas (Zod/Pydantic)
- [ ] Auth endpoints protected against brute force (rate limiting + lockout)
- [ ] Passwords hashed with Argon2id or bcrypt (12+ rounds)
- [ ] CORS configured with explicit origin allowlist
- [ ] All secrets from environment variables, none in code
- [ ] Database queries use parameterized inputs (no string concatenation)
- [ ] Error responses don't leak internal details (stack traces, SQL)
- [ ] Structured logging on all endpoints
- [ ] Health check endpoint returns DB + Redis connectivity status
- [ ] All test suites pass with >80% coverage on services
