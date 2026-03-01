# OWASP Top 10 Defense Reference

## A01: Broken Access Control

### Attack Vectors

- Direct URL access to admin pages without authentication
- Modifying IDs in requests to access other users' data (IDOR)
- Elevation of privilege by modifying JWT claims or role parameters
- Accessing API endpoints without proper authorization checks

### Defense Patterns

```typescript
// 1. Deny by default — middleware before every route
function authGuard(req, reply, done) {
  if (!req.user) return reply.status(401).send({ error: 'Unauthorized' })
  done()
}

// 2. Resource-level authorization (prevent IDOR)
async function getOrder(req) {
  const order = await db.order.findUnique({ where: { id: req.params.id } })
  if (!order) throw errors.notFound('Order')

  // CRITICAL: verify ownership
  if (order.userId !== req.user.id && !req.user.roles.includes('admin')) {
    throw errors.forbidden('You do not have access to this order')
  }
  return order
}

// 3. RBAC middleware
function requireRole(...roles: string[]) {
  return (req, reply, done) => {
    if (!roles.some(r => req.user.roles.includes(r))) {
      return reply.status(403).send({ error: 'Insufficient permissions' })
    }
    done()
  }
}

app.delete('/api/v1/users/:id', authGuard, requireRole('admin'), deleteUser)
```

### Testing

