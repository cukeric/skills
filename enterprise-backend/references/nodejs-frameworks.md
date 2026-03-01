# Node.js Backend Frameworks Reference

## Framework Comparison

| Feature | Fastify | Express | NestJS | Hono |
|---|---|---|---|---|
| Performance | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| TypeScript | Built-in | Requires setup | Built-in | Built-in |
| Validation | Plugin (Zod/Typebox) | Manual | Built-in (class-validator) | Built-in (Zod) |
| Structure | Flexible | Flexible | Enforced (modules/DI) | Flexible |
| Ecosystem | Large | Massive | Large | Growing |
| Learning Curve | Low | Low | Medium-High | Low |
| Best For | APIs, microservices | Legacy, simple APIs | Large teams, enterprise | Edge, serverless |

---

## Fastify (Recommended Default)

### Project Setup

```bash
mkdir my-api && cd my-api
pnpm init
pnpm add fastify @fastify/cors @fastify/helmet @fastify/rate-limit @fastify/cookie @fastify/jwt @fastify/swagger @fastify/swagger-ui zod pino
pnpm add -D typescript @types/node tsx vitest
```

### App Structure

```typescript
// src/index.ts
import Fastify from 'fastify'
import cors from '@fastify/cors'
import helmet from '@fastify/helmet'
import rateLimit from '@fastify/rate-limit'
import cookie from '@fastify/cookie'
import { env } from './config/env'
import { authRoutes } from './modules/auth/auth.controller'
import { userRoutes } from './modules/users/users.controller'
import { errorHandler } from './middleware/error-handler'

const app = Fastify({
  logger: {
    level: env.NODE_ENV === 'production' ? 'info' : 'debug',
    transport: env.NODE_ENV !== 'production' ? { target: 'pino-pretty' } : undefined,
  },
})

// Plugins
await app.register(helmet)
await app.register(cors, { origin: env.CORS_ORIGINS, credentials: true })
await app.register(rateLimit, { max: 100, timeWindow: '1 minute' })
await app.register(cookie, { secret: env.COOKIE_SECRET })

// Routes
await app.register(authRoutes, { prefix: '/api/auth' })
await app.register(userRoutes, { prefix: '/api/users' })

// Health check
app.get('/health', async () => {
  const dbOk = await checkDatabase()
  const redisOk = await checkRedis()
  return { status: dbOk && redisOk ? 'healthy' : 'degraded', db: dbOk, redis: redisOk }
})

// Error handler
app.setErrorHandler(errorHandler)

// Start
await app.listen({ port: env.PORT, host: '0.0.0.0' })
```

### Route Module Pattern

```typescript
// src/modules/users/users.controller.ts
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { UsersService } from './users.service'
import { authGuard } from '../../middleware/auth-guard'
import { requireRole } from '../../middleware/require-role'

const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(100),
  role: z.enum(['admin', 'user', 'viewer']),
})

const QuerySchema = z.object({
  page: z.coerce.number().min(1).default(1),
  limit: z.coerce.number().min(1).max(100).default(20),
  search: z.string().optional(),
})

export const userRoutes: FastifyPluginAsync = async (app) => {
  const service = new UsersService()

  // All routes require auth
  app.addHook('onRequest', authGuard)

  app.get('/', async (req) => {
    const query = QuerySchema.parse(req.query)
    return service.list(query)
  })

  app.get<{ Params: { id: string } }>('/:id', async (req) => {
    return service.getById(req.params.id)
  })

  app.post('/', {
    preHandler: [requireRole('admin')],
  }, async (req, reply) => {
    const body = CreateUserSchema.parse(req.body)
    const user = await service.create(body)
    return reply.status(201).send(user)
  })

  app.delete<{ Params: { id: string } }>('/:id', {
    preHandler: [requireRole('admin')],
  }, async (req, reply) => {
    await service.softDelete(req.params.id)
    return reply.status(204).send()
  })
}
```

### Service Layer Pattern

