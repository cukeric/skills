# Test Environment Setup (Zero to Running)

## Prerequisites

You need Node.js 18+ and pnpm (or npm/yarn). Docker is needed for integration tests (Testcontainers).

```bash
# Verify
node --version   # v18+ required
pnpm --version   # any recent version
docker --version # needed for integration tests
```

---

## Step 1: Install Vitest (Unit + Integration Testing)

```bash
# From your project root
pnpm add -D vitest @vitest/coverage-v8 @vitest/ui
```

### Create Configuration

```typescript
// vitest.config.ts (project root)
import { defineConfig } from 'vitest/config'
import path from 'path'

export default defineConfig({
  test: {
    // Global settings
    globals: true,                    // Use describe/it/expect without imports
    environment: 'node',              // 'node' for backend, 'jsdom' for frontend
    root: '.',

    // File patterns
    include: [
      'src/**/*.test.ts',            // Co-located unit tests
      'tests/**/*.test.ts',          // Integration + AI tests
    ],
    exclude: ['tests/e2e/**', 'tests/load/**', 'node_modules'],

    // Coverage
    coverage: {
      provider: 'v8',                // Fast, accurate
      reporter: ['text', 'html', 'json-summary', 'lcov'],
      reportsDirectory: './coverage',
      include: ['src/**/*.ts'],
      exclude: [
        'src/**/*.test.ts',
        'src/**/*.spec.ts',
        'src/**/index.ts',           // Re-export files
        'src/types/**',              // Type definitions
        'src/**/*.d.ts',
      ],
      thresholds: {
        statements: 70,
        branches: 65,
        functions: 70,
        lines: 70,
      },
    },

    // Performance
    pool: 'forks',                   // Isolate tests in separate processes
    poolOptions: {
      forks: { maxForks: undefined }, // Use all CPU cores
    },

    // Timeouts
    testTimeout: 10000,              // 10s per test (increase for integration)
    hookTimeout: 30000,              // 30s for setup/teardown

    // Path aliases (match your tsconfig)
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@tests': path.resolve(__dirname, './tests'),
    },

    // Monorepo ESM resolution: Vitest 4+ uses Node's native ESM loader
    // which does NOT fall back from .js to .ts for relative imports.
    // If tests import from other workspace packages via relative paths
    // (e.g., ../../packages/proxy/src/auth/agent-auth.js), add a regex alias:
    //
    // alias: [
    //   ...other aliases,
    //   { find: /^(\.\.\/)+packages\/(.+)\.js$/, replacement: path.resolve(__dirname, 'packages/$2.ts') },
    // ]
    //
    // This rewrites .js extensions to .ts at test time, matching TypeScript source files.

    // Setup files (run before all tests)
    setupFiles: ['./tests/setup.ts'],
  },
})
```

### Global Setup File

```typescript
// tests/setup.ts
// Runs before all test files

// Load environment variables for testing
import { config } from 'dotenv'
config({ path: '.env.test' })

// Global test utilities
import { expect } from 'vitest'

// Custom matchers (optional)
expect.extend({
  toBeWithinRange(received: number, floor: number, ceiling: number) {
    const pass = received >= floor && received <= ceiling
    return {
      pass,
      message: () => `expected ${received} to be within range ${floor} - ${ceiling}`,
    }
  },
})
```

### Test Environment Variables

```bash
# .env.test (create this file)
NODE_ENV=test
DATABASE_URL=postgresql://test:test@localhost:5433/testdb
REDIS_URL=redis://localhost:6380
LOG_LEVEL=silent
JWT_SECRET=test-secret-key-not-for-production
```

---

## Step 2: Install Playwright (E2E Testing)

```bash
# Install Playwright and browsers
pnpm add -D @playwright/test
npx playwright install --with-deps chromium
# Only install Chromium initially — add firefox/webkit later if needed
```

### Create Configuration

```typescript
// playwright.config.ts (project root)
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  testMatch: '**/*.spec.ts',

  // Run settings
  fullyParallel: true,
  forbidOnly: !!process.env.CI,     // Fail CI if .only is left in
  retries: process.env.CI ? 2 : 0,  // Retry on CI only
  workers: process.env.CI ? 1 : undefined,

  // Reporting
  reporter: process.env.CI
    ? [['html', { open: 'never' }], ['github']]
    : [['html', { open: 'on-failure' }]],

  // Shared settings for all tests
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',        // Collect trace on failure
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 10000,
  },

  // Browser configurations
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    // Uncomment to add more browsers:
    // { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    // { name: 'mobile-chrome', use: { ...devices['Pixel 5'] } },
  ],

  // Start your dev server before tests
  webServer: {
    command: 'pnpm dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 30000,
  },
})
```

---

## Step 3: Install k6 (Load Testing)

```bash
# macOS
brew install k6

# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6

# Windows
choco install k6

# Docker (works anywhere)
docker run --rm -i grafana/k6 version

# Verify
k6 version
```

---

## Step 4: Install Testcontainers (Real Databases in Tests)

```bash
pnpm add -D testcontainers @testcontainers/postgresql @testcontainers/redis
# Requires Docker running
```

### Quick Verify: Docker is Working

```bash
docker run --rm hello-world
# Should print "Hello from Docker!"
```

---

