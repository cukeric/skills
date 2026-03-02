# AI Cost Control & Governance Reference

## Cost Architecture

```
┌──────────────────────────────────────────────────────┐
│  Every LLM Request                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ Rate Limiter  │→│ Budget Check  │→│ Semantic    │ │
│  │ (req/min)     │  │ (tokens/day) │  │ Cache      │ │
│  └──────────────┘  └──────────────┘  └──────┬─────┘ │
│                                              │       │
│                    ┌─────────────────────────▼──┐    │
│                    │ Cache HIT → return cached  │    │
│                    │ Cache MISS → call LLM      │    │
│                    └─────────────────────────┬──┘    │
│                                              │       │
│  ┌──────────────────────────────────────────▼──────┐ │
│  │ Audit Logger                                     │ │
│  │ (user, model, tokens, cost, latency, feature)   │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## Token Budget System

### Database Schema

```sql
-- Track token usage per user per day
CREATE TABLE ai_token_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  tenant_id TEXT,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  model TEXT NOT NULL,
  input_tokens BIGINT DEFAULT 0,
  output_tokens BIGINT DEFAULT 0,
  total_tokens BIGINT DEFAULT 0,
  estimated_cost_usd NUMERIC(10, 6) DEFAULT 0,
  request_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, date, model)
);

CREATE INDEX ON ai_token_usage (user_id, date);
CREATE INDEX ON ai_token_usage (tenant_id, date);

-- Budget configuration per tenant or user
CREATE TABLE ai_budgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('user', 'tenant', 'global')),
  entity_id TEXT NOT NULL,
  daily_token_limit BIGINT DEFAULT 1000000,       -- 1M tokens/day
  monthly_token_limit BIGINT DEFAULT 30000000,     -- 30M tokens/month
  daily_cost_limit_usd NUMERIC(10, 2) DEFAULT 10,  -- $10/day
  monthly_cost_limit_usd NUMERIC(10, 2) DEFAULT 200, -- $200/month
  tier TEXT DEFAULT 'standard',                     -- standard, premium, unlimited
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(entity_type, entity_id)
);
```

### Budget Enforcement

```typescript
// src/ai/governance/token-budget.ts
import { Pool } from 'pg'
import { redis } from '../../lib/redis'
import { logger } from '../../lib/logger'

export interface BudgetCheck {
  allowed: boolean
  reason?: string
  usage: { tokensToday: number; costToday: number; limit: number }
}

export function createTokenBudget(pool: Pool) {
  return {
    async check(userId: string, tenantId?: string): Promise<BudgetCheck> {
      // Fast check: Redis counter (updated on every request)
      const cacheKey = `budget:${userId}:${new Date().toISOString().slice(0, 10)}`
      const cached = await redis.get(cacheKey)

      if (cached) {
        const usage = JSON.parse(cached)
        if (usage.tokensToday >= usage.limit) {
          return { allowed: false, reason: 'Daily token limit exceeded', usage }
        }
        return { allowed: true, usage }
      }

      // DB check (cold path — first request of the day)
      const budgetResult = await pool.query(`
        SELECT COALESCE(b.daily_token_limit, 1000000) AS daily_limit,
               COALESCE(SUM(u.total_tokens), 0) AS tokens_today,
               COALESCE(SUM(u.estimated_cost_usd), 0) AS cost_today
        FROM ai_budgets b
        LEFT JOIN ai_token_usage u ON u.user_id = $1 AND u.date = CURRENT_DATE
        WHERE b.entity_type = 'user' AND b.entity_id = $1
        GROUP BY b.daily_token_limit
      `, [userId])

      const row = budgetResult.rows[0] || { daily_limit: 1000000, tokens_today: 0, cost_today: 0 }
      const usage = {
        tokensToday: parseInt(row.tokens_today),
        costToday: parseFloat(row.cost_today),
        limit: parseInt(row.daily_limit),
      }

      // Cache for 60 seconds
      await redis.setex(cacheKey, 60, JSON.stringify(usage))

      if (usage.tokensToday >= usage.limit) {
        return { allowed: false, reason: 'Daily token limit exceeded', usage }
      }

      return { allowed: true, usage }
    },

    async record(userId: string, tenantId: string | undefined, model: string, inputTokens: number, outputTokens: number, estimatedCost: number) {
      const totalTokens = inputTokens + outputTokens

      // Upsert daily usage
      await pool.query(`
        INSERT INTO ai_token_usage (user_id, tenant_id, date, model, input_tokens, output_tokens, total_tokens, estimated_cost_usd, request_count)
        VALUES ($1, $2, CURRENT_DATE, $3, $4, $5, $6, $7, 1)
        ON CONFLICT (user_id, date, model) DO UPDATE SET
          input_tokens = ai_token_usage.input_tokens + $4,
          output_tokens = ai_token_usage.output_tokens + $5,
          total_tokens = ai_token_usage.total_tokens + $6,
          estimated_cost_usd = ai_token_usage.estimated_cost_usd + $7,
          request_count = ai_token_usage.request_count + 1,
          updated_at = NOW()
      `, [userId, tenantId, model, inputTokens, outputTokens, totalTokens, estimatedCost])

      // Update Redis counter
      const cacheKey = `budget:${userId}:${new Date().toISOString().slice(0, 10)}`
      await redis.del(cacheKey)  // Invalidate cache to force fresh read
    },

    // Dashboard queries
    async getUsageReport(tenantId: string, startDate: string, endDate: string) {
      return pool.query(`
        SELECT date, model,
               SUM(total_tokens) AS total_tokens,
               SUM(estimated_cost_usd) AS total_cost,
               SUM(request_count) AS total_requests,
               COUNT(DISTINCT user_id) AS unique_users
        FROM ai_token_usage
        WHERE tenant_id = $1 AND date BETWEEN $2 AND $3
        GROUP BY date, model
        ORDER BY date DESC, total_cost DESC
      `, [tenantId, startDate, endDate])
    },
  }
}
```

---

## AI-Specific Rate Limiting

```typescript
// src/ai/governance/rate-limiter.ts
import { redis } from '../../lib/redis'

