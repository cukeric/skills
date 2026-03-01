# Raw SDK Patterns Reference (No-Framework)

## When to Use Raw SDK

Use these patterns when you want full control, minimal dependencies, and maximum transparency. Best for Level 1-3 complexity (direct LLM, simple RAG, conversational chat). For Level 4-5 (complex stateful agents), consider LangGraph.

---

## Tool Use / Function Calling (Provider-Agnostic)

```typescript
// src/ai/patterns/tool-use.ts
// Complete tool-use loop using the unified LLM client from enterprise-ai-foundations

import type { LLMProvider, LLMMessage, ToolDefinition, ToolCall } from '../clients/llm-client'

export interface ToolHandler {
  definition: ToolDefinition
  execute(args: Record<string, unknown>): Promise<unknown>
}

export async function runToolLoop(
  llmClient: LLMProvider,
  systemPrompt: string,
  userMessage: string,
  toolHandlers: ToolHandler[],
  options?: { maxIterations?: number; model?: string },
): Promise<{ response: string; toolResults: { tool: string; result: unknown }[]; usage: { inputTokens: number; outputTokens: number } }> {
  const maxIterations = options?.maxIterations || 8
  const messages: LLMMessage[] = [{ role: 'user', content: userMessage }]
  const toolResults: { tool: string; result: unknown }[] = []
  let totalInput = 0, totalOutput = 0

  for (let i = 0; i < maxIterations; i++) {
    const response = await llmClient.complete({
      systemPrompt,
      messages,
      tools: toolHandlers.map(h => h.definition),
      toolChoice: 'auto',
      model: options?.model,
    })

    totalInput += response.usage.inputTokens
    totalOutput += response.usage.outputTokens

    // No tool calls = final answer
    if (!response.toolCalls || response.toolCalls.length === 0) {
      return { response: response.content, toolResults, usage: { inputTokens: totalInput, outputTokens: totalOutput } }
    }

    // Add assistant message (with tool call info)
    messages.push({ role: 'assistant', content: response.content || '' })

    // Execute each tool call
    for (const tc of response.toolCalls) {
      const handler = toolHandlers.find(h => h.definition.name === tc.name)
      let result: unknown

      if (!handler) {
        result = { error: `Unknown tool: ${tc.name}` }
      } else {
        try {
          result = await handler.execute(tc.arguments)
        } catch (err: any) {
          result = { error: err.message }
        }
      }

      toolResults.push({ tool: tc.name, result })
      messages.push({ role: 'tool', content: JSON.stringify(result), toolCallId: tc.id, name: tc.name })
    }
  }

  return { response: 'Reached maximum iterations without completing.', toolResults, usage: { inputTokens: totalInput, outputTokens: totalOutput } }
}

// Example usage:
// const result = await runToolLoop(llmClient, 'You are a helpful assistant.', 'What is the weather in Ottawa?', [
//   { definition: { name: 'get_weather', description: '...', parameters: { ... } }, execute: async (args) => fetchWeather(args.city) },
// ])
```

---

## Structured Output (JSON Mode)

