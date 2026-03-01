# Integration Testing Reference

## What Integration Tests Cover

Integration tests verify that multiple components work together correctly — your API routes hit real databases, your auth middleware actually blocks unauthorized requests, and your service layer interacts with real (containerized) dependencies.

---

## Testcontainers Setup (Real Databases in Docker)

```bash
pnpm add -D testcontainers @testcontainers/postgresql @testcontainers/redis
```

### Global Setup: Start Containers Once

```typescript
// tests/integration/setup.ts
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql'
import { RedisContainer, type StartedRedisContainer } from '@testcontainers/redis'
import { Pool } from 'pg'
import { createClient } from 'redis'
import { readFileSync } from 'fs'
import path from 'path'

let pgContainer: StartedPostgreSqlContainer
let redisContainer: StartedRedisContainer
let pool: Pool
let redis: ReturnType<typeof createClient>

export async function setupTestDatabase() {
  // Start PostgreSQL container
  pgContainer = await new PostgreSqlContainer('postgres:16-alpine')
    .withDatabase('testdb')
    .withUsername('test')
    .withPassword('test')
    .withExposedPorts(5432)
    .start()

  // Create connection pool
  pool = new Pool({ connectionString: pgContainer.getConnectionUri() })

  // Run migrations
  const migrationSQL = readFileSync(path.join(__dirname, '../../migrations/001_initial.sql'), 'utf-8')
  await pool.query(migrationSQL)

  return pool
}

export async function setupTestRedis() {
  redisContainer = await new RedisContainer('redis:7-alpine').start()
  redis = createClient({ url: redisContainer.getConnectionUrl() })
  await redis.connect()
  return redis
}

export async function teardownTestDatabase() {
  await pool?.end()
  await pgContainer?.stop()
}

export async function teardownTestRedis() {
  await redis?.quit()
  await redisContainer?.stop()
}

export async function cleanDatabase() {
  // Truncate all tables between tests (fast, preserves schema)
  const tables = await pool.query(`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename != 'schema_migrations'
  `)
  if (tables.rows.length > 0) {
    const tableNames = tables.rows.map(r => `"${r.tablename}"`).join(', ')
    await pool.query(`TRUNCATE ${tableNames} CASCADE`)
  }
}

export { pool, redis }
```

### Vitest Config for Integration Tests

```typescript
// tests/integration/vitest.config.ts (optional — or use project root config)
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['tests/integration/**/*.test.ts'],
    testTimeout: 30000,        // Containers need more time
    hookTimeout: 60000,        // Container startup
    pool: 'forks',
    poolOptions: { forks: { maxForks: 1 } },  // Sequential — shared DB
    globalSetup: ['./tests/integration/global-setup.ts'],
  },
})
```

### Global Setup/Teardown (Start Containers Once for All Tests)

```typescript
// tests/integration/global-setup.ts
import { setupTestDatabase, setupTestRedis, teardownTestDatabase, teardownTestRedis } from './setup'

export async function setup() {
  const pool = await setupTestDatabase()
  const redis = await setupTestRedis()

  // Store connection URIs for test processes
  process.env.DATABASE_URL = pool.options?.connectionString || ''
  process.env.REDIS_URL = redis.options?.url || ''

  return async () => {
    await teardownTestRedis()
    await teardownTestDatabase()
  }
}
```

---

## API Route Testing

### With Fastify .inject() (Recommended for Fastify)

```typescript
// tests/integration/api/users.test.ts
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import { buildApp } from '@/app'
import { setupTestDatabase, teardownTestDatabase, cleanDatabase, pool } from '../setup'
import { buildUser } from '@tests/fixtures/factory'

describe('Users API', () => {
  let app: ReturnType<typeof buildApp>

  beforeAll(async () => {
    await setupTestDatabase()
    app = await buildApp({ database: pool })
  })

  afterAll(async () => {
    await app.close()
    await teardownTestDatabase()
  })

  beforeEach(async () => {
    await cleanDatabase()
  })

  describe('POST /api/users', () => {
    it('creates a user and returns 201', async () => {
      const response = await app.inject({
        method: 'POST',
        url: '/api/users',
        headers: { authorization: `Bearer ${getTestAdminToken()}` },
        payload: { name: 'Jane Doe', email: 'jane@test.com', password: 'SecurePass123!' },
      })

      expect(response.statusCode).toBe(201)
      const body = response.json()
      expect(body.name).toBe('Jane Doe')
      expect(body.email).toBe('jane@test.com')
      expect(body).not.toHaveProperty('password')

      // Verify in database
      const dbUser = await pool.query('SELECT * FROM users WHERE email = $1', ['jane@test.com'])
      expect(dbUser.rows).toHaveLength(1)
    })

    it('returns 409 for duplicate email', async () => {
      // Seed existing user
      await pool.query("INSERT INTO users (name, email, password_hash) VALUES ('Existing', 'jane@test.com', 'hash')")

      const response = await app.inject({
        method: 'POST',
        url: '/api/users',
        headers: { authorization: `Bearer ${getTestAdminToken()}` },
        payload: { name: 'Jane', email: 'jane@test.com', password: 'SecurePass123!' },
      })

      expect(response.statusCode).toBe(409)
    })

    it('returns 401 without auth token', async () => {
      const response = await app.inject({
        method: 'POST',
        url: '/api/users',
        payload: { name: 'Jane', email: 'jane@test.com', password: 'SecurePass123!' },
      })

      expect(response.statusCode).toBe(401)
    })

    it('returns 400 for invalid input', async () => {
      const response = await app.inject({
        method: 'POST',
        url: '/api/users',
        headers: { authorization: `Bearer ${getTestAdminToken()}` },
        payload: { name: '', email: 'not-an-email' },
      })

      expect(response.statusCode).toBe(400)
      expect(response.json().errors).toBeDefined()
    })
  })

  describe('GET /api/users/:id', () => {
    it('returns user by ID', async () => {
      const { rows } = await pool.query(
        "INSERT INTO users (name, email, password_hash) VALUES ('Jane', 'jane@test.com', 'hash') RETURNING id"
      )

      const response = await app.inject({
        method: 'GET',
        url: `/api/users/${rows[0].id}`,
        headers: { authorization: `Bearer ${getTestAdminToken()}` },
      })

      expect(response.statusCode).toBe(200)
      expect(response.json().name).toBe('Jane')
    })

    it('returns 404 for non-existent user', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/api/users/00000000-0000-0000-0000-000000000000',
        headers: { authorization: `Bearer ${getTestAdminToken()}` },
      })

      expect(response.statusCode).toBe(404)
    })
  })
})
```

