---
name: enterprise-ai-foundations
description: Trigger this skill whenever the user mentions AI infrastructure, LLM integration, embeddings, vector database, vector search, semantic search, RAG infrastructure, chunking, document ingestion, AI provider, model selection, Azure OpenAI, AWS Bedrock, Claude API, OpenAI API, Gemini API, local models, Ollama, AI safety, guardrails, content filtering, prompt injection, PII detection, AI cost management, token budget, AI governance, AI compliance, AI audit logging, model routing, LLM abstraction, embedding pipeline, or any foundational AI/ML infrastructure work. Also trigger when the user needs to set up the plumbing that AI features depend on — provider clients, vector stores, document processing, safety layers, or cost controls — even if they don't use these exact terms. This skill covers the infrastructure layer; for application patterns (RAG, agents, chatbots, multimodal), see enterprise-ai-applications.
---

# Enterprise AI Foundations Skill

This skill covers the infrastructure layer that every AI feature sits on: LLM provider abstraction, vector databases, embedding pipelines, document ingestion, safety guardrails, and cost governance. It is provider-agnostic by design — applications built on this layer can switch between Claude, OpenAI, Gemini, or local models without rewriting business logic.

## Reference Files

Read this SKILL.md first for architecture decisions, then consult the relevant reference files:

### Provider & Model Infrastructure
- `references/provider-abstraction.md` — Unified LLM client wrapping Claude, OpenAI, Gemini, local models. Streaming, retries, fallback chains, model routing.
- `references/azure-ai-services.md` — Enterprise Path A: Azure OpenAI, Azure AI Search, Azure Document Intelligence, Managed Identity.
- `references/aws-bedrock.md` — Enterprise Path B: AWS Bedrock (Claude, Titan, Llama), Knowledge Bases, Guardrails API, IAM auth.

### Data & Retrieval Infrastructure
- `references/vector-databases.md` — Selection matrix and setup for pgvector, Pinecone, Azure AI Search, Qdrant, Weaviate, ChromaDB.
- `references/embeddings-chunking.md` — Embedding model selection, chunking strategies, document ingestion pipelines (PDF, DOCX, HTML, images), metadata extraction.

### Safety & Governance
- `references/ai-safety-guardrails.md` — Content filtering, prompt injection defense, PII detection/redaction, hallucination mitigation, toxicity filtering.
- `references/cost-governance.md` — Token budgeting, per-user/tenant rate limiting, semantic caching, audit logging, compliance, data residency.

### Multimodal & Fallback Architecture
- `references/multimodal-fallback-chains.md` — Capability-matching across fallback tiers, multimodal provider comparison, image format for OpenAI-compatible APIs, Zod runtime validation for AI outputs.

---

## Decision Framework: Choosing Your AI Infrastructure

### Environment Selection (Consistent with Other Enterprise Skills)

| Question | Enterprise: Azure (Env A1) | Enterprise: AWS (Env A2) | Standalone (Env B) |
|---|---|---|---|
| LLM access | Azure OpenAI (dedicated capacity) | AWS Bedrock (on-demand) | Direct API (Claude, OpenAI, etc.) |
| Vector search | Azure AI Search | Amazon OpenSearch / Bedrock Knowledge Bases | pgvector / Pinecone / Qdrant |
| Document processing | Azure Document Intelligence | Amazon Textract | Unstructured.io / custom parsers |
| Secrets | Key Vault + Managed Identity | Secrets Manager + IAM roles | .env / Doppler |
| Guardrails | Azure Content Safety + custom | Bedrock Guardrails + custom | Custom middleware |
| Compliance | Built-in Azure compliance | Built-in AWS compliance | Self-managed |
| Data residency | Azure region selection | AWS region selection | Your responsibility |
| Cost model | Provisioned throughput (PTU) or pay-per-token | On-demand per-token | Per-token from provider |

### LLM Provider Selection

| Provider | Best For | Strengths | Considerations |
|---|---|---|---|
| **Anthropic Claude** | Complex reasoning, long context, safety-critical | 200K context, excellent instruction following, tool use | API-only (or via Azure/AWS) |
| **OpenAI GPT-4o** | Broad capability, multimodal, ecosystem | Large ecosystem, function calling, vision | Higher cost at scale |
| **Google Gemini** | Long context, multimodal, Google ecosystem | 1M+ context, native multimodal | Newer enterprise story |
| **Local models (Ollama)** | Privacy, offline, cost savings | Zero API cost, full data control | Lower quality, requires GPU |
| **Azure OpenAI** | Enterprise compliance, dedicated capacity | SLA, data residency, VNet integration | Azure lock-in, provisioning delay |
| **AWS Bedrock** | Multi-model access, AWS ecosystem | Claude + many models, Knowledge Bases | AWS ecosystem coupling |

