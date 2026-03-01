# Chatbot & Conversational AI Reference

## Chatbot Types

| Type | Use Case | Memory | Tools | Complexity |
|---|---|---|---|---|
| **Simple Q&A** | FAQ, info lookup | None | None | Low |
| **Contextual Chat** | General assistant | Sliding window | None | Low |
| **RAG-Powered** | Document Q&A, support | Window + RAG | Search | Medium |
| **Agent-Powered** | Task execution, workflow | Full + summary | Multiple | High |
| **Support Bot** | Customer service | Full + CRM | Ticket, escalation | Medium-High |

---

## Conversation Memory Strategies

### Strategy 1: Sliding Window (Default)

```typescript
// Keep last N messages — simple, predictable token usage
export class SlidingWindowMemory implements ConversationMemory {
  private messages: LLMMessage[] = []
  private maxMessages: number

  constructor(maxMessages = 20) { this.maxMessages = maxMessages }

  async add(message: LLMMessage) {
    this.messages.push(message)
    if (this.messages.length > this.maxMessages) {
      this.messages = this.messages.slice(-this.maxMessages)
    }
  }

  async getHistory(options?: { maxMessages?: number }) {
    const limit = options?.maxMessages || this.maxMessages
    return this.messages.slice(-limit)
  }

  async clear() { this.messages = [] }
  async summarize() { return '' }
}
```

### Strategy 2: Summary Memory (Long Conversations)

```typescript
// Summarize older messages, keep recent ones verbatim
export class SummaryMemory implements ConversationMemory {
  private messages: LLMMessage[] = []
  private summary: string = ''
  private summaryThreshold = 20    // Summarize after this many messages
  private keepRecent = 6           // Keep this many recent messages verbatim

  constructor(private llmClient: LLMProvider) {}

  async add(message: LLMMessage) {
    this.messages.push(message)
    if (this.messages.length > this.summaryThreshold) {
      await this.compactHistory()
    }
  }

  private async compactHistory() {
    const toSummarize = this.messages.slice(0, -this.keepRecent)
    const response = await this.llmClient.complete({
      systemPrompt: 'Summarize the following conversation concisely, preserving key facts, decisions, and context needed for future messages. Be brief.',
      messages: [{ role: 'user', content: toSummarize.map(m => `${m.role}: ${typeof m.content === 'string' ? m.content : ''}`).join('\n') }],
      temperature: 0,
      maxTokens: 500,
      model: 'claude-haiku-4-5-20251001',
    })
    this.summary = response.content
    this.messages = this.messages.slice(-this.keepRecent)
  }

  async getHistory() {
    const history: LLMMessage[] = []
    if (this.summary) {
      history.push({ role: 'user', content: `[Previous conversation summary: ${this.summary}]` })
    }
    history.push(...this.messages)
    return history
  }

  async clear() { this.messages = []; this.summary = '' }
  async summarize() { return this.summary }
}
```

### Strategy 3: Persistent Database Memory

```typescript
// Store in PostgreSQL for cross-session persistence
export class DatabaseMemory implements ConversationMemory {
  constructor(
    private pool: Pool,
    private conversationId: string,
    private maxMessages = 50,
  ) {}

  async add(message: LLMMessage) {
    await this.pool.query(
      `INSERT INTO conversation_messages (conversation_id, role, content, created_at)
       VALUES ($1, $2, $3, NOW())`,
      [this.conversationId, message.role, typeof message.content === 'string' ? message.content : JSON.stringify(message.content)]
    )
  }

  async getHistory(options?: { maxMessages?: number }) {
    const limit = options?.maxMessages || this.maxMessages
    const result = await this.pool.query(
      `SELECT role, content FROM conversation_messages
       WHERE conversation_id = $1
       ORDER BY created_at DESC LIMIT $2`,
      [this.conversationId, limit]
    )
    return result.rows.reverse().map(r => ({ role: r.role, content: r.content }))
  }

  async clear() {
    await this.pool.query('DELETE FROM conversation_messages WHERE conversation_id = $1', [this.conversationId])
  }

  async summarize() { return '' }
}

// Schema
// CREATE TABLE conversations (
//   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//   user_id TEXT NOT NULL,
//   tenant_id TEXT,
//   title TEXT,
//   created_at TIMESTAMPTZ DEFAULT NOW(),
//   updated_at TIMESTAMPTZ DEFAULT NOW()
// );
// CREATE TABLE conversation_messages (
//   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//   conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
//   role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
//   content TEXT NOT NULL,
//   metadata JSONB DEFAULT '{}',
//   created_at TIMESTAMPTZ DEFAULT NOW()
// );
// CREATE INDEX ON conversation_messages (conversation_id, created_at);
```

---

## Chat Service

```typescript
// src/ai/patterns/chat.ts
export interface ChatConfig {
  systemPrompt: string
  memoryStrategy: 'sliding' | 'summary' | 'database'
  maxMemoryMessages?: number
  enableRAG?: boolean
  enableTools?: boolean
  tools?: ToolRegistry
  personality?: string            // Tone/style customization
  model?: string
}

export function createChatService(llmClient: LLMProvider, config: ChatConfig) {
  return {
    async respond(
      userMessage: string,
      memory: ConversationMemory,
      options?: { userId?: string; tenantId?: string; stream?: boolean }
    ) {
      // Add user message to memory
      await memory.add({ role: 'user', content: userMessage })

      // Build messages from memory
      const history = await memory.getHistory({ maxMessages: config.maxMemoryMessages || 20 })

      // Build system prompt with personality
      const systemPrompt = config.personality
        ? `${config.systemPrompt}\n\nPERSONALITY: ${config.personality}`
        : config.systemPrompt

      const response = await llmClient.complete({
        systemPrompt,
        messages: history,
        tools: config.enableTools ? config.tools?.toDefinitions() : undefined,
        model: config.model,
        metadata: { userId: options?.userId, tenantId: options?.tenantId, feature: 'chat' },
      })

      // Add assistant response to memory
      await memory.add({ role: 'assistant', content: response.content })

      return response
    },

    async *respondStream(userMessage: string, memory: ConversationMemory, options?: { userId?: string; tenantId?: string }) {
      await memory.add({ role: 'user', content: userMessage })
      const history = await memory.getHistory()
      let fullResponse = ''

      for await (const chunk of llmClient.stream({
        systemPrompt: config.systemPrompt,
        messages: history,
        model: config.model,
      })) {
        if (chunk.type === 'text') fullResponse += chunk.text
        yield chunk
      }

      await memory.add({ role: 'assistant', content: fullResponse })
    },
  }
}
```

