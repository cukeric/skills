# Unit Testing Reference (Vitest)

## Core Principles

1. **Test behavior, not implementation** — test what a function does, not how
2. **One assertion per concept** — each test should verify one thing
3. **Fast and isolated** — no database, no network, no file system
4. **Readable** — test names describe the expected behavior in plain English

---

## Test Structure: AAA Pattern

```typescript
import { describe, it, expect } from 'vitest'

describe('calculateDiscount', () => {
  it('applies 10% discount for orders over $100', () => {
    // Arrange — set up test data
    const order = { total: 150, customerTier: 'standard' }

    // Act — call the function
    const result = calculateDiscount(order)

    // Assert — verify the result
    expect(result).toBe(15)
  })
})
```

---

## Testing Services (with Mocking)

```typescript
// src/services/user.service.ts
export class UserService {
  constructor(
    private db: DatabaseClient,
    private emailService: EmailService,
    private cache: CacheClient,
  ) {}

  async createUser(data: CreateUserInput) {
    const existing = await this.db.query('SELECT id FROM users WHERE email = $1', [data.email])
    if (existing.rows.length > 0) throw new Error('Email already registered')

    const user = await this.db.query(
      'INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING *',
      [data.name, data.email, await hashPassword(data.password)]
    )

    await this.emailService.sendWelcome(user.rows[0].email, user.rows[0].name)
    await this.cache.del('users:count')

    return user.rows[0]
  }
}
```

```typescript
// src/services/user.service.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { UserService } from './user.service'

describe('UserService', () => {
  // Create mocks
  const mockDb = {
    query: vi.fn(),
  }
  const mockEmail = {
    sendWelcome: vi.fn(),
  }
  const mockCache = {
    del: vi.fn(),
  }

  let service: UserService

  beforeEach(() => {
    // Reset all mocks before each test
    vi.clearAllMocks()
    service = new UserService(mockDb as any, mockEmail as any, mockCache as any)
  })

  describe('createUser', () => {
    const validInput = { name: 'Jane', email: 'jane@example.com', password: 'SecurePass123!' }

    it('creates a user and sends welcome email', async () => {
      // Arrange: DB says email doesn't exist, then returns new user
      mockDb.query
        .mockResolvedValueOnce({ rows: [] })                    // SELECT (no existing user)
        .mockResolvedValueOnce({ rows: [{ id: '1', name: 'Jane', email: 'jane@example.com' }] }) // INSERT

      // Act
      const user = await service.createUser(validInput)

      // Assert
      expect(user.name).toBe('Jane')
      expect(mockEmail.sendWelcome).toHaveBeenCalledWith('jane@example.com', 'Jane')
      expect(mockCache.del).toHaveBeenCalledWith('users:count')
      expect(mockDb.query).toHaveBeenCalledTimes(2)
    })

    it('throws if email already registered', async () => {
      mockDb.query.mockResolvedValueOnce({ rows: [{ id: 'existing' }] })

      await expect(service.createUser(validInput)).rejects.toThrow('Email already registered')
      expect(mockEmail.sendWelcome).not.toHaveBeenCalled()
    })
  })
})
```

---

## Mocking Patterns

### vi.mock — Module-Level Mocking

```typescript
// Mock an entire module
vi.mock('@/lib/redis', () => ({
  redis: {
    get: vi.fn(),
    set: vi.fn(),
    del: vi.fn(),
  },
}))

import { redis } from '@/lib/redis'

it('uses cache', async () => {
  vi.mocked(redis.get).mockResolvedValue('cached-value')
  // ... test code that uses redis
})
```

### vi.spyOn — Spy on Existing Methods

```typescript
import * as dateUtils from '@/lib/date'

it('uses current date', () => {
  const spy = vi.spyOn(dateUtils, 'getCurrentDate').mockReturnValue(new Date('2025-01-15'))

  const result = getReport()

  expect(result.date).toBe('2025-01-15')
  spy.mockRestore()  // Clean up
})
```

### Mock Timers

```typescript
describe('debounce', () => {
  beforeEach(() => { vi.useFakeTimers() })
  afterEach(() => { vi.useRealTimers() })

  it('debounces function calls', () => {
    const fn = vi.fn()
    const debounced = debounce(fn, 300)

    debounced()
    debounced()
    debounced()

    expect(fn).not.toHaveBeenCalled()

    vi.advanceTimersByTime(300)

    expect(fn).toHaveBeenCalledTimes(1)
  })
})
```

### Mock Fetch / HTTP

```typescript
// Option A: vi.stubGlobal
it('fetches external data', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve({ data: 'test' }),
  }))

  const result = await fetchExternalAPI('/endpoint')
  expect(result.data).toBe('test')

  vi.unstubAllGlobals()
})

// Option B: msw (Mock Service Worker) for more realistic mocking
// pnpm add -D msw
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'

const server = setupServer(
  http.get('https://api.example.com/data', () => {
    return HttpResponse.json({ data: 'mocked' })
  }),
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
```