### Model Tier Strategy

Every AI application should have a model routing strategy — not every request needs the most expensive model:

```
Tier 1 (Fast/Cheap): Claude Haiku / GPT-4o-mini / Gemini Flash
  → Classification, extraction, simple Q&A, routing decisions
  → < 50ms latency target, < $0.001 per request

Tier 2 (Balanced): Claude Sonnet / GPT-4o / Gemini Pro
  → RAG generation, conversational AI, moderate reasoning
  → < 2s latency target, < $0.01 per request

Tier 3 (Maximum): Claude Opus / GPT-4o (high reasoning) / Gemini Ultra
  → Complex analysis, multi-step agents, critical decisions
  → < 10s acceptable, < $0.10 per request
```

### Vector Database Selection

| Database | Best For | Hosting | Scaling | Cost |
|---|---|---|---|---|
| **pgvector** | Already using PostgreSQL, < 5M vectors | Self-hosted or managed PG | Vertical | Low (free with PG) |
| **Azure AI Search** | Enterprise Azure, hybrid search built-in | Managed Azure | Auto | Medium-High |
| **Pinecone** | Fully managed, serverless scaling | Cloud (managed) | Automatic | Medium |
| **Qdrant** | Open-source, high performance, rich filtering | Self-hosted or cloud | Horizontal | Low-Medium |
| **Weaviate** | Multi-modal, built-in vectorization | Self-hosted or cloud | Horizontal | Low-Medium |
| **ChromaDB** | Prototyping, simple API, embedded mode | Embedded or server | Limited | Free |

**Default recommendation:** pgvector for standalone (you already have PostgreSQL from the database skill), Azure AI Search for Azure enterprise, Pinecone for managed standalone at scale.

---

## Architecture: Provider Abstraction Layer

The abstraction layer is the core pattern. All AI features call through this layer — never direct provider SDKs in business logic.

```
┌─────────────────────────────────────────────────────┐
│                  Application Layer                    │
│  (RAG, Agents, Chatbots, Multimodal)                 │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              AI Foundation Layer                      │
│  ┌──────────────┐  ┌────────────┐  ┌──────────────┐│
│  │ LLM Client   │  │ Vector     │  │ Document     ││
│  │ (provider-   │  │ Store      │  │ Processor    ││
│  │  agnostic)   │  │ (search)   │  │ (ingest)     ││
│  └──────┬───────┘  └──────┬─────┘  └──────┬───────┘│
│  ┌──────┴───────┐  ┌──────┴─────┐  ┌──────┴───────┐│
│  │ Safety       │  │ Embedding  │  │ Chunking     ││
│  │ Guardrails   │  │ Client     │  │ Engine       ││
│  └──────────────┘  └────────────┘  └──────────────┘│
│  ┌──────────────────────────────────────────────────┐│
│  │ Cost Governance (budgets, caching, audit)         ││
│  └──────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              Provider Layer (swappable)               │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────────┐ │
│  │ Claude │ │ OpenAI │ │ Gemini │ │ Azure/AWS/   │ │
│  │  API   │ │  API   │ │  API   │ │ Ollama/Local │ │
│  └────────┘ └────────┘ └────────┘ └──────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## Priority Order

1. **Safety** — Guardrails on inputs and outputs, prompt injection defense, PII protection
2. **Data Integrity** — Embeddings are accurate, retrieval is relevant, citations are traceable
3. **Cost Control** — Token budgets enforced, caching active, model routing optimized
4. **Performance** — Streaming responses, parallel retrieval, connection pooling
5. **Scalability** — Horizontal scaling of vector search, queue-based ingestion, multi-tenant isolation

---

## Project Structure

```
src/
├── ai/
│   ├── clients/
│   │   ├── llm-client.ts          # Provider-agnostic LLM interface
│   │   ├── embedding-client.ts    # Provider-agnostic embedding interface
│   │   ├── providers/
│   │   │   ├── anthropic.ts       # Claude implementation
│   │   │   ├── openai.ts          # OpenAI implementation
│   │   │   ├── azure-openai.ts    # Azure OpenAI implementation
│   │   │   ├── bedrock.ts         # AWS Bedrock implementation
│   │   │   ├── gemini.ts          # Google Gemini implementation
│   │   │   └── ollama.ts          # Local model implementation
│   │   └── router.ts             # Model routing / fallback logic
│   ├── vector/
│   │   ├── vector-store.ts        # Provider-agnostic vector interface
│   │   ├── providers/
│   │   │   ├── pgvector.ts
│   │   │   ├── pinecone.ts
│   │   │   ├── azure-search.ts
│   │   │   ├── qdrant.ts
│   │   │   └── chromadb.ts
│   │   └── embeddings.ts         # Embedding generation + caching
│   ├── ingestion/
│   │   ├── chunker.ts            # Chunking strategies
│   │   ├── parsers/
│   │   │   ├── pdf.ts
│   │   │   ├── docx.ts
│   │   │   ├── html.ts
│   │   │   ├── markdown.ts
│   │   │   └── image.ts
│   │   └── pipeline.ts           # Document → chunks → embeddings → store
│   ├── safety/
│   │   ├── guardrails.ts         # Input/output filtering
│   │   ├── injection-detect.ts   # Prompt injection detection
│   │   ├── pii-redactor.ts       # PII detection and redaction
│   │   └── content-filter.ts     # Toxicity / harmful content
│   ├── governance/
│   │   ├── token-budget.ts       # Per-user/tenant token tracking
│   │   ├── rate-limiter.ts       # AI-specific rate limiting
│   │   ├── semantic-cache.ts     # Cache similar queries
│   │   ├── audit-logger.ts       # Log all AI interactions
│   │   └── compliance.ts         # Data residency, retention
│   └── index.ts                  # Public API exports
├── config/
│   └── ai.ts                    # AI-specific configuration
└── tests/
    └── ai/
        ├── llm-client.test.ts
        ├── vector-store.test.ts
        └── guardrails.test.ts