interface RateLimitConfig {
  requestsPerMinute: number
  requestsPerHour: number
  tokensPerMinute: number
  concurrentRequests: number
}

const TIER_LIMITS: Record<string, RateLimitConfig> = {
  free: { requestsPerMinute: 5, requestsPerHour: 50, tokensPerMinute: 10000, concurrentRequests: 1 },
  standard: { requestsPerMinute: 20, requestsPerHour: 500, tokensPerMinute: 100000, concurrentRequests: 3 },
  premium: { requestsPerMinute: 60, requestsPerHour: 2000, tokensPerMinute: 500000, concurrentRequests: 10 },
  unlimited: { requestsPerMinute: 200, requestsPerHour: 10000, tokensPerMinute: 2000000, concurrentRequests: 50 },
}

export function createAIRateLimiter() {
  return {
    async check(userId: string, tier: string = 'standard'): Promise<{ allowed: boolean; retryAfterMs?: number }> {
      const limits = TIER_LIMITS[tier] || TIER_LIMITS.standard

      // Sliding window rate limit (requests per minute)
      const minuteKey = `rl:ai:rpm:${userId}`
      const minuteCount = await redis.incr(minuteKey)
      if (minuteCount === 1) await redis.expire(minuteKey, 60)

      if (minuteCount > limits.requestsPerMinute) {
        const ttl = await redis.ttl(minuteKey)
        return { allowed: false, retryAfterMs: ttl * 1000 }
      }

      // Concurrent request limit
      const concurrentKey = `rl:ai:concurrent:${userId}`
      const concurrent = await redis.incr(concurrentKey)
      if (concurrent === 1) await redis.expire(concurrentKey, 300)  // 5 min safety TTL

      if (concurrent > limits.concurrentRequests) {
        await redis.decr(concurrentKey)
        return { allowed: false, retryAfterMs: 1000 }
      }

      return { allowed: true }
    },

    async release(userId: string) {
      await redis.decr(`rl:ai:concurrent:${userId}`)
    },
  }
}
```

---

## Semantic Cache

```typescript
// src/ai/governance/semantic-cache.ts
// Cache LLM responses for semantically similar queries to reduce cost

import type { VectorStore } from '../vector/vector-store'
import type { EmbeddingProvider } from '../clients/embedding-client'
import { redis } from '../../lib/redis'

interface CacheConfig {
  similarityThreshold: number    // 0.92 = 92% similar considered a hit
  ttlSeconds: number             // How long cached responses live
  maxCacheSize: number           // Max entries
}

