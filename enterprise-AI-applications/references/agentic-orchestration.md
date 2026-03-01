# Agentic Orchestration Reference

## Agent Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Agent Loop                         │
│                                                       │
│  ┌─────────┐   ┌─────────────┐   ┌───────────────┐  │
│  │ Observe  │──▶│   Reason    │──▶│   Act         │  │
│  │ (input + │   │ (LLM plans  │   │ (execute tool │  │
│  │  context)│   │  next step) │   │  or respond)  │  │
│  └─────────┘   └──────┬──────┘   └───────┬───────┘  │
│       ▲               │                   │          │
│       └───────────────┴───────────────────┘          │
│                  Loop until done                      │
└──────────────────────────────────────────────────────┘
```

---

## Tool Registry

```typescript
// src/ai/services/tool-registry.ts
import { z } from 'zod'
import type { ToolDefinition } from '../clients/llm-client'

export interface Tool {
  name: string
  description: string
  parameters: z.ZodSchema
  execute(args: Record<string, unknown>, context: ToolContext): Promise<ToolResult>
  requiresApproval?: boolean       // Human-in-the-loop gate
  timeout?: number                 // Max execution time (ms)
  rateLimit?: { maxPerMinute: number }
}

export interface ToolContext {
  userId: string
  tenantId?: string
  conversationId?: string
  requestId: string
}

export interface ToolResult {
  success: boolean
  data?: unknown
  error?: string
}

export class ToolRegistry {
  private tools: Map<string, Tool> = new Map()

  register(tool: Tool) { this.tools.set(tool.name, tool) }
  get(name: string) { return this.tools.get(name) }
  list() { return Array.from(this.tools.values()) }

  toDefinitions(): ToolDefinition[] {
    return this.list().map(t => ({
      name: t.name,
      description: t.description,
      parameters: zodToJsonSchema(t.parameters),
    }))
  }

  async execute(name: string, args: Record<string, unknown>, context: ToolContext): Promise<ToolResult> {
    const tool = this.get(name)
    if (!tool) return { success: false, error: `Unknown tool: ${name}` }

    // Validate args
    const parsed = tool.parameters.safeParse(args)
    if (!parsed.success) return { success: false, error: `Invalid arguments: ${parsed.error.message}` }

    // Execute with timeout
    const timeout = tool.timeout || 30000
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeout)

    try {
      const result = await tool.execute(parsed.data, context)
      clearTimeout(timer)
      return result
    } catch (error: any) {
      clearTimeout(timer)
      return { success: false, error: error.message || 'Tool execution failed' }
    }
  }
}

// Helper: Convert Zod schema to JSON Schema (for LLM tool definitions)
function zodToJsonSchema(schema: z.ZodSchema): Record<string, unknown> {
  // Use zod-to-json-schema package in production
  // pnpm add zod-to-json-schema
  const { zodToJsonSchema: convert } = require('zod-to-json-schema')
  return convert(schema)
}
```

---

## Example Tools

```typescript
// src/ai/tools/search-database.ts
export const searchDatabaseTool: Tool = {
  name: 'search_database',
  description: 'Search the internal database for records. Use when the user asks about customers, orders, products, or any business data.',
  parameters: z.object({
    table: z.enum(['customers', 'orders', 'products', 'invoices']),
    query: z.string().describe('Search term or filter condition'),
    limit: z.number().min(1).max(50).default(10),
  }),
  async execute(args, context) {
    const results = await db.query(`SELECT * FROM ${args.table} WHERE tenant_id = $1 AND (name ILIKE $2 OR description ILIKE $2) LIMIT $3`,
      [context.tenantId, `%${args.query}%`, args.limit])
    return { success: true, data: results.rows }
  },
}

// src/ai/tools/send-email.ts
export const sendEmailTool: Tool = {
  name: 'send_email',
  description: 'Send an email to a specified recipient. Use when the user explicitly asks to send an email.',
  parameters: z.object({
    to: z.string().email(),
    subject: z.string().max(200),
    body: z.string().max(5000),
  }),
  requiresApproval: true,  // Human must approve before sending
  async execute(args, context) {
    await emailService.send({ to: args.to, subject: args.subject, body: args.body, from: `noreply@${context.tenantId}.app` })
    return { success: true, data: { message: `Email sent to ${args.to}` } }
  },
}

// src/ai/tools/web-search.ts
export const webSearchTool: Tool = {
  name: 'web_search',
  description: 'Search the web for current information. Use when the user asks about recent events or external information not in our database.',
  parameters: z.object({
    query: z.string().max(200),
  }),
  async execute(args) {
    const results = await searchAPI.search(args.query, { maxResults: 5 })
    return { success: true, data: results.map(r => ({ title: r.title, snippet: r.snippet, url: r.url })) }
  },
}