- Attempt accessing resources with different user IDs
- Try accessing admin endpoints with regular user tokens
- Modify JWT payload and verify rejection
- Test horizontal privilege escalation (user A accessing user B's data)

---

## A02: Cryptographic Failures

### Defense Patterns

- **Passwords**: Argon2id with proper parameters (memory: 64MB, iterations: 3, parallelism: 4)
- **Data at rest**: AES-256-GCM for sensitive fields (see SKILL.md encryption section)
- **Data in transit**: TLS 1.2+ everywhere, HSTS header
- **Tokens**: Cryptographically random (crypto.randomBytes), not predictable

```typescript
import argon2 from 'argon2'

async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 65536,    // 64MB
    timeCost: 3,
    parallelism: 4,
  })
}

async function verifyPassword(hash: string, password: string): Promise<boolean> {
  return argon2.verify(hash, password)
}
```

### What NOT to Do

- Never use MD5, SHA-1, or plain SHA-256 for passwords
- Never store encryption keys in code or config files
- Never use `Math.random()` for tokens — use `crypto.randomUUID()` or `crypto.randomBytes()`
- Never disable TLS certificate verification

---

## A03: Injection

### SQL Injection Defense

```typescript
// ✅ Parameterized query (safe)
const user = await db.query('SELECT * FROM users WHERE email = $1', [email])

// ✅ ORM (safe — uses parameterized queries internally)
const user = await prisma.user.findUnique({ where: { email } })

// ❌ String concatenation (VULNERABLE)
const user = await db.query(`SELECT * FROM users WHERE email = '${email}'`)
```

### NoSQL Injection Defense

```typescript
// ✅ Validate input type
const id = z.string().uuid().parse(req.params.id)
const user = await collection.findOne({ _id: new ObjectId(id) })

// ❌ Passing raw request body (VULNERABLE to $gt, $regex operators)
const user = await collection.findOne(req.body)
```

### OS Command Injection

```typescript
// ✅ Use libraries, not shell commands
import { execFile } from 'child_process' // execFile, not exec
execFile('convert', [inputPath, '-resize', '200x200', outputPath])

// ❌ Never interpolate user input into shell commands
exec(`convert ${userInput} output.jpg`) // VULNERABLE
```

---

## A04: Insecure Design

### Defense Patterns

- Threat model every feature before implementation
- Use established security patterns (don't invent your own crypto/auth)
- Implement rate limiting on all endpoints
- Use allowlists over denylists
- Principle of least privilege for all service accounts

---

## A05: Security Misconfiguration

### Checklist

- [ ] Debug mode disabled in production
- [ ] Default credentials changed
- [ ] Directory listing disabled
- [ ] Stack traces not shown in error responses
- [ ] Unnecessary HTTP methods disabled
- [ ] Security headers set on all responses
- [ ] Admin panels not publicly accessible
- [ ] Cloud storage buckets not publicly readable
- [ ] CORS configured with explicit origins (no `*`)

---

## A06: Vulnerable & Outdated Components

### Defense

- Run `npm audit` / `pip audit` in CI pipeline
- Use Snyk or Trivy for deep scanning (see dependency-scanning.md)
- Pin major versions, allow patch updates
- Review changelogs before major updates
- Generate SBOM for supply chain transparency

---

## A07: Identification & Authentication Failures

### Defense Patterns

```typescript
// Account lockout
const MAX_ATTEMPTS = 5
const LOCKOUT_DURATION = 15 * 60 * 1000 // 15 minutes

async function checkAccountLockout(email: string): Promise<void> {
  const attempts = await redis.get(`login_attempts:${email}`)
  if (parseInt(attempts || '0') >= MAX_ATTEMPTS) {
    const ttl = await redis.ttl(`login_attempts:${email}`)
    throw new Error(`Account locked. Try again in ${ttl} seconds.`)
  }
}

async function recordFailedAttempt(email: string): Promise<void> {
  const key = `login_attempts:${email}`
  await redis.incr(key)
  await redis.expire(key, LOCKOUT_DURATION / 1000)
}

async function clearAttempts(email: string): Promise<void> {
  await redis.del(`login_attempts:${email}`)
}
```

---

## A08: Software & Data Integrity Failures

### Defense

- Verify signatures on all downloaded dependencies
- Lock files committed (package-lock.json, pnpm-lock.yaml)
- CI/CD pipeline integrity (signed commits, protected branches)
- Subresource Integrity (SRI) for CDN scripts

```html
<script src="https://cdn.example.com/lib.js"
  integrity="sha384-oqVuAfXRKap7fdgcCY5uykM6+R9GqQ8K/uxy9rx7HNQlGYl1kPzQho1wx4JwY8w"
  crossorigin="anonymous"></script>
```

---

## A09: Security Logging & Monitoring Failures

### What to Log

```typescript
// Always log these events
logger.info({ userId, ip, userAgent }, 'Login successful')
logger.warn({ userId, ip, email }, 'Login failed')
logger.warn({ userId, ip }, 'Account locked after multiple failures')
logger.info({ userId, targetUserId, action: 'delete' }, 'Admin action')
logger.warn({ userId, resourceId, resourceType }, 'Authorization denied')
logger.info({ userId }, 'Password changed')
logger.info({ userId }, 'MFA enabled')
logger.warn({ userId, ip }, 'Session invalidated due to suspicious activity')
```

### Never Log

- Passwords (even hashed)
- Full credit card numbers
- Social security numbers
- API keys or tokens
- Session IDs

---

## A10: Server-Side Request Forgery (SSRF)

### Defense

```typescript
import { URL } from 'url'
import dns from 'dns/promises'
import { isPrivate } from 'ip'

async function validateExternalUrl(urlString: string): Promise<URL> {
  const url = new URL(urlString)

  // Only allow HTTPS
  if (url.protocol !== 'https:') {
    throw new Error('Only HTTPS URLs are allowed')
  }

  // Block internal hostnames
  const blockedHosts = ['localhost', '127.0.0.1', '0.0.0.0', '169.254.169.254']
  if (blockedHosts.includes(url.hostname)) {
    throw new Error('Internal URLs are not allowed')
  }

  // Resolve DNS and check for private IPs
  const addresses = await dns.resolve4(url.hostname)
  for (const addr of addresses) {
    if (isPrivate(addr)) {
      throw new Error('URL resolves to private IP')
    }
  }

  return url
}
```

---

## OWASP Testing Checklist

- [ ] A01: Access control tested for every endpoint (authN + authZ)
- [ ] A02: Passwords hashed with Argon2id, sensitive data encrypted
- [ ] A03: All inputs go through parameterized queries/ORM
- [ ] A04: Threat model documented, security patterns used
- [ ] A05: No debug mode, default creds, or exposed internals
- [ ] A06: Dependency scan clean (no critical/high vulns)
- [ ] A07: Account lockout, MFA support, session management
- [ ] A08: Lockfiles committed, SRI on CDN scripts
- [ ] A09: Auth events logged, monitoring alerts configured
- [ ] A10: URL validation blocks SSRF to internal networks
