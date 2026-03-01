# Load & Performance Testing Reference (k6)

## Setup

```bash
# Install k6 (see environment-setup.md for OS-specific instructions)
k6 version

# Or run via Docker (no install needed)
docker run --rm -i grafana/k6 run - < tests/load/scenarios/api-stress.js
```

---

## Test Types

| Type | Purpose | Pattern |
|---|---|---|
| **Smoke** | Verify system works under minimal load | 1-2 VUs, 1 minute |
| **Load** | Validate performance under expected load | Ramp to expected users |
| **Stress** | Find breaking point | Ramp beyond capacity |
| **Spike** | Test sudden traffic bursts | Jump to high load instantly |
| **Soak** | Find memory leaks / degradation | Sustained load for hours |

---

## Smoke Test (Start Here)

```javascript
// tests/load/scenarios/smoke.js
import http from 'k6/http'
import { check, sleep } from 'k6'

export const options = {
  vus: 1,              // 1 virtual user
  duration: '30s',     // Run for 30 seconds
  thresholds: {
    http_req_duration: ['p(95)<500'],   // 95% of requests under 500ms
    http_req_failed: ['rate<0.01'],      // Less than 1% failures
  },
}

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000'

export default function () {
  // Test your main endpoints
  const responses = http.batch([
    ['GET', `${BASE_URL}/api/health`],
    ['GET', `${BASE_URL}/api/products`],
  ])

  check(responses[0], {
    'health check status 200': (r) => r.status === 200,
  })

  check(responses[1], {
    'products status 200': (r) => r.status === 200,
    'products has data': (r) => JSON.parse(r.body).length > 0,
  })

  sleep(1)  // Think time between requests
}
```

### Run It

```bash
k6 run tests/load/scenarios/smoke.js

# With custom base URL
k6 run -e BASE_URL=https://staging.myapp.com tests/load/scenarios/smoke.js
```

---

## Load Test (Expected Traffic)

```javascript
// tests/load/scenarios/load.js
import http from 'k6/http'
import { check, sleep } from 'k6'

export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up to 50 users over 2 min
    { duration: '5m', target: 50 },   // Stay at 50 users for 5 min
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],  // 95th < 1s, 99th < 2s
    http_req_failed: ['rate<0.05'],                     // < 5% failure
    http_reqs: ['rate>100'],                            // At least 100 req/s
  },
}

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000'

export function setup() {
  // Login and get token
  const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
    email: 'loadtest@test.com',
    password: 'LoadTestPassword123!',
  }), { headers: { 'Content-Type': 'application/json' } })

  return { token: JSON.parse(loginRes.body).token }
}

export default function (data) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.token}`,
  }

  // Simulate typical user behavior
  const scenario = Math.random()

  if (scenario < 0.5) {
    // 50%: Browse products
    const res = http.get(`${BASE_URL}/api/products`, { headers })
    check(res, { 'products 200': (r) => r.status === 200 })
  } else if (scenario < 0.8) {
    // 30%: View single product
    const res = http.get(`${BASE_URL}/api/products/1`, { headers })
    check(res, { 'product detail 200': (r) => r.status === 200 })
  } else {
    // 20%: Search
    const res = http.get(`${BASE_URL}/api/search?q=widget`, { headers })
    check(res, { 'search 200': (r) => r.status === 200 })
  }

  sleep(Math.random() * 3 + 1)  // 1-4 second think time
}
```

---

## Stress Test (Find Breaking Point)

```javascript
// tests/load/scenarios/stress.js
export const options = {
  stages: [
    { duration: '2m', target: 50 },    // Normal load
    { duration: '5m', target: 50 },
    { duration: '2m', target: 100 },   // Above normal
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },   // Stress territory
    { duration: '5m', target: 200 },
    { duration: '2m', target: 300 },   // Breaking point?
    { duration: '5m', target: 300 },
    { duration: '5m', target: 0 },     // Recovery
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'],  // Relaxed: 3s acceptable under stress
    http_req_failed: ['rate<0.15'],      // Up to 15% failure acceptable
  },
}
```

---

## Spike Test (Sudden Traffic Burst)

```javascript
// tests/load/scenarios/spike.js
export const options = {
  stages: [
    { duration: '1m', target: 10 },    // Normal baseline
    { duration: '10s', target: 500 },   // SPIKE: instant jump to 500 users
    { duration: '3m', target: 500 },    // Sustain spike
    { duration: '10s', target: 10 },    // Back to normal
    { duration: '3m', target: 10 },     // Recovery period
  ],
}
```

---

## Performance Budgets

```javascript
// tests/load/scenarios/budget.js
// Run in CI to enforce performance standards

