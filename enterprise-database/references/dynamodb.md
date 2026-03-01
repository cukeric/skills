# DynamoDB Reference Guide

## Table of Contents
1. [When to Choose DynamoDB](#when-to-choose-dynamodb)
2. [Core Concepts](#core-concepts)
3. [Single-Table Design](#single-table-design)
4. [Secondary Indexes](#secondary-indexes)
5. [Capacity & Pricing](#capacity--pricing)
6. [Security](#security)
7. [Streams & Event-Driven Patterns](#streams--event-driven-patterns)
8. [Backup & Recovery](#backup--recovery)
9. [Best Practices & Anti-Patterns](#best-practices--anti-patterns)

---

## When to Choose DynamoDB

DynamoDB is the right choice when:
- You are on AWS and need a fully managed, zero-maintenance database
- You need guaranteed single-digit millisecond latency at any scale
- Your access patterns are known and well-defined upfront
- You need seamless scaling from 0 to millions of requests per second
- You want built-in high availability (data replicated across 3 AZs)

DynamoDB is NOT the right choice when:
- You need complex joins or ad-hoc querying (use PostgreSQL)
- Your access patterns are unpredictable or constantly changing
- You need strong relational integrity (foreign keys, cascades)
- You're not on AWS
- Your data model is deeply relational

---

## Core Concepts

### Keys

- **Partition Key (PK)**: Required. Determines which partition stores the item. Must distribute data evenly.
- **Sort Key (SK)**: Optional. Combined with PK, enables range queries within a partition. PK + SK together form the primary key.

### Item Size

Maximum item size is 400KB. Design documents to stay well under this limit.

### Read/Write Consistency

- **Eventually consistent reads**: Default. May not reflect recent writes (typically consistent within 1 second). Half the cost of strongly consistent reads.
- **Strongly consistent reads**: Guaranteed to return the latest data. Use when reading immediately after writing matters.
- **Transactional reads/writes**: ACID transactions across up to 100 items, 2x the cost.

---

## Single-Table Design

DynamoDB best practices favor putting multiple entity types in a single table. This enables fetching related data in a single query.

### Design Process

1. List all entities (Users, Orders, Products, etc.)
2. List all access patterns (get user by ID, get orders for user, get order items, etc.)
3. Design PK/SK patterns to serve all access patterns
4. Add GSIs for access patterns the base table can't serve

### Example: E-Commerce Application

```
Access patterns:
1. Get user by ID
2. Get all orders for a user (sorted by date)
3. Get order details with items
4. Get user by email (for login)
5. Get all orders by status

Table design:
| PK              | SK                   | Type   | Data              |
|-----------------|----------------------|--------|-------------------|
| USER#123        | PROFILE              | User   | name, email, role |
| USER#123        | ORDER#2025-03-15#789 | Order  | total, status     |
| USER#123        | ORDER#2025-03-14#788 | Order  | total, status     |
| ORDER#789       | ITEM#1               | Item   | product, qty, price|
| ORDER#789       | ITEM#2               | Item   | product, qty, price|
| ORDER#789       | METADATA             | Order  | total, status, user_id |

GSI1 (for access pattern 4 — get user by email):
  GSI1PK: email         GSI1SK: "PROFILE"

GSI2 (for access pattern 5 — get orders by status):
  GSI2PK: status        GSI2SK: created_at
```

### Key Design Principles

```javascript
// Use prefixes to distinguish entity types
const keys = {
  user:    { PK: `USER#${userId}`,  SK: 'PROFILE' },
  order:   { PK: `USER#${userId}`,  SK: `ORDER#${date}#${orderId}` },
  orderDetail: { PK: `ORDER#${orderId}`, SK: `ITEM#${itemId}` },
};

// Query all orders for a user (sorted by date)
const params = {
  TableName: 'MyTable',
  KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
  ExpressionAttributeValues: {
    ':pk': `USER#${userId}`,
    ':sk': 'ORDER#'
  },
  ScanIndexForward: false  // Descending (newest first)
};
```

---

## Secondary Indexes

### Global Secondary Indexes (GSI)

- Different partition key from the base table
- Eventually consistent reads only
- Have their own provisioned capacity
- Maximum 20 GSIs per table

```javascript
// Create table with GSI
const params = {
  TableName: 'MyTable',
  KeySchema: [
    { AttributeName: 'PK', KeyType: 'HASH' },
    { AttributeName: 'SK', KeyType: 'RANGE' }
  ],
  GlobalSecondaryIndexes: [{
    IndexName: 'GSI1',
    KeySchema: [
      { AttributeName: 'GSI1PK', KeyType: 'HASH' },
      { AttributeName: 'GSI1SK', KeyType: 'RANGE' }
    ],
    Projection: { ProjectionType: 'ALL' }  // Or KEYS_ONLY, INCLUDE
  }]
};
```

### Local Secondary Indexes (LSI)

- Same partition key, different sort key
- Support strongly consistent reads
- Must be created at table creation time (cannot be added later)
- Maximum 5 LSIs per table
- Share throughput with base table

### Sparse Indexes

Only items with the GSI key attributes are included in the index. Use this to create efficient filtered views:

```
// Only "active" orders appear in this GSI
// Items without 'active_status' attribute are excluded from the index
GSI: active_status (PK) + created_at (SK)
// Set active_status only on active orders; remove the attribute to "deindex"
```

---

## Capacity & Pricing

### On-Demand Mode

- Pay per request, no capacity planning
- Best for: unpredictable workloads, new applications, spiky traffic
- More expensive per request than provisioned at steady-state

### Provisioned Mode

- Pre-allocate read/write capacity units (RCUs/WCUs)
- Best for: predictable workloads, cost optimization
- Use Auto Scaling to adjust based on actual usage

```javascript
// Provisioned with auto-scaling
const params = {
  TableName: 'MyTable',
  BillingMode: 'PROVISIONED',
  ProvisionedThroughput: {
    ReadCapacityUnits: 100,
    WriteCapacityUnits: 50
  }
};

// Auto-scaling target: 70% utilization
// Configure via AWS Application Auto Scaling or CDK/Terraform
```

### Cost Optimization Tips

- Start with on-demand for new tables, switch to provisioned once patterns stabilize
- Use DAX (DynamoDB Accelerator) for read-heavy workloads to reduce RCU consumption
- Project only needed attributes in queries (`ProjectionExpression`)
- Use sparse GSIs instead of scanning with filters
- Enable TTL for auto-deleting expired data (no cost for deletes via TTL)

---

## Security

### IAM-Based Access Control

DynamoDB uses IAM for authentication and authorization — no database-level passwords.

```json
// Fine-grained IAM policy — app can only access its own table
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query"
    ],
    "Resource": "arn:aws:dynamodb:us-east-1:123456789:table/MyTable",
    "Condition": {
      "ForAllValues:StringEquals": {
        "dynamodb:LeadingKeys": ["USER#${aws:PrincipalTag/user_id}"]
      }
    }
  }]
}
```

### Encryption

- **At rest**: Enabled by default with AWS-owned keys. Optionally use customer-managed KMS keys.
- **In transit**: All DynamoDB API calls use HTTPS (TLS). No configuration needed.

### VPC Endpoints

Use VPC endpoints to keep DynamoDB traffic within your VPC (no internet traversal):

```hcl
# Terraform
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.dynamodb"
  route_table_ids = [aws_route_table.private.id]
}
```

---

## Streams & Event-Driven Patterns

DynamoDB Streams captures item-level changes in real-time:

```javascript
// Enable streams on a table
const params = {
  TableName: 'MyTable',
  StreamSpecification: {
    StreamEnabled: true,
    StreamViewType: 'NEW_AND_OLD_IMAGES'  // Capture before and after
    // Options: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES
  }
};
```

### Common Stream Patterns

- **Lambda triggers**: Process changes in real-time (send notifications, update search index, sync to analytics)
- **Cross-region replication**: Use Global Tables (built on streams) for multi-region active-active
- **Event sourcing**: Use streams as an event log for CQRS patterns
- **Data pipeline**: Stream changes to Kinesis, S3, or OpenSearch

---

## Backup & Recovery

### On-Demand Backup

```bash
# Create a backup
aws dynamodb create-backup \
  --table-name MyTable \
  --backup-name "MyTable-2025-03-15"

# Restore from backup (creates a new table)
aws dynamodb restore-table-from-backup \
  --target-table-name MyTable-Restored \
  --backup-arn arn:aws:dynamodb:us-east-1:123456789:table/MyTable/backup/...
```

### Point-in-Time Recovery (PITR)

```bash
# Enable PITR
aws dynamodb update-continuous-backups \
  --table-name MyTable \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true

# Restore to a specific point (creates a new table)
aws dynamodb restore-table-to-point-in-time \
  --source-table-name MyTable \
  --target-table-name MyTable-Restored \
  --restore-date-time "2025-03-15T10:30:00Z"
```

Always enable PITR for production tables. The cost is minimal compared to the risk of data loss.

---

## Best Practices & Anti-Patterns

### Do

- Design for your access patterns first, then model the table
- Use composite sort keys for flexible querying (`TYPE#DATE#ID`)
- Use `begins_with` on sort keys for hierarchical queries
- Use sparse GSIs for filtered access patterns
- Enable PITR on all production tables
- Use TTL to auto-expire temporary data
- Use batch operations (`BatchWriteItem`, `BatchGetItem`) for bulk work
- Use transactions (`TransactWriteItems`) for multi-item atomic operations

### Don't

- Don't use `Scan` in production — it reads the entire table and is expensive
- Don't use a monotonically increasing partition key (timestamps, auto-increment) — creates hot partitions
- Don't store large items (approaching 400KB) — split into multiple items
- Don't use filter expressions as a substitute for proper key design — filters run after the read and still consume RCUs
- Don't create GSIs you don't need — each GSI duplicates data and consumes capacity
- Don't use strongly consistent reads unless you specifically need them — they cost 2x
