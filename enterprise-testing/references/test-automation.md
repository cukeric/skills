# Test Automation Reference

## Automation Overview

```
┌──────────────────────────────────────────────────────┐
│                   Automation Layers                   │
│                                                       │
│  1. Pre-Commit Hook                                   │
│     └── Lint + type-check + affected unit tests       │
│                                                       │
│  2. Pull Request Pipeline                             │
│     ├── Unit tests (full suite)                       │
│     ├── Integration tests (Testcontainers)            │
│     ├── Coverage gate (fail if below threshold)       │
│     └── E2E smoke (critical paths only)               │
│                                                       │
│  3. Merge to Main Pipeline                            │
│     ├── Full E2E suite (all browsers)                 │
│     ├── Performance budgets (k6 smoke)                │
│     └── Deploy to staging                             │
│                                                       │
│  4. Pre-Production Pipeline                           │
│     ├── Load tests against staging                    │
│     ├── Full E2E against staging                      │
│     └── Promote to production                         │
└──────────────────────────────────────────────────────┘
```

---

## Pre-Commit Hooks (Husky + lint-staged)

### Setup

```bash
pnpm add -D husky lint-staged

# Initialize Husky
npx husky init
```

### Configure

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": [
      "eslint --fix",
      "vitest related --run"
    ],
    "*.{json,md,css}": [
      "prettier --write"
    ]
  }
}
```

```bash
# .husky/pre-commit
pnpm lint-staged
```

### What This Does

When you `git commit`:
1. ESLint fixes linting issues on staged files
2. Vitest runs **only tests related to changed files** (fast!)
3. Prettier formats non-code files
4. If any step fails, commit is blocked

### Optional: Pre-Push Hook (Heavier Checks)

```bash
# .husky/pre-push
pnpm test:unit
pnpm tsc --noEmit
```

---

## GitHub Actions: PR Pipeline

```yaml
# .github/workflows/test.yml
name: Tests

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main]

concurrency:
  group: tests-${{ github.ref }}
  cancel-in-progress: true         # Cancel outdated runs on same branch

