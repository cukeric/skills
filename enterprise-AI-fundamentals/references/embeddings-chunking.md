# Embeddings & Document Chunking Reference

## Embedding Model Selection

| Model | Provider | Dimensions | Max Tokens | Cost/1M tokens | Best For |
|---|---|---|---|---|---|
| **text-embedding-3-small** | OpenAI | 1536 | 8191 | $0.02 | Default choice — best price/performance |
| **text-embedding-3-large** | OpenAI | 3072 | 8191 | $0.13 | Higher accuracy when needed |
| text-embedding-ada-002 | OpenAI | 1536 | 8191 | $0.10 | Legacy, no reason to use |
| **Titan Embed v2** | AWS Bedrock | 1024 | 8192 | $0.02 | AWS ecosystem |
| **Azure OpenAI embed** | Azure | 1536 | 8191 | Varies | Azure ecosystem + data residency |
| **nomic-embed-text** | Ollama (local) | 768 | 8192 | Free | Privacy, offline, dev/testing |
| **Cohere embed-v3** | Cohere | 1024 | 512 | $0.10 | Multi-lingual excellence |

**Default: OpenAI text-embedding-3-small** — best accuracy per dollar, 1536 dimensions is sufficient for most use cases.

---

## Chunking Strategies

### Strategy Selection Matrix

| Strategy | Best For | Chunk Size | Overlap |
|---|---|---|---|
| **Fixed-size** | Uniform documents, simple | 512-1024 tokens | 50-100 tokens |
| **Recursive text** | General-purpose (default) | 512-1024 tokens | 50-100 tokens |
| **Semantic** | Documents with clear topic shifts | Varies | None |
| **Document-aware** | Markdown, HTML (with headers) | By section | Include parent header |
| **Sentence** | Short passages, Q&A pairs | 3-5 sentences | 1 sentence |

**Default: Recursive text splitting with 512 tokens, 50 token overlap.**

### Chunking Engine

```typescript
// src/ai/ingestion/chunker.ts

export interface Chunk {
  content: string
  metadata: {
    chunkIndex: number
    totalChunks: number
    source: string
    title?: string
    section?: string
    startChar: number
    endChar: number
    tokenCount: number
  }
}

export interface ChunkingOptions {
  strategy: 'fixed' | 'recursive' | 'semantic' | 'markdown' | 'sentence'
  chunkSize?: number        // Target tokens per chunk (default: 512)
  chunkOverlap?: number     // Overlap tokens (default: 50)
  minChunkSize?: number     // Minimum chunk size (discard smaller, default: 50)
}

// Recursive text splitter (default, best general-purpose)
export function recursiveChunk(text: string, options: ChunkingOptions = { strategy: 'recursive' }): Chunk[] {
  const {
    chunkSize = 512,
    chunkOverlap = 50,
    minChunkSize = 50,
  } = options

  // Approximate tokens as chars / 4
  const charSize = chunkSize * 4
  const charOverlap = chunkOverlap * 4
  const minCharSize = minChunkSize * 4

  // Split by progressively smaller separators
  const separators = ['\n\n\n', '\n\n', '\n', '. ', '? ', '! ', '; ', ', ', ' ', '']

  function splitText(text: string, separators: string[]): string[] {
    if (text.length <= charSize) return [text]

    const separator = separators[0]
    const remaining = separators.slice(1)

    if (!separator) {
      // Last resort: hard split at charSize
      const chunks: string[] = []
      for (let i = 0; i < text.length; i += charSize - charOverlap) {
        chunks.push(text.slice(i, i + charSize))
      }
      return chunks
    }

    const parts = text.split(separator)
    const chunks: string[] = []
    let currentChunk = ''

    for (const part of parts) {
      const candidate = currentChunk ? currentChunk + separator + part : part

      if (candidate.length > charSize && currentChunk) {
        chunks.push(currentChunk)
        // Start new chunk with overlap
        const overlapStart = Math.max(0, currentChunk.length - charOverlap)
        currentChunk = currentChunk.slice(overlapStart) + separator + part
      } else {
        currentChunk = candidate
      }
    }

    if (currentChunk) chunks.push(currentChunk)

    // Recursively split any chunks that are still too large
    return chunks.flatMap(chunk =>
      chunk.length > charSize * 1.5 ? splitText(chunk, remaining) : [chunk]
    )
  }

  const rawChunks = splitText(text, separators)
  const filteredChunks = rawChunks.filter(c => c.trim().length >= minCharSize)

  return filteredChunks.map((content, index) => ({
    content: content.trim(),
    metadata: {
      chunkIndex: index,
      totalChunks: filteredChunks.length,
      source: '',
      startChar: text.indexOf(content.trim()),
      endChar: text.indexOf(content.trim()) + content.trim().length,
      tokenCount: Math.ceil(content.length / 4),
    },
  }))
}

// Markdown-aware chunker (splits by headers, preserves section context)
export function markdownChunk(text: string, options: ChunkingOptions = { strategy: 'markdown' }): Chunk[] {
  const { chunkSize = 512, chunkOverlap = 50 } = options
  const charSize = chunkSize * 4

  const sections: { level: number; title: string; content: string }[] = []
  let currentSection = { level: 0, title: '', content: '' }

  for (const line of text.split('\n')) {
    const headerMatch = line.match(/^(#{1,6})\s+(.+)/)
    if (headerMatch) {
      if (currentSection.content.trim()) sections.push({ ...currentSection })
      currentSection = { level: headerMatch[1].length, title: headerMatch[2], content: '' }
    } else {
      currentSection.content += line + '\n'
    }
  }
  if (currentSection.content.trim()) sections.push(currentSection)

  // Split large sections recursively
  const chunks: Chunk[] = []
  for (const section of sections) {
    const prefix = section.title ? `## ${section.title}\n\n` : ''
    const sectionText = prefix + section.content.trim()

    if (sectionText.length <= charSize) {
      chunks.push({
        content: sectionText,
        metadata: { chunkIndex: chunks.length, totalChunks: 0, source: '', section: section.title, startChar: 0, endChar: sectionText.length, tokenCount: Math.ceil(sectionText.length / 4) },
      })
    } else {
      const subChunks = recursiveChunk(section.content, { strategy: 'recursive', chunkSize, chunkOverlap })
      for (const sub of subChunks) {
        sub.content = prefix + sub.content
        sub.metadata.section = section.title
        sub.metadata.chunkIndex = chunks.length
        chunks.push(sub)
      }
    }
  }

  chunks.forEach((c, i) => { c.metadata.chunkIndex = i; c.metadata.totalChunks = chunks.length })
  return chunks
}
```

---

## Document Parsers

### PDF Parser

```bash
pnpm add pdf-parse
# For complex PDFs with tables/images: use Azure Document Intelligence or Unstructured.io
```

```typescript
// src/ai/ingestion/parsers/pdf.ts
import pdf from 'pdf-parse'

