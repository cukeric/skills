# Provider Abstraction Layer Reference

## Architecture Principle

Never call provider SDKs directly from business logic. Every LLM interaction flows through a unified interface. This lets you switch providers, add fallbacks, inject safety layers, and track costs — all without touching application code.

---

## Unified LLM Client Interface

```typescript
// src/ai/clients/llm-client.ts
export interface LLMMessage {
  role: 'system' | 'user' | 'assistant' | 'tool'
  content: string | ContentBlock[]
  toolCallId?: string      // For tool results
  name?: string            // Tool name
}

export interface ContentBlock {
  type: 'text' | 'image' | 'document'
  text?: string
  source?: { type: 'base64'; mediaType: string; data: string }
  url?: string
}

export interface ToolDefinition {
  name: string
  description: string
  parameters: Record<string, unknown>   // JSON Schema
}

export interface ToolCall {
  id: string
  name: string
  arguments: Record<string, unknown>
}

export interface LLMRequest {
  messages: LLMMessage[]
  model?: string                // Override default model
  maxTokens?: number
  temperature?: number
  tools?: ToolDefinition[]
  toolChoice?: 'auto' | 'any' | 'none' | { name: string }
  stream?: boolean
  systemPrompt?: string
  metadata?: {
    userId?: string
    tenantId?: string
    feature?: string          // For cost tracking per feature
    requestId?: string
  }
}

export interface LLMResponse {
  content: string
  toolCalls?: ToolCall[]
  stopReason: 'end' | 'tool_use' | 'max_tokens' | 'content_filtered'
  usage: {
    inputTokens: number
    outputTokens: number
    totalTokens: number
    estimatedCost: number     // USD
  }
  model: string
  provider: string
  latencyMs: number
}

export interface LLMStreamChunk {
  type: 'text' | 'tool_call_start' | 'tool_call_delta' | 'tool_call_end' | 'done'
  text?: string
  toolCall?: Partial<ToolCall>
  usage?: LLMResponse['usage']
}

export interface LLMProvider {
  name: string
  complete(request: LLMRequest): Promise<LLMResponse>
  stream(request: LLMRequest): AsyncIterable<LLMStreamChunk>
  countTokens?(text: string): Promise<number>
}
```

---

## Provider Implementations

### Anthropic Claude

