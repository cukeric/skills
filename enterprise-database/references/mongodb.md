# MongoDB Reference Guide

## Table of Contents
1. [Version Policy & Installation](#version-policy--installation)
2. [Schema Design Patterns](#schema-design-patterns)
3. [Schema Validation](#schema-validation)
4. [Indexing Deep Dive](#indexing-deep-dive)
5. [Replica Sets](#replica-sets)
6. [Sharding](#sharding)
7. [Security Configuration](#security-configuration)
8. [Aggregation Pipeline Patterns](#aggregation-pipeline-patterns)
9. [Atlas (Cloud-Managed) Setup](#atlas-cloud-managed-setup)
10. [Monitoring & Maintenance](#monitoring--maintenance)

---

## Version Policy & Installation

Use the latest stable version of MongoDB (currently MongoDB 7.x). For new projects, strongly consider MongoDB Atlas (cloud-managed) unless there are specific requirements for self-hosting.

### Docker Development Setup

```yaml
services:
  mongo:
    image: mongo:7
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_DB}
    ports:
      - "${MONGO_PORT:-27017}:27017"
    volumes:
      - mongodata:/data/db
      - ./mongo-init:/docker-entrypoint-initdb.d
    command: ["mongod", "--replSet", "rs0", "--keyFile", "/etc/mongo-keyfile"]
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh --quiet
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  mongodata:
```

For development with transactions, you need a replica set even on a single node:
```bash
# Initialize single-node replica set for development
mongosh --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'localhost:27017'}]})"
```

---

## Schema Design Patterns

MongoDB's flexibility is powerful but dangerous without discipline. Follow these patterns:

### Embed vs. Reference Decision Framework

**Embed when:**
- Data is read together (e.g., a blog post and its comments)
- The child data belongs exclusively to the parent (1:1 or 1:few)
- The embedded array has a bounded, predictable size
- You need atomic updates across parent and children

**Reference when:**
- The child data is shared across multiple parents (many:many)
- The embedded array would grow unboundedly
- The child data is large and rarely read with the parent
- You need to query the child data independently

### Common Patterns

**Subset Pattern** — Embed only the most recent/relevant subset:
```javascript
// User document with only the 10 most recent orders embedded
{
  _id: ObjectId("..."),
  name: "Jane Smith",
  email: "jane@example.com",
  recent_orders: [
    // Only last 10 orders embedded for quick display
    { order_id: ObjectId("..."), total: 59.99, date: ISODate("2025-03-01") }
  ]
}
// Full order history lives in a separate 'orders' collection
```

**Computed Pattern** — Pre-compute frequently accessed aggregations:
```javascript
// Product document with pre-computed review stats
{
  _id: ObjectId("..."),
  name: "Widget Pro",
  price: 29.99,
  review_stats: {
    count: 1247,
    average_rating: 4.3,
    last_updated: ISODate("2025-03-15")
  }
}
// Update review_stats on each new review using $inc and recalculation
```

**Bucket Pattern** — Group time-series data into buckets:
```javascript
// IoT sensor readings bucketed by hour
{
  sensor_id: "sensor-001",
  bucket_start: ISODate("2025-03-15T14:00:00Z"),
  bucket_end: ISODate("2025-03-15T15:00:00Z"),
  reading_count: 120,
  readings: [
    { timestamp: ISODate("2025-03-15T14:00:30Z"), value: 22.5 },
    { timestamp: ISODate("2025-03-15T14:01:00Z"), value: 22.7 }
    // ... up to ~120 readings per bucket
  ]
}
```

### Anti-Patterns to Avoid

- **Unbounded arrays**: Never allow an array to grow indefinitely. Cap embedded arrays or use the bucket pattern.
- **Massive documents**: Keep documents well under the 16MB limit. If a document approaches 1MB, reconsider the schema.
- **Deep nesting**: More than 3 levels of nesting makes queries painful. Flatten or reference instead.
- **Using MongoDB like SQL**: Don't normalize everything into tiny collections with references everywhere — you lose MongoDB's advantages.

---

## Schema Validation

Enforce structure at the database level. This is MongoDB's equivalent of SQL constraints:

```javascript
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "name", "role", "created_at"],
      properties: {
        email: {
          bsonType: "string",
          pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
          description: "Must be a valid email address"
        },
        name: {
          bsonType: "object",
          required: ["first", "last"],
          properties: {
            first: { bsonType: "string", minLength: 1, maxLength: 100 },
            last: { bsonType: "string", minLength: 1, maxLength: 100 }
          }
        },
        role: {
          enum: ["admin", "editor", "viewer"],
          description: "Must be a valid role"
        },
        created_at: {
          bsonType: "date"
        },
        is_active: {
          bsonType: "bool"
        }
      },
      additionalProperties: false
    }
  },
  validationLevel: "strict",      // Reject all invalid documents
  validationAction: "error"        // Error on violation (vs. "warn" which only logs)
});
```

---

## Indexing Deep Dive

### Index Types and When to Use Them

```javascript
// Single field index — most common
db.users.createIndex({ email: 1 }, { unique: true });

// Compound index — for queries filtering on multiple fields
// Order matters: equality filters first, then sort, then range
db.orders.createIndex({ customer_id: 1, created_at: -1 });

// Partial index — only index documents matching a filter
db.orders.createIndex(
  { status: 1 },
  { partialFilterExpression: { status: { $in: ["pending", "processing"] } } }
);

// TTL index — auto-delete documents after a time period
db.sessions.createIndex(
  { expires_at: 1 },
  { expireAfterSeconds: 0 }  // Delete when expires_at is reached
);

// Text index — for full-text search
db.articles.createIndex({ title: "text", body: "text" });

// Wildcard index — for variable/dynamic field names in JSONB-like data
db.metadata.createIndex({ "attributes.$**": 1 });
```

### Index Optimization

```javascript
// Check if a query uses an index
db.orders.find({ customer_id: "abc", status: "active" }).explain("executionStats");

// Look for: "stage": "IXSCAN" (good) vs "COLLSCAN" (bad — full collection scan)

// Find unused indexes
db.orders.aggregate([{ $indexStats: {} }]);
// Drop indexes where ops = 0 for extended periods
```

---

## Replica Sets

Minimum 3 members for production (primary + secondary + secondary OR primary + secondary + arbiter).

### Production Replica Set Configuration

```javascript
// Initialize replica set
rs.initiate({
  _id: "rs-prod",
  members: [
    { _id: 0, host: "mongo-1:27017", priority: 2 },   // Preferred primary
    { _id: 1, host: "mongo-2:27017", priority: 1 },
    { _id: 2, host: "mongo-3:27017", priority: 1 }
  ],
  settings: {
    chainingAllowed: true,
    heartbeatTimeoutSecs: 10
  }
});
```

### Read Preference

```javascript
// Application connection string with read preference
const uri = "mongodb://mongo-1:27017,mongo-2:27017,mongo-3:27017/mydb?replicaSet=rs-prod&readPreference=secondaryPreferred";

// Read preferences:
// primary          — all reads go to primary (default, strongest consistency)
// primaryPreferred — primary if available, else secondary
// secondary        — all reads go to secondaries (eventual consistency)
// secondaryPreferred — secondary if available, else primary
// nearest          — lowest latency member
```

---

## Sharding

Use sharding when a single replica set can't handle the write throughput or data volume. This is a significant architectural decision — don't shard prematurely.

### Shard Key Selection

The shard key determines how data is distributed. A bad shard key creates hotspots and is extremely difficult to change later.

**Good shard keys:**
- Have high cardinality (many unique values)
- Distribute writes evenly
- Match your most common query patterns
- Example: `{ tenant_id: 1, _id: 1 }` for multi-tenant SaaS

**Bad shard keys:**
- Monotonically increasing values alone (timestamps, auto-increment IDs) — all writes go to one shard
- Low cardinality fields (status, boolean) — data concentrates on few shards

```javascript
// Enable sharding on a database
sh.enableSharding("mydb");

// Shard a collection with a hashed shard key (even distribution)
sh.shardCollection("mydb.events", { event_id: "hashed" });

// Or a compound shard key (targeted queries + distribution)
sh.shardCollection("mydb.tenant_data", { tenant_id: 1, created_at: 1 });
```

---

## Security Configuration

### Authentication & Authorization

```javascript
// Enable authentication in mongod.conf
// security:
//   authorization: enabled
//   keyFile: /etc/mongo-keyfile   (for replica set internal auth)

// Create admin user
use admin
db.createUser({
  user: "admin",
  pwd: passwordPrompt(),
  roles: [{ role: "userAdminAnyDatabase", db: "admin" }]
});

// Create application-specific users with minimal privileges
use mydb
db.createUser({
  user: "app_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "mydb" }]
});

// Create read-only user for reporting
db.createUser({
  user: "report_user",
  pwd: passwordPrompt(),
  roles: [{ role: "read", db: "mydb" }]
});
```

### Network Security

```yaml
# mongod.conf
net:
  port: 27017
  bindIp: 10.0.1.0            # Bind to private network only, never 0.0.0.0
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/ssl/mongodb.pem
    CAFile: /etc/ssl/ca.pem

security:
  authorization: enabled
```

### Field-Level Encryption (Client-Side)

MongoDB supports Client-Side Field Level Encryption (CSFLE) for encrypting sensitive fields before they reach the server:

```javascript
// Using MongoDB driver with CSFLE
const client = new MongoClient(uri, {
  autoEncryption: {
    keyVaultNamespace: "encryption.__keyVault",
    kmsProviders: {
      aws: { accessKeyId: "...", secretAccessKey: "..." }
    },
    schemaMap: {
      "mydb.users": {
        properties: {
          ssn: {
            encrypt: {
              bsonType: "string",
              algorithm: "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic"
            }
          }
        }
      }
    }
  }
});
```

---

## Aggregation Pipeline Patterns

### Multi-Stage Aggregation Example

```javascript
// Sales analytics: revenue by product category, last 30 days
db.orders.aggregate([
  // Stage 1: Filter to recent orders
  { $match: {
      created_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) },
      status: "completed"
  }},
  // Stage 2: Flatten order items
  { $unwind: "$items" },
  // Stage 3: Lookup product details
  { $lookup: {
      from: "products",
      localField: "items.product_id",
      foreignField: "_id",
      as: "product"
  }},
  { $unwind: "$product" },
  // Stage 4: Group by category
  { $group: {
      _id: "$product.category",
      total_revenue: { $sum: { $multiply: ["$items.quantity", "$items.price"] } },
      order_count: { $sum: 1 },
      avg_order_value: { $avg: { $multiply: ["$items.quantity", "$items.price"] } }
  }},
  // Stage 5: Sort by revenue
  { $sort: { total_revenue: -1 } }
]);
```

### Use $merge for Materialized Views

```javascript
// Refresh a materialized view of daily stats
db.orders.aggregate([
  { $match: { status: "completed" } },
  { $group: {
      _id: { $dateToString: { format: "%Y-%m-%d", date: "$created_at" } },
      revenue: { $sum: "$total" },
      orders: { $sum: 1 }
  }},
  { $merge: {
      into: "daily_stats",
      whenMatched: "replace",
      whenNotMatched: "insert"
  }}
]);
```

---

## Atlas (Cloud-Managed) Setup

MongoDB Atlas is recommended for production when using MongoDB. It handles replication, backups, security patches, and monitoring.

### Atlas Tier Recommendations

| Workload | Tier | Notes |
|----------|------|-------|
| Development/staging | M10–M20 | Shared resources, good for testing |
| Small production | M30 | Dedicated resources, adequate for most startups |
| Medium production | M40–M50 | Higher IOPS, more RAM |
| Large production | M60+ | NVMe storage, highest performance |

### Atlas Security Checklist

1. Enable IP Access List — restrict to your VPC/VPN IPs only
2. Enable VPC Peering or Private Link — never use public endpoints for production
3. Enable Encryption at Rest (enabled by default on M10+)
4. Enable Audit Logging (available on M10+)
5. Enable Database Access — create users with minimal roles
6. Enable LDAP or SCRAM authentication (disable legacy MONGODB-CR)
7. Enable backup with continuous backup and point-in-time recovery

---

## Monitoring & Maintenance

### Key Metrics

| Metric | Alert Threshold | Method |
|--------|----------------|--------|
| Opcounters (ops/sec) | Baseline deviation > 50% | `db.serverStatus().opcounters` |
| Connections in use | > 80% of max | `db.serverStatus().connections` |
| Replication lag | > 10 seconds | `rs.printSecondaryReplicationInfo()` |
| Page faults | Sustained high rate | `db.serverStatus().extra_info.page_faults` |
| Document size growth | Approaching 16MB | Application-level monitoring |
| Slow queries | > 100ms | Enable profiler: `db.setProfilingLevel(1, { slowms: 100 })` |

### Monitoring Tools

- **Atlas**: Built-in monitoring, Performance Advisor, Real-Time Performance Panel
- **Self-hosted**: MongoDB Ops Manager, Prometheus + MongoDB exporter, Grafana dashboards
- Always enable the **slow query profiler** in development and staging
