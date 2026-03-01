# LangChain & LangGraph Reference

## When to Use

| Scenario | Use LangChain | Use LangGraph | Use Raw SDK |
|---|---|---|---|
| Simple RAG | Optional (LCEL chains) | No | ✅ Preferred |
| Multi-step chain | ✅ LCEL pipes | No | ✅ Also fine |
| Agent with tools | ✅ createToolCallingAgent | ✅ If complex routing | ✅ Simple agent loop |
| Stateful workflow | No | ✅ State machines | Manual state mgmt |
| Multi-agent | No | ✅ Agent handoffs | Complex to build |
| Checkpointing/replay | No | ✅ Built-in | Must build yourself |
| Human-in-the-loop | No | ✅ interrupt_before | Manual callbacks |

**LangGraph is the primary recommendation for Level 4-5 complexity.** LangChain's LCEL is useful for composable chains but optional.

---

## LangChain Setup (TypeScript)

```bash
pnpm add langchain @langchain/core @langchain/anthropic @langchain/openai @langchain/community
```

### Basic Chain (LCEL)

```typescript
import { ChatAnthropic } from '@langchain/anthropic'
import { ChatPromptTemplate } from '@langchain/core/prompts'
import { StringOutputParser } from '@langchain/core/output_parsers'

const model = new ChatAnthropic({ model: 'claude-sonnet-4-20250514' })

// Simple chain: prompt → model → parse output
const chain = ChatPromptTemplate.fromMessages([
  ['system', 'You are a helpful assistant that summarizes documents concisely.'],
  ['human', 'Summarize this document:\n\n{document}'],
])
  .pipe(model)
  .pipe(new StringOutputParser())

const summary = await chain.invoke({ document: 'Long document text here...' })
```

### RAG Chain with Retriever

```typescript
import { ChatAnthropic } from '@langchain/anthropic'
import { createStuffDocumentsChain } from 'langchain/chains/combine_documents'
import { createRetrievalChain } from 'langchain/chains/retrieval'
import { PGVectorStore } from '@langchain/community/vectorstores/pgvector'
import { OpenAIEmbeddings } from '@langchain/openai'

const embeddings = new OpenAIEmbeddings({ model: 'text-embedding-3-small' })
const vectorStore = await PGVectorStore.initialize(embeddings, { postgresConnectionOptions: { connectionString: env.DATABASE_URL }, tableName: 'documents' })
const retriever = vectorStore.asRetriever({ k: 5 })

const llm = new ChatAnthropic({ model: 'claude-sonnet-4-20250514', temperature: 0.3 })

const combineDocsChain = await createStuffDocumentsChain({
  llm,
  prompt: ChatPromptTemplate.fromMessages([
    ['system', 'Answer questions based only on the provided context. Cite sources.\n\nContext: {context}'],
    ['human', '{input}'],
  ]),
})

const ragChain = await createRetrievalChain({ retriever, combineDocsChain })

const result = await ragChain.invoke({ input: 'What is our refund policy?' })
// result.answer, result.context (retrieved docs)
```

### Tool-Calling Agent

```typescript
import { ChatAnthropic } from '@langchain/anthropic'
import { createToolCallingAgent, AgentExecutor } from 'langchain/agents'
import { DynamicStructuredTool } from '@langchain/core/tools'
import { z } from 'zod'

const searchTool = new DynamicStructuredTool({
  name: 'search_database',
  description: 'Search the database for records',
  schema: z.object({ query: z.string(), table: z.enum(['customers', 'orders']) }),
  func: async ({ query, table }) => {
    const results = await db.query(`SELECT * FROM ${table} WHERE name ILIKE $1 LIMIT 5`, [`%${query}%`])
    return JSON.stringify(results.rows)
  },
})

const llm = new ChatAnthropic({ model: 'claude-sonnet-4-20250514' })
const agent = createToolCallingAgent({ llm, tools: [searchTool], prompt: agentPrompt })
const executor = new AgentExecutor({ agent, tools: [searchTool], maxIterations: 10 })

const result = await executor.invoke({ input: 'Find all orders for Acme Corp' })
```

---

## LangGraph (Stateful Agent Workflows)

```bash
pnpm add @langchain/langgraph
```

### Core Concepts

```
StateGraph: Defines nodes (functions) and edges (transitions)
State: Shared data that flows through the graph
Nodes: Functions that read/modify state
Edges: Connections between nodes (conditional or fixed)
Checkpointer: Persists state for resume/replay
```

### Basic Agent Graph