export async function parsePDF(buffer: Buffer): Promise<{ text: string; pages: number }> {
  const data = await pdf(buffer)
  return { text: data.text, pages: data.numpages }
}

// For enterprise (Azure Document Intelligence) — preserves tables, layout
export async function parsePDFEnterprise(buffer: Buffer): Promise<string> {
  // Uses Azure Document Intelligence — see azure-ai-services.md
  return extractFromDocument(buffer, 'application/pdf')
}
```

### DOCX Parser

```bash
pnpm add mammoth
```

```typescript
// src/ai/ingestion/parsers/docx.ts
import mammoth from 'mammoth'

export async function parseDocx(buffer: Buffer): Promise<string> {
  const result = await mammoth.convertToMarkdown({ buffer })
  return result.value
}
```

### HTML Parser

```bash
pnpm add cheerio
```

```typescript
// src/ai/ingestion/parsers/html.ts
import * as cheerio from 'cheerio'

export function parseHTML(html: string): string {
  const $ = cheerio.load(html)
  // Remove non-content elements
  $('script, style, nav, footer, header, aside, .sidebar, .menu, .advertisement').remove()
  // Extract main content
  const main = $('main, article, .content, #content').first()
  const text = (main.length ? main : $('body')).text()
  return text.replace(/\s+/g, ' ').trim()
}
```

### Image (OCR via LLM Vision)

```typescript
// src/ai/ingestion/parsers/image.ts
export async function parseImage(buffer: Buffer, mimeType: string, llmClient: LLMProvider): Promise<string> {
  const base64 = buffer.toString('base64')
  const response = await llmClient.complete({
    messages: [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', mediaType: mimeType, data: base64 } },
        { type: 'text', text: 'Extract all text from this image. If it contains diagrams, describe them. Preserve the structure and formatting.' },
      ],
    }],
    maxTokens: 4096,
  })
  return response.content
}
```

---

## Ingestion Pipeline

```typescript
// src/ai/ingestion/pipeline.ts
import { parsePDF, parsePDFEnterprise } from './parsers/pdf'
import { parseDocx } from './parsers/docx'
import { parseHTML } from './parsers/html'
import { recursiveChunk, markdownChunk } from './chunker'
import type { VectorStore, VectorDocument } from '../vector/vector-store'
import type { EmbeddingProvider } from '../clients/embedding-client'
import { logger } from '../../lib/logger'

export interface IngestionOptions {
  source: string                // URL or file path for reference
  title?: string
  tenantId?: string
  chunkSize?: number
  chunkOverlap?: number
  metadata?: Record<string, unknown>
  useEnterpriseParser?: boolean  // Use Azure Document Intelligence for PDFs
}

