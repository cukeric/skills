---
name: enterprise-database
description: Explains how to create, design, modify, migrate, optimize, or troubleshoot databases with enterprise standards. Trigger on ANY mention of database, DB, schema, tables, collections, queries, SQL, NoSQL, PostgreSQL, MySQL, MongoDB, Redis, DynamoDB, migrations, indexes, data model, ORM, database security, RBAC, row-level security, connection pooling, replication, sharding, backup, or data integrity. Also trigger when the user discusses data storage needs, asks to persist data, mentions storing user data, or when a project clearly requires a data layer even if the word database is never used. This skill applies to greenfield design AND modifications to existing databases.
---

# Enterprise Database Development Skill

Every database created or modified using this skill must meet enterprise-grade standards for security, performance, scalability, and data integrity — in that priority order. Even for prototypes or small projects, the foundations must be production-ready because retrofitting security and architecture is orders of magnitude harder than building it right from the start.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) based on the project's database engine and deployment target:

### Database-Specific Setup & Configuration
- `references/postgresql.md` — Any project using PostgreSQL
- `references/mongodb.md` — Any project using MongoDB
- `references/redis.md` — Any project using Redis
- `references/dynamodb.md` — Any project using DynamoDB

### ORM & Data Access Layer
- `references/orm-guide.md` — When choosing or configuring an ORM (Prisma, Drizzle, TypeORM, Sequelize, SQLAlchemy, Mongoose)

### Cloud Provider Deployment
- `references/aws-database.md` — Deploying to AWS (RDS, Aurora, ElastiCache, DynamoDB)
- `references/azure-database.md` — Deploying to Azure (Flexible Server, Cosmos DB, Azure Cache)
- `references/gcp-database.md` — Deploying to GCP (Cloud SQL, AlloyDB, Firestore, Memorystore)

Read this SKILL.md first for architecture decisions and standards, then consult the relevant reference files for implementation specifics.

---

## Decision Framework: Choosing the Right Database

Before writing any schema or code, evaluate the project's data characteristics and select the appropriate database engine.

### When to use SQL (Relational)

Use PostgreSQL as the default relational database unless there's a compelling reason not to.

Choose relational when the data has:
- Well-defined relationships between entities (foreign keys matter)
- Need for ACID transactions across multiple tables
- Complex querying patterns (joins, aggregations, window functions)
- Regulatory or compliance requirements (financial, healthcare, legal)
- Structured data with a predictable schema

### When to use NoSQL

Choose the NoSQL engine that fits the access pattern:
- **MongoDB**: Document store — hierarchical/nested data, variable schema per record, rapid iteration
- **Redis**: In-memory key-value — caching, sessions, rate limiting, pub/sub. Not a primary data store.
- **DynamoDB**: Managed key-value/document — guaranteed single-digit-ms latency at any scale on AWS
- **Cassandra**: Wide-column — write-heavy at massive scale (IoT, time-series, messaging)

### When to use both (Polyglot Persistence)

Common production patterns:
- PostgreSQL for transactions + Redis for caching/sessions
- PostgreSQL for core data + MongoDB for flexible content/metadata
- Primary relational DB + DynamoDB for high-throughput event streams

Always document the rationale for each engine choice.

---

## Priority 1: Security & Access Control

### Authentication & Connection Security
- **Never use default credentials.** Generate strong, unique passwords (minimum 24 chars, cryptographically random).
- **Enforce TLS/SSL for all connections.** No exceptions, including local development.
- **Use environment variables or secret managers** (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault, GCP Secret Manager). Never hardcode credentials.
- **Connection pooling is mandatory.** Use PgBouncer for PostgreSQL, or built-in ORM pooling.
- **Set connection and statement timeouts** to prevent runaway queries.

### Authorization & RBAC
Implement least privilege at every level:
- Application role: read/write on application tables only
- Read-only role: for reporting and dashboards
- Migration role: elevated privileges for schema changes only
- Each service/user gets its own role with minimum required permissions

Enable **Row-Level Security (RLS)** for multi-tenant data. Use **column-level encryption** for PII. Enable **audit logging** (pgaudit for PostgreSQL).

### Network Security
- Databases must **never** be publicly accessible. Use private subnets/VPCs.
- Require VPN or SSH tunneling for development access.
- Enable IP allowlisting where supported.

### SQL Injection Prevention
- **Always use parameterized queries.** No string concatenation of user input into queries.

---

## Priority 2: Performance & Speed

### Schema Design
- Normalize to 3NF baseline, then selectively denormalize based on measured query patterns
- Use appropriate data types — `UUID` for distributed, `BIGSERIAL` for single-instance
- Use `TIMESTAMPTZ`, never `TIMESTAMP` without timezone
- Use `JSONB` (not `JSON`) in PostgreSQL for flexible fields

### Indexing Strategy
- **Every foreign key must be indexed** (PostgreSQL doesn't auto-create these)
- Create indexes for `WHERE`, `JOIN`, `ORDER BY`, `GROUP BY` columns
- Use composite indexes for multi-column filters (most selective first)
- Use partial indexes for subset queries, covering indexes for index-only scans
- Monitor for unused indexes with `pg_stat_user_indexes`

### Query Optimization
- Use `EXPLAIN ANALYZE` before deploying queries
- Avoid `SELECT *` — specify only needed columns
- Use cursor-based pagination, not `OFFSET`
- Batch inserts and updates

### Configuration
- `shared_buffers` → ~25% of RAM
- `effective_cache_size` → ~75% of RAM
- Enable autovacuum tuning for high-write workloads

---

## Priority 3: Scalability

### Vertical First
Before horizontal scaling: proper indexing, query optimization, connection pooling, hardware-appropriate config.

### Horizontal Scaling
- **Read replicas** for read-heavy workloads (be aware of replication lag)
- **Table partitioning** for tables exceeding tens of millions of rows
- **Database sharding** when single instance can't handle write throughput

### Schema Migration Strategy
- Use a migration tool (Prisma Migrate, Knex, Flyway, Alembic, golang-migrate)
- Every migration must have up and down (apply and rollback)
- Never run destructive migrations in the same deployment as the code change
- Use online schema changes for large tables (`CREATE INDEX CONCURRENTLY`, `pg_repack`)

---

## Priority 4: Data Integrity & Backup

### Constraints
- Primary keys on every table
- Foreign key constraints for all relationships
- NOT NULL by default unless nullability is needed
- CHECK constraints for value validation
- UNIQUE constraints for business-critical uniqueness

### Backup & Recovery (3-2-1 Rule)
- Automated daily backups minimum; continuous archiving for critical data
- **Test restores regularly**
- Encrypt backups at rest, store keys separately
- Document RTO and RPO for each database

---

## Project Deliverables Checklist

Every database task should produce or update:
1. Schema files (migration files, version controlled)
2. Entity Relationship Diagram (ERD)
3. RBAC configuration
4. Environment config (`.env.example`, never real values)
5. Docker Compose for local development
6. Seed data scripts
7. Backup configuration and restore procedure
8. Performance baseline
9. README section with setup instructions and architecture decisions

---

## Anti-Patterns to Prevent
- Storing passwords in plaintext (use bcrypt/scrypt/argon2id)
- `VARCHAR(255)` everywhere (size columns intentionally)
- Missing foreign key indexes
- No connection pooling
- `SELECT *` in production
- OFFSET pagination (use cursor-based)
- Relying only on application validation (use DB constraints)
- Migrations without rollback plans
- Public-facing database ports
- Shared credentials across services
- No monitoring or alerting
