---
name: enterprise-ai-applications
description: Trigger this skill whenever the user wants to build AI-powered features or applications. This includes RAG (retrieval-augmented generation), document Q&A, knowledge base search, AI agents, tool use, multi-step reasoning, agentic workflows, orchestration, chatbots, conversational AI, customer support bots, internal assistants, AI chat, multimodal AI (vision, audio, PDF analysis, image understanding), LangChain, LangGraph, AI evaluation, LLM testing, prompt engineering for applications, streaming chat UI, conversation memory, AI pipeline, agent loop, function calling, structured output, or any request to add AI/LLM capabilities to an application. Also trigger when the user asks how to make an app "smart", add "AI features", or integrate LLM capabilities into existing software. This skill covers application patterns; for infrastructure setup (providers, vector DBs, safety, cost), see enterprise-ai-foundations.
---

# Enterprise AI Applications Skill

This skill covers the application patterns built on top of the AI foundation layer: RAG pipelines, agentic orchestration, conversational AI, and multimodal processing. Every pattern uses the provider-agnostic interfaces defined in `enterprise-ai-foundations` — meaning you can switch LLM providers, vector databases, or cloud environments without rewriting application logic.

## Reference Files

Read this SKILL.md first for pattern selection, then consult the relevant reference files:

### Core Patterns (by priority)
1. `references/rag-pipelines.md` — Full RAG: ingestion→retrieval→generation, hybrid search, reranking, citations, conversational RAG with memory
2. `references/agentic-orchestration.md` — Tool use, multi-step reasoning, planning loops, agent handoffs, human-in-the-loop, parallel tool execution
3. `references/chatbot-conversational.md` — Customer support bots, internal assistants, conversation memory strategies, streaming, escalation, personality
4. `references/multimodal-pipelines.md` — Vision (image analysis, OCR), audio (transcription, TTS), PDF processing, multi-format document Q&A

### Media Generation
5. `references/ai-video-generation.md` — Google Veo 3.1 image-to-video (REST + SDK), multi-clip FFmpeg crossfade stitching, EXIF stripping, cross-browser video serving, async polling

### Framework & Implementation
6. `references/langchain-langgraph.md` — LangChain chains/retrievers, LangGraph state machines, tool nodes, conditional routing, checkpointing
7. `references/raw-sdk-patterns.md` — No-framework: direct API tool use, streaming, structured output (JSON mode), batch processing, function calling
8. `references/evaluation-testing.md` — RAG evaluation (faithfulness, relevance), agent testing, LLM-as-judge, regression benchmarks, A/B testing

### Local / Offline AI
9. `references/local-offline-embeddings.md` — `@huggingface/transformers` (transformers.js): ONNX/WASM in Node.js, model selection, batch API shape (critical gotcha), quantized models (q8), cosine similarity, lazy load pattern for MCP servers, performance benchmarks by hardware

---

## Pattern Selection: What Should You Build?

### Decision Matrix

| User Need | Pattern | Complexity | Reference |
|---|---|---|---|
| "Search our documents and answer questions" | **RAG** | Medium | rag-pipelines.md |
| "AI that can take actions (send email, query DB, call APIs)" | **Agent** | High | agentic-orchestration.md |
| "Chat interface for customer support / internal help" | **Chatbot** | Low-Medium | chatbot-conversational.md |
| "Analyze images, PDFs, or audio files" | **Multimodal** | Medium | multimodal-pipelines.md |
| "Simple Q&A without documents" | **Direct LLM** | Low | raw-sdk-patterns.md |
| "Complex multi-step workflow with branching logic" | **Agent + LangGraph** | High | agentic-orchestration.md + langchain-langgraph.md |
| "Summarize / extract data from uploaded files" | **Multimodal + RAG** | Medium | multimodal-pipelines.md + rag-pipelines.md |

### Complexity Assessment

```
Level 1 — Direct LLM (no retrieval, no tools)
├── Simple chat, text generation, summarization
├── Use: raw-sdk-patterns.md
└── Time: hours

Level 2 — RAG (retrieval + generation)
├── Document Q&A, knowledge base, search + answer
├── Use: rag-pipelines.md + enterprise-ai-foundations
└── Time: days

Level 3 — Conversational AI (memory + context management)
├── Support bots, assistants with history, multi-turn
├── Use: chatbot-conversational.md + rag-pipelines.md
└── Time: days-week

Level 4 — Agentic (tools + reasoning + orchestration)
├── Multi-step tasks, API integration, decision-making
├── Use: agentic-orchestration.md + langchain-langgraph.md
└── Time: weeks

Level 5 — Multi-Agent Systems (agent coordination)
├── Specialized agents collaborating, complex workflows
├── Use: agentic-orchestration.md (advanced section)
└── Time: weeks-months
```