---

## Customer Support Bot

```typescript
// Specialized chatbot with escalation, ticket creation, knowledge base

const SUPPORT_SYSTEM_PROMPT = `You are a helpful customer support assistant for {COMPANY_NAME}.

Your responsibilities:
1. Answer customer questions using the provided knowledge base.
2. Help troubleshoot common issues step by step.
3. Create support tickets for issues you cannot resolve.
4. Escalate to a human agent when the customer is frustrated or the issue is complex.

Guidelines:
- Be empathetic, patient, and professional.
- Ask clarifying questions before attempting to troubleshoot.
- Always confirm you understand the issue before providing solutions.
- If you can't help, be honest and offer to escalate.
- Never make promises about timelines or outcomes you can't guarantee.
- Never share internal information, policies, or system details.

Escalation triggers (automatically escalate to human):
- Customer explicitly asks for a human agent
- Issue involves billing disputes or refunds over $100
- Customer has messaged more than 5 times without resolution
- Customer uses hostile or abusive language
- Issue requires access to internal systems you can't reach`

export function createSupportBot(llmClient: LLMProvider, ragPipeline: RAGPipeline, tools: ToolRegistry) {
  const chat = createChatService(llmClient, {
    systemPrompt: SUPPORT_SYSTEM_PROMPT,
    memoryStrategy: 'database',
    enableRAG: true,
    enableTools: true,
    tools,
    personality: 'Warm, professional, solution-oriented. Uses simple language.',
  })

  return {
    async handleMessage(message: string, conversationId: string, userId: string) {
      // Check for escalation triggers
      const escalation = checkEscalationTriggers(message, conversationId)
      if (escalation.shouldEscalate) {
        return { type: 'escalation', reason: escalation.reason, handoffTo: 'human_agent' }
      }

      // RAG: search knowledge base for relevant articles
      const ragResults = await ragPipeline.query(message, { topK: 3 })

      // Augment system prompt with knowledge base results
      const contextAugment = ragResults.sources.length > 0
        ? `\n\nRelevant knowledge base articles:\n${ragResults.sources.map(s => s.content).join('\n\n')}`
        : ''

      const memory = new DatabaseMemory(pool, conversationId)
      const response = await chat.respond(message + contextAugment, memory, { userId })

      return { type: 'response', content: response.content, sources: ragResults.sources }
    },
  }
}

function checkEscalationTriggers(message: string, conversationId: string) {
  if (/speak to (a |an )?(human|agent|person|manager|supervisor)/i.test(message)) {
    return { shouldEscalate: true, reason: 'Customer requested human agent' }
  }
  if (/refund|chargeback|dispute/i.test(message)) {
    return { shouldEscalate: true, reason: 'Billing dispute detected' }
  }
  return { shouldEscalate: false, reason: '' }
}
```

---

## Streaming Chat API Endpoint

```typescript
// SSE streaming endpoint for real-time chat responses
app.post('/api/ai/chat/stream', { preHandler: [authGuard] }, async (req, reply) => {
  const { message, conversationId } = ChatSchema.parse(req.body)
  const convId = conversationId || crypto.randomUUID()

  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Conversation-Id': convId,
  })

  const memory = new DatabaseMemory(pool, convId, 20)
  const stream = chatService.respondStream(message, memory, { userId: req.user.id, tenantId: req.user.tenantId })

  for await (const chunk of stream) {
    if (chunk.type === 'text') {
      reply.raw.write(`data: ${JSON.stringify({ type: 'text', text: chunk.text })}\n\n`)
    }
    if (chunk.type === 'done') {
      reply.raw.write(`data: ${JSON.stringify({ type: 'done', conversationId: convId, usage: chunk.usage })}\n\n`)
    }
  }

  reply.raw.end()
})
```

---

## Conversation Title Generation

```typescript
// Auto-generate conversation title from first message
export async function generateConversationTitle(firstMessage: string, llmClient: LLMProvider): Promise<string> {
  const response = await llmClient.complete({
    systemPrompt: 'Generate a short title (3-6 words) for a conversation that starts with this message. Return ONLY the title, nothing else.',
    messages: [{ role: 'user', content: firstMessage }],
    temperature: 0.5,
    maxTokens: 20,
    model: 'claude-haiku-4-5-20251001',
  })
  return response.content.replace(/^["']|["']$/g, '').trim()
}
```

---

## Checklist

- [ ] Memory strategy selected (sliding window default, summary for long chats, DB for persistence)
- [ ] Memory bounded: won't exceed context window regardless of conversation length
- [ ] Streaming: SSE endpoint delivers partial responses in real-time
- [ ] Conversation persistence: messages stored in DB with conversation grouping
- [ ] Escalation: human handoff triggers for support bots
- [ ] Personality: system prompt includes tone/style guidance
- [ ] Title generation: auto-title from first message
- [ ] Multi-tenant: conversations isolated by tenant
- [ ] History loading: existing conversations resumable
