# Vector Database Reference

## Selection Matrix

| Database | Best For | Hosting | Max Vectors | Hybrid Search | Filtering | Cost |
|---|---|---|---|---|---|---|
| **pgvector** | Already using PG, < 5M vectors | Self-hosted / managed PG | ~10M (practical) | With tsvector | SQL WHERE | Free (PG extension) |
| **Azure AI Search** | Azure enterprise, managed hybrid | Azure managed | Unlimited (partitioned) | Built-in (vector + keyword + semantic) | OData filters | $$-$$$ |
| **Pinecone** | Fully managed, serverless, no ops | Cloud (managed) | Unlimited (serverless) | Sparse + dense | Metadata filters | $$  |
| **Qdrant** | High performance, rich filtering | Self-hosted or cloud | Billions | Sparse + dense | Payload filters | Free / $$ |
| **Weaviate** | Multi-modal, built-in vectorizers | Self-hosted or cloud | Billions | BM25 + vector | GraphQL filters | Free / $$ |
| **ChromaDB** | Prototyping, embedded, simple | Embedded / server | ~1M (practical) | Basic | Metadata filters | Free |

**Default recommendations:**
- **Standalone (already using PostgreSQL):** pgvector — zero additional infrastructure
- **Azure enterprise:** Azure AI Search — native integration, hybrid search, semantic reranking
- **Managed standalone at scale:** Pinecone serverless — zero ops, auto-scaling
- **Self-hosted at scale:** Qdrant — best performance/dollar, Docker deploy

---

## Unified Vector Store Interface

```typescript
// src/ai/vector/vector-store.ts
export interface VectorDocument {
  id: string
  content: string
  embedding: number[]
  metadata: Record<string, unknown>
}

export interface SearchResult {
  id: string
  content: string
  score: number
  metadata: Record<string, unknown>
}

export interface SearchOptions {
  topK?: number             // Default: 10
  filter?: Record<string, unknown>
  minScore?: number         // Minimum similarity threshold
  includeMetadata?: boolean
}

export interface VectorStore {
  name: string
  upsert(documents: VectorDocument[]): Promise<void>
  search(embedding: number[], options?: SearchOptions): Promise<SearchResult[]>
  delete(ids: string[]): Promise<void>
  count(): Promise<number>
}
```

---

## pgvector Implementation

```bash
# Enable extension (run once on your PostgreSQL database)
CREATE EXTENSION IF NOT EXISTS vector;
```

### Schema

```sql
CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT NOT NULL,
  embedding vector(1536) NOT NULL,     -- Match your embedding dimensions
  metadata JSONB DEFAULT '{}',
  tenant_id TEXT,                       -- Multi-tenant isolation
  source TEXT,
  chunk_index INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- HNSW index (fast approximate nearest neighbor)
CREATE INDEX ON documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 200);

-- Filtering indexes
CREATE INDEX ON documents (tenant_id);
CREATE INDEX ON documents USING gin (metadata jsonb_path_ops);

-- Full-text search index (for hybrid search)
ALTER TABLE documents ADD COLUMN content_tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;
CREATE INDEX ON documents USING gin (content_tsv);
```

### Provider