```typescript
// src/ai/patterns/structured-output.ts
// Force LLM to return valid JSON matching a schema

import { z } from 'zod'

export async function getStructuredOutput<T>(
  llmClient: LLMProvider,
  prompt: string,
  schema: z.ZodSchema<T>,
  options?: { model?: string; retries?: number },
): Promise<T> {
  const retries = options?.retries || 2

  const schemaDescription = JSON.stringify(zodToJsonSchema(schema), null, 2)

  for (let attempt = 0; attempt <= retries; attempt++) {
    const response = await llmClient.complete({
      systemPrompt: `You are a data extraction assistant. Return ONLY valid JSON matching this schema. No markdown, no explanation, no code blocks — just the raw JSON object.\n\nSchema:\n${schemaDescription}`,
      messages: [{ role: 'user', content: prompt }],
      temperature: 0,
      model: options?.model,
    })

    try {
      // Clean common LLM artifacts
      const cleaned = response.content
        .replace(/```json\n?/g, '')
        .replace(/```\n?/g, '')
        .trim()

      const parsed = JSON.parse(cleaned)
      const validated = schema.parse(parsed)
      return validated
    } catch (error) {
      if (attempt === retries) throw new Error(`Failed to get valid structured output after ${retries + 1} attempts: ${error}`)
      // Retry with error feedback
    }
  }

  throw new Error('Unreachable')
}

// Example: Extract contact info from text
// const ContactSchema = z.object({
//   name: z.string(),
//   email: z.string().email().optional(),
//   phone: z.string().optional(),
//   company: z.string().optional(),
// })
// const contact = await getStructuredOutput(llmClient, emailBody, ContactSchema)
```

---

## Streaming to Client (SSE)

```typescript
// src/ai/patterns/streaming.ts
// Server-Sent Events pattern for real-time LLM responses

import type { FastifyReply, FastifyRequest } from 'fastify'

export async function streamLLMResponse(
  llmClient: LLMProvider,
  messages: LLMMessage[],
  systemPrompt: string,
  reply: FastifyReply,
  options?: { model?: string; onComplete?: (fullText: string, usage: any) => void },
) {
  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',  // Disable nginx buffering
  })

  let fullText = ''

  try {
    const stream = llmClient.stream({ systemPrompt, messages, model: options?.model })

    for await (const chunk of stream) {
      if (chunk.type === 'text') {
        fullText += chunk.text
        reply.raw.write(`data: ${JSON.stringify({ type: 'text', text: chunk.text })}\n\n`)
      }
      if (chunk.type === 'done') {
        reply.raw.write(`data: ${JSON.stringify({ type: 'done', usage: chunk.usage })}\n\n`)
        options?.onComplete?.(fullText, chunk.usage)
      }
    }
  } catch (error: any) {
    reply.raw.write(`data: ${JSON.stringify({ type: 'error', error: error.message })}\n\n`)
  }

  reply.raw.end()
}

// Client-side consumption (browser):
// const evtSource = new EventSource('/api/ai/chat/stream', { method: 'POST', body: ... })
// Or with fetch:
async function consumeStream(url: string, body: object, onChunk: (text: string) => void) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })

  const reader = response.body!.getReader()
  const decoder = new TextDecoder()

  while (true) {
    const { done, value } = await reader.read()
    if (done) break

    const text = decoder.decode(value)
    const lines = text.split('\n').filter(l => l.startsWith('data: '))

    for (const line of lines) {
      const data = JSON.parse(line.slice(6))
      if (data.type === 'text') onChunk(data.text)
      if (data.type === 'done') return data.usage
    }
  }
}
```

---

## Batch Processing

```typescript
// src/ai/patterns/batch.ts
// Process many items efficiently using Anthropic's Batch API or parallel requests

// Option A: Anthropic Batch API (50% cheaper, non-real-time)
export async function batchProcess(
  items: { id: string; prompt: string }[],
  systemPrompt: string,
  options?: { model?: string },
): Promise<Map<string, string>> {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY })

  // Create batch
  const requests = items.map(item => ({
    custom_id: item.id,
    params: {
      model: options?.model || 'claude-sonnet-4-20250514',
      max_tokens: 1024,
      system: systemPrompt,
      messages: [{ role: 'user' as const, content: item.prompt }],
    },
  }))

  const batch = await client.batches.create({ requests })

  // Poll for completion
  let status = batch.processing_status
  while (status !== 'ended') {
    await new Promise(r => setTimeout(r, 10000))  // Poll every 10s
    const updated = await client.batches.retrieve(batch.id)
    status = updated.processing_status
  }

  // Retrieve results
  const results = new Map<string, string>()
  const resultStream = await client.batches.results(batch.id)
  for await (const result of resultStream) {
    if (result.result.type === 'succeeded') {
      const content = result.result.message.content
        .filter((b: any) => b.type === 'text')
        .map((b: any) => b.text)
        .join('')
      results.set(result.custom_id, content)
    }
  }

  return results
}

// Option B: Parallel requests with concurrency control
export async function parallelProcess(
  items: { id: string; prompt: string }[],
  llmClient: LLMProvider,
  systemPrompt: string,
  concurrency = 5,
): Promise<Map<string, string>> {
  const results = new Map<string, string>()
  const queue = [...items]

  async function worker() {
    while (queue.length > 0) {
      const item = queue.shift()!
      try {
        const response = await llmClient.complete({
          systemPrompt,
          messages: [{ role: 'user', content: item.prompt }],
        })
        results.set(item.id, response.content)
      } catch (error: any) {
        results.set(item.id, `ERROR: ${error.message}`)
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => worker()))
  return results
}
```

---

## Classification / Routing

```typescript
// src/ai/patterns/classification.ts
// Use a cheap, fast model to classify inputs before expensive processing

export async function classify<T extends string>(
  llmClient: LLMProvider,
  input: string,
  categories: { value: T; description: string }[],
): Promise<{ category: T; confidence: number }> {
  const categoryList = categories.map(c => `- "${c.value}": ${c.description}`).join('\n')

  const response = await llmClient.complete({
    systemPrompt: `Classify the input into one of these categories. Return ONLY a JSON object with "category" and "confidence" (0-1).\n\nCategories:\n${categoryList}`,
    messages: [{ role: 'user', content: input }],
    temperature: 0,
    maxTokens: 50,
    model: 'claude-haiku-4-5-20251001',  // Always use cheapest model for classification
  })

  try {
    const result = JSON.parse(response.content.replace(/```json\n?|```/g, '').trim())
    return { category: result.category, confidence: result.confidence }
  } catch {
    return { category: categories[0].value, confidence: 0 }
  }
}

// Example: Route customer messages
// const result = await classify(llmClient, message, [
//   { value: 'sales', description: 'Product inquiries, pricing, purchasing' },
//   { value: 'support', description: 'Technical issues, bugs, troubleshooting' },
//   { value: 'billing', description: 'Invoices, payments, refunds' },
//   { value: 'general', description: 'Everything else' },
// ])
```

---

## Prompt Templates

```typescript
// src/ai/patterns/prompts.ts
// Reusable, composable prompt patterns

export const PROMPTS = {
  summarize: (text: string, maxLength = 'concise') =>
    `Summarize the following text ${maxLength === 'concise' ? 'in 2-3 sentences' : 'comprehensively'}:\n\n${text}`,

  extractEntities: (text: string) =>
    `Extract all named entities (people, organizations, locations, dates, monetary amounts) from this text. Return as JSON: { people: [], organizations: [], locations: [], dates: [], amounts: [] }\n\n${text}`,

  translateTo: (text: string, language: string) =>
    `Translate the following text to ${language}. Preserve formatting and tone.\n\n${text}`,

  sentimentAnalysis: (text: string) =>
    `Analyze the sentiment of this text. Return JSON: { sentiment: "positive"|"negative"|"neutral"|"mixed", confidence: 0-1, explanation: string }\n\n${text}`,

  generateSQL: (schema: string, question: string) =>
    `Given this database schema:\n${schema}\n\nGenerate a SQL query to answer: ${question}\n\nReturn ONLY the SQL query, no explanation.`,

  codeReview: (code: string, language: string) =>
    `Review this ${language} code for bugs, security issues, and improvements. Be specific and actionable.\n\n\`\`\`${language}\n${code}\n\`\`\``,
}