export function createSemanticCache(vectorStore: VectorStore, embeddingClient: EmbeddingProvider, config: CacheConfig = { similarityThreshold: 0.92, ttlSeconds: 3600, maxCacheSize: 10000 }) {
  const CACHE_COLLECTION = 'semantic_cache'

  return {
    async get(query: string, context?: string): Promise<{ hit: boolean; response?: string; similarity?: number }> {
      // Embed the query
      const [embedding] = await embeddingClient.embed([query])

      // Search for similar cached queries
      const results = await vectorStore.search(embedding, { topK: 1, minScore: config.similarityThreshold })

      if (results.length > 0) {
        const cacheKey = `scache:${results[0].id}`
        const cached = await redis.get(cacheKey)

        if (cached) {
          const parsed = JSON.parse(cached)
          // Additional check: if context is provided, verify it matches
          if (context && parsed.context && parsed.context !== context) {
            return { hit: false }  // Different context = cache miss
          }
          return { hit: true, response: parsed.response, similarity: results[0].score }
        }
      }

      return { hit: false }
    },

    async set(query: string, response: string, context?: string) {
      const [embedding] = await embeddingClient.embed([query])
      const id = `cache_${Date.now()}_${Math.random().toString(36).slice(2)}`

      // Store embedding for similarity search
      await vectorStore.upsert([{ id, content: query, embedding, metadata: { type: 'cache' } }])

      // Store response in Redis (with TTL)
      await redis.setex(`scache:${id}`, config.ttlSeconds, JSON.stringify({ response, context, query, timestamp: Date.now() }))
    },
  }
}
```

---

## Audit Logging

```typescript
// src/ai/governance/audit-logger.ts

export interface AIAuditEntry {
  requestId: string
  userId: string
  tenantId?: string
  timestamp: Date
  provider: string
  model: string
  feature: string              // 'chat', 'rag_search', 'document_qa', etc.
  inputTokens: number
  outputTokens: number
  totalTokens: number
  estimatedCostUsd: number
  latencyMs: number
  status: 'success' | 'error' | 'filtered' | 'budget_exceeded'
  guardrailFlags: string[]     // Any safety flags triggered
  errorMessage?: string
  // For compliance: store hash of input/output, not raw text (unless required)
  inputHash?: string
  outputHash?: string
}

export function createAIAuditLogger(pool: Pool) {
  // Batch insert for performance
  const buffer: AIAuditEntry[] = []
  let flushTimer: NodeJS.Timeout | null = null

  async function flush() {
    if (buffer.length === 0) return
    const entries = buffer.splice(0, buffer.length)

    const values = entries.map((e, i) => {
      const offset = i * 14
      return `($${offset+1}, $${offset+2}, $${offset+3}, $${offset+4}, $${offset+5}, $${offset+6}, $${offset+7}, $${offset+8}, $${offset+9}, $${offset+10}, $${offset+11}, $${offset+12}, $${offset+13}, $${offset+14})`
    }).join(', ')

    const params = entries.flatMap(e => [
      e.requestId, e.userId, e.tenantId, e.provider, e.model, e.feature,
      e.inputTokens, e.outputTokens, e.estimatedCostUsd, e.latencyMs,
      e.status, JSON.stringify(e.guardrailFlags), e.errorMessage, e.timestamp.toISOString(),
    ])

    await pool.query(`
      INSERT INTO ai_audit_log (request_id, user_id, tenant_id, provider, model, feature,
        input_tokens, output_tokens, estimated_cost_usd, latency_ms, status, guardrail_flags, error_message, timestamp)
      VALUES ${values}
    `, params)
  }

  return {
    log(entry: AIAuditEntry) {
      buffer.push(entry)
      if (buffer.length >= 50) flush()
      if (!flushTimer) flushTimer = setInterval(flush, 5000)  // Flush every 5s
    },
    flush,
  }
}
```

### Audit Log Schema

```sql
CREATE TABLE ai_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  tenant_id TEXT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  feature TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  estimated_cost_usd NUMERIC(10, 6),
  latency_ms INTEGER,
  status TEXT NOT NULL,
  guardrail_flags JSONB DEFAULT '[]',
  error_message TEXT
);

CREATE INDEX ON ai_audit_log (user_id, timestamp);
CREATE INDEX ON ai_audit_log (tenant_id, timestamp);
CREATE INDEX ON ai_audit_log (status) WHERE status != 'success';
CREATE INDEX ON ai_audit_log (feature, timestamp);

