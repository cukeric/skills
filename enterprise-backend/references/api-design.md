# API Design Reference

## REST API Conventions

### URL Structure

```
GET    /api/v1/users              # List users (paginated)
GET    /api/v1/users/:id          # Get single user
POST   /api/v1/users              # Create user
PUT    /api/v1/users/:id          # Full update (replace)
PATCH  /api/v1/users/:id          # Partial update
DELETE /api/v1/users/:id          # Delete user (soft delete)

# Nested resources
GET    /api/v1/users/:id/orders         # List user's orders
POST   /api/v1/users/:id/orders         # Create order for user

# Actions that don't fit CRUD (use verbs as exception)
POST   /api/v1/users/:id/deactivate     # Custom action
POST   /api/v1/reports/generate          # Trigger async process
```

### Naming Rules
- **Plural nouns** for resources: `/users`, `/orders`, `/invoices` (not `/user`, `/order`)
- **Lowercase with hyphens**: `/payment-methods` (not `/paymentMethods` or `/payment_methods`)
- **No trailing slashes**: `/api/v1/users` (not `/api/v1/users/`)
- **Nest max 2 levels deep**: `/users/:id/orders` (not `/users/:id/orders/:orderId/items/:itemId`)
- **Version prefix**: `/api/v1/...` — increment major version for breaking changes

### HTTP Methods & Status Codes

| Method | Action | Success | Body |
|---|---|---|---|
| GET | Read | 200 OK | Resource(s) |
| POST | Create | 201 Created | Created resource |
| PUT | Full update | 200 OK | Updated resource |
| PATCH | Partial update | 200 OK | Updated resource |
| DELETE | Soft delete | 204 No Content | Empty |

### Error Status Codes

| Code | Meaning | When |
|---|---|---|
| 400 | Bad Request | Validation failed, malformed input |
| 401 | Unauthorized | No auth token or invalid token |
| 403 | Forbidden | Valid auth but insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate email, version conflict |
| 422 | Unprocessable Entity | Valid syntax but invalid business logic |
| 429 | Too Many Requests | Rate limited |
| 500 | Internal Server Error | Unexpected server failure |

---

## Response Formats

### Success: Single Resource

```json
{
  "id": "usr_a1b2c3d4",
  "email": "jane@company.com",
  "name": "Jane Doe",
  "role": "admin",
  "createdAt": "2024-06-15T10:30:00Z",
  "updatedAt": "2024-06-20T14:22:00Z"
}
```

### Success: List (Paginated)

```json
{
  "data": [
    { "id": "usr_a1b2c3d4", "email": "jane@company.com", "name": "Jane Doe" },
    { "id": "usr_e5f6g7h8", "email": "bob@company.com", "name": "Bob Smith" }
  ],
  "pagination": {
    "total": 248,
    "page": 1,
    "limit": 20,
    "totalPages": 13,
    "hasNext": true,
    "hasPrev": false
  }
}
```

### Cursor-Based Pagination (Preferred for Large Datasets)

```json
{
  "data": [ /* items */ ],
  "pagination": {
    "nextCursor": "eyJpZCI6InVzcl94eXoifQ==",
    "prevCursor": null,
    "hasNext": true,
    "hasPrev": false,
    "limit": 20
  }
}
```

**Why cursor > offset:** Offset pagination breaks when rows are inserted/deleted between pages. Cursor pagination (usually based on `id` or `createdAt`) is stable and performant.

```typescript
// Cursor pagination implementation
app.get('/api/v1/users', async (req) => {
  const { limit = 20, cursor, direction = 'next' } = req.query

  const decodedCursor = cursor ? JSON.parse(Buffer.from(cursor, 'base64url').toString()) : null

  const where = decodedCursor
    ? { createdAt: direction === 'next' ? { lt: decodedCursor.createdAt } : { gt: decodedCursor.createdAt } }
    : {}

  const users = await db.user.findMany({
    where,
    take: limit + 1,  // Fetch one extra to detect hasNext
    orderBy: { createdAt: 'desc' },
  })

  const hasNext = users.length > limit
  if (hasNext) users.pop()

  const nextCursor = hasNext
    ? Buffer.from(JSON.stringify({ createdAt: users[users.length - 1].createdAt })).toString('base64url')
    : null

  return { data: users, pagination: { nextCursor, hasNext, limit } }
})
```

