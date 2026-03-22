---
name: enterprise-security
description: Explains how to implement application security, compliance, and defensive patterns with enterprise standards. Trigger on ANY mention of security audit, OWASP, vulnerability, penetration test, pen test, dependency scanning, Snyk, Trivy, npm audit, CSP, Content Security Policy, CORS, security headers, HSTS, X-Frame-Options, XSS, CSRF, SQL injection, SSRF, IDOR, SOC2, SOC 2, HIPAA, PCI-DSS, PCI DSS, ISO 27001, GDPR, CCPA, CPRA, PIPEDA, LGPD, privacy compliance, cookie consent, data export, data portability, right to erasure, account deletion, data retention, encryption key rotation, compliance, security review, secrets management, secrets rotation, Vault, Doppler, security policy, WAF, rate limiting, brute force, zero trust, SBOM, supply chain security, code scanning, SAST, DAST, or any request requiring security hardening, compliance preparation, privacy implementation, or vulnerability assessment.
---

# Enterprise Security & Compliance Skill

Every application must be secured against known attack vectors and comply with applicable regulatory frameworks. Security is not a feature — it is a property of every line of code. This skill centralizes security patterns that are scattered across other enterprise skills and adds depth for OWASP defense, compliance frameworks, vulnerability management, and automated security tooling.

## Reference Files

### OWASP Top 10 Defense

- `references/owasp-top10.md` — All 10 categories with attack examples, defense patterns, code samples, testing procedures

### Dependency & Supply Chain Security

- `references/dependency-scanning.md` — Snyk, Trivy, npm audit, pip audit, CI integration, SBOM generation, vulnerability triage

### Security Headers & CORS

- `references/csp-cors-headers.md` — Content Security Policy, CORS deep-dive, HSTS, X-Frame-Options, Permissions-Policy, reporting

### Penetration Testing

- `references/pentesting-checklist.md` — Methodology, reconnaissance, auth testing, injection, XSS, CSRF, IDOR, SSRF, reporting template

### Compliance Frameworks

- `references/compliance-soc2-hipaa.md` — SOC2 Type II controls, HIPAA technical safeguards, PCI-DSS requirements, audit preparation

### GDPR & Privacy Compliance

- `references/gdpr-privacy-compliance.md` — Cookie consent implementation, data export/portability, account deletion cascades, app-level encryption key rotation, GDPR/CCPA/PIPEDA requirements

### Secrets Management

- `references/secrets-rotation.md` — Vault, Doppler, AWS Secrets Manager, rotation automation, zero-downtime rotation, emergency procedures

### Third-Party Vendor & API Risk

- `references/third-party-vendor-audit.md` — Vendor identity verification, privacy/compliance checklist, technical security audit, data safeguards for high-risk vendors, risk rating matrix, ToS violation detection

Read this SKILL.md first for the security-first mindset and decision framework, then consult references for implementation specifics.

---

## Security-First Decision Framework

### Threat Modeling (Before Writing Code)

For every feature, ask:

1. **What data does this touch?** (PII, financial, credentials, health data)
2. **Who can access it?** (authenticated, specific roles, public)
3. **What can go wrong?** (injection, unauthorized access, data leak, denial of service)
4. **What's the blast radius?** (single user, all users, entire system)
5. **What compliance requirements apply?** (GDPR, HIPAA, PCI-DSS, SOC2)

### Security Tier Selection

| Tier | Description | Requirements | Examples |
|---|---|---|---|
| **Tier 1: Standard** | Most web apps | OWASP Top 10 defense, input validation, auth, HTTPS | Blog, internal tool, portfolio |
| **Tier 2: Sensitive** | User data, payments | Tier 1 + encryption at rest, audit logging, dependency scanning, pen testing | SaaS, e-commerce, CRM |
| **Tier 3: Regulated** | Healthcare, finance | Tier 2 + compliance framework (HIPAA/SOC2/PCI), data residency, retention policies | Health app, fintech, insurance |
| **Tier 4: Critical** | Infrastructure, gov | Tier 3 + zero trust, HSM, air-gapped secrets, red team exercises | Banking core, government, defense |