```typescript
// src/ai/vector/providers/pgvector.ts
import { Pool } from 'pg'
import type { VectorStore, VectorDocument, SearchResult, SearchOptions } from '../vector-store'

export function createPgVectorStore(pool: Pool, tableName = 'documents'): VectorStore {
  return {
    name: 'pgvector',

    async upsert(documents: VectorDocument[]) {
      const query = `
        INSERT INTO ${tableName} (id, content, embedding, metadata)
        VALUES ($1, $2, $3::vector, $4::jsonb)
        ON CONFLICT (id) DO UPDATE SET
          content = EXCLUDED.content,
          embedding = EXCLUDED.embedding,
          metadata = EXCLUDED.metadata,
          updated_at = NOW()
      `
      for (const doc of documents) {
        await pool.query(query, [doc.id, doc.content, JSON.stringify(doc.embedding), JSON.stringify(doc.metadata)])
      }
    },

    async search(embedding: number[], options: SearchOptions = {}): Promise<SearchResult[]> {
      const { topK = 10, filter, minScore = 0.0 } = options

      // Hybrid search: combine vector similarity + full-text relevance
      let filterClause = ''
      const params: any[] = [JSON.stringify(embedding), topK]

      if (filter?.tenantId) {
        filterClause += ` AND tenant_id = $${params.length + 1}`
        params.push(filter.tenantId)
      }

      const query = `
        SELECT id, content, metadata,
               1 - (embedding <=> $1::vector) AS score
        FROM ${tableName}
        WHERE 1 - (embedding <=> $1::vector) > ${minScore}
        ${filterClause}
        ORDER BY embedding <=> $1::vector
        LIMIT $2
      `
      const result = await pool.query(query, params)
      return result.rows.map(r => ({ id: r.id, content: r.content, score: r.score, metadata: r.metadata }))
    },

    async delete(ids: string[]) {
      await pool.query(`DELETE FROM ${tableName} WHERE id = ANY($1)`, [ids])
    },

    async count() {
      const result = await pool.query(`SELECT COUNT(*) FROM ${tableName}`)
      return parseInt(result.rows[0].count)
    },
  }
}

// Hybrid search (vector + keyword)
export async function hybridSearch(pool: Pool, query: string, embedding: number[], options: SearchOptions & { tenantId?: string } = {}) {
  const { topK = 10, tenantId } = options

  const result = await pool.query(`
    WITH vector_results AS (
      SELECT id, content, metadata,
             1 - (embedding <=> $1::vector) AS vector_score
      FROM documents
      WHERE ($3::text IS NULL OR tenant_id = $3)
      ORDER BY embedding <=> $1::vector
      LIMIT $2 * 2
    ),
    text_results AS (
      SELECT id, content, metadata,
             ts_rank(content_tsv, plainto_tsquery('english', $4)) AS text_score
      FROM documents
      WHERE content_tsv @@ plainto_tsquery('english', $4)
        AND ($3::text IS NULL OR tenant_id = $3)
      LIMIT $2 * 2
    )
    SELECT COALESCE(v.id, t.id) AS id,
           COALESCE(v.content, t.content) AS content,
           COALESCE(v.metadata, t.metadata) AS metadata,
           COALESCE(v.vector_score, 0) * 0.7 + COALESCE(t.text_score, 0) * 0.3 AS score
    FROM vector_results v
    FULL OUTER JOIN text_results t ON v.id = t.id
    ORDER BY score DESC
    LIMIT $2
  `, [JSON.stringify(embedding), topK, tenantId || null, query])

  return result.rows
}
```

---

## Pinecone Implementation

```bash
pnpm add @pinecone-database/pinecone
```

```typescript
// src/ai/vector/providers/pinecone.ts
import { Pinecone } from '@pinecone-database/pinecone'
import type { VectorStore, VectorDocument, SearchResult, SearchOptions } from '../vector-store'

export function createPineconeStore(apiKey: string, indexName: string): VectorStore {
  const pc = new Pinecone({ apiKey })
  const index = pc.index(indexName)

  return {
    name: 'pinecone',

    async upsert(documents: VectorDocument[]) {
      const vectors = documents.map(d => ({
        id: d.id,
        values: d.embedding,
        metadata: { content: d.content, ...d.metadata },
      }))
      // Batch in chunks of 100
      for (let i = 0; i < vectors.length; i += 100) {
        await index.upsert(vectors.slice(i, i + 100))
      }
    },

    async search(embedding: number[], options: SearchOptions = {}): Promise<SearchResult[]> {
      const { topK = 10, filter, minScore = 0.0 } = options

      const results = await index.query({
        vector: embedding,
        topK,
        includeMetadata: true,
        filter: filter as any,
      })

      return (results.matches || [])
        .filter(m => (m.score || 0) >= minScore)
        .map(m => ({
          id: m.id,
          content: (m.metadata?.content as string) || '',
          score: m.score || 0,
          metadata: m.metadata || {},
        }))
    },

    async delete(ids: string[]) { await index.deleteMany(ids) },
    async count() { const stats = await index.describeIndexStats(); return stats.totalRecordCount || 0 },
  }
}
```

---

## Qdrant Implementation

```bash
pnpm add @qdrant/js-client-rest
```

