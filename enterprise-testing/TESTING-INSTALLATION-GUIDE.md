# Enterprise Testing Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | 197 | Test strategy decision framework, testing pyramid, coverage targets, file organization, technology stack (Vitest + Playwright + k6), test scripts, integration with other enterprise skills |
| **Setup & Core Testing** | | |
| `references/environment-setup.md` | 429 | **Zero to running.** Install Vitest + Playwright + k6 + Testcontainers. Config files (vitest.config.ts, playwright.config.ts). .env.test. VS Code extensions. Path aliases. First unit test walkthrough. First E2E test walkthrough. Directory structure creation. Troubleshooting table. |
| `references/unit-testing.md` | 389 | AAA pattern (Arrange/Act/Assert). Service testing with dependency mocking. Mocking patterns: vi.mock (modules), vi.spyOn (methods), mock timers, mock fetch, MSW. Validator/schema testing (Zod). Error handling testing. Async code testing. Snapshot testing. Test factories (@faker-js). Coverage configuration and thresholds. |
| `references/integration-testing.md` | 376 | Testcontainers setup (real PostgreSQL + Redis in Docker). Global setup/teardown (start once, share across files). cleanDatabase() between tests. API route testing with Fastify .inject() and Supertest. Database operation testing (transactions, rollbacks). Auth testing helpers (JWT token generation). Seed data utilities. |
| `references/e2e-testing.md` | 345 | Playwright full setup. Page Object Model pattern. User flow tests (auth, forms, navigation). Auth state reuse (login once, save cookies). Visual regression screenshots. Accessibility testing (axe-core WCAG 2.0 AA). Codegen (record tests by clicking). Debugging (headed, debug mode, traces, UI mode). Selector best practices (getByRole, getByLabel). |
| **Performance & AI** | | |
| `references/load-testing.md` | 277 | k6 setup. Five test types: smoke, load, stress, spike, soak. Ramp-up patterns. Performance budgets per endpoint (p95/p99 thresholds). Auth handling (login in setup, reuse token). AI endpoint load testing (higher timeouts). Result export (JSON, HTML). CI integration. |
| `references/ai-testing.md` | 417 | Mock LLM client (deterministic responses, keyword matching). Mock tool-calling LLM (predetermined tool sequences). Mock embeddings (deterministic vectors from text hash). RAG pipeline testing (mock LLM + real vector store). Guardrail testing (injection detection, PII detection/redaction, content filtering). Agent loop testing (tool execution, max iterations, usage tracking). Snapshot regression for AI pipelines. |
| **Automation** | | |
| `references/test-automation.md` | 586 | Pre-commit hooks (Husky + lint-staged: lint + related tests). GitHub Actions CI pipeline (unit + integration with Postgres/Redis services, E2E with Playwright, coverage gate, artifact upload). Azure DevOps pipeline (equivalent). PR comment bot (posts coverage summary). Parallel execution (Vitest forks, Playwright workers). E2E sharding (split across CI machines). Playwright codegen. Vitest watch mode. HTML reports. **One-command setup script** (scripts/setup-testing.sh installs everything). |

**Total: 3,016 lines across 8 files — complete testing lifecycle from zero-setup to CI/CD.**

---

## Installation

### Option A: Claude Code (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-testing/references
cp SKILL.md ~/.claude/skills/enterprise-testing/
cp references/* ~/.claude/skills/enterprise-testing/references/
```

### Option B: From .skill Package

```bash
mkdir -p ~/.claude/skills
tar -xzf enterprise-testing.skill -C ~/.claude/skills/
```

### Option C: Project-Level

```bash
mkdir -p .claude/skills/enterprise-testing/references
cp SKILL.md .claude/skills/enterprise-testing/
cp references/* .claude/skills/enterprise-testing/references/
```

---

## Trigger Keywords

> test, testing, unit test, integration test, E2E, end-to-end, Vitest, Playwright, coverage, mocking, mock, test setup, test environment, Testcontainers, test database, test fixtures, snapshot, regression, visual regression, accessibility testing, load test, performance test, k6, stress test, TDD, test automation, CI testing, pre-commit, coverage gate, test pipeline, AI testing, LLM testing, RAG testing, test factory

---

## Complete Enterprise Skill Library

| # | Skill | Layer | Lines | Files |
|---|---|---|---|---|
| 1 | `enterprise-database` | Data | ~3,200 | 9 |
| 2 | `enterprise-backend` | API | ~3,100 | 9 |
| 3 | `enterprise-frontend` | UI | ~3,000 | 8 |
| 4 | `enterprise-deployment` | DevOps | ~3,254 | 9 |
| 5 | `enterprise-ai-foundations` | AI Infra | 3,362 | 8 |
| 6 | `enterprise-ai-applications` | AI Patterns | 2,976 | 8 |
| 7 | `enterprise-testing` | QA | 3,016 | 8 |
| | **Total** | | **~22,000** | **~59** |