jobs:
  # ──────────────────────────────────────────────
  # Job 1: Unit + Integration Tests
  # ──────────────────────────────────────────────
  unit-integration:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports: ['5432:5432']
        options: >-
          --health-cmd="pg_isready"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
        options: >-
          --health-cmd="redis-cli ping"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile

      # Type check
      - name: TypeScript check
        run: pnpm tsc --noEmit

      # Unit tests with coverage
      - name: Unit tests
        run: pnpm test:unit -- --coverage
        env:
          NODE_ENV: test

      # Integration tests
      - name: Integration tests
        run: pnpm test:integration
        env:
          NODE_ENV: test
          DATABASE_URL: postgresql://test:test@localhost:5432/testdb
          REDIS_URL: redis://localhost:6379

      # Coverage gate
      - name: Check coverage thresholds
        run: |
          # Extract coverage from json-summary
          COVERAGE=$(node -e "
            const c = require('./coverage/coverage-summary.json').total;
            const avg = (c.lines.pct + c.functions.pct + c.branches.pct) / 3;
            console.log(avg.toFixed(1));
          ")
          echo "Coverage: ${COVERAGE}%"
          if (( $(echo "$COVERAGE < 70" | bc -l) )); then
            echo "::error::Coverage ${COVERAGE}% is below 70% threshold"
            exit 1
          fi

      # Upload coverage report
      - name: Upload coverage
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-report
          path: coverage/

  # ──────────────────────────────────────────────
  # Job 2: E2E Tests (runs in parallel with Job 1)
  # ──────────────────────────────────────────────
  e2e:
    runs-on: ubuntu-latest
    timeout-minutes: 20

    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: Build app
        run: pnpm build
        env:
          NODE_ENV: test

      - name: Run E2E tests
        run: pnpm test:e2e
        env:
          CI: true

      # Upload traces and screenshots on failure
      - name: Upload E2E artifacts
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: |
            playwright-report/
            test-results/
          retention-days: 7

  # ──────────────────────────────────────────────
  # Job 3: Performance Budget (on merge to main only)
  # ──────────────────────────────────────────────
  performance:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    needs: [unit-integration, e2e]   # Only after other tests pass
    timeout-minutes: 10

    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update && sudo apt-get install k6

      - name: Run performance budget
        run: k6 run tests/load/scenarios/budget.js
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}
```

---

## Azure DevOps Pipeline (Alternative)

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main, develop]

pr:
  branches:
    include: [main]

pool:
  vmImage: 'ubuntu-latest'

variables:
  NODE_VERSION: '20'

stages:
  - stage: Test
    jobs:
      - job: UnitIntegration
        displayName: 'Unit + Integration Tests'
        services:
          postgres:
            image: postgres:16-alpine
            ports: ['5432:5432']
            env:
              POSTGRES_DB: testdb
              POSTGRES_USER: test
              POSTGRES_PASSWORD: test
          redis:
            image: redis:7-alpine
            ports: ['6379:6379']
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: $(NODE_VERSION)

          - script: |
              corepack enable
              pnpm install --frozen-lockfile
            displayName: 'Install dependencies'

          - script: pnpm tsc --noEmit
            displayName: 'Type check'

          - script: pnpm test:unit -- --coverage
            displayName: 'Unit tests'
            env:
              NODE_ENV: test

          - script: pnpm test:integration
            displayName: 'Integration tests'
            env:
              NODE_ENV: test
              DATABASE_URL: postgresql://test:test@localhost:5432/testdb
              REDIS_URL: redis://localhost:6379

          - task: PublishCodeCoverageResults@2
            inputs:
              summaryFileLocation: '$(System.DefaultWorkingDirectory)/coverage/lcov.info'
              pathToSources: '$(System.DefaultWorkingDirectory)/src'

      - job: E2E
        displayName: 'E2E Tests'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: $(NODE_VERSION)

          - script: |
              corepack enable
              pnpm install --frozen-lockfile
              npx playwright install --with-deps chromium
            displayName: 'Install'

          - script: pnpm build
            displayName: 'Build'
            env:
              NODE_ENV: test

          - script: pnpm test:e2e
            displayName: 'Playwright tests'
            env:
              CI: true

          - task: PublishTestResults@2
            condition: always()
            inputs:
              testResultsFormat: 'JUnit'
              testResultsFiles: 'test-results/results.xml'
```

---

## PR Comment: Test Results Summary

```yaml
# Add to GitHub Actions workflow (after test jobs)
  report:
    needs: [unit-integration, e2e]
    if: github.event_name == 'pull_request' && always()
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: coverage-report
          path: coverage/

      - name: Post coverage comment
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs')
            let summary = ''
            try {
              const coverage = JSON.parse(fs.readFileSync('coverage/coverage-summary.json', 'utf8'))
              const t = coverage.total
              summary = `## 🧪 Test Results

            | Metric | Coverage |
            |---|---|
            | Lines | ${t.lines.pct}% |
            | Functions | ${t.functions.pct}% |
            | Branches | ${t.branches.pct}% |
            | Statements | ${t.statements.pct}% |

            ${t.lines.pct >= 70 ? '✅ Coverage meets threshold (70%)' : '❌ Coverage below threshold (70%)'}`
            } catch {
              summary = '⚠️ Coverage data not available'
            }

            // Find existing comment
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            })
            const existing = comments.find(c => c.body.includes('🧪 Test Results'))

            const body = summary
            if (existing) {
              await github.rest.issues.updateComment({ owner: context.repo.owner, repo: context.repo.repo, comment_id: existing.id, body })
            } else {
              await github.rest.issues.createComment({ owner: context.repo.owner, repo: context.repo.repo, issue_number: context.issue.number, body })
            }
```

---

## Parallel Test Execution

### Vitest (Built-in)

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    pool: 'forks',                    // Isolated processes
    poolOptions: {
      forks: {
        maxForks: undefined,          // Use all CPU cores (default)
      },
    },
  },
})