// src/ai/tools/calculate.ts
export const calculateTool: Tool = {
  name: 'calculate',
  description: 'Perform mathematical calculations. Use for any math, statistics, or numerical analysis.',
  parameters: z.object({
    expression: z.string().describe('Mathematical expression (e.g., "2 + 2", "sqrt(144)", "sum(10, 20, 30)")'),
  }),
  async execute(args) {
    const mathjs = require('mathjs')
    const result = mathjs.evaluate(args.expression)
    return { success: true, data: { expression: args.expression, result: String(result) } }
  },
}
```

---

## Agent Loop (Raw SDK)

```typescript
// src/ai/patterns/agent.ts
import type { LLMProvider, LLMMessage, LLMResponse } from '../clients/llm-client'
import { ToolRegistry } from '../services/tool-registry'
import { logger } from '../../lib/logger'

export interface AgentConfig {
  maxIterations: number          // Prevent infinite loops (default: 10)
  systemPrompt: string
  tools: ToolRegistry
  requireApprovalCallback?: (toolName: string, args: Record<string, unknown>) => Promise<boolean>
}

export interface AgentResult {
  response: string
  toolCalls: { tool: string; args: Record<string, unknown>; result: unknown }[]
  iterations: number
  totalUsage: { inputTokens: number; outputTokens: number; estimatedCost: number }
}

export async function runAgent(
  llmClient: LLMProvider,
  initialMessage: string,
  config: AgentConfig,
  context: { userId: string; tenantId?: string; requestId: string },
): Promise<AgentResult> {
  const { maxIterations = 10, systemPrompt, tools } = config
  const messages: LLMMessage[] = [{ role: 'user', content: initialMessage }]
  const toolCallLog: AgentResult['toolCalls'] = []
  let totalUsage = { inputTokens: 0, outputTokens: 0, estimatedCost: 0 }

  for (let iteration = 0; iteration < maxIterations; iteration++) {
    logger.info({ iteration, messageCount: messages.length, requestId: context.requestId }, 'Agent iteration')

    // Call LLM with tools
    const response = await llmClient.complete({
      systemPrompt,
      messages,
      tools: tools.toDefinitions(),
      toolChoice: 'auto',
      metadata: context,
    })

    // Accumulate usage
    totalUsage.inputTokens += response.usage.inputTokens
    totalUsage.outputTokens += response.usage.outputTokens
    totalUsage.estimatedCost += response.usage.estimatedCost

    // If no tool calls — agent is done
    if (!response.toolCalls || response.toolCalls.length === 0) {
      return { response: response.content, toolCalls: toolCallLog, iterations: iteration + 1, totalUsage }
    }

    // Add assistant message with tool calls
    messages.push({ role: 'assistant', content: response.content || '' })

    // Execute each tool call
    for (const toolCall of response.toolCalls) {
      const tool = tools.get(toolCall.name)

      // Human-in-the-loop approval
      if (tool?.requiresApproval && config.requireApprovalCallback) {
        const approved = await config.requireApprovalCallback(toolCall.name, toolCall.arguments)
        if (!approved) {
          messages.push({ role: 'tool', content: 'User declined this action.', toolCallId: toolCall.id })
          toolCallLog.push({ tool: toolCall.name, args: toolCall.arguments, result: 'DECLINED_BY_USER' })
          continue
        }
      }

      // Execute tool
      const result = await tools.execute(toolCall.name, toolCall.arguments, context)

      // Add tool result to conversation
      messages.push({
        role: 'tool',
        content: JSON.stringify(result.data || result.error),
        toolCallId: toolCall.id,
        name: toolCall.name,
      })

      toolCallLog.push({ tool: toolCall.name, args: toolCall.arguments, result: result.data || result.error })
      logger.info({ tool: toolCall.name, success: result.success, requestId: context.requestId }, 'Tool executed')
    }
  }

  // Max iterations reached
  logger.warn({ maxIterations, requestId: context.requestId }, 'Agent reached max iterations')
  return {
    response: 'I was unable to complete this task within the allowed number of steps. Please try breaking it into smaller requests.',
    toolCalls: toolCallLog,
    iterations: maxIterations,
    totalUsage,
  }
}
```

---

## Streaming Agent

```typescript
// For real-time UI: stream both thinking and tool results