```typescript
// src/ai/vector/providers/qdrant.ts
import { QdrantClient } from '@qdrant/js-client-rest'
import type { VectorStore, VectorDocument, SearchResult, SearchOptions } from '../vector-store'

export function createQdrantStore(url: string, collectionName: string, apiKey?: string): VectorStore {
  const client = new QdrantClient({ url, apiKey })

  return {
    name: 'qdrant',

    async upsert(documents: VectorDocument[]) {
      await client.upsert(collectionName, {
        wait: true,
        points: documents.map(d => ({
          id: d.id,
          vector: d.embedding,
          payload: { content: d.content, ...d.metadata },
        })),
      })
    },

    async search(embedding: number[], options: SearchOptions = {}): Promise<SearchResult[]> {
      const { topK = 10, filter, minScore = 0.0 } = options

      const results = await client.search(collectionName, {
        vector: embedding,
        limit: topK,
        score_threshold: minScore,
        with_payload: true,
        filter: filter ? { must: Object.entries(filter).map(([k, v]) => ({ key: k, match: { value: v } })) } : undefined,
      })

      return results.map(r => ({
        id: String(r.id),
        content: (r.payload?.content as string) || '',
        score: r.score,
        metadata: (r.payload as Record<string, unknown>) || {},
      }))
    },

    async delete(ids: string[]) {
      await client.delete(collectionName, { wait: true, points: ids })
    },
    async count() {
      const info = await client.getCollection(collectionName)
      return info.points_count || 0
    },
  }
}
```

---

## ChromaDB Implementation (Prototyping)

```bash
pnpm add chromadb
```

```typescript
// src/ai/vector/providers/chromadb.ts
import { ChromaClient } from 'chromadb'
import type { VectorStore, VectorDocument, SearchResult, SearchOptions } from '../vector-store'

export function createChromaStore(collectionName: string, url = 'http://localhost:8000'): VectorStore {
  const client = new ChromaClient({ path: url })
  let collection: any

  async function getCollection() {
    if (!collection) collection = await client.getOrCreateCollection({ name: collectionName, metadata: { 'hnsw:space': 'cosine' } })
    return collection
  }

  return {
    name: 'chromadb',
    async upsert(documents: VectorDocument[]) {
      const col = await getCollection()
      await col.upsert({
        ids: documents.map(d => d.id),
        embeddings: documents.map(d => d.embedding),
        documents: documents.map(d => d.content),
        metadatas: documents.map(d => d.metadata),
      })
    },
    async search(embedding: number[], options: SearchOptions = {}): Promise<SearchResult[]> {
      const col = await getCollection()
      const results = await col.query({ queryEmbeddings: [embedding], nResults: options.topK || 10, where: options.filter as any })
      return (results.ids[0] || []).map((id: string, i: number) => ({
        id, content: results.documents?.[0]?.[i] || '', score: 1 - (results.distances?.[0]?.[i] || 0), metadata: results.metadatas?.[0]?.[i] || {},
      }))
    },
    async delete(ids: string[]) { const col = await getCollection(); await col.delete({ ids }) },
    async count() { const col = await getCollection(); return await col.count() },
  }
}
```

---

## Vector Store Factory

```typescript
// src/ai/vector/factory.ts
import type { AIConfig } from '../../config/ai'
import type { VectorStore } from './vector-store'

export function createVectorStore(config: AIConfig): VectorStore {
  switch (config.vector.provider) {
    case 'pgvector': return createPgVectorStore(dbPool)
    case 'pinecone': return createPineconeStore(env.PINECONE_API_KEY, env.PINECONE_INDEX)
    case 'azure-search': return createAzureSearchStore(env.AZURE_SEARCH_ENDPOINT, env.AZURE_SEARCH_KEY, 'documents')
    case 'qdrant': return createQdrantStore(env.QDRANT_URL, 'documents', env.QDRANT_API_KEY)
    case 'chromadb': return createChromaStore('documents', env.CHROMA_URL)
    default: throw new Error(`Unknown vector provider: ${config.vector.provider}`)
  }
}
```

---

## Checklist

- [ ] Vector store selected based on scale, hosting preference, and existing infrastructure
- [ ] Unified VectorStore interface: all providers implement same contract
- [ ] HNSW or IVF index created for efficient approximate nearest neighbor search
- [ ] Multi-tenant filtering: tenant_id field indexed and enforced in all queries
- [ ] Hybrid search implemented (vector + keyword) where supported
- [ ] Batch upsert handles large document sets (chunked at provider limits)
- [ ] Connection pooling / client reuse (not creating new client per request)
- [ ] Backup strategy for vector data (especially pgvector — included in PG backups)