```typescript
// src/ai/clients/providers/anthropic.ts
import Anthropic from '@anthropic-ai/sdk'
import type { LLMProvider, LLMRequest, LLMResponse, LLMStreamChunk } from '../llm-client'

const COST_PER_1K: Record<string, { input: number; output: number }> = {
  'claude-sonnet-4-20250514': { input: 0.003, output: 0.015 },
  'claude-haiku-4-5-20251001': { input: 0.0008, output: 0.004 },
  'claude-opus-4-6': { input: 0.015, output: 0.075 },
}

export function createAnthropicProvider(apiKey: string): LLMProvider {
  const client = new Anthropic({ apiKey })

  return {
    name: 'anthropic',

    async complete(request: LLMRequest): Promise<LLMResponse> {
      const model = request.model || 'claude-sonnet-4-20250514'
      const start = Date.now()

      const response = await client.messages.create({
        model,
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        system: request.systemPrompt || undefined,
        messages: mapMessages(request.messages),
        tools: request.tools?.map(mapTool),
        tool_choice: request.toolChoice ? mapToolChoice(request.toolChoice) : undefined,
      })

      const costs = COST_PER_1K[model] || { input: 0.003, output: 0.015 }

      return {
        content: response.content.filter(b => b.type === 'text').map(b => b.text).join(''),
        toolCalls: response.content.filter(b => b.type === 'tool_use').map(b => ({
          id: b.id, name: b.name, arguments: b.input as Record<string, unknown>,
        })),
        stopReason: mapStopReason(response.stop_reason),
        usage: {
          inputTokens: response.usage.input_tokens,
          outputTokens: response.usage.output_tokens,
          totalTokens: response.usage.input_tokens + response.usage.output_tokens,
          estimatedCost: (response.usage.input_tokens / 1000 * costs.input) + (response.usage.output_tokens / 1000 * costs.output),
        },
        model,
        provider: 'anthropic',
        latencyMs: Date.now() - start,
      }
    },

    async *stream(request: LLMRequest): AsyncIterable<LLMStreamChunk> {
      const model = request.model || 'claude-sonnet-4-20250514'

      const stream = client.messages.stream({
        model,
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        system: request.systemPrompt || undefined,
        messages: mapMessages(request.messages),
        tools: request.tools?.map(mapTool),
      })

      for await (const event of stream) {
        if (event.type === 'content_block_delta') {
          if (event.delta.type === 'text_delta') {
            yield { type: 'text', text: event.delta.text }
          } else if (event.delta.type === 'input_json_delta') {
            yield { type: 'tool_call_delta', text: event.delta.partial_json }
          }
        }
        if (event.type === 'message_stop') {
          const finalMessage = await stream.finalMessage()
          yield {
            type: 'done',
            usage: {
              inputTokens: finalMessage.usage.input_tokens,
              outputTokens: finalMessage.usage.output_tokens,
              totalTokens: finalMessage.usage.input_tokens + finalMessage.usage.output_tokens,
              estimatedCost: 0, // Calculate same as complete()
            },
          }
        }
      }
    },
  }
}

function mapMessages(messages: LLMRequest['messages']) {
  return messages
    .filter(m => m.role !== 'system')
    .map(m => ({
      role: m.role === 'tool' ? 'user' as const : m.role as 'user' | 'assistant',
      content: m.role === 'tool'
        ? [{ type: 'tool_result' as const, tool_use_id: m.toolCallId!, content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content) }]
        : typeof m.content === 'string' ? m.content : mapContentBlocks(m.content),
    }))
}

function mapContentBlocks(blocks: ContentBlock[]) {
  return blocks.map(b => {
    if (b.type === 'text') return { type: 'text' as const, text: b.text! }
    if (b.type === 'image') return { type: 'image' as const, source: b.source! }
    if (b.type === 'document') return { type: 'document' as const, source: b.source! }
    return { type: 'text' as const, text: '' }
  })
}

function mapTool(tool: ToolDefinition) {
  return { name: tool.name, description: tool.description, input_schema: tool.parameters }
}

function mapToolChoice(choice: LLMRequest['toolChoice']) {
  if (choice === 'auto') return { type: 'auto' as const }
  if (choice === 'any') return { type: 'any' as const }
  if (choice === 'none') return { type: 'none' as const } // Note: Anthropic doesn't have 'none', omit tools instead
  if (typeof choice === 'object') return { type: 'tool' as const, name: choice.name }
  return undefined
}

function mapStopReason(reason: string): LLMResponse['stopReason'] {
  if (reason === 'end_turn') return 'end'
  if (reason === 'tool_use') return 'tool_use'
  if (reason === 'max_tokens') return 'max_tokens'
  return 'end'
}
```

### OpenAI