export async function* runAgentStreaming(
  llmClient: LLMProvider,
  initialMessage: string,
  config: AgentConfig,
  context: { userId: string; tenantId?: string; requestId: string },
): AsyncIterable<{ type: 'thinking' | 'text' | 'tool_start' | 'tool_result' | 'done'; data: unknown }> {
  const messages: LLMMessage[] = [{ role: 'user', content: initialMessage }]

  for (let i = 0; i < (config.maxIterations || 10); i++) {
    let fullText = ''
    const toolCalls: any[] = []

    // Stream LLM response
    for await (const chunk of llmClient.stream({
      systemPrompt: config.systemPrompt,
      messages,
      tools: config.tools.toDefinitions(),
    })) {
      if (chunk.type === 'text') {
        fullText += chunk.text
        yield { type: 'text', data: chunk.text }
      }
      if (chunk.type === 'tool_call_start') toolCalls.push(chunk.toolCall)
    }

    if (toolCalls.length === 0) {
      yield { type: 'done', data: { iterations: i + 1 } }
      return
    }

    messages.push({ role: 'assistant', content: fullText })

    for (const tc of toolCalls) {
      yield { type: 'tool_start', data: { tool: tc.name, args: tc.arguments } }
      const result = await config.tools.execute(tc.name, tc.arguments, context)
      yield { type: 'tool_result', data: { tool: tc.name, result: result.data } }
      messages.push({ role: 'tool', content: JSON.stringify(result.data), toolCallId: tc.id })
    }
  }
}
```

---

## Multi-Agent Orchestration

```typescript
// Specialized agents that hand off to each other

interface AgentDefinition {
  name: string
  description: string
  systemPrompt: string
  tools: ToolRegistry
  canHandleQuery: (query: string) => boolean  // Routing logic
}

export function createAgentOrchestrator(agents: AgentDefinition[], llmClient: LLMProvider) {
  // Router agent decides which specialized agent handles the query
  return {
    async route(query: string, context: ToolContext): Promise<{ agent: string; result: AgentResult }> {
      // Option A: Rule-based routing
      for (const agent of agents) {
        if (agent.canHandleQuery(query)) {
          const result = await runAgent(llmClient, query, { maxIterations: 10, systemPrompt: agent.systemPrompt, tools: agent.tools }, context)
          return { agent: agent.name, result }
        }
      }

      // Option B: LLM-based routing (when rules aren't sufficient)
      const routerResponse = await llmClient.complete({
        systemPrompt: `You are a routing agent. Given a user query, decide which specialist agent should handle it. Return ONLY the agent name.\n\nAvailable agents:\n${agents.map(a => `- ${a.name}: ${a.description}`).join('\n')}`,
        messages: [{ role: 'user', content: query }],
        temperature: 0,
        model: 'claude-haiku-4-5-20251001',  // Cheap model for routing
      })

      const selectedAgent = agents.find(a => routerResponse.content.toLowerCase().includes(a.name.toLowerCase()))
      if (!selectedAgent) throw new Error('No agent matched the query')

      const result = await runAgent(llmClient, query, { maxIterations: 10, systemPrompt: selectedAgent.systemPrompt, tools: selectedAgent.tools }, context)
      return { agent: selectedAgent.name, result }
    },
  }
}

// Example: Specialized agents
const salesAgent: AgentDefinition = {
  name: 'sales',
  description: 'Handles queries about products, pricing, and orders',
  systemPrompt: 'You are a sales assistant...',
  tools: salesToolRegistry,
  canHandleQuery: (q) => /product|price|order|buy|purchase|catalog/i.test(q),
}

const supportAgent: AgentDefinition = {
  name: 'support',
  description: 'Handles technical support and troubleshooting',
  systemPrompt: 'You are a technical support agent...',
  tools: supportToolRegistry,
  canHandleQuery: (q) => /bug|error|broken|help|issue|problem|fix/i.test(q),
}
```

---

## Safety Constraints for Agents

```typescript
// Critical: Agents can take real actions — safety is paramount

const AGENT_SAFETY_PROMPT = `
SAFETY RULES (never violate):
1. Never execute destructive actions (DELETE, DROP, remove) without explicit user confirmation.
2. Never access data outside the user's tenant/organization.
3. Never send emails, messages, or make external API calls without user approval.
4. If unsure about an action, ask the user for clarification rather than guessing.
5. Always explain what you're about to do before doing it.
6. If a tool returns an error, report it to the user — don't retry indefinitely.
7. Maximum cost per agent run: $0.50. Stop and report if approaching this limit.
`

// Tool execution guardrails
function validateToolCall(toolName: string, args: Record<string, unknown>, context: ToolContext): boolean {
  // Block cross-tenant data access
  if (args.tenantId && args.tenantId !== context.tenantId) return false
  // Block destructive operations without approval flag
  if (['delete_record', 'drop_table', 'send_email'].includes(toolName) && !args._approved) return false
  return true
}
```

---

## Checklist

- [ ] Agent loop with max iteration limit (prevent infinite loops)
- [ ] Tool registry: validated inputs, timeout, error handling
- [ ] Human-in-the-loop: destructive/external actions require approval
- [ ] Streaming agent: real-time tool execution visibility
- [ ] Multi-agent routing: specialized agents for different domains
- [ ] Safety prompt: destructive action prevention, tenant isolation
- [ ] Cost tracking: total tokens across all iterations tracked
- [ ] Tool errors handled gracefully (reported to user, not retried blindly)