### Error Response (Consistent Format)

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input",
    "details": {
      "fieldErrors": {
        "email": ["Invalid email format"],
        "name": ["Must be at least 2 characters"]
      }
    }
  }
}
```

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "User not found"
  }
}
```

Error response must **never** contain: stack traces, SQL queries, internal IDs, file paths, or environment details.

---

## Request Validation Pattern

```typescript
// Define schemas once, use everywhere
const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(100).trim(),
  role: z.enum(['admin', 'user', 'viewer']).default('user'),
})

const UpdateUserSchema = CreateUserSchema.partial()  // All fields optional for PATCH

const ListQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().max(200).optional(),
  sort: z.enum(['createdAt', 'name', 'email']).default('createdAt'),
  order: z.enum(['asc', 'desc']).default('desc'),
})

// Validate at route level — fail fast
app.post('/api/v1/users', async (req, reply) => {
  const body = CreateUserSchema.parse(req.body)   // Throws ZodError → caught by error handler
  const user = await usersService.create(body)
  return reply.status(201).send(user)
})
```

---

## API Versioning

### Strategy: URL Path Versioning (Recommended)

```
/api/v1/users   ← Current stable version
/api/v2/users   ← Breaking changes only
```

### When to Bump Version
- Removing a field from responses
- Changing a field's type
- Changing URL structure
- Changing authentication mechanism
- Removing an endpoint

### When NOT to Bump Version
- Adding new optional fields to responses
- Adding new endpoints
- Adding new optional query parameters
- Bug fixes

### Deprecation Process
1. Announce deprecation with `Deprecation` header and `Sunset` date
2. Keep old version running for minimum 6 months
3. Send email to API consumers 90, 30, and 7 days before sunset
4. Return `410 Gone` after sunset date

```typescript
// Deprecation header middleware
function deprecatedVersion(sunsetDate: string) {
  return (req, reply, next) => {
    reply.header('Deprecation', 'true')
    reply.header('Sunset', sunsetDate)
    reply.header('Link', '</api/v2/docs>; rel="successor-version"')
    next()
  }
}

app.register(v1Routes, { prefix: '/api/v1', preHandler: [deprecatedVersion('2025-06-01')] })
app.register(v2Routes, { prefix: '/api/v2' })
```

---

## OpenAPI / Swagger Documentation

### Auto-Generation (Fastify)

```bash
pnpm add @fastify/swagger @fastify/swagger-ui
```

```typescript
await app.register(swagger, {
  openapi: {
    info: { title: 'Enterprise API', version: '1.0.0', description: 'API documentation' },
    servers: [{ url: env.API_URL }],
    components: {
      securitySchemes: {
        cookieAuth: { type: 'apiKey', in: 'cookie', name: 'session' },
      },
    },
    security: [{ cookieAuth: [] }],
  },
})

await app.register(swaggerUi, {
  routePrefix: '/api/docs',
  uiConfig: { docExpansion: 'list', deepLinking: true },
})
```

### Auto-Generation (FastAPI — built in)

```python
# FastAPI generates OpenAPI docs automatically from type hints
# Available at /docs (Swagger UI) and /redoc (ReDoc)
app = FastAPI(
    title="Enterprise API",
    version="1.0.0",
    docs_url="/api/docs" if settings.DEBUG else None,   # Disable in production
    redoc_url="/api/redoc" if settings.DEBUG else None,
)
```

---

## Rate Limiting Strategy

```typescript
// Global rate limit
await app.register(rateLimit, { max: 100, timeWindow: '1 minute' })

// Per-route overrides
app.post('/api/v1/auth/login', {
  config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
}, loginHandler)

app.post('/api/v1/auth/password-reset', {
  config: { rateLimit: { max: 3, timeWindow: '1 minute' } },
}, resetHandler)

app.post('/api/v1/auth/register', {
  config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
}, registerHandler)

// API heavy endpoints (reports, exports)
app.get('/api/v1/reports/export', {
  config: { rateLimit: { max: 5, timeWindow: '1 hour' } },
}, exportHandler)
```

