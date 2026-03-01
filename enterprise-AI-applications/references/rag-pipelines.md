# RAG Pipelines Reference

## RAG Architecture

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Query   │───▶│ Retrieve │───▶│ Augment  │───▶│ Generate │
│          │    │ (search) │    │ (context)│    │ (LLM)    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     │               │               │               │
  User question  Vector + keyword  Build prompt    LLM generates
                 search, rerank   with retrieved   answer with
                                  chunks           citations
```

---

## Basic RAG Pipeline

```typescript
// src/ai/patterns/rag.ts
import type { LLMProvider, LLMRequest } from '../clients/llm-client'
import type { VectorStore } from '../vector/vector-store'
import type { EmbeddingProvider } from '../clients/embedding-client'

export interface RAGOptions {
  topK?: number                    // Number of chunks to retrieve (default: 5)
  minScore?: number                // Minimum similarity threshold (default: 0.7)
  tenantId?: string                // Multi-tenant isolation
  systemPrompt?: string            // Custom system prompt
  includeSourceCitations?: boolean // Add source references (default: true)
  maxContextTokens?: number        // Max tokens for context window (default: 4000)
}

export interface RAGResponse {
  answer: string
  sources: { content: string; source: string; score: number }[]
  usage: { inputTokens: number; outputTokens: number; estimatedCost: number }
  retrievalTimeMs: number
  generationTimeMs: number
}

export function createRAGPipeline(
  llmClient: LLMProvider,
  vectorStore: VectorStore,
  embeddingClient: EmbeddingProvider,
) {
  return {
    async query(question: string, options: RAGOptions = {}): Promise<RAGResponse> {
      const {
        topK = 5,
        minScore = 0.7,
        tenantId,
        includeSourceCitations = true,
        maxContextTokens = 4000,
      } = options

      // Step 1: Embed the question
      const retrievalStart = Date.now()
      const [queryEmbedding] = await embeddingClient.embed([question])

      // Step 2: Retrieve relevant chunks
      const results = await vectorStore.search(queryEmbedding, {
        topK,
        minScore,
        filter: tenantId ? { tenantId } : undefined,
      })

      const retrievalTimeMs = Date.now() - retrievalStart

      // Step 3: Build context (respect token limit)
      let contextTokens = 0
      const selectedChunks: typeof results = []

      for (const result of results) {
        const chunkTokens = Math.ceil(result.content.length / 4)
        if (contextTokens + chunkTokens > maxContextTokens) break
        selectedChunks.push(result)
        contextTokens += chunkTokens
      }

      // Step 4: Build prompt with context
      const context = selectedChunks
        .map((chunk, i) => `[Source ${i + 1}: ${chunk.metadata?.source || 'unknown'}]\n${chunk.content}`)
        .join('\n\n---\n\n')

      const systemPrompt = options.systemPrompt || buildRAGSystemPrompt(includeSourceCitations)

      // Step 5: Generate answer
      const genStart = Date.now()
      const response = await llmClient.complete({
        systemPrompt,
        messages: [{
          role: 'user',
          content: `Context documents:\n\n${context}\n\n---\n\nQuestion: ${question}`,
        }],
        temperature: 0.3,  // Lower temperature for factual RAG
      })

      return {
        answer: response.content,
        sources: selectedChunks.map(c => ({
          content: c.content.slice(0, 200) + '...',
          source: String(c.metadata?.source || 'unknown'),
          score: c.score,
        })),
        usage: response.usage,
        retrievalTimeMs,
        generationTimeMs: Date.now() - genStart,
      }
    },
  }
}

function buildRAGSystemPrompt(includeCitations: boolean): string {
  return `You are a helpful assistant that answers questions based on the provided context documents.

RULES:
1. Only use information from the provided context documents to answer.
2. If the context doesn't contain the answer, say "I don't have enough information to answer that based on the available documents."
3. Never fabricate information, statistics, quotes, or sources.
${includeCitations ? '4. When citing information, reference the source like [Source 1], [Source 2], etc.' : ''}
5. If documents contain conflicting information, present both perspectives and note the discrepancy.
6. Be concise and direct. Don't repeat the question back.
7. If the question is ambiguous, ask for clarification rather than guessing.`
}
```

---

## Advanced RAG: Query Preprocessing

```typescript
// Improve retrieval quality by transforming the user's question

