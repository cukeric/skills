---
name: enterprise-testing
description: Trigger this skill whenever the user mentions testing, tests, test setup, test environment, unit test, integration test, end-to-end test, E2E, Vitest, Playwright, test coverage, mocking, test doubles, API testing, load testing, performance testing, k6, stress test, test automation, CI testing, pre-commit hooks, Testcontainers, test database, test fixtures, snapshot testing, regression testing, visual regression, accessibility testing, TDD, test-driven development, coverage gate, test pipeline, AI testing, LLM testing, RAG testing, or any request to add, fix, run, or configure tests. Also trigger when the user asks about quality assurance, code confidence, "how do I test this", or wants to verify that code works correctly. This skill covers the complete testing lifecycle from zero-setup through CI/CD automation.
---

# Enterprise Testing Skill

Complete testing skill from zero-setup to CI/CD automation. Covers unit, integration, E2E, load, and AI-specific testing with Vitest + Playwright as the default stack. Every reference file starts with setup instructions — no prior test environment assumed.

## Reference Files

**Start here if you have no testing setup:**
1. `references/environment-setup.md` — **Read this first.** Full install, config, directory structure, IDE setup, your first passing test.

**Then choose by what you're testing:**
2. `references/unit-testing.md` — Functions, services, utilities, validators. Mocking, snapshots, coverage.
3. `references/integration-testing.md` — API endpoints, database queries, auth flows. Real PG/Redis via Testcontainers.
4. `references/e2e-testing.md` — Browser testing: user flows, forms, navigation. Playwright setup, page objects, visual regression.
5. `references/load-testing.md` — Performance: k6 stress/spike/soak tests, thresholds, budgets.
6. `references/ai-testing.md` — LLM mocking, RAG pipeline testing, guardrail verification, embedding mocks.

**Automation:**
7. `references/test-automation.md` — CI/CD pipelines, pre-commit hooks, coverage gates, parallel execution, test reporting.

---

## Test Strategy: What to Test, When

### The Testing Pyramid

```
        ╱╲
       ╱  ╲        E2E Tests (few, slow, expensive)
      ╱ E2E╲       → Critical user journeys only
     ╱──────╲      → 5-15 tests
    ╱        ╲
   ╱Integration╲   Integration Tests (moderate)
  ╱────────────╲   → API endpoints, DB queries, auth
 ╱              ╲  → 50-200 tests
╱   Unit Tests   ╲ Unit Tests (many, fast, cheap)
╱────────────────╲ → Functions, services, validators
                    → 200-1000+ tests
```

### What to Test at Each Layer

| Layer | What to Test | Tool | Speed |
|---|---|---|---|
| **Unit** | Pure functions, validators, transformers, formatters, business logic | Vitest | < 1ms/test |
| **Unit (with mocks)** | Services, controllers, middleware (mock dependencies) | Vitest + vi.mock | < 10ms/test |
| **Integration** | API routes end-to-end, database operations, auth flows | Vitest + Supertest + Testcontainers | < 500ms/test |
| **E2E** | Critical user flows (signup, checkout, dashboard) | Playwright | 2-30s/test |
| **Load** | API throughput, response times under load, breaking points | k6 | minutes |
| **AI** | LLM response quality, RAG relevance, guardrail enforcement | Vitest + mocks/snapshots | varies |

### When NOT to Test

- Don't unit-test simple getters/setters or trivial pass-through functions
- Don't mock everything — if the real thing is fast and reliable, use it
- Don't write E2E tests for things integration tests already cover
- Don't test third-party library internals (test your usage of them)
- Don't aim for 100% coverage — aim for confidence in critical paths

### Coverage Targets (Pragmatic)

| Area | Target | Why |
|---|---|---|
| Business logic / services | 80-90% | Core value, high bug risk |
| API routes | 70-80% | Integration coverage is key |
| Utilities / helpers | 90%+ | Pure functions, easy to test |
| Frontend components | 60-70% | Focus on interactive behavior |
| E2E critical paths | 100% of user journeys | Not line coverage — journey coverage |
| AI pipelines | Feature-specific | Snapshot + regression over coverage % |

---

## Test File Organization

