# Enterprise AI Foundations Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | 268 | Decision framework: environment selection (Azure vs AWS vs standalone), LLM provider matrix, model tier strategy (Haiku/mini→Sonnet/4o→Opus), vector DB selection matrix, architecture diagram, project structure, config schema |
| **Provider & Model Infrastructure** | | |
| `references/provider-abstraction.md` | 582 | Unified LLM interface (LLMProvider, LLMRequest, LLMResponse, streaming). Full implementations: Anthropic Claude (tool use, streaming, cost tracking), OpenAI (GPT-4o, function calling), Ollama (local models). Model router with retry + exponential backoff + fallback chains. Embedding client (OpenAI + Ollama). Factory pattern from config. |
| `references/azure-ai-services.md` | 398 | **Enterprise Path A:** Azure OpenAI (deployment, Managed Identity auth, streaming), Azure AI Search (index creation, hybrid search: vector + keyword + semantic reranking, multi-tenant filtering), Azure Document Intelligence (PDF/image → structured markdown), Private Endpoints for all AI services, Bicep IaC module |
| `references/aws-bedrock.md` | 353 | **Enterprise Path A2:** Bedrock Runtime (Claude/Titan/Llama invocation, streaming), Knowledge Bases (managed RAG: S3 → OpenSearch → answer with citations), Guardrails API (content filtering, PII anonymization, topic blocking), Titan embeddings, VPC Endpoints, IAM policies (least privilege) |
| **Data & Retrieval Infrastructure** | | |
| `references/vector-databases.md` | 388 | Unified VectorStore interface. Full implementations: pgvector (schema, HNSW index, hybrid search with tsvector, multi-tenant), Pinecone (serverless, batched upsert), Qdrant (payload filtering), ChromaDB (prototyping). Azure AI Search covered in azure-ai-services.md. Factory from config. |
| `references/embeddings-chunking.md` | 433 | Embedding model selection matrix (OpenAI, Titan, Azure, Ollama, Cohere). Chunking engine: recursive text splitter (default), markdown-aware splitter (preserves headers/sections). Document parsers: PDF (pdf-parse + Azure Doc Intelligence), DOCX (mammoth), HTML (cheerio), images (LLM vision OCR). Full ingestion pipeline: parse→chunk→embed→store. Queue-based batch ingestion. Embedding cache (SHA256 dedup, Redis, 7-day TTL). |
| **Safety & Governance** | | |
| `references/ai-safety-guardrails.md` | 469 | 3-layer defense: input validation → LLM interaction → output validation. Guardrails middleware wrapping LLM client. Prompt injection detection (12 heuristic patterns + base64 decode + optional LLM classifier). PII detection & redaction (email, phone, SSN, credit card, IP, DOB). Content filtering (violence, illegal, self-harm). System prompt security template. RAG hallucination mitigation (citation verification). Enterprise managed options (Azure Content Safety, Bedrock Guardrails). |
| `references/cost-governance.md` | 471 | Token budget system (per-user daily limits, DB schema, Redis fast-path, budget enforcement middleware). AI-specific rate limiting (requests/min, concurrent, tier-based: free/standard/premium/unlimited). Semantic cache (vector similarity 92%+ → return cached response). Audit logging (batched inserts, every AI call tracked: user, model, tokens, cost, latency, feature, guardrail flags). Compliance: data residency (region→provider mapping), GDPR data deletion, retention policies. Cost optimization strategies table. |

**Total: 3,362 lines — provider-agnostic AI infrastructure layer.**

---

## Three-Environment Architecture

### Enterprise Path A1 — Azure
Azure OpenAI (dedicated capacity) + Azure AI Search (hybrid search) + Azure Document Intelligence + Key Vault + Managed Identity + Private Endpoints + Azure Content Safety

### Enterprise Path A2 — AWS
AWS Bedrock (Claude/Titan/Llama) + Bedrock Knowledge Bases (managed RAG) + Bedrock Guardrails + OpenSearch Serverless + Secrets Manager + IAM roles + VPC Endpoints

### Standalone Path B
Direct APIs (Anthropic, OpenAI, Gemini, Ollama) + pgvector / Pinecone / Qdrant + custom parsers + custom guardrails + .env secrets

---

## Installation

### Option A: Claude Code (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-ai-foundations/references
cp SKILL.md ~/.claude/skills/enterprise-ai-foundations/
cp references/* ~/.claude/skills/enterprise-ai-foundations/references/
```

### Option B: From .skill Package

```bash
mkdir -p ~/.claude/skills
tar -xzf enterprise-ai-foundations.skill -C ~/.claude/skills/
```

### Option C: Project-Level

```bash
mkdir -p .claude/skills/enterprise-ai-foundations/references
cp SKILL.md .claude/skills/enterprise-ai-foundations/
cp references/* .claude/skills/enterprise-ai-foundations/references/
```

---

## Trigger Keywords

> AI, LLM, embedding, vector database, vector search, semantic search, RAG infrastructure, chunking, document ingestion, AI provider, model selection, Azure OpenAI, AWS Bedrock, Claude API, OpenAI API, Gemini API, Ollama, local models, AI safety, guardrails, content filtering, prompt injection, PII detection, AI cost, token budget, AI governance, AI compliance, audit logging, model routing, LLM abstraction, embedding pipeline

---

## Companion Skill

This skill provides the **infrastructure layer**. For application patterns built on top of it, see:

- `enterprise-ai-applications` — RAG pipelines, agentic orchestration, chatbots, multimodal, LangChain/LangGraph, evaluation & testing
