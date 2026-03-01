# Elasticsearch & Meilisearch Reference

## Meilisearch (Recommended Default)

### Setup

```bash
# Docker
docker run -d -p 7700:7700 \
  -v $(pwd)/meili_data:/meili_data \
  -e MEILI_MASTER_KEY='your-master-key' \
  getmeili/meilisearch:latest

# Node.js client
npm install meilisearch
```

### Index Configuration

```typescript
import { MeiliSearch } from 'meilisearch'

const meili = new MeiliSearch({
  host: process.env.MEILI_URL || 'http://localhost:7700',
  apiKey: process.env.MEILI_MASTER_KEY,
})

// Create and configure index
async function setupProductsIndex() {
  const index = meili.index('products')

  await index.updateSettings({
    searchableAttributes: ['name', 'description', 'category', 'brand'],
    filterableAttributes: ['category', 'brand', 'price', 'inStock', 'rating'],
    sortableAttributes: ['price', 'rating', 'createdAt'],
    rankingRules: [
      'words', 'typo', 'proximity', 'attribute', 'sort', 'exactness',
    ],
    distinctAttribute: 'sku',
    typoTolerance: {
      minWordSizeForTypos: { oneTypo: 4, twoTypos: 8 },
      disableOnAttributes: ['sku', 'barcode'],
    },
    pagination: { maxTotalHits: 10000 },
    faceting: { maxValuesPerFacet: 100 },
  })
}
```

### Indexing Documents

```typescript
// Batch indexing (recommended: chunks of 10K)
async function indexProducts(products: Product[]) {
  const index = meili.index('products')
  const BATCH_SIZE = 10_000

  for (let i = 0; i < products.length; i += BATCH_SIZE) {
    const batch = products.slice(i, i + BATCH_SIZE)
    const task = await index.addDocuments(batch, { primaryKey: 'id' })
    // Wait for indexing to complete
    await meili.waitForTask(task.taskUid, { timeOutMs: 60_000 })
  }
}

// Incremental updates (upsert)
async function updateProduct(product: Product) {
  const index = meili.index('products')
  await index.addDocuments([product]) // Upserts by primaryKey
}

// Delete
async function deleteProduct(productId: string) {
  await meili.index('products').deleteDocument(productId)
}
```

### Search Queries

```typescript
// Basic search
const results = await meili.index('products').search('running shoes', {
  limit: 20,
  offset: 0,
})

// Filtered search with facets
const results = await meili.index('products').search('laptop', {
  filter: ['category = "Electronics"', 'price >= 500', 'price <= 2000', 'inStock = true'],
  facets: ['category', 'brand', 'rating'],
  sort: ['price:asc'],
  limit: 20,
  attributesToHighlight: ['name', 'description'],
  highlightPreTag: '<mark>',
  highlightPostTag: '</mark>',
})

// Response shape
// {
//   hits: [{ id: '1', name: 'MacBook Pro', _formatted: { name: '<mark>MacBook</mark> Pro' } }],
//   query: 'laptop',
//   processingTimeMs: 3,
//   estimatedTotalHits: 142,
//   facetDistribution: {
//     category: { Electronics: 89, Accessories: 53 },
//     brand: { Apple: 24, Dell: 18, Lenovo: 15 }
//   }
// }
```

### Autocomplete / Typeahead

```typescript
// Fast prefix search for autocomplete
async function autocomplete(query: string) {
  return meili.index('products').search(query, {
    limit: 5,
    attributesToRetrieve: ['id', 'name', 'category'],
    attributesToHighlight: ['name'],
  })
}
```

### Multi-Index Search

```typescript
const results = await meili.multiSearch({
  queries: [
    { indexUid: 'products', q: 'laptop', limit: 5 },
    { indexUid: 'articles', q: 'laptop', limit: 3 },
    { indexUid: 'users', q: 'laptop', limit: 2 },
  ],
})
```

---

## Elasticsearch

### Setup

```bash
# Docker Compose
# docker-compose.yml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - 9200:9200
    volumes:
      - es_data:/usr/share/elasticsearch/data

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    ports:
      - 5601:5601
    depends_on:
      - elasticsearch

volumes:
  es_data:
```

```bash
npm install @elastic/elasticsearch
```

### Client Setup

```typescript
import { Client } from '@elastic/elasticsearch'

const elastic = new Client({
  node: process.env.ELASTICSEARCH_URL || 'http://localhost:9200',
  auth: process.env.ELASTICSEARCH_PASSWORD
    ? { username: 'elastic', password: process.env.ELASTICSEARCH_PASSWORD }
    : undefined,
})
```

### Index Mapping

```typescript
await elastic.indices.create({
  index: 'products',
  mappings: {
    properties: {
      name: {
        type: 'text',
        analyzer: 'standard',
        fields: { keyword: { type: 'keyword' }, autocomplete: { type: 'search_as_you_type' } },
      },
      description: { type: 'text', analyzer: 'english' },
      category: { type: 'keyword' },
      brand: { type: 'keyword' },
      price: { type: 'float' },
      rating: { type: 'float' },
      inStock: { type: 'boolean' },
      tags: { type: 'keyword' },
      location: { type: 'geo_point' },
      createdAt: { type: 'date' },
    },
  },
  settings: {
    number_of_shards: 1,
    number_of_replicas: 1,
    analysis: {
      analyzer: {
        autocomplete_analyzer: {
          type: 'custom',
          tokenizer: 'standard',
          filter: ['lowercase', 'autocomplete_filter'],
        },
      },
      filter: {
        autocomplete_filter: { type: 'edge_ngram', min_gram: 2, max_gram: 20 },
      },
    },
  },
})
```

