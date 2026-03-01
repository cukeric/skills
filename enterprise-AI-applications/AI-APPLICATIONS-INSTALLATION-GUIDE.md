# Enterprise AI Applications Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | 186 | Pattern selection decision matrix (RAG vs Agent vs Chatbot vs Multimodal), complexity assessment (Level 1-5), framework vs raw SDK decision guide, architecture diagram, shared services interfaces (RetrievalEngine, ToolRegistry, ConversationMemory) |
| **Core Patterns** | | |
| `references/rag-pipelines.md` | 410 | Full RAG pipeline: embed query→vector search→augment prompt→generate with citations. Query preprocessing (follow-up resolution, multi-query generation). LLM-based reranking. Conversational RAG with multi-turn history. Streaming RAG endpoint (SSE). Document upload/ingestion endpoint. Multi-tenant retrieval filtering. |
| `references/agentic-orchestration.md` | 416 | Tool Registry (Zod validation, timeout, rate limits). Example tools (DB search, email, web search, calculator). Agent loop with max iterations, tool execution, error handling. Streaming agent (real-time tool visibility). Human-in-the-loop (approval gates for destructive actions). Multi-agent orchestration (supervisor routing to specialized workers). Agent safety constraints. |
| `references/chatbot-conversational.md` | 354 | Three memory strategies: sliding window (default), summary memory (LLM-compressed history), persistent database memory (cross-session). Chat service with personality/tone control. Customer support bot (knowledge base integration, escalation triggers, human handoff). Streaming SSE chat endpoint. Conversation title auto-generation. DB schema for conversations + messages. |
| `references/multimodal-pipelines.md` | 310 | Provider capability matrix (Claude/GPT-4o/Gemini/Ollama). Image analysis (single + batch). OCR via LLM vision. Structured data extraction (receipts, invoices → JSON). PDF processing (native + parsed fallback). Audio transcription (Whisper API + local whisper.cpp). Text-to-speech. Unified multi-format document Q&A endpoint. |
| **Framework & Implementation** | | |
| `references/langchain-langgraph.md` | 284 | When-to-use decision matrix. LangChain: LCEL chains, RAG chain with retriever, tool-calling agent. LangGraph: StateGraph with annotations, basic agent graph, checkpointing (MemorySaver → PostgresSaver), human-in-the-loop (interruptBefore), multi-agent supervisor pattern, streaming events. |
| `references/raw-sdk-patterns.md` | 465 | No-framework tool-use loop (multi-iteration, validation, error handling). Structured output with Zod schema + retry. SSE streaming (server + client code). Batch processing (Anthropic Batch API 50% cheaper + parallel with concurrency). Classification/routing (cheap model). Prompt templates (composable system prompts). Request/response middleware (guardrails + budget + audit + cache wrapping every LLM call). |
| `references/evaluation-testing.md` | 551 | 4-layer evaluation framework (unit→LLM-judge→benchmark→human). RAG evaluation (faithfulness, relevance, context precision, hallucination rate). Agent evaluation (task completion, tool correctness, safety). LLM-as-judge quality scorer (weighted criteria). Evaluation dataset management (PostgreSQL). Regression benchmark runner (batch with concurrency). A/B testing framework (consistent user assignment). User feedback collection (thumbs up/down → eval dataset). CI/CD pipeline (GitHub Actions: run evals on every PR, compare to baseline, fail on regression). |

**Total: 2,976 lines across 8 files — complete AI application pattern library.**

---

## Dependency on Foundation Skill

This skill **requires** `enterprise-ai-foundations` for:
- LLM client (provider abstraction, streaming, fallback)
- Vector store (search, upsert)
- Embedding client (query + document embedding)
- Safety guardrails (input/output validation)
- Cost governance (token budgets, audit logging, semantic cache)

Install both skills together for a complete AI stack.

---

## Installation

### Option A: Claude Code (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-ai-applications/references
cp SKILL.md ~/.claude/skills/enterprise-ai-applications/
cp references/* ~/.claude/skills/enterprise-ai-applications/references/
```

### Option B: From .skill Package

```bash
mkdir -p ~/.claude/skills
tar -xzf enterprise-ai-applications.skill -C ~/.claude/skills/
```

### Option C: Project-Level

```bash
mkdir -p .claude/skills/enterprise-ai-applications/references
cp SKILL.md .claude/skills/enterprise-ai-applications/
cp references/* .claude/skills/enterprise-ai-applications/references/
```

---

## Trigger Keywords

> RAG, retrieval-augmented generation, document Q&A, knowledge base, AI agent, tool use, multi-step reasoning, agentic workflow, orchestration, chatbot, conversational AI, customer support bot, internal assistant, AI chat, multimodal, vision, audio, PDF analysis, image understanding, LangChain, LangGraph, AI evaluation, LLM testing, streaming chat, conversation memory, agent loop, function calling, structured output, batch processing, classification, prompt template

---

## Complete Enterprise AI Skill Set

| Skill | Layer | Lines | Files |
|---|---|---|---|
| `enterprise-ai-foundations` | Infrastructure (providers, vector DBs, safety, cost) | 3,362 | 8 |
| `enterprise-ai-applications` | Patterns (RAG, agents, chatbots, multimodal, eval) | 2,976 | 8 |
| **Combined** | **Full AI stack** | **6,338** | **16** |
