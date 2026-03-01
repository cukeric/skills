# Enterprise Skills Repository

Welcome to the **Enterprise Skills Repository**. This repository contains a curated collection of foundational patterns, architectural guidelines, and implementable "skills" for building modern, scalable, and AI-powered enterprise applications.

## Overview

Each directory in this repository represents a distinct **Skill**—a modular knowledge base containing documentation, best practices, and reference implementations for a specific domain. These skills are designed to be consumed by both human engineers and AI agents to standardize development, ensure security, and accelerate the delivery of enterprise software.

## Available Skills

### 🧠 AI Capabilities
- **[Enterprise AI Applications](./enterprise-AI-applications)**
  - Covers application-level AI patterns including RAG (Retrieval-Augmented Generation), agentic orchestration, conversational chatbots, and multimodal processing.
  - *Key Concepts*: Agents, LangChain, Document Q&A, Tool Use.
- **[Enterprise AI Foundations](./enterprise-AI-foundations)**
  - The infrastructure layer for AI. Covers LLM provider abstraction, vector databases, guardrails, safety, and cost governance.
  - *Key Concepts*: Vector Stores, Embeddings, AI Safety, Provider Setup.

### 💻 Core Engineering
- **[Enterprise Frontend](./enterprise-frontend)**
  - Architectural patterns for modern user interfaces, focusing on scalable setups using React/Next.js, Vue/Nuxt, state management, and design systems.
- **[Enterprise Backend](./enterprise-backend)**
  - Robust server-side architecture, API design, authentication, authorization, and microservices patterns.
- **[Enterprise Database](./enterprise-database)**
  - Guidelines on database selection, schema design, ORM usage (e.g., Prisma, Drizzle), indexing strategies, and migration management across SQL and NoSQL.

### 🚀 Operations & Quality
- **[Enterprise Deployment](./enterprise-deployment)**
  - CI/CD pipelines, containerization (Docker), infrastructure as code, cloud provider setups, and monitoring/logging.
- **[Enterprise Testing](./enterprise-testing)**
  - Comprehensive testing strategies including unit, integration, end-to-end (E2E), and AI-specific evaluation methodologies.

## Repository Structure

Inside each skill directory, you will typically find:
- `SKILL.md`: The core definition and entry point for the skill, outlining its purpose and decision matrices.
- `*.skill`: A prompt or config format for AI agents to ingest the skill.
- `INSTALLATION-GUIDE.md`: Step-by-step setup instructions for the technologies covered by the skill.
- `references/`: Detailed markdown files covering specific technical patterns, tools, or frameworks associated with the skill.
- `*.zip`: A portable archive of the skill for easy distribution or ingestion by certain platforms.

## Usage

**For Engineers:**
Browse the `references/` folders within the relevant skill to find standardized approaches to common enterprise engineering problems. Use the `INSTALLATION-GUIDE.md` when setting up new projects.

**For AI Agents:**
When an agent is triggered to assist with a specific domain (e.g., adding an AI chatbot or deploying to AWS), it should first read the relevant `SKILL.md` to understand the enterprise's approved patterns before generating code.

## License
Proprietary & Confidential.