## Step 5: Add Test Scripts to package.json

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "test:unit": "vitest run --dir src",
    "test:integration": "vitest run --dir tests/integration --testTimeout=30000",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:codegen": "playwright codegen http://localhost:3000",
    "test:e2e:debug": "playwright test --debug",
    "test:load": "k6 run tests/load/scenarios/api-stress.js",
    "test:ai": "vitest run --dir tests/ai",
    "test:all": "vitest run && playwright test"
  }
}
```

---

## Step 6: VS Code Integration

### Extensions to Install

```json
// .vscode/extensions.json
{
  "recommendations": [
    "vitest.explorer",              // Vitest test explorer (run/debug from sidebar)
    "ms-playwright.playwright",     // Playwright test explorer + codegen
    "ryanluker.vscode-coverage-gutters" // Show coverage in editor gutters
  ]
}
```

### Settings

```json
// .vscode/settings.json (add to existing)
{
  "vitest.enable": true,
  "vitest.commandLine": "pnpm vitest",
  "testing.automaticallyOpenPeekView": "failureInVisibleDocument",
  "coverage-gutters.showLineCoverage": true,
  "coverage-gutters.coverageFileNames": ["coverage/lcov.info"]
}
```

---

## Step 7: Your First Tests (Walkthrough)

### First Unit Test

```typescript
// src/lib/validators.ts
export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

export function slugify(text: string): string {
  return text.toLowerCase().trim().replace(/[^\w\s-]/g, '').replace(/[\s_-]+/g, '-').replace(/^-+|-+$/g, '')
}
```

```typescript
// src/lib/validators.test.ts
import { describe, it, expect } from 'vitest'
import { isValidEmail, slugify } from './validators'

describe('isValidEmail', () => {
  it('accepts valid emails', () => {
    expect(isValidEmail('user@example.com')).toBe(true)
    expect(isValidEmail('name+tag@domain.co.uk')).toBe(true)
  })

  it('rejects invalid emails', () => {
    expect(isValidEmail('')).toBe(false)
    expect(isValidEmail('not-an-email')).toBe(false)
    expect(isValidEmail('@no-local.com')).toBe(false)
    expect(isValidEmail('no-domain@')).toBe(false)
  })
})

describe('slugify', () => {
  it('converts text to URL-safe slugs', () => {
    expect(slugify('Hello World')).toBe('hello-world')
    expect(slugify('  Lots   of   spaces  ')).toBe('lots-of-spaces')
    expect(slugify('Special Ch@r$!')).toBe('special-chr')
  })
})
```

### Run It

```bash
# Run all tests
pnpm test

# Run in watch mode (re-runs on file changes)
pnpm test:watch

# Run with coverage
pnpm test:coverage

# Run a specific file
pnpm vitest run src/lib/validators.test.ts
```

### First E2E Test

```typescript
// tests/e2e/flows/homepage.spec.ts
import { test, expect } from '@playwright/test'

test('homepage loads and shows title', async ({ page }) => {
  await page.goto('/')
  await expect(page).toHaveTitle(/My App/)
})

test('navigation works', async ({ page }) => {
  await page.goto('/')
  await page.click('text=About')
  await expect(page).toHaveURL('/about')
})
```

### Run It

```bash
# Run E2E tests (headless)
pnpm test:e2e

# Run with Playwright UI (visual test runner — great for debugging)
pnpm test:e2e:ui

# Generate tests by recording your actions in the browser
pnpm test:e2e:codegen
```

---

## Step 8: Create Directory Structure

```bash
# Run this to create the full test directory structure
mkdir -p tests/{integration/api,e2e/{flows,pages},load/scenarios,ai/mocks,fixtures}

# Create placeholder files
touch tests/integration/setup.ts
touch tests/integration/helpers.ts
touch tests/fixtures/factory.ts
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `vitest: command not found` | Run `pnpm add -D vitest` and use `pnpm vitest` |
| TypeScript errors in test files | Ensure `tsconfig.json` includes `"types": ["vitest/globals"]` |
| Testcontainers: Docker not running | Start Docker Desktop or `sudo systemctl start docker` |
| Playwright: browser not found | Run `npx playwright install chromium` |
| Coverage thresholds failing | Lower thresholds initially, increase as you add tests |
| Tests timing out | Increase `testTimeout` in vitest.config.ts |
| Path aliases not resolving | Ensure `alias` in vitest.config.ts matches tsconfig `paths` |

### TypeScript Config for Tests

```json
// tsconfig.json — add to compilerOptions
{
  "compilerOptions": {
    "types": ["vitest/globals"],
    "paths": {
      "@/*": ["./src/*"],
      "@tests/*": ["./tests/*"]
    }
  },
  "include": ["src", "tests"]
}
```

---

## Checklist

- [ ] Vitest installed and `pnpm test` runs without errors
- [ ] vitest.config.ts created with coverage, aliases, and setup file
- [ ] .env.test created with test-specific environment variables
- [ ] Playwright installed and `pnpm test:e2e` opens a browser
- [ ] playwright.config.ts created with webServer auto-start
- [ ] k6 installed and `k6 version` works
- [ ] Testcontainers installed and Docker is running
- [ ] Test scripts added to package.json
- [ ] VS Code extensions installed (Vitest Explorer, Playwright)
- [ ] First unit test passes
- [ ] First E2E test passes
- [ ] Directory structure created