-- Retention policy: auto-delete after 90 days (or per compliance requirements)
-- Use pg_cron or application-level cleanup
```

---

## Compliance & Data Residency

### Data Residency Rules

```typescript
// src/ai/governance/compliance.ts

interface ComplianceConfig {
  dataResidency: {
    region: 'us' | 'eu' | 'ap'     // Where data must stay
    providers: string[]              // Allowed providers for this region
  }
  retention: {
    auditLogDays: number             // How long to keep audit logs
    conversationDays: number         // How long to keep conversation history
    embeddingsDays: number           // How long to keep document embeddings
  }
  features: {
    allowExternalProviders: boolean  // Can use non-enterprise providers?
    allowLocalModels: boolean        // Can use Ollama/local?
    requireAuditLog: boolean         // Mandatory audit logging?
    requireInputFiltering: boolean   // Mandatory input guardrails?
  }
}

const REGION_PROVIDERS: Record<string, string[]> = {
  'us': ['azure-openai', 'bedrock', 'anthropic', 'openai'],
  'eu': ['azure-openai', 'bedrock'],   // EU data residency: only Azure (EU regions) and Bedrock (Frankfurt)
  'ap': ['azure-openai', 'bedrock'],   // APAC: Azure (SE Asia, Japan, Australia) and Bedrock (Tokyo, Sydney)
}

export function validateCompliance(config: ComplianceConfig, request: { provider: string; model: string }) {
  const allowed = REGION_PROVIDERS[config.dataResidency.region] || []
  if (!allowed.includes(request.provider)) {
    throw new Error(`Provider ${request.provider} is not allowed in ${config.dataResidency.region} region. Allowed: ${allowed.join(', ')}`)
  }
}
```

### GDPR / Data Subject Requests

```typescript
// Delete all AI data for a user (GDPR right to erasure)
export async function deleteUserAIData(pool: Pool, vectorStore: VectorStore, userId: string) {
  // 1. Delete audit logs
  await pool.query('DELETE FROM ai_audit_log WHERE user_id = $1', [userId])

  // 2. Delete token usage records
  await pool.query('DELETE FROM ai_token_usage WHERE user_id = $1', [userId])

  // 3. Delete conversation history
  await pool.query('DELETE FROM conversations WHERE user_id = $1', [userId])

  // 4. Delete user-uploaded document embeddings
  const docIds = await pool.query('SELECT id FROM documents WHERE metadata->>\'uploadedBy\' = $1', [userId])
  if (docIds.rows.length > 0) {
    await vectorStore.delete(docIds.rows.map(r => r.id))
    await pool.query('DELETE FROM documents WHERE metadata->>\'uploadedBy\' = $1', [userId])
  }

  // 5. Delete budget config
  await pool.query('DELETE FROM ai_budgets WHERE entity_type = \'user\' AND entity_id = $1', [userId])
}
```

---

## Cost Optimization Strategies

| Strategy | Savings | Implementation |
|---|---|---|
| **Model tiering** | 50-80% | Route simple tasks to Haiku/4o-mini, complex to Sonnet/4o |
| **Semantic caching** | 20-40% | Cache responses for similar queries |
| **Embedding caching** | 30-50% | Cache embeddings for identical text chunks |
| **Prompt optimization** | 10-30% | Shorter system prompts, fewer examples, structured output |
| **Streaming abort** | 5-15% | Stop generation early when answer is sufficient |
| **Batch API** | 50% | Use Anthropic/OpenAI batch APIs for non-real-time tasks |
| **Token budget alerts** | Prevention | Alert before costs spike, hard limits per user/tenant |

---

## Checklist

- [ ] Token budgets: per-user daily limits enforced (check before every LLM call)
- [ ] Usage tracking: every request recorded (user, model, tokens, cost)
- [ ] Rate limiting: requests/min + concurrent request limits per tier
- [ ] Semantic cache: similar queries served from cache (92%+ similarity)
- [ ] Audit logging: every AI interaction logged with user context
- [ ] Cost dashboard: daily/weekly/monthly cost breakdown by user, model, feature
- [ ] Budget alerts: email/Slack notification when usage approaches limits
- [ ] Data residency: providers restricted by region (EU users → EU endpoints only)
- [ ] Retention policy: automatic cleanup of old audit logs and conversation data
- [ ] GDPR support: user data deletion endpoint covers all AI-related tables
- [ ] Model tiering: cheap models for classification, expensive for generation
