# E2E Testing Reference (Playwright)

## What E2E Tests Cover

E2E tests verify complete user journeys through the actual browser. They're the most expensive tests to run but catch integration issues that unit and integration tests miss — broken UI, incorrect navigation, form submission failures, and visual regressions.

**Rule: Only test critical paths.** Don't replicate your unit tests in the browser.

---

## Setup Recap

```bash
# If not already done (see environment-setup.md)
pnpm add -D @playwright/test
npx playwright install --with-deps chromium
```

---

## Page Object Model (Recommended Pattern)

Page objects encapsulate page-specific selectors and actions, keeping tests clean and maintainable.

```typescript
// tests/e2e/pages/login.page.ts
import { type Page, type Locator } from '@playwright/test'

export class LoginPage {
  readonly page: Page
  readonly emailInput: Locator
  readonly passwordInput: Locator
  readonly submitButton: Locator
  readonly errorMessage: Locator

  constructor(page: Page) {
    this.page = page
    this.emailInput = page.getByLabel('Email')
    this.passwordInput = page.getByLabel('Password')
    this.submitButton = page.getByRole('button', { name: 'Sign in' })
    this.errorMessage = page.getByRole('alert')
  }

  async goto() {
    await this.page.goto('/login')
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email)
    await this.passwordInput.fill(password)
    await this.submitButton.click()
  }
}

// tests/e2e/pages/dashboard.page.ts
export class DashboardPage {
  readonly page: Page
  readonly heading: Locator
  readonly userMenu: Locator
  readonly logoutButton: Locator

  constructor(page: Page) {
    this.page = page
    this.heading = page.getByRole('heading', { level: 1 })
    this.userMenu = page.getByTestId('user-menu')
    this.logoutButton = page.getByRole('menuitem', { name: 'Logout' })
  }

  async expectLoaded() {
    await this.page.waitForURL('/dashboard')
    await expect(this.heading).toBeVisible()
  }

  async logout() {
    await this.userMenu.click()
    await this.logoutButton.click()
  }
}
```

---

## User Flow Tests

### Authentication Flow

```typescript
// tests/e2e/flows/auth.spec.ts
import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { DashboardPage } from '../pages/dashboard.page'

test.describe('Authentication', () => {
  test('successful login redirects to dashboard', async ({ page }) => {
    const loginPage = new LoginPage(page)
    const dashboardPage = new DashboardPage(page)

    await loginPage.goto()
    await loginPage.login('admin@test.com', 'TestPassword123!')

    await dashboardPage.expectLoaded()
    await expect(dashboardPage.heading).toContainText('Dashboard')
  })

  test('invalid credentials show error', async ({ page }) => {
    const loginPage = new LoginPage(page)

    await loginPage.goto()
    await loginPage.login('wrong@test.com', 'wrongpassword')

    await expect(loginPage.errorMessage).toBeVisible()
    await expect(loginPage.errorMessage).toContainText('Invalid credentials')
    await expect(page).toHaveURL('/login')  // Stay on login page
  })

  test('logout returns to login page', async ({ page }) => {
    // Login first
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('admin@test.com', 'TestPassword123!')

    // Then logout
    const dashboardPage = new DashboardPage(page)
    await dashboardPage.expectLoaded()
    await dashboardPage.logout()

    await expect(page).toHaveURL('/login')
  })

  test('protected routes redirect to login when unauthenticated', async ({ page }) => {
    await page.goto('/dashboard')
    await expect(page).toHaveURL('/login?redirect=/dashboard')
  })
})
```

### Form Submission Flow

```typescript
// tests/e2e/flows/create-order.spec.ts
test.describe('Create Order', () => {
  // Reuse auth state (logged in)
  test.use({ storageState: 'tests/e2e/.auth/user.json' })

  test('complete order creation flow', async ({ page }) => {
    await page.goto('/orders/new')

    // Fill out order form
    await page.getByLabel('Customer').fill('Acme Corp')
    await page.getByLabel('Product').selectOption('widget-pro')
    await page.getByLabel('Quantity').fill('10')

    // Submit
    await page.getByRole('button', { name: 'Create Order' }).click()

    // Verify success
    await expect(page.getByText('Order created successfully')).toBeVisible()
    await expect(page).toHaveURL(/\/orders\/[a-f0-9-]+/)

    // Verify order details on confirmation page
    await expect(page.getByText('Acme Corp')).toBeVisible()
    await expect(page.getByText('Widget Pro × 10')).toBeVisible()
  })

  test('validates required fields', async ({ page }) => {
    await page.goto('/orders/new')
    await page.getByRole('button', { name: 'Create Order' }).click()

    await expect(page.getByText('Customer is required')).toBeVisible()
    await expect(page.getByText('Product is required')).toBeVisible()
  })
})
```