**Every project is at least Tier 1.** Determine tier during planning and document it.

---

## OWASP Top 10 — Defense Summary

| # | Category | Primary Defense |
|---|---|---|
| A01 | Broken Access Control | RBAC/ABAC middleware, resource-level authz, deny by default |
| A02 | Cryptographic Failures | TLS everywhere, AES-256-GCM at rest, Argon2id for passwords |
| A03 | Injection | Parameterized queries, input validation (Zod/Pydantic), ORM |
| A04 | Insecure Design | Threat modeling, secure defaults, principle of least privilege |
| A05 | Security Misconfiguration | Hardened defaults, no debug in prod, security headers |
| A06 | Vulnerable Components | Dependency scanning, automated updates, SBOM |
| A07 | Auth Failures | MFA, session management, account lockout, password policies |
| A08 | Data Integrity Failures | Signed updates, CI/CD pipeline security, input verification |
| A09 | Logging & Monitoring | Structured logging, alerting on auth failures, SIEM integration |
| A10 | SSRF | URL allowlists, private network blocking, DNS rebinding defense |

See `references/owasp-top10.md` for full implementation details on each category.

---

## Security Headers (Non-Negotiable)

```typescript
// Minimum security headers for every response
app.addHook('onSend', (req, reply, payload, done) => {
  reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload')
  reply.header('X-Content-Type-Options', 'nosniff')
  reply.header('X-Frame-Options', 'DENY')
  reply.header('X-XSS-Protection', '0') // Disabled — CSP is the modern replacement
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin')
  reply.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
  reply.header('Content-Security-Policy', buildCSP())
  done()
})

function buildCSP(): string {
  return [
    "default-src 'self'",
    "script-src 'self' 'strict-dynamic'",
    "style-src 'self' 'unsafe-inline'",   // Consider nonces for stricter
    "img-src 'self' data: https:",
    "font-src 'self' https://fonts.gstatic.com",
    "connect-src 'self' https://api.company.com",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "upgrade-insecure-requests",
  ].join('; ')
}
```

---

## Input Validation & Sanitization

```typescript
// ALWAYS validate at the API boundary
import { z } from 'zod'
import DOMPurify from 'isomorphic-dompurify'

// Strict schemas that reject unknown fields
const CreateUserSchema = z.object({
  email: z.string().email().max(255).toLowerCase(),
  name: z.string().min(2).max(100).trim(),
  password: z.string()
    .min(12, 'Password must be at least 12 characters')
    .regex(/[A-Z]/, 'Must contain uppercase letter')
    .regex(/[a-z]/, 'Must contain lowercase letter')
    .regex(/[0-9]/, 'Must contain number')
    .regex(/[^A-Za-z0-9]/, 'Must contain special character'),
  bio: z.string().max(500).transform((val) => DOMPurify.sanitize(val)).optional(),
}).strict() // Reject unknown fields

// URL validation (prevent SSRF)
const WebhookUrlSchema = z.string().url().refine((url) => {
  const parsed = new URL(url)
  // Block internal networks
  const blocked = ['localhost', '127.0.0.1', '0.0.0.0', '10.', '172.16.', '192.168.', '169.254.']
  return !blocked.some((b) => parsed.hostname.startsWith(b))
}, 'URL must not point to internal network')
```

---

## Encryption

### At Rest

```typescript
import crypto from 'crypto'

const ALGORITHM = 'aes-256-gcm'
const KEY = Buffer.from(process.env.ENCRYPTION_KEY!, 'hex') // 32 bytes

export function encrypt(plaintext: string): string {
  const iv = crypto.randomBytes(16)
  const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv)
  let encrypted = cipher.update(plaintext, 'utf8', 'hex')
  encrypted += cipher.final('hex')
  const authTag = cipher.getAuthTag().toString('hex')
  return `${iv.toString('hex')}:${authTag}:${encrypted}`
}

export function decrypt(ciphertext: string): string {
  const [ivHex, authTagHex, encrypted] = ciphertext.split(':')
  const decipher = crypto.createDecipheriv(ALGORITHM, KEY, Buffer.from(ivHex, 'hex'))
  decipher.setAuthTag(Buffer.from(authTagHex, 'hex'))
  let decrypted = decipher.update(encrypted, 'hex', 'utf8')
  decrypted += decipher.final('utf8')
  return decrypted
}
```