```typescript
// src/ai/clients/providers/openai.ts
import OpenAI from 'openai'
import type { LLMProvider, LLMRequest, LLMResponse, LLMStreamChunk } from '../llm-client'

const COST_PER_1K: Record<string, { input: number; output: number }> = {
  'gpt-4o': { input: 0.0025, output: 0.01 },
  'gpt-4o-mini': { input: 0.00015, output: 0.0006 },
}

export function createOpenAIProvider(apiKey: string): LLMProvider {
  const client = new OpenAI({ apiKey })

  return {
    name: 'openai',

    async complete(request: LLMRequest): Promise<LLMResponse> {
      const model = request.model || 'gpt-4o'
      const start = Date.now()

      const messages: OpenAI.ChatCompletionMessageParam[] = []
      if (request.systemPrompt) messages.push({ role: 'system', content: request.systemPrompt })

      for (const msg of request.messages) {
        if (msg.role === 'tool') {
          messages.push({ role: 'tool', content: typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content), tool_call_id: msg.toolCallId! })
        } else {
          messages.push({ role: msg.role as 'user' | 'assistant', content: typeof msg.content === 'string' ? msg.content : msg.content.map(b => b.type === 'text' ? { type: 'text' as const, text: b.text! } : { type: 'image_url' as const, image_url: { url: b.url || `data:${b.source?.mediaType};base64,${b.source?.data}` } }).filter(Boolean) })
        }
      }

      const response = await client.chat.completions.create({
        model,
        messages,
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        tools: request.tools?.map(t => ({
          type: 'function' as const,
          function: { name: t.name, description: t.description, parameters: t.parameters },
        })),
        tool_choice: request.toolChoice === 'auto' ? 'auto' : request.toolChoice === 'none' ? 'none' : request.toolChoice && typeof request.toolChoice === 'object' ? { type: 'function' as const, function: { name: request.toolChoice.name } } : undefined,
      })

      const choice = response.choices[0]
      const costs = COST_PER_1K[model] || { input: 0.0025, output: 0.01 }

      return {
        content: choice.message.content || '',
        toolCalls: choice.message.tool_calls?.map(tc => ({
          id: tc.id, name: tc.function.name, arguments: JSON.parse(tc.function.arguments),
        })),
        stopReason: choice.finish_reason === 'tool_calls' ? 'tool_use' : choice.finish_reason === 'length' ? 'max_tokens' : 'end',
        usage: {
          inputTokens: response.usage?.prompt_tokens || 0,
          outputTokens: response.usage?.completion_tokens || 0,
          totalTokens: response.usage?.total_tokens || 0,
          estimatedCost: ((response.usage?.prompt_tokens || 0) / 1000 * costs.input) + ((response.usage?.completion_tokens || 0) / 1000 * costs.output),
        },
        model,
        provider: 'openai',
        latencyMs: Date.now() - start,
      }
    },

    async *stream(request: LLMRequest): AsyncIterable<LLMStreamChunk> {
      const model = request.model || 'gpt-4o'
      const messages: OpenAI.ChatCompletionMessageParam[] = []
      if (request.systemPrompt) messages.push({ role: 'system', content: request.systemPrompt })
      for (const msg of request.messages) {
        messages.push({ role: msg.role as any, content: typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content) })
      }

      const stream = await client.chat.completions.create({
        model, messages,
        max_tokens: request.maxTokens || 4096,
        temperature: request.temperature ?? 0.7,
        stream: true, stream_options: { include_usage: true },
      })

      for await (const chunk of stream) {
        const delta = chunk.choices[0]?.delta
        if (delta?.content) yield { type: 'text', text: delta.content }
        if (chunk.usage) {
          yield { type: 'done', usage: { inputTokens: chunk.usage.prompt_tokens, outputTokens: chunk.usage.completion_tokens, totalTokens: chunk.usage.total_tokens, estimatedCost: 0 } }
        }
      }
    },
  }
}
```

### Ollama (Local Models)