---

## Auth State Reuse (Login Once, Reuse Everywhere)

```typescript
// tests/e2e/auth.setup.ts
import { test as setup, expect } from '@playwright/test'

setup('authenticate as user', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Email').fill('user@test.com')
  await page.getByLabel('Password').fill('TestPassword123!')
  await page.getByRole('button', { name: 'Sign in' }).click()

  await page.waitForURL('/dashboard')

  // Save auth state (cookies, localStorage)
  await page.context().storageState({ path: 'tests/e2e/.auth/user.json' })
})

setup('authenticate as admin', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Email').fill('admin@test.com')
  await page.getByLabel('Password').fill('AdminPassword123!')
  await page.getByRole('button', { name: 'Sign in' }).click()

  await page.waitForURL('/dashboard')
  await page.context().storageState({ path: 'tests/e2e/.auth/admin.json' })
})
```

```typescript
// playwright.config.ts — add setup project
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], storageState: 'tests/e2e/.auth/user.json' },
      dependencies: ['setup'],
    },
  ],
})
```

---

## Visual Regression Testing

```typescript
test('dashboard matches visual snapshot', async ({ page }) => {
  await page.goto('/dashboard')
  await page.waitForLoadState('networkidle')

  // Full page screenshot comparison
  await expect(page).toHaveScreenshot('dashboard.png', {
    maxDiffPixelRatio: 0.01,  // Allow 1% pixel difference
  })
})

test('order table renders correctly', async ({ page }) => {
  await page.goto('/orders')

  // Component-level screenshot
  const table = page.getByRole('table')
  await expect(table).toHaveScreenshot('orders-table.png')
})

// Update snapshots: npx playwright test --update-snapshots
```

---

## Accessibility Testing

```bash
pnpm add -D @axe-core/playwright
```

```typescript
// tests/e2e/flows/accessibility.spec.ts
import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

test.describe('Accessibility', () => {
  test('login page has no a11y violations', async ({ page }) => {
    await page.goto('/login')

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])  // WCAG 2.0 Level AA
      .analyze()

    expect(results.violations).toEqual([])
  })

  test('dashboard has no critical a11y violations', async ({ page }) => {
    await page.goto('/dashboard')

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .exclude('.third-party-widget')  // Exclude elements you can't control
      .analyze()

    // Allow minor violations, fail on serious/critical
    const serious = results.violations.filter(v => ['serious', 'critical'].includes(v.impact!))
    expect(serious).toEqual([])
  })
})
```

---

## Codegen: Record Tests by Clicking

```bash
# Open your app in a browser and record your actions as test code
npx playwright codegen http://localhost:3000

# This generates ready-to-use test code you can copy into your spec files
```

---

## Debugging Failed Tests

```bash
# Run with headed browser (see what's happening)
npx playwright test --headed

# Debug mode (step through with Playwright Inspector)
npx playwright test --debug

# Open HTML report with traces, screenshots, videos
npx playwright show-report

# UI mode (visual test runner — best debugging experience)
npx playwright test --ui
```

---

## Selectors: Best Practices

```typescript
// ✅ GOOD — Accessible, resilient to UI changes
page.getByRole('button', { name: 'Submit' })
page.getByLabel('Email address')
page.getByText('Welcome back')
page.getByTestId('order-total')           // data-testid attribute

// ❌ BAD — Fragile, breaks with CSS/HTML changes
page.locator('.btn-primary')              // CSS class
page.locator('#submit-btn')              // ID
page.locator('div > form > button:nth-child(2)')  // Position-based
```

---

## Checklist

- [ ] Playwright installed with chromium browser
- [ ] playwright.config.ts with webServer auto-start
- [ ] Page objects for all main pages (Login, Dashboard, etc.)
- [ ] Auth state saved and reused (login once per test suite)
- [ ] Critical user flows tested (login, core feature, logout)
- [ ] Form validation tested (required fields, error messages)
- [ ] Protected routes tested (redirect to login)
- [ ] Visual regression snapshots for key pages
- [ ] Accessibility testing with axe-core (WCAG 2.0 AA)
- [ ] Codegen used for initial test creation
- [ ] Selectors use accessible locators (getByRole, getByLabel)