### Database Field Encryption

```typescript
// Prisma middleware for transparent field encryption
prisma.$use(async (params, next) => {
  const sensitiveFields = ['ssn', 'taxId', 'bankAccountNumber']

  // Encrypt on write
  if (['create', 'update', 'upsert'].includes(params.action)) {
    for (const field of sensitiveFields) {
      if (params.args.data?.[field]) {
        params.args.data[field] = encrypt(params.args.data[field])
      }
    }
  }

  const result = await next(params)

  // Decrypt on read
  if (result && typeof result === 'object') {
    for (const field of sensitiveFields) {
      if (result[field]) {
        result[field] = decrypt(result[field])
      }
    }
  }

  return result
})
```

---

## Security Review Workflow

### For Every PR

1. **Automated checks** (CI pipeline):
   - Dependency scanning (Snyk/Trivy)
   - SAST (static analysis)
   - Secret detection (git-secrets, trufflehog)
   - License compliance

2. **Manual review checklist:**
   - [ ] No secrets in code (API keys, passwords, tokens)
   - [ ] All inputs validated with typed schemas
   - [ ] SQL queries use parameterized inputs (no string concatenation)
   - [ ] Authorization checked for every new endpoint
   - [ ] Error responses don't leak internal details
   - [ ] Logging doesn't include PII or secrets
   - [ ] New dependencies reviewed for security posture

### Quarterly Security Reviews

- [ ] Run full dependency scan, triage all findings
- [ ] Review and rotate all secrets
- [ ] Update CSP policy if new external resources added
- [ ] Review access control matrix (who has access to what)
- [ ] Review audit logs for anomalies
- [ ] Test incident response runbook

---

## Testing Requirements

### What Must Be Tested

- [ ] All OWASP Top 10 vectors tested per category
- [ ] Auth bypass attempts (direct URL access, JWT manipulation)
- [ ] IDOR: accessing resources with other users' IDs
- [ ] Injection: SQL, NoSQL, OS command, LDAP
- [ ] XSS: stored, reflected, DOM-based
- [ ] CSRF: state-changing requests without valid token
- [ ] Rate limiting: brute force login, API abuse
- [ ] Security headers present on all responses
- [ ] Error messages don't leak stack traces or internal paths
- [ ] File uploads: type validation, size limits, no execution
- [ ] Dependency scan: no critical or high vulnerabilities

---

## Integration with Other Enterprise Skills

- **enterprise-backend**: Security middleware (auth, rate limiting, CORS) implemented at backend layer. This skill adds OWASP defense depth and compliance checklists.
- **enterprise-frontend**: CSP headers affect frontend script loading. XSS prevention requires both frontend escaping and backend sanitization.
- **enterprise-deployment**: Security scanning in CI/CD pipelines, secrets management in infrastructure, WAF configuration.
- **enterprise-database**: SQL injection prevention, encryption at rest, access control at database level, audit logging.
- **enterprise-search-messaging**: Webhook signature verification, event payload encryption, message authentication.

---

## Verification Checklist

Before considering any security work complete, verify:

- [ ] Security tier determined and documented
- [ ] OWASP Top 10 defenses implemented for the application's tier
- [ ] All security headers configured (HSTS, CSP, X-Frame-Options, etc.)
- [ ] Input validation on every API endpoint (Zod/Pydantic)
- [ ] CORS strict origin allowlist (no wildcards in production)
- [ ] Secrets in environment variables or secrets manager (none in code)
- [ ] Dependency scanning in CI pipeline (Snyk or Trivy)
- [ ] Secret detection in CI (prevent committed secrets)
- [ ] Encryption at rest for PII and sensitive data
- [ ] Audit logging on all auth events and data modifications
- [ ] Error responses sanitized (no stack traces, SQL, file paths)
- [ ] Rate limiting on auth endpoints and sensitive operations
- [ ] Compliance checklist completed for applicable framework (SOC2/HIPAA/PCI)