```

---

## Configuration Pattern

```typescript
// src/config/ai.ts
import { z } from 'zod'

export const AIConfigSchema = z.object({
  // Primary LLM provider
  llm: z.object({
    provider: z.enum(['anthropic', 'openai', 'azure-openai', 'bedrock', 'gemini', 'ollama']),
    model: z.string(),
    fallbackProvider: z.enum(['anthropic', 'openai', 'azure-openai', 'bedrock', 'gemini', 'ollama']).optional(),
    fallbackModel: z.string().optional(),
    maxTokens: z.number().default(4096),
    temperature: z.number().min(0).max(2).default(0.7),
  }),

  // Embedding provider
  embedding: z.object({
    provider: z.enum(['openai', 'azure-openai', 'bedrock', 'ollama', 'cohere']),
    model: z.string(),
    dimensions: z.number(),
  }),

  // Vector store
  vector: z.object({
    provider: z.enum(['pgvector', 'pinecone', 'azure-search', 'qdrant', 'weaviate', 'chromadb']),
  }),

  // Safety
  safety: z.object({
    enableInputFiltering: z.boolean().default(true),
    enableOutputFiltering: z.boolean().default(true),
    enablePIIRedaction: z.boolean().default(false),
    enableInjectionDetection: z.boolean().default(true),
    maxInputTokens: z.number().default(8192),
  }),

  // Governance
  governance: z.object({
    enableTokenBudgets: z.boolean().default(true),
    enableSemanticCache: z.boolean().default(true),
    enableAuditLog: z.boolean().default(true),
    defaultDailyTokenBudget: z.number().default(1_000_000),
    cacheThreshold: z.number().min(0).max(1).default(0.92),  // Similarity threshold
  }),
})

export type AIConfig = z.infer<typeof AIConfigSchema>
```

---

## Integration with Other Enterprise Skills

- **enterprise-database**: pgvector extension for vector search, audit log tables, token usage tables
- **enterprise-backend**: AI endpoints (chat, search, upload), auth middleware on AI routes, webhook handlers for async ingestion
- **enterprise-frontend**: Chat UI components, streaming response display, file upload for documents
- **enterprise-deployment**: Azure AI resource provisioning (Bicep), GPU instance setup, model endpoint monitoring

---

## Verification Checklist

Before considering any AI infrastructure complete:

- [ ] Provider abstraction: can switch LLM provider by changing config, no business logic changes
- [ ] Streaming works end-to-end (provider → API → client)
- [ ] Fallback chain: if primary provider fails, fallback kicks in automatically
- [ ] Vector store: documents indexed, similarity search returns relevant results
- [ ] Embedding pipeline: documents processed, chunked, embedded, and searchable
- [ ] Safety guardrails: prompt injection detected, harmful content filtered, PII redacted (if enabled)
- [ ] Token budgets: per-user limits enforced, overages rejected gracefully
- [ ] Semantic cache: repeated/similar queries served from cache, reducing cost
- [ ] Audit log: every LLM call logged (user, model, tokens, latency, cost estimate)
- [ ] Secrets: API keys in Key Vault / Secrets Manager / .env (never in code)
- [ ] Error handling: provider errors (rate limit, timeout, 5xx) handled with retry + fallback