export const options = {
  vus: 10,
  duration: '2m',
  thresholds: {
    // Response time budgets
    'http_req_duration{name:health}': ['p(99)<100'],     // Health: 100ms
    'http_req_duration{name:list}': ['p(95)<500'],       // List: 500ms
    'http_req_duration{name:detail}': ['p(95)<300'],     // Detail: 300ms
    'http_req_duration{name:search}': ['p(95)<1000'],    // Search: 1s
    'http_req_duration{name:create}': ['p(95)<2000'],    // Create: 2s

    // Reliability budgets
    http_req_failed: ['rate<0.01'],                       // 99% success
    'checks{name:status_ok}': ['rate>0.99'],              // 99% correct status

    // Throughput budget
    http_reqs: ['rate>50'],                               // Minimum 50 req/s
  },
}

export default function (data) {
  check(http.get(`${BASE_URL}/api/health`, { tags: { name: 'health' } }), { 'status_ok': (r) => r.status === 200 })
  check(http.get(`${BASE_URL}/api/products`, { tags: { name: 'list' } }), { 'status_ok': (r) => r.status === 200 })
  check(http.get(`${BASE_URL}/api/products/1`, { tags: { name: 'detail' } }), { 'status_ok': (r) => r.status === 200 })
  sleep(1)
}
```

---

## Testing AI Endpoints Under Load

```javascript
// tests/load/scenarios/ai-load.js
// Test AI/chat endpoints — important because LLM calls are slow and expensive

export const options = {
  stages: [
    { duration: '1m', target: 5 },     // AI endpoints: fewer concurrent users
    { duration: '5m', target: 20 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    'http_req_duration{name:chat}': ['p(95)<10000'],     // 10s for AI chat
    'http_req_duration{name:rag}': ['p(95)<5000'],       // 5s for RAG query
    http_req_failed: ['rate<0.05'],
  },
}

export default function (data) {
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${data.token}` }

  // RAG query
  const ragRes = http.post(`${BASE_URL}/api/ai/rag/query`, JSON.stringify({
    question: 'What is the refund policy?',
  }), { headers, tags: { name: 'rag' }, timeout: '15s' })

  check(ragRes, { 'rag 200': (r) => r.status === 200 })

  sleep(3)  // Longer think time for AI features
}
```

---

## Viewing Results

```bash
# Console output (default)
k6 run tests/load/scenarios/load.js

# JSON output (for CI parsing)
k6 run --out json=results.json tests/load/scenarios/load.js

# HTML report (via k6-reporter)
# pnpm add -D k6-reporter
# Add: import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js'
# export function handleSummary(data) { return { 'report.html': htmlReport(data) } }
```

---

## Checklist

- [ ] k6 installed and smoke test passes
- [ ] Load test simulates expected production traffic patterns
- [ ] Stress test identifies breaking point (document it)
- [ ] Performance budgets defined per endpoint (p95, p99 thresholds)
- [ ] AI endpoints tested separately (higher latency acceptable)
- [ ] Auth handled (login in setup(), token reused)
- [ ] Think time added between requests (realistic user behavior)
- [ ] CI integration: performance budgets enforced on every deploy
- [ ] Results exported (JSON/HTML) for trend tracking