// Composable system prompts
export function buildSystemPrompt(parts: {
  role: string
  instructions?: string[]
  constraints?: string[]
  outputFormat?: string
  examples?: { input: string; output: string }[]
}): string {
  let prompt = `You are ${parts.role}.`

  if (parts.instructions?.length) {
    prompt += `\n\nINSTRUCTIONS:\n${parts.instructions.map((inst, i) => `${i + 1}. ${inst}`).join('\n')}`
  }

  if (parts.constraints?.length) {
    prompt += `\n\nCONSTRAINTS:\n${parts.constraints.map(c => `- ${c}`).join('\n')}`
  }

  if (parts.outputFormat) {
    prompt += `\n\nOUTPUT FORMAT:\n${parts.outputFormat}`
  }

  if (parts.examples?.length) {
    prompt += `\n\nEXAMPLES:`
    for (const ex of parts.examples) {
      prompt += `\n\nInput: ${ex.input}\nOutput: ${ex.output}`
    }
  }

  return prompt
}
```

---

## Request/Response Middleware Pattern

```typescript
// Wrap every LLM call with consistent pre/post processing
export function createLLMMiddleware(llmClient: LLMProvider, services: {
  guardrails: GuardrailService
  budget: TokenBudgetService
  audit: AuditLogger
  cache?: SemanticCache
}) {
  return {
    async complete(request: LLMRequest): Promise<LLMResponse> {
      const requestId = crypto.randomUUID()
      const userId = request.metadata?.userId || 'anonymous'

      // Pre: Budget check
      const budgetCheck = await services.budget.check(userId)
      if (!budgetCheck.allowed) throw new Error(`Token budget exceeded: ${budgetCheck.reason}`)

      // Pre: Input guardrails
      const lastMsg = request.messages[request.messages.length - 1]
      const inputText = typeof lastMsg.content === 'string' ? lastMsg.content : ''
      const inputCheck = await services.guardrails.validateInput(inputText)
      if (!inputCheck.allowed) throw new Error(`Input blocked: ${inputCheck.reason}`)

      // Pre: Semantic cache check
      if (services.cache) {
        const cached = await services.cache.get(inputText)
        if (cached.hit) return { content: cached.response!, stopReason: 'end', usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0, estimatedCost: 0 }, model: 'cache', provider: 'cache', latencyMs: 0 }
      }

      // Execute
      const response = await llmClient.complete(request)

      // Post: Output guardrails
      const outputCheck = await services.guardrails.validateOutput(response.content)
      if (!outputCheck.allowed) response.content = 'Response was filtered.'

      // Post: Record usage
      await services.budget.record(userId, request.metadata?.tenantId, response.model, response.usage.inputTokens, response.usage.outputTokens, response.usage.estimatedCost)

      // Post: Audit log
      services.audit.log({ requestId, userId, tenantId: request.metadata?.tenantId, timestamp: new Date(), provider: response.provider, model: response.model, feature: request.metadata?.feature || 'unknown', inputTokens: response.usage.inputTokens, outputTokens: response.usage.outputTokens, estimatedCostUsd: response.usage.estimatedCost, latencyMs: response.latencyMs, status: 'success', guardrailFlags: [] })

      // Post: Cache response
      if (services.cache) await services.cache.set(inputText, response.content)

      return response
    },
  }
}
```

---

## Checklist

- [ ] Tool-use loop: handles multiple iterations, validates args, handles errors
- [ ] Structured output: JSON parsing with retry, schema validation
- [ ] Streaming: SSE endpoint with proper headers, client-side consumption
- [ ] Batch processing: Anthropic Batch API or parallel with concurrency control
- [ ] Classification: cheap model (Haiku/mini) for routing decisions
- [ ] Prompt templates: reusable, composable, tested
- [ ] Middleware: every LLM call passes through guardrails + budget + audit + cache
- [ ] Error handling: parse failures, API errors, timeout — all handled gracefully