export async function preprocessQuery(
  question: string,
  llmClient: LLMProvider,
  conversationHistory?: LLMMessage[],
): Promise<{ searchQueries: string[]; isFollowUp: boolean }> {

  // For follow-up questions, resolve references using conversation history
  const hasHistory = conversationHistory && conversationHistory.length > 0
  const historyContext = hasHistory
    ? conversationHistory.slice(-4).map(m => `${m.role}: ${typeof m.content === 'string' ? m.content : ''}`).join('\n')
    : ''

  const response = await llmClient.complete({
    systemPrompt: `You are a search query optimizer. Given a user question (and optionally conversation history), generate 1-3 search queries that would find the most relevant documents. Return ONLY a JSON array of strings.

If the question references previous conversation ("it", "that", "the same"), resolve the reference using the conversation history.

Examples:
- "What is our refund policy?" → ["refund policy terms conditions"]
- "How does it compare to competitors?" (after discussing Product X) → ["Product X competitor comparison", "Product X vs alternatives"]`,
    messages: [{
      role: 'user',
      content: hasHistory
        ? `Conversation history:\n${historyContext}\n\nCurrent question: ${question}`
        : question,
    }],
    temperature: 0,
    maxTokens: 200,
  })

  try {
    const queries = JSON.parse(response.content)
    return { searchQueries: Array.isArray(queries) ? queries : [question], isFollowUp: hasHistory || false }
  } catch {
    return { searchQueries: [question], isFollowUp: false }
  }
}
```

---

## Advanced RAG: Reranking

```typescript
// Rerank retrieved chunks using a cross-encoder or LLM for better relevance

export async function rerankChunks(
  query: string,
  chunks: { content: string; score: number; metadata: Record<string, unknown> }[],
  llmClient: LLMProvider,
  topK: number = 5,
): Promise<typeof chunks> {
  if (chunks.length <= topK) return chunks

  // LLM-based reranking (works with any provider)
  const response = await llmClient.complete({
    systemPrompt: 'You are a relevance judge. Given a query and a list of text passages, rate each passage\'s relevance to the query on a scale of 0-10. Return ONLY a JSON array of numbers (one score per passage).',
    messages: [{
      role: 'user',
      content: `Query: ${query}\n\nPassages:\n${chunks.map((c, i) => `[${i}] ${c.content.slice(0, 300)}`).join('\n\n')}`,
    }],
    temperature: 0,
    maxTokens: 100,
    model: 'claude-haiku-4-5-20251001',  // Cheap model for scoring
  })

  try {
    const scores: number[] = JSON.parse(response.content)
    return chunks
      .map((chunk, i) => ({ ...chunk, rerankScore: scores[i] || 0 }))
      .sort((a, b) => b.rerankScore - a.rerankScore)
      .slice(0, topK)
  } catch {
    return chunks.slice(0, topK)  // Fallback to original order
  }
}

// Alternative: Cohere Rerank API (better quality, dedicated model)
// import { CohereClient } from 'cohere-ai'
// const cohere = new CohereClient({ token: env.COHERE_API_KEY })
// const reranked = await cohere.rerank({ query, documents: chunks.map(c => c.content), topN: topK, model: 'rerank-english-v3.0' })
```

---

## Conversational RAG (Multi-Turn)

```typescript
// RAG with conversation history — handles follow-up questions

export function createConversationalRAG(
  llmClient: LLMProvider,
  vectorStore: VectorStore,
  embeddingClient: EmbeddingProvider,
) {
  const ragPipeline = createRAGPipeline(llmClient, vectorStore, embeddingClient)

  return {
    async query(
      question: string,
      conversationHistory: LLMMessage[],
      options: RAGOptions = {},
    ): Promise<RAGResponse & { resolvedQuery: string }> {

      // Step 1: Resolve follow-up references
      const { searchQueries } = await preprocessQuery(question, llmClient, conversationHistory)

      // Step 2: Multi-query retrieval (search with all generated queries)
      const allChunks: Map<string, { content: string; score: number; metadata: Record<string, unknown> }> = new Map()

      for (const searchQuery of searchQueries) {
        const [embedding] = await embeddingClient.embed([searchQuery])
        const results = await vectorStore.search(embedding, {
          topK: options.topK || 5,
          minScore: options.minScore || 0.7,
          filter: options.tenantId ? { tenantId: options.tenantId } : undefined,
        })
        for (const r of results) {
          if (!allChunks.has(r.id) || r.score > allChunks.get(r.id)!.score) {
            allChunks.set(r.id, r)
          }
        }
      }

      // Step 3: Rerank combined results
      const chunks = Array.from(allChunks.values()).sort((a, b) => b.score - a.score)
      const reranked = await rerankChunks(question, chunks, llmClient, options.topK || 5)

      // Step 4: Build context with conversation history
      const context = reranked
        .map((chunk, i) => `[Source ${i + 1}: ${chunk.metadata?.source || 'unknown'}]\n${chunk.content}`)
        .join('\n\n---\n\n')

      const historyMessages = conversationHistory.slice(-6)  // Last 3 turns (6 messages)

      const response = await llmClient.complete({
        systemPrompt: buildRAGSystemPrompt(true),
        messages: [
          ...historyMessages,
          { role: 'user', content: `Context documents:\n\n${context}\n\n---\n\nQuestion: ${question}` },
        ],
        temperature: 0.3,
      })

      return {
        answer: response.content,
        resolvedQuery: searchQueries[0],
        sources: reranked.map(c => ({ content: c.content.slice(0, 200) + '...', source: String(c.metadata?.source || ''), score: c.score })),
        usage: response.usage,
        retrievalTimeMs: 0,
        generationTimeMs: 0,
      }
    },
  }
}
```

---

## RAG API Endpoint

```typescript
// src/modules/ai/routes/rag.ts
import { z } from 'zod'