### Search Queries

```typescript
// Full-text search with filters, facets, and highlighting
const results = await elastic.search({
  index: 'products',
  query: {
    bool: {
      must: [
        {
          multi_match: {
            query: 'running shoes',
            fields: ['name^3', 'description', 'tags^2'],
            type: 'best_fields',
            fuzziness: 'AUTO',
          },
        },
      ],
      filter: [
        { term: { inStock: true } },
        { range: { price: { gte: 50, lte: 200 } } },
        { terms: { category: ['Footwear', 'Sports'] } },
      ],
    },
  },
  aggs: {
    categories: { terms: { field: 'category', size: 20 } },
    brands: { terms: { field: 'brand', size: 20 } },
    price_ranges: {
      range: {
        field: 'price',
        ranges: [
          { to: 50 }, { from: 50, to: 100 },
          { from: 100, to: 200 }, { from: 200 },
        ],
      },
    },
    avg_rating: { avg: { field: 'rating' } },
  },
  highlight: {
    fields: { name: {}, description: { fragment_size: 150 } },
    pre_tags: ['<mark>'], post_tags: ['</mark>'],
  },
  from: 0,
  size: 20,
  sort: [{ _score: 'desc' }, { createdAt: 'desc' }],
})
```

### Geo Search

```typescript
// Find products near a location
const nearbyResults = await elastic.search({
  index: 'stores',
  query: {
    bool: {
      filter: {
        geo_distance: {
          distance: '10km',
          location: { lat: 40.7128, lon: -74.0060 },
        },
      },
    },
  },
  sort: [
    {
      _geo_distance: {
        location: { lat: 40.7128, lon: -74.0060 },
        order: 'asc',
        unit: 'km',
      },
    },
  ],
})
```

---

## Search Service Pattern

```typescript
// src/services/search.service.ts
import { meili } from '@/lib/meilisearch' // or elastic

export interface SearchParams {
  query: string
  filters?: Record<string, string | string[] | number[]>
  sort?: string
  page?: number
  limit?: number
  facets?: string[]
}

export interface SearchResult<T> {
  hits: T[]
  total: number
  processingTimeMs: number
  facets?: Record<string, Record<string, number>>
  page: number
  totalPages: number
}

export class SearchService {
  async search<T>(index: string, params: SearchParams): Promise<SearchResult<T>> {
    const { query, filters, sort, page = 1, limit = 20, facets } = params

    // Build filter string for Meilisearch
    const filterArray: string[] = []
    if (filters) {
      for (const [key, value] of Object.entries(filters)) {
        if (Array.isArray(value)) {
          filterArray.push(`${key} IN [${value.map((v) => `"${v}"`).join(', ')}]`)
        } else {
          filterArray.push(`${key} = "${value}"`)
        }
      }
    }

    const results = await meili.index(index).search(query, {
      filter: filterArray.length > 0 ? filterArray : undefined,
      sort: sort ? [sort] : undefined,
      offset: (page - 1) * limit,
      limit,
      facets,
    })

    return {
      hits: results.hits as T[],
      total: results.estimatedTotalHits || 0,
      processingTimeMs: results.processingTimeMs,
      facets: results.facetDistribution,
      page,
      totalPages: Math.ceil((results.estimatedTotalHits || 0) / limit),
    }
  }
}
```

---

## Keeping Search Index in Sync

### Event-Driven Sync (Recommended)

```typescript
// Consumer: listen for entity changes and update search index
worker.on('order.created', async (event) => {
  await meili.index('orders').addDocuments([mapToSearchDoc(event.data)])
})

worker.on('order.updated', async (event) => {
  await meili.index('orders').addDocuments([mapToSearchDoc(event.data)])
})

worker.on('order.deleted', async (event) => {
  await meili.index('orders').deleteDocument(event.data.orderId)
})
```

### Full Reindex (Scheduled)

```typescript
async function fullReindex(indexName: string) {
  const tempIndex = `${indexName}_temp_${Date.now()}`

  // Index all documents to temp index
  await indexAllDocuments(tempIndex)

  // Swap indexes atomically
  await meili.swapIndexes([{ indexes: [indexName, tempIndex] }])

  // Delete old temp index
  await meili.deleteIndex(tempIndex)
}
```

---

## Search Checklist

- [ ] Search engine selected with documented rationale
- [ ] Index mapping/settings configured (searchable, filterable, sortable fields)
- [ ] Batch indexing implemented for initial data load
- [ ] Incremental sync via events (create/update/delete)
- [ ] Full reindex job available (for recovery/schema changes)
- [ ] Autocomplete/typeahead implemented (< 50ms)
- [ ] Faceted search with counts
- [ ] Relevance tuning tested with real queries
- [ ] Typo tolerance configured appropriately
- [ ] Search latency monitored (< 200ms target)
- [ ] Index size monitored (storage alerts)