// For integration tests (shared DB): limit to 1 fork
// vitest run --dir tests/integration --poolOptions.forks.maxForks=1
```

### Playwright (Built-in)

```typescript
// playwright.config.ts
export default defineConfig({
  fullyParallel: true,               // Run tests in parallel
  workers: process.env.CI ? 1 : undefined,  // Sequential on CI (stability), parallel locally
})
```

### GitHub Actions (Parallel Jobs)

```yaml
# Tests run in parallel by default when they're separate jobs
jobs:
  unit-integration:  # Job 1 — runs immediately
    ...
  e2e:               # Job 2 — runs at same time as Job 1
    ...
  performance:       # Job 3 — waits for Jobs 1+2
    needs: [unit-integration, e2e]
```

---

## Sharded E2E Tests (Large Test Suites)

```yaml
# Split E2E tests across multiple CI machines
e2e:
  strategy:
    matrix:
      shard: [1, 2, 3, 4]           # 4 parallel shards
  steps:
    - name: Run E2E (shard ${{ matrix.shard }}/4)
      run: npx playwright test --shard=${{ matrix.shard }}/4
```

---

## Automated Test Generation

### Playwright Codegen (Record Tests by Clicking)

```bash
# Opens a browser — click through your app, tests are generated
npx playwright codegen http://localhost:3000

# Record with specific device
npx playwright codegen --device="iPhone 13" http://localhost:3000

# Record with specific viewport
npx playwright codegen --viewport-size=1280,720 http://localhost:3000
```

### Vitest Watch Mode (TDD Workflow)

```bash
# Runs tests automatically when you save files
pnpm test:watch

# Filter to specific files
pnpm vitest --watch src/services/auth
```

---

## Test Reporting Dashboard

### Vitest HTML Report

```bash
pnpm add -D @vitest/ui

# Run with UI
pnpm vitest --ui

# Opens browser at http://localhost:51204/__vitest__/
```

### Playwright HTML Report

```bash
# Auto-generated on failure, or manually:
npx playwright show-report

# Always generate:
# In playwright.config.ts: reporter: [['html', { open: 'always' }]]
```

---

## Quick Setup Script (One Command)

```bash
#!/bin/bash
# scripts/setup-testing.sh — Run once to configure entire test environment

set -e

echo "📦 Installing test dependencies..."
pnpm add -D vitest @vitest/coverage-v8 @vitest/ui
pnpm add -D @playwright/test
pnpm add -D testcontainers @testcontainers/postgresql @testcontainers/redis
pnpm add -D supertest @types/supertest
pnpm add -D husky lint-staged
pnpm add -D @faker-js/faker
pnpm add -D @axe-core/playwright

echo "🎭 Installing Playwright browsers..."
npx playwright install --with-deps chromium

echo "🪝 Setting up Git hooks..."
npx husky init
echo 'pnpm lint-staged' > .husky/pre-commit

echo "📁 Creating test directories..."
mkdir -p tests/{integration/api,e2e/{flows,pages},load/scenarios,ai/mocks,fixtures}

echo "📝 Creating .env.test..."
cat > .env.test << EOF
NODE_ENV=test
DATABASE_URL=postgresql://test:test@localhost:5433/testdb
REDIS_URL=redis://localhost:6380
LOG_LEVEL=silent
JWT_SECRET=test-secret-key-not-for-production
EOF

echo "✅ Test environment ready!"
echo ""
echo "Next steps:"
echo "  pnpm test              — Run unit tests"
echo "  pnpm test:watch        — Watch mode"
echo "  pnpm test:coverage     — With coverage"
echo "  pnpm test:e2e          — E2E tests"
echo "  pnpm test:e2e:codegen  — Record E2E tests"
```

```bash
# Make executable and run
chmod +x scripts/setup-testing.sh
./scripts/setup-testing.sh
```

---

## Checklist

- [ ] Pre-commit hooks: lint + type-check + related tests on every commit
- [ ] CI pipeline: unit + integration + E2E on every PR
- [ ] Coverage gate: PRs fail if coverage drops below threshold
- [ ] PR comments: automated coverage summary posted to pull requests
- [ ] Parallel execution: tests run in parallel locally and in CI
- [ ] E2E sharding: large test suites split across CI machines
- [ ] Playwright codegen: team can record tests by clicking
- [ ] Performance budgets: k6 smoke test on merge to main
- [ ] Artifacts: failure traces/screenshots uploaded for debugging
- [ ] One-command setup: scripts/setup-testing.sh configures everything