```
project/
├── src/
│   ├── services/
│   │   ├── auth.ts
│   │   └── auth.test.ts          ← Co-located unit tests (preferred)
│   ├── routes/
│   │   ├── users.ts
│   │   └── users.test.ts
│   └── lib/
│       ├── validators.ts
│       └── validators.test.ts
├── tests/
│   ├── integration/               ← Integration tests (need DB/services)
│   │   ├── api/
│   │   │   ├── auth.test.ts
│   │   │   └── users.test.ts
│   │   ├── setup.ts              ← Testcontainers setup
│   │   └── helpers.ts            ← Test utilities, factories
│   ├── e2e/                       ← Playwright E2E tests
│   │   ├── flows/
│   │   │   ├── auth.spec.ts
│   │   │   └── dashboard.spec.ts
│   │   ├── pages/                ← Page object models
│   │   │   ├── login.page.ts
│   │   │   └── dashboard.page.ts
│   │   └── playwright.config.ts
│   ├── load/                      ← k6 load tests
│   │   ├── scenarios/
│   │   │   ├── api-stress.js
│   │   │   └── spike.js
│   │   └── k6.config.js
│   ├── ai/                        ← AI-specific tests
│   │   ├── rag.test.ts
│   │   └── mocks/
│   │       └── llm-responses.json
│   └── fixtures/                  ← Shared test data
│       ├── users.ts
│       ├── products.ts
│       └── factory.ts            ← Test data factories
├── vitest.config.ts
├── playwright.config.ts
└── package.json                   ← Test scripts
```

### Co-located vs Separate Tests

**Unit tests: co-located** (next to the file they test)
- `src/services/auth.ts` → `src/services/auth.test.ts`
- Easy to find, easy to maintain, clear ownership

**Integration/E2E/Load: separate `tests/` directory**
- Test multiple modules together, need shared setup
- Different configuration, different run commands

---

## Default Technology Stack

| Purpose | Tool | Why |
|---|---|---|
| Unit + Integration | **Vitest** | Fast, ESM-native, built-in mocking, TypeScript native, watch mode |
| E2E / Browser | **Playwright** | Multi-browser, auto-wait, codegen, traces, best debugging |
| Load / Performance | **k6** | Developer-friendly (JS scripts), CI-ready, excellent reporting |
| Test containers | **Testcontainers** | Real databases in Docker, auto-cleanup, CI-compatible |
| API testing | **Supertest** or Fastify `.inject()` | In-process HTTP testing, no server needed |
| Coverage | **V8 (via Vitest)** | Fast, accurate, built into Vitest |
| Assertions | **Vitest expect** (Chai-compatible) | Rich matchers, extensible |
| Mocking | **vi.mock / vi.spyOn** | Built into Vitest, no extra deps |
| Fixtures | **Custom factories** | Type-safe, composable test data |

---

## Quick Reference: Test Scripts

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "test:unit": "vitest run --dir src",
    "test:integration": "vitest run --dir tests/integration",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:codegen": "playwright codegen localhost:3000",
    "test:load": "k6 run tests/load/scenarios/api-stress.js",
    "test:ai": "vitest run --dir tests/ai",
    "test:all": "vitest run && playwright test"
  }
}
```

---

## Integration with Other Enterprise Skills

| Skill | Testing Integration |
|---|---|
| **enterprise-database** | Testcontainers for real PG/Redis/Mongo, migration testing, seed data |
| **enterprise-backend** | API route testing (Supertest/inject), auth mocking, middleware testing |
| **enterprise-frontend** | Component testing (Vitest + Testing Library), E2E user flows (Playwright) |
| **enterprise-deployment** | CI/CD test stages, coverage gates, test reporting |
| **enterprise-ai-foundations** | LLM response mocking, embedding mocks, guardrail testing |
| **enterprise-ai-applications** | RAG evaluation, agent loop testing, chatbot conversation testing |

---

## Verification Checklist

- [ ] Vitest installed and configured (vitest.config.ts)
- [ ] First unit test runs and passes
- [ ] Testcontainers running real PostgreSQL for integration tests
- [ ] Playwright installed with at least one E2E test passing
- [ ] Coverage reporting enabled (V8 provider)
- [ ] Test scripts in package.json (test, test:watch, test:coverage, test:e2e)
- [ ] CI pipeline runs tests on every push/PR
- [ ] Coverage gate: PRs fail below threshold
- [ ] Pre-commit hook: runs relevant tests before commit