```typescript
// src/modules/users/users.service.ts
import { db } from '../../lib/database'
import { errors } from '../../lib/errors'
import { logger } from '../../lib/logger'

export class UsersService {
  async list({ page, limit, search }: { page: number; limit: number; search?: string }) {
    const offset = (page - 1) * limit
    const where = search ? { name: { contains: search, mode: 'insensitive' } } : {}

    const [users, total] = await Promise.all([
      db.user.findMany({ where, skip: offset, take: limit, orderBy: { createdAt: 'desc' } }),
      db.user.count({ where }),
    ])

    return { users, total, page, limit, totalPages: Math.ceil(total / limit) }
  }

  async getById(id: string) {
    const user = await db.user.findUnique({ where: { id } })
    if (!user) throw errors.notFound('User')
    return user
  }

  async create(data: { email: string; name: string; role: string }) {
    const existing = await db.user.findUnique({ where: { email: data.email } })
    if (existing) throw errors.conflict('Email already in use')

    const user = await db.user.create({ data })
    logger.info({ userId: user.id, email: user.email }, 'User created')
    return user
  }

  async softDelete(id: string) {
    const user = await this.getById(id)
    await db.user.update({ where: { id }, data: { deletedAt: new Date() } })
    logger.info({ userId: id }, 'User soft deleted')
  }
}
```

### Middleware Patterns

```typescript
// src/middleware/auth-guard.ts
import type { FastifyRequest, FastifyReply } from 'fastify'
import { verifySession } from '../lib/auth'

export async function authGuard(req: FastifyRequest, reply: FastifyReply) {
  const sessionToken = req.cookies.session
  if (!sessionToken) return reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'Authentication required' } })

  const user = await verifySession(sessionToken)
  if (!user) return reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'Invalid or expired session' } })

  req.user = user  // Attach to request for route handlers
}

// src/middleware/require-role.ts
export function requireRole(...roles: string[]) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Insufficient permissions' } })
    }
  }
}

// src/middleware/error-handler.ts
import type { FastifyError, FastifyRequest, FastifyReply } from 'fastify'
import { ZodError } from 'zod'
import { AppError } from '../lib/errors'
import { logger } from '../lib/logger'

export function errorHandler(error: FastifyError, req: FastifyRequest, reply: FastifyReply) {
  if (error instanceof ZodError) {
    return reply.status(400).send({
      error: { code: 'VALIDATION_ERROR', message: 'Invalid input', details: error.flatten() },
    })
  }
  if (error instanceof AppError) {
    return reply.status(error.statusCode).send({
      error: { code: error.code, message: error.message, details: error.details },
    })
  }
  logger.error({ err: error, url: req.url, method: req.method }, 'Unhandled error')
  return reply.status(500).send({ error: { code: 'INTERNAL_ERROR', message: 'An unexpected error occurred' } })
}
```

---

## NestJS (Large Teams / Complex Architecture)

### Setup
```bash
npx @nestjs/cli new my-api
pnpm add @nestjs/config @nestjs/passport @nestjs/jwt @nestjs/swagger class-validator class-transformer
```

### Module Pattern
```typescript
// src/users/users.module.ts
@Module({
  imports: [DatabaseModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}

// src/users/users.controller.ts
@Controller('users')
@UseGuards(AuthGuard)
export class UsersController {
  constructor(private usersService: UsersService) {}

  @Get() findAll(@Query() query: ListUsersDto) { return this.usersService.list(query) }
  @Get(':id') findOne(@Param('id') id: string) { return this.usersService.getById(id) }
  @Post() @Roles('admin') create(@Body() dto: CreateUserDto) { return this.usersService.create(dto) }
}
```

---

## Hono (Edge / Serverless)

### Setup
```bash
pnpm create hono my-api  # Choose: nodejs or cloudflare-workers
pnpm add zod @hono/zod-validator
```

### Pattern
```typescript
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { zValidator } from '@hono/zod-validator'
import { z } from 'zod'

const app = new Hono()
app.use('*', cors({ origin: ['https://app.example.com'], credentials: true }))
app.use('*', logger())

const usersRoute = new Hono()
  .get('/', async (c) => { /* list users */ })
  .post('/', zValidator('json', CreateUserSchema), async (c) => {
    const data = c.req.valid('json')
    /* create user */
  })

app.route('/api/users', usersRoute)
export default app
```

---

## Testing (All Frameworks)

```typescript
// Integration test pattern using Vitest
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { buildApp } from '../src/app'

describe('Users API', () => {
  let app: ReturnType<typeof buildApp>

  beforeAll(async () => { app = await buildApp(); await app.ready() })
  afterAll(async () => { await app.close() })

  it('GET /api/users requires auth', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/users' })
    expect(res.statusCode).toBe(401)
  })

  it('POST /api/users validates input', async () => {
    const res = await app.inject({
      method: 'POST', url: '/api/users',
      headers: { cookie: 'session=valid-test-session' },
      payload: { email: 'not-an-email' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error.code).toBe('VALIDATION_ERROR')
  })
})
```