---

## Testing Common Patterns

### Validators / Schemas (Zod)

```typescript
import { describe, it, expect } from 'vitest'
import { CreateUserSchema } from './schemas'

describe('CreateUserSchema', () => {
  it('accepts valid input', () => {
    const result = CreateUserSchema.safeParse({ name: 'Jane', email: 'jane@test.com', password: 'Secure123!' })
    expect(result.success).toBe(true)
  })

  it.each([
    [{ name: '', email: 'jane@test.com', password: 'Secure123!' }, 'empty name'],
    [{ name: 'Jane', email: 'not-email', password: 'Secure123!' }, 'invalid email'],
    [{ name: 'Jane', email: 'jane@test.com', password: '123' }, 'weak password'],
  ])('rejects %s', (input, _description) => {
    const result = CreateUserSchema.safeParse(input)
    expect(result.success).toBe(false)
  })
})
```

### Error Handling

```typescript
describe('processPayment', () => {
  it('throws PaymentError for insufficient funds', async () => {
    mockPaymentGateway.charge.mockRejectedValue(new Error('insufficient_funds'))

    await expect(processPayment({ amount: 100 })).rejects.toThrow(PaymentError)
    await expect(processPayment({ amount: 100 })).rejects.toMatchObject({
      code: 'INSUFFICIENT_FUNDS',
      statusCode: 402,
    })
  })
})
```

### Async Code

```typescript
describe('queue processor', () => {
  it('processes jobs in order', async () => {
    const results: number[] = []
    const processor = createProcessor(async (job: number) => {
      results.push(job)
    })

    await processor.add(1)
    await processor.add(2)
    await processor.add(3)
    await processor.drain()

    expect(results).toEqual([1, 2, 3])
  })

  it('retries failed jobs', async () => {
    let attempts = 0
    const processor = createProcessor(async () => {
      attempts++
      if (attempts < 3) throw new Error('fail')
    }, { retries: 3 })

    await processor.add('job')
    await processor.drain()

    expect(attempts).toBe(3)
  })
})
```

---

## Snapshot Testing

```typescript
describe('generateReport', () => {
  it('produces expected output format', () => {
    const report = generateReport({ month: 'January', revenue: 50000, expenses: 30000 })

    // First run: creates snapshot file
    // Subsequent runs: compares against snapshot
    expect(report).toMatchSnapshot()
  })

  // Inline snapshot (stored in the test file itself)
  it('formats currency correctly', () => {
    expect(formatCurrency(1234.56)).toMatchInlineSnapshot('"$1,234.56"')
  })
})

// Update snapshots: pnpm vitest run --update
```

---

## Test Factories (Reusable Test Data)

```typescript
// tests/fixtures/factory.ts
import { faker } from '@faker-js/faker'

// pnpm add -D @faker-js/faker

export function buildUser(overrides: Partial<User> = {}): User {
  return {
    id: faker.string.uuid(),
    name: faker.person.fullName(),
    email: faker.internet.email(),
    role: 'user',
    createdAt: new Date(),
    ...overrides,
  }
}

export function buildOrder(overrides: Partial<Order> = {}): Order {
  return {
    id: faker.string.uuid(),
    userId: faker.string.uuid(),
    total: faker.number.float({ min: 10, max: 500, fractionDigits: 2 }),
    status: 'pending',
    items: [{ productId: faker.string.uuid(), quantity: 1, price: 29.99 }],
    createdAt: new Date(),
    ...overrides,
  }
}

// Usage in tests:
// const admin = buildUser({ role: 'admin' })
// const bigOrder = buildOrder({ total: 999.99 })
```

---

## Coverage

```bash
# Run with coverage
pnpm test:coverage

# View HTML report
open coverage/index.html

# Check in CI (fails if below thresholds)
pnpm vitest run --coverage
```

### Coverage Config in vitest.config.ts

```typescript
coverage: {
  provider: 'v8',
  reporter: ['text', 'html', 'json-summary', 'lcov'],
  thresholds: {
    statements: 70,
    branches: 65,
    functions: 70,
    lines: 70,
  },
},
```

---

## Checklist

- [ ] Tests follow AAA pattern (Arrange, Act, Assert)
- [ ] Each test verifies one behavior
- [ ] Mocks reset between tests (vi.clearAllMocks in beforeEach)
- [ ] No real database/network calls in unit tests
- [ ] Validators/schemas tested with valid and invalid inputs
- [ ] Error paths tested (throws expected errors)
- [ ] Test factories for reusable test data
- [ ] Coverage targets set and enforced
- [ ] Snapshots used sparingly (format verification, not logic)