export async function ingestDocument(
  fileBuffer: Buffer,
  mimeType: string,
  vectorStore: VectorStore,
  embeddingClient: EmbeddingProvider,
  options: IngestionOptions,
) {
  const start = Date.now()

  // Step 1: Parse document to text
  let text: string
  switch (mimeType) {
    case 'application/pdf':
      text = options.useEnterpriseParser
        ? await parsePDFEnterprise(fileBuffer)
        : (await parsePDF(fileBuffer)).text
      break
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      text = await parseDocx(fileBuffer)
      break
    case 'text/html':
      text = parseHTML(fileBuffer.toString())
      break
    case 'text/markdown':
    case 'text/plain':
      text = fileBuffer.toString()
      break
    default:
      throw new Error(`Unsupported file type: ${mimeType}`)
  }

  logger.info({ source: options.source, textLength: text.length }, 'Document parsed')

  // Step 2: Chunk
  const isMarkdown = mimeType === 'text/markdown' || text.match(/^#+\s/m)
  const chunks = isMarkdown
    ? markdownChunk(text, { strategy: 'markdown', chunkSize: options.chunkSize, chunkOverlap: options.chunkOverlap })
    : recursiveChunk(text, { strategy: 'recursive', chunkSize: options.chunkSize, chunkOverlap: options.chunkOverlap })

  logger.info({ source: options.source, chunkCount: chunks.length }, 'Document chunked')

  // Step 3: Embed (batched)
  const texts = chunks.map(c => c.content)
  const embeddings = await embeddingClient.embed(texts)

  // Step 4: Store in vector database
  const documents: VectorDocument[] = chunks.map((chunk, i) => ({
    id: `${options.source}::${i}`,
    content: chunk.content,
    embedding: embeddings[i],
    metadata: {
      source: options.source,
      title: options.title,
      tenantId: options.tenantId,
      chunkIndex: chunk.metadata.chunkIndex,
      totalChunks: chunk.metadata.totalChunks,
      section: chunk.metadata.section,
      ...options.metadata,
    },
  }))

  await vectorStore.upsert(documents)

  const duration = Date.now() - start
  logger.info({ source: options.source, chunks: documents.length, durationMs: duration }, 'Document ingested')

  return { chunksCreated: documents.length, durationMs: duration }
}
```

### Batch Ingestion (Queue-Based)

```typescript
// For large-scale ingestion, use background jobs
import { ingestionQueue } from '../../lib/queue'

export async function queueDocumentIngestion(file: { buffer: Buffer; mimeType: string; filename: string }, options: IngestionOptions) {
  // Store file temporarily in S3/blob storage
  const fileKey = await uploadToStorage(file.buffer, file.filename)

  await ingestionQueue.add('ingest-document', {
    fileKey,
    mimeType: file.mimeType,
    options,
  }, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: { age: 86400 },
  })
}
```

---

## Embedding Cache

```typescript
// Cache embeddings for identical text (saves API calls + cost)
import { redis } from '../../lib/redis'
import crypto from 'crypto'

export function createCachedEmbeddingClient(baseClient: EmbeddingProvider): EmbeddingProvider {
  return {
    ...baseClient,
    async embed(texts: string[]): Promise<number[][]> {
      const results: (number[] | null)[] = new Array(texts.length).fill(null)
      const uncachedTexts: { index: number; text: string }[] = []

      // Check cache
      for (let i = 0; i < texts.length; i++) {
        const hash = crypto.createHash('sha256').update(texts[i]).digest('hex')
        const cached = await redis.get(`emb:${hash}`)
        if (cached) {
          results[i] = JSON.parse(cached)
        } else {
          uncachedTexts.push({ index: i, text: texts[i] })
        }
      }

      // Embed uncached texts
      if (uncachedTexts.length > 0) {
        const newEmbeddings = await baseClient.embed(uncachedTexts.map(t => t.text))
        for (let j = 0; j < uncachedTexts.length; j++) {
          const { index, text } = uncachedTexts[j]
          results[index] = newEmbeddings[j]
          const hash = crypto.createHash('sha256').update(text).digest('hex')
          await redis.setex(`emb:${hash}`, 86400 * 7, JSON.stringify(newEmbeddings[j]))  // Cache 7 days
        }
      }

      return results as number[][]
    },
  }
}
```

---

## Checklist

- [ ] Embedding model selected based on quality/cost tradeoff
- [ ] Chunking strategy matches document type (recursive for general, markdown for structured)
- [ ] Chunk size: 512 tokens default, with 50 token overlap
- [ ] Parsers handle: PDF, DOCX, HTML, Markdown, plain text, images (via vision)
- [ ] Ingestion pipeline: parse → chunk → embed → store (end-to-end)
- [ ] Batch ingestion via background queue for large document sets
- [ ] Embedding cache reduces duplicate API calls
- [ ] Metadata (source, title, tenant, section) attached to every chunk
- [ ] Chunk IDs are deterministic (same document → same IDs for upsert)
