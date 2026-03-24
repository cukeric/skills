# ORM & Data Access Layer Guide

## Table of Contents
1. [Choosing an ORM](#choosing-an-orm)
2. [Prisma (Recommended for TypeScript/Node.js)](#prisma)
3. [Drizzle ORM](#drizzle-orm)
4. [TypeORM](#typeorm)
5. [Sequelize](#sequelize)
6. [SQLAlchemy (Python)](#sqlalchemy)
7. [Mongoose (MongoDB ODM)](#mongoose)
8. [Universal Best Practices](#universal-best-practices)

---

## Choosing an ORM

### Decision Matrix

| Criteria | Prisma | Drizzle | TypeORM | Sequelize | SQLAlchemy | Mongoose |
|----------|--------|---------|---------|-----------|------------|----------|
| **Language** | TS/JS | TS/JS | TS/JS | JS/TS | Python | TS/JS |
| **Database** | SQL | SQL | SQL | SQL | SQL | MongoDB |
| **Type Safety** | Excellent | Excellent | Good | Limited | Good | Good (TS) |
| **Query Builder** | Prisma Client | SQL-like | Both | OOP | Both | Chaining |
| **Migrations** | Built-in | Built-in | Built-in | Built-in | Alembic | N/A |
| **Learning Curve** | Low | Medium | Medium | Low | Medium-High | Low |
| **Raw SQL** | Yes | Native | Yes | Yes | Native | N/A |
| **Performance** | Good | Excellent | Good | Good | Excellent | Good |
| **Best For** | Rapid dev, type safety | Performance-critical, SQL control | Legacy/enterprise | Simple projects | Python projects | MongoDB projects |

### Recommendations

- **New TypeScript/Node.js project with SQL**: Use **Prisma** for rapid development and developer experience, or **Drizzle** if you want maximum performance and SQL-level control.
- **Existing TypeScript project**: Evaluate switching cost. TypeORM and Sequelize are fine if already in use — migration to Prisma/Drizzle should be justified by pain points, not trends.
- **Python project**: Use **SQLAlchemy** (2.0+ with the new async-first API). There is no real competitor in the Python ecosystem.
- **MongoDB project**: Use **Mongoose** for Node.js/TypeScript. For Python, use **Motor** (async) or **PyMongo** (sync).

---

## Prisma

### Setup

```bash
npm install prisma @prisma/client
npx prisma init
```

### Schema Definition

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(uuid()) @db.Uuid
  email     String   @unique
  name      String
  role      Role     @default(VIEWER)
  isActive  Boolean  @default(true) @map("is_active")
  createdAt DateTime @default(now()) @map("created_at") @db.Timestamptz
  updatedAt DateTime @updatedAt @map("updated_at") @db.Timestamptz

  orders    Order[]
  sessions  Session[]

  @@map("users")
  @@index([email])
  @@index([role, isActive])
}

model Order {
  id         String      @id @default(uuid()) @db.Uuid
  userId     String      @map("user_id") @db.Uuid
  status     OrderStatus @default(PENDING)
  total      Decimal     @db.Decimal(10, 2)
  createdAt  DateTime    @default(now()) @map("created_at") @db.Timestamptz

  user       User        @relation(fields: [userId], references: [id], onDelete: Cascade)
  items      OrderItem[]

  @@map("orders")
  @@index([userId, createdAt(sort: Desc)])
  @@index([status])
}

enum Role {
  ADMIN
  EDITOR
  VIEWER
}

enum OrderStatus {
  PENDING
  PROCESSING
  COMPLETED
  CANCELLED
}
```

### Naming Convention

Use `@@map` to keep Prisma models in PascalCase/camelCase while the actual database uses snake_case. This bridges TypeScript conventions with SQL conventions.

### Migrations

```bash
# Create and apply migration
npx prisma migrate dev --name add_user_orders

# Apply migrations in production (no interactive prompts)
npx prisma migrate deploy

# Generate client after schema changes
npx prisma generate
```

### CI / Monorepo: Always Run `prisma generate` Before Build

In CI environments and monorepos, `@prisma/client` requires `prisma generate` to produce TypeScript types before `tsc` compilation. Unlike local dev (where `node_modules/.prisma/client` persists between runs), CI starts from a clean `node_modules` after each `pnpm install`.

**Fix:** Include `prisma generate` in the package's build script:

```json
{
  "scripts": {
    "build": "prisma generate && tsc"
  }
}
```

This ensures the Prisma client is generated before TypeScript compilation in any environment — local, CI, or Docker. Forgetting this is the #1 cause of "Cannot find module '@prisma/client'" errors in CI pipelines.

### Query Patterns

```typescript
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development' ? ['query', 'warn', 'error'] : ['error'],
});

// Type-safe query with relations
const userWithOrders = await prisma.user.findUnique({
  where: { id: userId },
  include: {
    orders: {
      where: { status: 'COMPLETED' },
      orderBy: { createdAt: 'desc' },
      take: 10,
    },
  },
});

// Transaction
const [order, updatedStock] = await prisma.$transaction([
  prisma.order.create({ data: { userId, total, status: 'PENDING' } }),
  prisma.product.update({
    where: { id: productId },
    data: { stock: { decrement: quantity } },
  }),
]);

// Cursor-based pagination (preferred over offset)
const nextPage = await prisma.order.findMany({
  take: 20,
  skip: 1,
  cursor: { id: lastSeenOrderId },
  orderBy: { createdAt: 'desc' },
});

// Optimistic locking with interactive transaction
// Add a `version Int @default(0)` field to the model
const result = await prisma.$transaction(async (tx) => {
  const updated = await tx.order.updateMany({
    where: { id: orderId, version: currentVersion },
    data: { status: 'COMPLETED', version: { increment: 1 } },
  });
  if (updated.count === 0) {
    throw new Error("OPTIMISTIC_LOCK_CONFLICT");
  }
  // Additional writes in same transaction (audit log, related records)
  const log = await tx.auditLog.create({
    data: { orderId, eventType: 'order.completed', actor: userId },
  });
  return { updated, log };
});
// Catch OPTIMISTIC_LOCK_CONFLICT → return 409 Conflict to client
```

**Optimistic locking pattern:** Use `updateMany` with a `version` check (not `update`, which throws on no match). Wrap in `$transaction(async (tx) => ...)` for atomicity — if any step fails, all writes roll back. The client should handle 409 by refetching and retrying.

### Connection Management

```typescript
// Singleton pattern — create one PrismaClient instance per application
// prisma.ts
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ||
  new PrismaClient({
    datasources: {
      db: { url: process.env.DATABASE_URL },
    },
  });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;

// Graceful shutdown
process.on('beforeExit', async () => {
  await prisma.$disconnect();
});
```

---

## Drizzle ORM

### Setup

```bash
npm install drizzle-orm postgres
npm install -D drizzle-kit
```

### Schema Definition

```typescript
// src/db/schema.ts
import { pgTable, uuid, text, boolean, timestamp, decimal, pgEnum, index } from 'drizzle-orm/pg-core';

export const roleEnum = pgEnum('role', ['admin', 'editor', 'viewer']);
export const orderStatusEnum = pgEnum('order_status', ['pending', 'processing', 'completed', 'cancelled']);

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  role: roleEnum('role').notNull().default('viewer'),
  isActive: boolean('is_active').notNull().default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => ({
  emailIdx: index('idx_users_email').on(table.email),
  roleActiveIdx: index('idx_users_role_active').on(table.role, table.isActive),
}));

export const orders = pgTable('orders', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  status: orderStatusEnum('status').notNull().default('pending'),
  total: decimal('total', { precision: 10, scale: 2 }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => ({
  userDateIdx: index('idx_orders_user_date').on(table.userId, table.createdAt),
  statusIdx: index('idx_orders_status').on(table.status),
}));
```

### Query Patterns

```typescript
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { eq, desc, and, sql } from 'drizzle-orm';
import * as schema from './schema';

const client = postgres(process.env.DATABASE_URL!);
const db = drizzle(client, { schema });

// Type-safe query with join
const userOrders = await db
  .select()
  .from(schema.users)
  .leftJoin(schema.orders, eq(schema.users.id, schema.orders.userId))
  .where(eq(schema.users.id, userId))
  .orderBy(desc(schema.orders.createdAt))
  .limit(10);

// Transaction
await db.transaction(async (tx) => {
  await tx.insert(schema.orders).values({ userId, total, status: 'pending' });
  await tx.execute(
    sql`UPDATE products SET stock = stock - ${quantity} WHERE id = ${productId}`
  );
});
```

### Drizzle vs Prisma Trade-offs

- **Drizzle**: Closer to raw SQL, thinner abstraction, better for complex queries, smaller bundle size, no code generation step.
- **Prisma**: Better DX for rapid development, more intuitive relations API, built-in studio GUI, larger ecosystem.

---

## TypeORM

Best for existing projects already using it. For new projects, prefer Prisma or Drizzle.

```typescript
// Entity definition
@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  @Column({ type: 'enum', enum: Role, default: Role.VIEWER })
  role: Role;

  @Column({ name: 'is_active', default: true })
  isActive: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  @OneToMany(() => Order, (order) => order.user)
  orders: Order[];
}
```

### TypeORM Gotchas

- Lazy relations load silently and can cause N+1 queries — always use `relations` option or QueryBuilder with explicit joins.
- The `synchronize: true` option modifies your database schema automatically — NEVER use in production.
- Active Record pattern (`User.find()`) makes testing harder than Repository pattern.

---

## Sequelize

Mature and stable. For new projects prefer Prisma/Drizzle, but Sequelize is acceptable for teams already familiar with it.

```javascript
// Model definition
const User = sequelize.define('User', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  email: { type: DataTypes.STRING, unique: true, allowNull: false },
  role: { type: DataTypes.ENUM('admin', 'editor', 'viewer'), defaultValue: 'viewer' },
  isActive: { type: DataTypes.BOOLEAN, defaultValue: true, field: 'is_active' },
}, {
  tableName: 'users',
  underscored: true,  // Automatically maps camelCase to snake_case
  timestamps: true,
});
```

---

## SQLAlchemy

The standard for Python database access. Use SQLAlchemy 2.0+ with the new-style API.

```python
# models.py
from sqlalchemy import String, Boolean, Enum, ForeignKey, Numeric, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from datetime import datetime
import uuid
import enum

class Base(DeclarativeBase):
    pass

class Role(str, enum.Enum):
    ADMIN = "admin"
    EDITOR = "editor"
    VIEWER = "viewer"

class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    role: Mapped[Role] = mapped_column(Enum(Role), default=Role.VIEWER)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=datetime.utcnow)

    orders: Mapped[list["Order"]] = relationship(back_populates="user", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_users_email", "email"),
        Index("idx_users_role_active", "role", "is_active"),
    )

# Async session factory (recommended for web applications)
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(
    "postgresql+asyncpg://user:pass@localhost/mydb",
    pool_size=20,
    max_overflow=10,
    pool_timeout=30,
    pool_recycle=1800,
)
async_session = async_sessionmaker(engine, expire_on_commit=False)
```

### Migrations with Alembic

```bash
# Initialize
alembic init alembic

# Generate migration from model changes
alembic revision --autogenerate -m "add user orders"

# Apply migrations
alembic upgrade head

# Rollback one migration
alembic downgrade -1
```

---

## Mongoose

The standard ODM for MongoDB with Node.js/TypeScript.

```typescript
// models/user.ts
import { Schema, model, Document } from 'mongoose';

interface IUser extends Document {
  email: string;
  name: { first: string; last: string };
  role: 'admin' | 'editor' | 'viewer';
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const userSchema = new Schema<IUser>({
  email: {
    type: String,
    required: true,
    unique: true,
    lowercase: true,
    trim: true,
    match: /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
  },
  name: {
    first: { type: String, required: true, maxlength: 100 },
    last: { type: String, required: true, maxlength: 100 },
  },
  role: {
    type: String,
    enum: ['admin', 'editor', 'viewer'],
    default: 'viewer',
  },
  isActive: { type: Boolean, default: true },
}, {
  timestamps: true,          // Auto-manages createdAt and updatedAt
  collection: 'users',
  toJSON: { virtuals: true },
});

// Indexes
userSchema.index({ email: 1 });
userSchema.index({ role: 1, isActive: 1 });
userSchema.index({ createdAt: -1 });

// Virtual (computed field, not stored in DB)
userSchema.virtual('fullName').get(function() {
  return `${this.name.first} ${this.name.last}`;
});

export const User = model<IUser>('User', userSchema);
```

### Connection Management

```typescript
import mongoose from 'mongoose';

const connectDB = async () => {
  await mongoose.connect(process.env.MONGODB_URI!, {
    maxPoolSize: 20,
    minPoolSize: 5,
    serverSelectionTimeoutMS: 5000,
    socketTimeoutMS: 45000,
  });
};

// Graceful shutdown
process.on('SIGINT', async () => {
  await mongoose.connection.close();
  process.exit(0);
});
```

---

## Universal Best Practices

These apply regardless of which ORM you choose:

### Connection Pooling

Always configure connection pools. Never create a new connection per request.

| Setting | Recommended | Notes |
|---------|-------------|-------|
| Pool size | 10–25 | Based on expected concurrency. Too many connections hurt the DB. |
| Pool timeout | 30 seconds | Fail fast rather than queue indefinitely |
| Idle timeout | 10 minutes | Reclaim unused connections |
| Max overflow | 5–10 | Temporary extra connections for bursts |

### N+1 Query Prevention

The most common ORM performance problem. Always eager-load relations you know you'll need:

```typescript
// BAD — N+1: 1 query for users + N queries for orders
const users = await prisma.user.findMany();
for (const user of users) {
  const orders = await prisma.order.findMany({ where: { userId: user.id } });
}

// GOOD — 2 queries total
const users = await prisma.user.findMany({
  include: { orders: true },
});
```

### Logging & Debugging

Enable query logging in development, disable in production:

```typescript
// Prisma
const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development'
    ? ['query', 'warn', 'error']
    : ['error'],
});

// Drizzle
const db = drizzle(client, { logger: process.env.NODE_ENV === 'development' });
```

### Migration Safety Rules

1. Never use auto-sync/auto-migration in production
2. Every migration must have a rollback (down migration)
3. Test migrations against a copy of production data before deploying
4. Never drop columns in the same deploy as the code change
5. Add columns as nullable first, backfill data, then add NOT NULL constraint