```typescript
// src/ai/clients/providers/ollama.ts
import type { LLMProvider, LLMRequest, LLMResponse, LLMStreamChunk } from '../llm-client'

export function createOllamaProvider(baseUrl = 'http://localhost:11434'): LLMProvider {
  return {
    name: 'ollama',

    async complete(request: LLMRequest): Promise<LLMResponse> {
      const model = request.model || 'llama3.1'
      const start = Date.now()

      const response = await fetch(`${baseUrl}/api/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model,
          messages: [
            ...(request.systemPrompt ? [{ role: 'system', content: request.systemPrompt }] : []),
            ...request.messages.map(m => ({ role: m.role, content: typeof m.content === 'string' ? m.content : m.content.map(b => b.text).join('') })),
          ],
          stream: false,
          options: { temperature: request.temperature ?? 0.7, num_predict: request.maxTokens || 4096 },
        }),
      })

      const data = await response.json()

      return {
        content: data.message.content,
        stopReason: 'end',
        usage: {
          inputTokens: data.prompt_eval_count || 0,
          outputTokens: data.eval_count || 0,
          totalTokens: (data.prompt_eval_count || 0) + (data.eval_count || 0),
          estimatedCost: 0,  // Local = free
        },
        model, provider: 'ollama', latencyMs: Date.now() - start,
      }
    },

    async *stream(request: LLMRequest): AsyncIterable<LLMStreamChunk> {
      const model = request.model || 'llama3.1'

      const response = await fetch(`${baseUrl}/api/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model, stream: true,
          messages: [
            ...(request.systemPrompt ? [{ role: 'system', content: request.systemPrompt }] : []),
            ...request.messages.map(m => ({ role: m.role, content: typeof m.content === 'string' ? m.content : '' })),
          ],
        }),
      })

      const reader = response.body!.getReader()
      const decoder = new TextDecoder()

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        const lines = decoder.decode(value).split('\n').filter(Boolean)
        for (const line of lines) {
          const data = JSON.parse(line)
          if (data.message?.content) yield { type: 'text', text: data.message.content }
          if (data.done) yield { type: 'done', usage: { inputTokens: data.prompt_eval_count || 0, outputTokens: data.eval_count || 0, totalTokens: 0, estimatedCost: 0 } }
        }
      }
    },
  }
}
```

---

## Model Router (Fallback + Tiering)

```typescript
// src/ai/clients/router.ts
import type { LLMProvider, LLMRequest, LLMResponse, LLMStreamChunk } from './llm-client'
import { logger } from '../../lib/logger'

interface RouterConfig {
  primary: LLMProvider
  fallback?: LLMProvider
  retryAttempts?: number
  retryDelayMs?: number
  timeout?: number
}

export function createModelRouter(config: RouterConfig) {
  const { primary, fallback, retryAttempts = 2, retryDelayMs = 1000, timeout = 30000 } = config

  async function completeWithRetry(provider: LLMProvider, request: LLMRequest, attempts: number): Promise<LLMResponse> {
    for (let i = 0; i < attempts; i++) {
      try {
        const controller = new AbortController()
        const timer = setTimeout(() => controller.abort(), timeout)

        const result = await provider.complete(request)
        clearTimeout(timer)
        return result
      } catch (error: any) {
        const isRetryable = error.status === 429 || error.status === 503 || error.status === 529 || error.code === 'ECONNRESET'

        logger.warn({ provider: provider.name, attempt: i + 1, error: error.message, retryable: isRetryable }, 'LLM request failed')

        if (!isRetryable || i === attempts - 1) throw error

        // Exponential backoff
        const delay = retryDelayMs * Math.pow(2, i) + Math.random() * 500
        await new Promise(r => setTimeout(r, delay))
      }
    }
    throw new Error('Exhausted retries')
  }

  return {
    async complete(request: LLMRequest): Promise<LLMResponse> {
      try {
        return await completeWithRetry(primary, request, retryAttempts)
      } catch (primaryError) {
        if (!fallback) throw primaryError

        logger.warn({ primaryProvider: primary.name, fallbackProvider: fallback.name }, 'Falling back to secondary provider')

        try {
          return await completeWithRetry(fallback, request, 1)
        } catch (fallbackError) {
          logger.error({ primaryError, fallbackError }, 'Both providers failed')
          throw primaryError  // Throw original error
        }
      }
    },

    async *stream(request: LLMRequest): AsyncIterable<LLMStreamChunk> {
      try {
        yield* primary.stream(request)
      } catch (error) {
        if (!fallback) throw error
        logger.warn({ provider: primary.name }, 'Streaming fallback to secondary provider')
        yield* fallback.stream(request)
      }
    },
  }
}
```

### Factory: Create Router from Config

```typescript
// src/ai/clients/factory.ts
import { createAnthropicProvider } from './providers/anthropic'
import { createOpenAIProvider } from './providers/openai'
import { createOllamaProvider } from './providers/ollama'
import { createAzureOpenAIProvider } from './providers/azure-openai'
import { createBedrockProvider } from './providers/bedrock'
import { createModelRouter } from './router'
import type { AIConfig } from '../../config/ai'

export function createLLMClient(config: AIConfig) {
  const providerMap: Record<string, () => LLMProvider> = {
    'anthropic': () => createAnthropicProvider(env.ANTHROPIC_API_KEY),
    'openai': () => createOpenAIProvider(env.OPENAI_API_KEY),
    'azure-openai': () => createAzureOpenAIProvider(env.AZURE_OPENAI_ENDPOINT, env.AZURE_OPENAI_API_KEY),
    'bedrock': () => createBedrockProvider(env.AWS_REGION),
    'gemini': () => createGeminiProvider(env.GEMINI_API_KEY),
    'ollama': () => createOllamaProvider(env.OLLAMA_URL),
  }

  const primary = providerMap[config.llm.provider]()
  const fallback = config.llm.fallbackProvider ? providerMap[config.llm.fallbackProvider]() : undefined

  return createModelRouter({ primary, fallback })
}
```

---

## Embedding Client (Provider-Agnostic)

```typescript
// src/ai/clients/embedding-client.ts
export interface EmbeddingProvider {
  name: string
  embed(texts: string[]): Promise<number[][]>
  dimensions: number
}

// OpenAI embeddings (default — best price/performance)
export function createOpenAIEmbeddings(apiKey: string, model = 'text-embedding-3-small'): EmbeddingProvider {
  const client = new OpenAI({ apiKey })
  const dims: Record<string, number> = { 'text-embedding-3-small': 1536, 'text-embedding-3-large': 3072 }

  return {
    name: 'openai',
    dimensions: dims[model] || 1536,
    async embed(texts: string[]): Promise<number[][]> {
      // Batch in chunks of 100 (API limit: 2048, but 100 is safe)
      const results: number[][] = []
      for (let i = 0; i < texts.length; i += 100) {
        const batch = texts.slice(i, i + 100)
        const response = await client.embeddings.create({ model, input: batch })
        results.push(...response.data.map(d => d.embedding))
      }
      return results
    },
  }
}

// Ollama embeddings (local, free)
export function createOllamaEmbeddings(baseUrl = 'http://localhost:11434', model = 'nomic-embed-text'): EmbeddingProvider {
  return {
    name: 'ollama',
    dimensions: 768,
    async embed(texts: string[]): Promise<number[][]> {
      const results: number[][] = []
      for (const text of texts) {
        const res = await fetch(`${baseUrl}/api/embed`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ model, input: text }),
        })
        const data = await res.json()
        results.push(data.embeddings[0])
      }
      return results
    },
  }
}
```

---

## Security: Never Expose API Keys

```typescript
// AI endpoints are ALWAYS server-side. Never send API keys to the client.
// The client sends a request to YOUR backend, which calls the LLM provider.

// ❌ NEVER: client → LLM provider directly (exposes API key)
// ✅ ALWAYS: client → your backend (auth'd) → LLM provider

// Backend route example:
app.post('/api/ai/chat', { preHandler: [authGuard, rateLimiter] }, async (req) => {
  const { messages } = ChatRequestSchema.parse(req.body)
  const response = await llmClient.complete({
    messages,
    metadata: { userId: req.user.id, feature: 'chat' },
  })
  return response
})
```

---

## Checklist

- [ ] Unified interface: all providers implement same LLMProvider contract
- [ ] Streaming: AsyncIterable pattern works for all providers
- [ ] Fallback chain: primary → retry → fallback (configurable)
- [ ] Cost tracking: every response includes token counts and estimated cost
- [ ] Latency tracking: every response includes latencyMs
- [ ] Model routing: tier 1/2/3 models selectable per request
- [ ] Embedding client: batched, provider-swappable
- [ ] API keys server-side only, never exposed to client
- [ ] Error handling: retryable errors retried, non-retryable thrown immediately