### With Supertest (Framework-Agnostic)

```bash
pnpm add -D supertest @types/supertest
```

```typescript
import request from 'supertest'
import { createApp } from '@/app'

const app = createApp()

describe('Auth API', () => {
  it('login returns JWT token', async () => {
    // Seed user first
    await seedUser({ email: 'test@test.com', password: 'hashed' })

    const response = await request(app)
      .post('/api/auth/login')
      .send({ email: 'test@test.com', password: 'SecurePass123!' })
      .expect(200)

    expect(response.body.token).toBeDefined()
    expect(response.body.token).toMatch(/^eyJ/)  // JWT format
  })
})
```

---

## Database Operation Testing

```typescript
// tests/integration/api/database-operations.test.ts
describe('Order Repository', () => {
  const repo = new OrderRepository(pool)

  beforeEach(async () => {
    await cleanDatabase()
    // Seed required foreign key data
    await pool.query("INSERT INTO users (id, name, email, password_hash) VALUES ('user-1', 'Test', 'test@test.com', 'hash')")
  })

  it('creates order with items in a transaction', async () => {
    const order = await repo.createOrder({
      userId: 'user-1',
      items: [
        { productId: 'prod-1', quantity: 2, price: 29.99 },
        { productId: 'prod-2', quantity: 1, price: 49.99 },
      ],
    })

    expect(order.total).toBeCloseTo(109.97)
    expect(order.items).toHaveLength(2)

    // Verify in database
    const dbOrder = await pool.query('SELECT * FROM orders WHERE id = $1', [order.id])
    expect(dbOrder.rows[0].total).toBe('109.97')
  })

  it('rolls back transaction on item failure', async () => {
    await expect(repo.createOrder({
      userId: 'user-1',
      items: [{ productId: 'nonexistent', quantity: 1, price: 10 }],
    })).rejects.toThrow()

    // Verify nothing was created
    const orders = await pool.query('SELECT COUNT(*) FROM orders')
    expect(parseInt(orders.rows[0].count)).toBe(0)
  })
})
```

---

## Auth Testing Helpers

```typescript
// tests/integration/helpers.ts
import jwt from 'jsonwebtoken'

const JWT_SECRET = process.env.JWT_SECRET || 'test-secret'

export function getTestToken(overrides: Partial<{ userId: string; role: string; tenantId: string }> = {}) {
  return jwt.sign({
    sub: overrides.userId || 'test-user-id',
    role: overrides.role || 'user',
    tenantId: overrides.tenantId || 'test-tenant',
  }, JWT_SECRET, { expiresIn: '1h' })
}

export function getTestAdminToken() {
  return getTestToken({ role: 'admin' })
}

// Usage: headers: { authorization: `Bearer ${getTestToken({ role: 'admin' })}` }
```

---

## Seed Data Utilities

```typescript
// tests/fixtures/seeds.ts
export async function seedUser(pool: Pool, overrides: Partial<User> = {}) {
  const user = buildUser(overrides)
  const result = await pool.query(
    'INSERT INTO users (id, name, email, password_hash, role) VALUES ($1, $2, $3, $4, $5) RETURNING *',
    [user.id, user.name, user.email, 'hashed-password', user.role]
  )
  return result.rows[0]
}

export async function seedOrder(pool: Pool, userId: string, overrides: Partial<Order> = {}) {
  const order = buildOrder({ userId, ...overrides })
  const result = await pool.query(
    'INSERT INTO orders (id, user_id, total, status) VALUES ($1, $2, $3, $4) RETURNING *',
    [order.id, order.userId, order.total, order.status]
  )
  return result.rows[0]
}

// Usage:
// const user = await seedUser(pool, { role: 'admin' })
// const order = await seedOrder(pool, user.id, { total: 500 })
```

---

## Checklist

- [ ] Testcontainers: real PostgreSQL + Redis in Docker for tests
- [ ] Global setup: containers start once, shared across test files
- [ ] cleanDatabase(): runs between tests (TRUNCATE CASCADE)
- [ ] API tests cover: success, validation errors, auth, not-found, duplicates
- [ ] Database operations tested with real transactions
- [ ] Auth helpers: generate test JWT tokens with configurable roles
- [ ] Seed utilities: easily create test data with factories
- [ ] Tests are independent: no test depends on another test's data
- [ ] Timeout increased for integration tests (30s)