### Framework vs Raw SDK Decision

| Factor | Use Framework (LangChain/LangGraph) | Use Raw SDK |
|---|---|---|
| Complex agent graphs with state | ✅ LangGraph excels | Possible but manual |
| Simple RAG or chat | Overkill | ✅ Simpler, fewer deps |
| Need checkpointing/replay | ✅ Built-in | Must build yourself |
| Team familiarity | If team knows LC/LG | If team prefers direct API |
| Vendor lock-in concern | Medium (framework coupling) | ✅ Minimal dependencies |
| Debugging / transparency | Harder (abstraction layers) | ✅ Full control |
| Speed of prototyping | ✅ Faster for complex patterns | Faster for simple patterns |

**Default recommendation:** Start with raw SDK patterns for Level 1-2. Move to LangGraph for Level 4-5 when you need state machines, checkpointing, or complex agent coordination.

---

## Architecture: How Patterns Compose

```
┌─────────────────────────────────────────────────────┐
│              Application Patterns                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │   RAG    │ │  Agent   │ │ Chatbot  │ │ Multi- │ │
│  │ Pipeline │ │  Loop    │ │ + Memory │ │ modal  │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
│       └─────────────┼────────────┼────────────┘     │
│  ┌──────────────────▼────────────▼─────────────────┐│
│  │         Shared Services Layer                    ││
│  │  Retrieval Engine │ Tool Registry │ Memory Mgr   ││
│  └──────────────────────────┬──────────────────────┘│
└─────────────────────────────┼───────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────┐
│           AI Foundation Layer                        │
│  (enterprise-ai-foundations skill)                   │
│  LLM Client │ Vector Store │ Guardrails │ Governance │
└─────────────────────────────────────────────────────┘
```

---

## Shared Services

### Retrieval Engine (used by RAG, Chatbot, Agent)

```typescript
// src/ai/services/retrieval.ts
export interface RetrievalResult {
  chunks: { content: string; source: string; score: number; metadata: Record<string, unknown> }[]
  query: string
  retrievalTimeMs: number
}

export interface RetrievalEngine {
  retrieve(query: string, options?: { topK?: number; tenantId?: string; filter?: Record<string, unknown> }): Promise<RetrievalResult>
}
```

### Tool Registry (used by Agent, Chatbot)

```typescript
// src/ai/services/tool-registry.ts
export interface Tool {
  name: string
  description: string
  parameters: Record<string, unknown>
  execute(args: Record<string, unknown>, context: { userId: string; tenantId?: string }): Promise<unknown>
  requiresApproval?: boolean
}

export interface ToolRegistry {
  register(tool: Tool): void
  get(name: string): Tool | undefined
  list(): Tool[]
  toDefinitions(): ToolDefinition[]
}
```

### Conversation Memory (used by Chatbot, RAG, Agent)

```typescript
// src/ai/services/memory.ts
export interface ConversationMemory {
  add(message: LLMMessage): Promise<void>
  getHistory(options?: { maxTokens?: number; maxMessages?: number }): Promise<LLMMessage[]>
  clear(): Promise<void>
  summarize(): Promise<string>
}
```

---

## Integration with Foundation Skill

| This Skill Uses | From enterprise-ai-foundations |
|---|---|
| `llmClient.complete()` / `.stream()` | provider-abstraction.md |
| `vectorStore.search()` | vector-databases.md |
| `embeddingClient.embed()` | embeddings-chunking.md |
| `guardrails.validateInput()` / `.validateOutput()` | ai-safety-guardrails.md |
| `tokenBudget.check()` / `.record()` | cost-governance.md |
| `ingestDocument()` | embeddings-chunking.md |

---

## Verification Checklist

- [ ] Pattern selected based on complexity assessment (not over-engineered)
- [ ] Foundation layer configured: LLM client, vector store, guardrails, budgets
- [ ] Retrieval returns relevant results (test with known Q&A pairs)
- [ ] Streaming works end-to-end (server → client, partial responses visible)
- [ ] Conversation memory bounded (won't grow unbounded and exceed context)
- [ ] Tools validated: inputs checked, outputs structured, errors handled
- [ ] Citations traceable: user can verify where the answer came from
- [ ] Evaluation suite: automated tests for accuracy, relevance, safety
- [ ] Error handling: LLM failures, empty retrieval, tool errors all handled gracefully
- [ ] Cost tracked: every AI interaction audited with token count and estimated cost