### Rate Limit Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 42
X-RateLimit-Reset: 1640000000
Retry-After: 30              (only on 429 responses)
```

---

## CORS Configuration

```typescript
// Production: strict allowlist
await app.register(cors, {
  origin: env.CORS_ORIGINS,   // ['https://app.yoursite.com', 'https://admin.yoursite.com']
  credentials: true,           // Required for cookie-based auth
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  exposedHeaders: ['X-RateLimit-Limit', 'X-RateLimit-Remaining'],
  maxAge: 86400,              // Preflight cache: 24 hours
})
```

**Never use `origin: '*'` with `credentials: true`.** It won't work (browser blocks it) and signals a misconfiguration.

---

## Health Check Endpoint

```typescript
app.get('/health', async () => {
  const checks = await Promise.allSettled([
    db.$queryRaw`SELECT 1`.then(() => true),
    redis.ping().then(() => true),
  ])

  const [dbOk, redisOk] = checks.map(r => r.status === 'fulfilled' && r.value === true)
  const healthy = dbOk && redisOk

  return {
    status: healthy ? 'healthy' : 'degraded',
    timestamp: new Date().toISOString(),
    checks: {
      database: dbOk ? 'ok' : 'fail',
      redis: redisOk ? 'ok' : 'fail',
    },
  }
})

// Liveness probe (for k8s/load balancers — always 200 if process is running)
app.get('/healthz', async () => ({ status: 'alive' }))

// Readiness probe (for k8s — 200 only if dependencies are connected)
app.get('/readyz', async (req, reply) => {
  const healthy = await checkAllDependencies()
  return reply.status(healthy ? 200 : 503).send({ status: healthy ? 'ready' : 'not ready' })
})
```

---

## Request Logging Middleware

```typescript
// Structured request logging (pino)
app.addHook('onResponse', (req, reply, done) => {
  req.log.info({
    method: req.method,
    url: req.url,
    statusCode: reply.statusCode,
    responseTime: reply.elapsedTime,
    userId: req.user?.id,
    ip: req.ip,
    userAgent: req.headers['user-agent'],
  }, 'request completed')
  done()
})
```

**Never log:** passwords, tokens, credit card numbers, request bodies containing PII (redact sensitive fields).

---

## File Upload Pattern

```typescript
// Use multipart/form-data with size limits
await app.register(multipart, {
  limits: {
    fileSize: 10 * 1024 * 1024,  // 10MB max
    files: 5,                     // Max 5 files per request
  },
})

app.post('/api/v1/uploads', { preHandler: [authGuard] }, async (req, reply) => {
  const file = await req.file()
  if (!file) throw errors.validation('No file provided')

  // Validate MIME type
  const allowed = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
  if (!allowed.includes(file.mimetype)) throw errors.validation('File type not allowed')

  // Stream to S3 (never store on local filesystem in production)
  const key = `uploads/${req.user.id}/${Date.now()}-${file.filename}`
  await uploadToS3(file.file, key, file.mimetype)

  return reply.status(201).send({ url: `${env.CDN_URL}/${key}`, key })
})
```

---

## API Design Checklist

- [ ] Consistent URL naming (plural nouns, hyphens, lowercase)
- [ ] Standard HTTP methods and status codes
- [ ] Consistent error response format across all endpoints
- [ ] Pagination on all list endpoints (cursor preferred)
- [ ] Input validation with typed schemas on every endpoint
- [ ] Rate limiting (global + per-endpoint for sensitive routes)
- [ ] CORS strict origin allowlist
- [ ] OpenAPI docs generated automatically
- [ ] Health check, liveness, and readiness endpoints
- [ ] Request logging (structured, no PII)
- [ ] File uploads streamed to object storage, not local disk
- [ ] API versioning strategy documented and implemented