```typescript
import { StateGraph, Annotation, END } from '@langchain/langgraph'
import { ChatAnthropic } from '@langchain/anthropic'
import { ToolNode } from '@langchain/langgraph/prebuilt'

// Define state schema
const AgentState = Annotation.Root({
  messages: Annotation<BaseMessage[]>({ reducer: (prev, next) => [...prev, ...next] }),
  iterations: Annotation<number>({ reducer: (_, next) => next, default: () => 0 }),
})

const model = new ChatAnthropic({ model: 'claude-sonnet-4-20250514' }).bindTools(tools)

// Node: Call the LLM
async function callModel(state: typeof AgentState.State) {
  const response = await model.invoke(state.messages)
  return { messages: [response], iterations: state.iterations + 1 }
}

// Node: Execute tools
const toolNode = new ToolNode(tools)

// Conditional edge: should we continue or stop?
function shouldContinue(state: typeof AgentState.State) {
  const lastMessage = state.messages[state.messages.length - 1]
  if (lastMessage.tool_calls?.length > 0) return 'tools'
  return END
}

// Build graph
const graph = new StateGraph(AgentState)
  .addNode('agent', callModel)
  .addNode('tools', toolNode)
  .addEdge('__start__', 'agent')
  .addConditionalEdges('agent', shouldContinue, { tools: 'tools', [END]: END })
  .addEdge('tools', 'agent')  // After tools, go back to agent

const app = graph.compile()

// Run
const result = await app.invoke({
  messages: [new HumanMessage('Find all orders for Acme Corp and calculate the total')],
})
```

### With Checkpointing (Resume/Replay)

```typescript
import { MemorySaver } from '@langchain/langgraph'
// Or for production: PostgresSaver, RedisSaver

const checkpointer = new MemorySaver()
const app = graph.compile({ checkpointer })

// Each conversation gets a thread_id
const config = { configurable: { thread_id: 'conversation-123' } }

// First message
await app.invoke({ messages: [new HumanMessage('Find orders for Acme')] }, config)

// Continue same thread (state is preserved)
await app.invoke({ messages: [new HumanMessage('Now calculate the total')] }, config)

// Replay from a specific checkpoint
const history = await checkpointer.list(config)
```

### Human-in-the-Loop

```typescript
const graph = new StateGraph(AgentState)
  .addNode('agent', callModel)
  .addNode('tools', toolNode)
  .addNode('human_review', async (state) => {
    // This node pauses execution — the graph stops here
    // Resume by calling app.invoke() again with approval
    return state
  })
  .addEdge('__start__', 'agent')
  .addConditionalEdges('agent', (state) => {
    const lastMsg = state.messages[state.messages.length - 1]
    if (!lastMsg.tool_calls?.length) return END
    // Check if any tool requires approval
    const needsApproval = lastMsg.tool_calls.some(tc => ['send_email', 'delete_record'].includes(tc.name))
    return needsApproval ? 'human_review' : 'tools'
  })
  .addEdge('human_review', 'tools')  // After approval, execute tools
  .addEdge('tools', 'agent')

const app = graph.compile({ checkpointer, interruptBefore: ['human_review'] })
```

### Multi-Agent Graph

```typescript
// Supervisor agent routes to specialized worker agents

const SupervisorState = Annotation.Root({
  messages: Annotation<BaseMessage[]>({ reducer: (prev, next) => [...prev, ...next] }),
  currentAgent: Annotation<string>({ reducer: (_, next) => next, default: () => 'supervisor' }),
})

async function supervisor(state: typeof SupervisorState.State) {
  const response = await supervisorLLM.invoke([
    new SystemMessage('You are a supervisor. Route the user request to the appropriate agent: "researcher", "writer", or "coder". Respond with ONLY the agent name.'),
    ...state.messages,
  ])
  return { currentAgent: response.content.trim().toLowerCase() }
}

async function researcher(state: typeof SupervisorState.State) {
  const response = await researcherLLM.invoke([new SystemMessage('You are a research agent...'), ...state.messages])
  return { messages: [response] }
}

async function writer(state: typeof SupervisorState.State) {
  const response = await writerLLM.invoke([new SystemMessage('You are a writing agent...'), ...state.messages])
  return { messages: [response] }
}

const graph = new StateGraph(SupervisorState)
  .addNode('supervisor', supervisor)
  .addNode('researcher', researcher)
  .addNode('writer', writer)
  .addEdge('__start__', 'supervisor')
  .addConditionalEdges('supervisor', (state) => state.currentAgent, {
    researcher: 'researcher',
    writer: 'writer',
  })
  .addEdge('researcher', 'supervisor')  // Report back to supervisor
  .addEdge('writer', END)
```

---

## Production Considerations

```typescript
// Use PostgreSQL checkpointer for production (not MemorySaver)
// pnpm add @langchain/langgraph-checkpoint-postgres

import { PostgresSaver } from '@langchain/langgraph-checkpoint-postgres'
const checkpointer = PostgresSaver.fromConnString(env.DATABASE_URL)
await checkpointer.setup()  // Creates necessary tables

// Streaming with LangGraph
const stream = await app.streamEvents({ messages: [new HumanMessage('...')] }, config, { version: 'v2' })
for await (const event of stream) {
  if (event.event === 'on_chat_model_stream') {
    process.stdout.write(event.data.chunk.content)
  }
}
```

---

## Checklist

- [ ] Framework choice justified (LangGraph for stateful/complex, raw SDK for simple)
- [ ] State schema defined with proper reducers
- [ ] Conditional edges handle all routing cases (including END)
- [ ] Max iterations / recursion limit set to prevent infinite loops
- [ ] Checkpointer configured (PostgreSQL for production)
- [ ] Human-in-the-loop: interruptBefore for approval-gated actions
- [ ] Streaming events propagated to client
- [ ] Error handling in each node (node failures don't crash the graph)