const RAGQuerySchema = z.object({
  question: z.string().min(1).max(2000),
  conversationId: z.string().uuid().optional(),
  topK: z.number().min(1).max(20).default(5),
})

app.post('/api/ai/rag/query', { preHandler: [authGuard] }, async (req, reply) => {
  const { question, conversationId, topK } = RAGQuerySchema.parse(req.body)

  // Load conversation history if continuing
  let history: LLMMessage[] = []
  if (conversationId) {
    history = await loadConversationHistory(conversationId)
  }

  const result = await conversationalRAG.query(question, history, {
    topK,
    tenantId: req.user.tenantId,
  })

  // Save to conversation history
  const convId = conversationId || crypto.randomUUID()
  await saveMessage(convId, req.user.id, 'user', question)
  await saveMessage(convId, req.user.id, 'assistant', result.answer)

  return {
    answer: result.answer,
    sources: result.sources,
    conversationId: convId,
    usage: result.usage,
  }
})

// Streaming variant
app.post('/api/ai/rag/stream', { preHandler: [authGuard] }, async (req, reply) => {
  const { question, conversationId, topK } = RAGQuerySchema.parse(req.body)

  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  })

  // Retrieve context (non-streaming)
  const [queryEmbedding] = await embeddingClient.embed([question])
  const chunks = await vectorStore.search(queryEmbedding, { topK, filter: { tenantId: req.user.tenantId } })

  // Send sources immediately
  reply.raw.write(`data: ${JSON.stringify({ type: 'sources', sources: chunks.map(c => ({ source: c.metadata?.source, score: c.score })) })}\n\n`)

  // Stream LLM response
  const context = chunks.map((c, i) => `[Source ${i + 1}]\n${c.content}`).join('\n\n---\n\n')
  const stream = llmClient.stream({
    systemPrompt: buildRAGSystemPrompt(true),
    messages: [{ role: 'user', content: `Context:\n\n${context}\n\n---\n\nQuestion: ${question}` }],
    temperature: 0.3,
  })

  for await (const chunk of stream) {
    if (chunk.type === 'text') {
      reply.raw.write(`data: ${JSON.stringify({ type: 'text', text: chunk.text })}\n\n`)
    }
    if (chunk.type === 'done') {
      reply.raw.write(`data: ${JSON.stringify({ type: 'done', usage: chunk.usage })}\n\n`)
    }
  }

  reply.raw.end()
})
```

---

## Document Ingestion Endpoint

```typescript
app.post('/api/ai/documents/upload', { preHandler: [authGuard, upload.single('file')] }, async (req, reply) => {
  const file = req.file
  if (!file) return reply.status(400).send({ error: 'No file uploaded' })

  const allowedTypes = ['application/pdf', 'text/plain', 'text/markdown', 'text/html',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
  if (!allowedTypes.includes(file.mimetype)) {
    return reply.status(400).send({ error: `Unsupported file type: ${file.mimetype}` })
  }

  // Queue for background processing
  const jobId = await queueDocumentIngestion(
    { buffer: file.buffer, mimeType: file.mimetype, filename: file.originalname },
    { source: file.originalname, title: req.body.title, tenantId: req.user.tenantId }
  )

  return { jobId, status: 'processing', message: 'Document queued for ingestion' }
})
```

---

## Checklist

- [ ] Basic RAG: question → embed → search → augment → generate works end-to-end
- [ ] Conversational RAG: follow-up questions resolved using history
- [ ] Multi-query retrieval: multiple search queries for broader coverage
- [ ] Reranking: chunks reordered by relevance after initial retrieval
- [ ] Citations: answer references [Source N] traceable to actual documents
- [ ] Context window managed: chunks selected to fit within token budget
- [ ] Streaming: partial answers delivered to client as generated
- [ ] Document ingestion: upload → parse → chunk → embed → store pipeline
- [ ] Multi-tenant: retrieval filtered by tenantId
- [ ] Low temperature (0.3) for factual RAG, higher for creative tasks
