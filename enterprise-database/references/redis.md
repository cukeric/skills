# Redis Reference Guide

## Table of Contents
1. [Role & Version Policy](#role--version-policy)
2. [Data Structures & Use Cases](#data-structures--use-cases)
3. [Persistence Strategies](#persistence-strategies)
4. [Clustering & High Availability](#clustering--high-availability)
5. [Security](#security)
6. [Caching Patterns](#caching-patterns)
7. [Performance Tuning](#performance-tuning)
8. [Monitoring](#monitoring)

---

## Role & Version Policy

Redis is a supplementary data store — it should be paired with a durable primary database (PostgreSQL, MongoDB, etc.). Use the latest stable version (Redis 7.x). For cloud deployments, use managed offerings (ElastiCache, Azure Cache, Memorystore).

**Redis excels at:**
- Caching (most common use case)
- Session management
- Rate limiting
- Real-time leaderboards and counters
- Pub/Sub messaging
- Job/task queues
- Geospatial queries

**Redis is NOT suitable as:**
- A primary/only data store for business-critical data (unless using Redis with AOF persistence and understanding the trade-offs)
- A replacement for a relational database
- Long-term storage of large datasets

### Docker Development Setup

```yaml
services:
  redis:
    image: redis:7-alpine
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  redisdata:
```

---

## Data Structures & Use Cases

### Strings — Simple Key-Value
```redis
# Caching an API response (with 5-minute TTL)
SET api:users:123 '{"name":"Jane","role":"admin"}' EX 300

# Atomic counter
INCR page:views:homepage
INCRBY product:stock:456 -1    # Decrement stock

# Distributed lock (simple version)
SET lock:order:789 "worker-1" NX EX 30   # NX = only if not exists
```

### Hashes — Object Storage
```redis
# Store user session data
HSET session:abc123 user_id 456 role "admin" last_active "2025-03-15T10:00:00Z"
HGET session:abc123 user_id
HGETALL session:abc123
EXPIRE session:abc123 3600    # 1 hour TTL
```

### Lists — Ordered Queues
```redis
# Job queue
LPUSH queue:emails '{"to":"jane@example.com","template":"welcome"}'
BRPOP queue:emails 30    # Blocking pop with 30s timeout (for workers)

# Recent activity feed (keep last 100 items)
LPUSH feed:user:123 '{"action":"posted","item":"article-456"}'
LTRIM feed:user:123 0 99
```

### Sets — Unique Collections
```redis
# Track unique visitors
SADD visitors:2025-03-15 "user:123" "user:456" "user:789"
SCARD visitors:2025-03-15    # Count unique visitors

# Intersection — users who visited both days
SINTER visitors:2025-03-14 visitors:2025-03-15
```

### Sorted Sets — Ranked Data
```redis
# Leaderboard
ZADD leaderboard:game1 1500 "player:alice" 1200 "player:bob" 1800 "player:charlie"
ZREVRANGE leaderboard:game1 0 9 WITHSCORES    # Top 10
ZRANK leaderboard:game1 "player:alice"          # Player's rank

# Rate limiting (sliding window)
ZADD ratelimit:api:user123 <timestamp> <request-id>
ZREMRANGEBYSCORE ratelimit:api:user123 0 <timestamp - window>
ZCARD ratelimit:api:user123    # Count requests in window
```

### Streams — Event/Message Streaming
```redis
# Append events to a stream
XADD events:orders * action "created" order_id "789" total "59.99"

# Consumer group for processing
XGROUP CREATE events:orders order-processors $ MKSTREAM
XREADGROUP GROUP order-processors worker-1 COUNT 10 BLOCK 5000 STREAMS events:orders >

# Acknowledge processed events
XACK events:orders order-processors <message-id>
```

---

## Persistence Strategies

### RDB Snapshots (Point-in-Time)

```
# redis.conf
save 900 1       # Snapshot if at least 1 key changed in 900 seconds
save 300 10      # Snapshot if at least 10 keys changed in 300 seconds
save 60 10000    # Snapshot if at least 10000 keys changed in 60 seconds

rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
```

**Pros:** Compact, fast restarts, good for backups.
**Cons:** Can lose data between snapshots.

### AOF (Append-Only File)

```
# redis.conf
appendonly yes
appendfsync everysec    # Sync every second (best balance of safety and performance)
# Options: always (safest, slowest), everysec (recommended), no (OS decides)

auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

**Pros:** Minimal data loss (at most 1 second with everysec).
**Cons:** Larger files, slower restarts.

### Recommended: Both RDB + AOF

Enable both for the best combination of fast restarts (RDB) and minimal data loss (AOF). Redis 7+ uses AOF for recovery when both are enabled.

---

## Clustering & High Availability

### Redis Sentinel (High Availability for Single-Shard)

Use Sentinel when you need automatic failover but your dataset fits on a single instance:

```
# sentinel.conf
sentinel monitor mymaster 10.0.1.10 6379 2    # 2 sentinels must agree on failure
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1

# Minimum 3 sentinel instances for quorum
```

Application connection: Use Sentinel-aware clients that query Sentinel for the current primary.

### Redis Cluster (Horizontal Scaling)

Use Redis Cluster when data exceeds single-instance capacity:

```bash
# Create a 6-node cluster (3 primaries + 3 replicas)
redis-cli --cluster create \
  10.0.1.10:6379 10.0.1.11:6379 10.0.1.12:6379 \
  10.0.1.13:6379 10.0.1.14:6379 10.0.1.15:6379 \
  --cluster-replicas 1
```

**Key design for clusters:**
- Use hash tags `{user:123}:profile` and `{user:123}:sessions` to colocate related keys on the same shard
- Avoid cross-slot operations (MGET across different hash slots)
- Multi-key commands only work within the same hash slot

---

## Security

```
# redis.conf
requirepass <strong-random-password>

# Rename dangerous commands (or disable them)
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG "CONFIG_b4f82a9c"    # Rename to prevent casual use
rename-command DEBUG ""

# Bind to private interface only
bind 10.0.1.10 127.0.0.1

# Enable TLS
tls-port 6380
port 0                                      # Disable non-TLS port
tls-cert-file /etc/redis/tls/redis.crt
tls-key-file /etc/redis/tls/redis.key
tls-ca-cert-file /etc/redis/tls/ca.crt

# ACL (Redis 6+) — fine-grained access control
user app_user on >password ~app:* +get +set +del +expire +hset +hget +hgetall
user readonly on >password ~* +get +hget +hgetall +smembers +lrange -@write
user default off                            # Disable default user
```

---

## Caching Patterns

### Cache-Aside (Lazy Loading)

The most common pattern. Application checks cache first, falls back to database:

```
1. App checks Redis for key
2. Cache HIT  → return cached data
3. Cache MISS → query database → write result to Redis with TTL → return data
```

### Write-Through

Write to cache and database simultaneously:

```
1. App writes to database
2. App writes to Redis (same data, with TTL)
3. Reads always hit Redis first
```

### Cache Invalidation

The hardest problem in caching. Strategies:

- **TTL-based**: Set reasonable expiration times. Simple and effective for most use cases.
- **Event-driven**: Invalidate cache on database writes (using application events or database triggers).
- **Versioned keys**: Include a version in the cache key (`product:456:v3`). Increment version to invalidate.

### Key Naming Convention

Use a consistent, hierarchical naming scheme:

```
{resource}:{identifier}:{attribute}

Examples:
  user:123:profile
  user:123:sessions
  cache:api:/v1/products:page=1
  ratelimit:api:user:456
  lock:order:789
  queue:emails:high-priority
```

---

## Performance Tuning

### Memory Configuration

```
# redis.conf
maxmemory 4gb                    # Set to ~75% of available RAM
maxmemory-policy allkeys-lru     # Evict least recently used keys when full

# Eviction policies:
# allkeys-lru      — LRU across all keys (best for caching)
# volatile-lru     — LRU only among keys with TTL
# allkeys-lfu      — Least frequently used (Redis 4+, often better than LRU)
# noeviction       — Return errors when memory is full (for queues/critical data)
```

### Pipelining

Batch commands to reduce round trips:

```python
# Python example with redis-py
pipe = redis_client.pipeline()
for user_id in user_ids:
    pipe.hgetall(f"user:{user_id}:profile")
results = pipe.execute()    # One round trip for all commands
```

### Lua Scripting for Atomic Operations

```lua
-- Rate limiter: atomic check-and-increment
-- KEYS[1] = rate limit key, ARGV[1] = max requests, ARGV[2] = window in seconds
local current = redis.call('INCR', KEYS[1])
if current == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[2])
end
if current > tonumber(ARGV[1]) then
    return 0    -- Rate limited
end
return 1        -- Allowed
```

---

## Monitoring

### Key Metrics

| Metric | Alert Threshold | Command |
|--------|----------------|---------|
| Memory usage | > 80% of maxmemory | `INFO memory` → `used_memory` |
| Hit ratio | < 90% (for caching) | `INFO stats` → `keyspace_hits / (hits + misses)` |
| Connected clients | > 80% of maxclients | `INFO clients` |
| Evicted keys | Sustained > 0/sec | `INFO stats` → `evicted_keys` |
| Blocked clients | Any for extended periods | `INFO clients` → `blocked_clients` |
| Replication lag | > 1 second | `INFO replication` → `master_repl_offset` difference |

### Monitoring Tools

- **Redis CLI**: `redis-cli --stat`, `redis-cli --latency`, `redis-cli --bigkeys`
- **RedisInsight**: Official GUI for monitoring and debugging
- **Prometheus**: Use `redis_exporter` for metrics collection
- **Cloud-managed**: CloudWatch (ElastiCache), Azure Monitor, Cloud Monitoring (Memorystore)

### Slow Log

```redis
# Configure slow log (log commands taking > 10ms)
CONFIG SET slowlog-log-slower-than 10000    # microseconds
CONFIG SET slowlog-max-len 128

# View slow commands
SLOWLOG GET 10
```
