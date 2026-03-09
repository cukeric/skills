---
name: pre-deploy-security-scanner
description: Pre-deployment security audit for OWASP Top 10 vulnerabilities, hardcoded secrets, authentication coverage, input validation, rate limiting, and data exposure. Trigger before any deployment, when the user says "security scan", "security audit", "check for vulnerabilities", "OWASP check", "is the code secure", "pre-deploy check", or as part of the mandatory pre-deploy verification pipeline. Also trigger when new API routes are added, auth logic changes, or user input handling is modified.
---

# Pre-Deploy Security Scanner

A security-focused gate that runs BEFORE every deployment. Systematically checks the codebase against OWASP Top 10, enterprise security standards, and common vulnerability patterns. Different from the code-reviewer (which reviews against a plan) — this is a focused security audit.

## When to Use

- Before every deployment (mandatory in session protocol)
- After adding new API routes or endpoints
- After modifying authentication or authorization logic
- After changing input validation or sanitization
- After adding new dependencies
- When the user asks for a security review

## Scan Categories

### 1. Hardcoded Secrets Detection

Scan for secrets that should be in env vars:

```bash
# API keys, tokens, passwords in source code
grep -rn "sk_live\|sk_test\|pk_live\|pk_test" src/ --include="*.ts" --include="*.tsx"
grep -rn "password\s*[:=]\s*['\"]" src/ --include="*.ts" --include="*.tsx"
grep -rn "apiKey\s*[:=]\s*['\"][a-zA-Z0-9]" src/ --include="*.ts" --include="*.tsx"
grep -rn "secret\s*[:=]\s*['\"][a-zA-Z0-9]" src/ --include="*.ts" --include="*.tsx"
grep -rn "Bearer [a-zA-Z0-9]" src/ --include="*.ts" --include="*.tsx"

# Check .env files aren't committed
git ls-files | grep -E "\.env$|\.env\.local$|\.env\.production$"
```

### 2. Authentication Coverage

Every API route must have auth checks. Scan for unprotected endpoints:

```bash
# List all API route files
find src/app/api -name "route.ts" | sort

# Check each for auth patterns
for f in $(find src/app/api -name "route.ts"); do
  if ! grep -q "getServerSession\|getToken\|auth()\|session\|CRON_SECRET" "$f"; then
    echo "UNPROTECTED: $f"
  fi
done
```

**Exceptions (intentionally public):**
- Webhook endpoints (validated by signature, not session)
- Public data endpoints (microsites, slug resolvers)
- Health check endpoints

Document every exception with justification.

### 3. Input Validation (OWASP A03: Injection)

Every endpoint that accepts user input must validate it:

```bash
# Find all request.json() calls — each needs validation
grep -rn "request\.json()" src/app/api/ --include="*.ts"

# Check for Zod/schema validation near each
# FAIL if request.json() result is used without validation
```

**Check for:**
- SQL injection: No raw string interpolation in queries (Prisma ORM protects, but check raw queries)
- XSS: No `dangerouslySetInnerHTML` with user data
- Command injection: No `exec()`, `spawn()`, `eval()` with user input
- Path traversal: No user input in file paths without sanitization

### 4. Rate Limiting (OWASP A04: Insecure Design)

Public-facing endpoints must have rate limits:

```bash
# Find all API routes
find src/app/api -name "route.ts" | sort

# Check for rate limiting
for f in $(find src/app/api -name "route.ts"); do
  if ! grep -q "rateLimit\|rate-limit\|rateLimiter" "$f"; then
    echo "NO RATE LIMIT: $f"
  fi
done
```

**Must be rate-limited:**
- Auth endpoints (login, register, forgot-password, reset-password)
- Generation endpoints (AI calls are expensive)
- Payment endpoints (prevent abuse)
- Contact/lead forms (spam prevention)

### 5. Data Exposure (OWASP A01: Broken Access Control)

```bash
# Check for overly broad selects (returning too many fields)
grep -rn "select:\s*{" src/app/api/ --include="*.ts" -A 5

# Check for password/secret fields in API responses
grep -rn "passwordHash\|password\|secret\|token" src/app/api/ --include="*.ts"

# Verify error responses don't leak internals
grep -rn "stack\|SQL\|prisma\|PrismaClient" src/app/api/ --include="*.ts"
```

**Rules:**
- Never return `passwordHash`, raw tokens, or internal IDs unnecessarily
- Error responses: machine-readable code + human message. No stack traces, SQL, or file paths.
- User A must not access User B's data (check `where: { userId: session.user.id }` patterns)

### 5b. Account Enumeration Prevention (OWASP A07)

Check that auth endpoints don't leak account existence:

```bash
# Registration should NOT return different status codes for existing vs new emails
# FAIL if registration returns 409 Conflict for existing emails
grep -rn "409\|CONFLICT\|already exists" src/app/api/auth/register/ --include="*.ts"

# Login should use generic error messages
# FAIL if login returns "user not found" vs "wrong password" differently
grep -rn "not found\|no account\|doesn't exist" src/app/api/auth/ --include="*.ts"

# Password reset should always return same response
grep -rn "user not found\|no account" src/app/api/auth/forgot-password/ --include="*.ts"
```

### 5c. Frontend/Backend Validation Sync

Check that frontend validation constraints match backend:

```bash
# Find all minLength in frontend forms
grep -rn "minLength" src/app/ --include="*.tsx"

# Compare with backend password validation
grep -rn "password.*length\|\.length.*<\|\.length.*>" src/app/api/auth/ --include="*.ts"

# FAIL if frontend minLength differs from backend minimum
```

### 5d. OAuth State Token Security

```bash
# OAuth state must be HMAC-signed, not just random
grep -rn "state\|createHmac\|signState\|verifyState" src/app/api/social/ --include="*.ts"

# FAIL if state tokens are unsigned (base64-only without HMAC)
# FAIL if callback doesn't verify signature with timingSafeEqual
grep -rn "timingSafeEqual" src/app/api/social/callback/ --include="*.ts"
```

### 5e. Content-Disposition Header Safety

```bash
# Any response that sets Content-Disposition must sanitize the filename
grep -rn "Content-Disposition" src/app/api/ --include="*.ts"

# FAIL if filename comes from DB or user input without path.basename() or regex sanitization
```

### 6. Security Headers

```bash
# Check next.config.ts for security headers
grep -A 30 "headers" next.config.ts
```

**Required headers:**
- `Strict-Transport-Security`: `max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options`: `nosniff`
- `X-Frame-Options`: `DENY`
- `Referrer-Policy`: `strict-origin-when-cross-origin`
- `Permissions-Policy`: camera, microphone, geolocation disabled
- `Content-Security-Policy`: Present (even if permissive initially)

### 7. Dependency Vulnerabilities

```bash
npm audit --production 2>&1 | tail -20
```

Flag any `high` or `critical` severity findings as blockers.

### 8. Cryptographic Practices

```bash
# Check password hashing (must be bcrypt/argon2, NOT MD5/SHA)
grep -rn "bcrypt\|argon2\|scrypt" src/ --include="*.ts"
grep -rn "md5\|sha1\|sha256" src/ --include="*.ts"

# Check encryption (must be AES-256-GCM or better)
grep -rn "createCipher\|aes-256" src/ --include="*.ts"

# Check token generation (must use crypto.randomBytes, NOT Math.random)
grep -rn "Math\.random\|uuid" src/ --include="*.ts"
grep -rn "crypto\.randomBytes\|randomUUID" src/ --include="*.ts"
```

### 9. Session & Token Security

```bash
# JWT/session config
grep -rn "maxAge\|expires\|httpOnly\|secure\|sameSite" src/ --include="*.ts"
```

**Check:**
- Session cookies: `httpOnly`, `secure`, `sameSite: lax` or `strict`
- JWT expiry: access tokens ≤ 15 min, refresh tokens ≤ 7 days
- CSRF protection on state-changing operations

### 10. File Upload Security

```bash
# Find file upload handling
grep -rn "formData\|multipart\|upload\|File\|Blob" src/app/api/ --include="*.ts"
```

**If file uploads exist:**
- Validate file type (magic bytes, not just extension)
- Enforce size limits
- Store outside web root
- Sanitize filenames

## Output Format

```
## Pre-Deploy Security Scan — {date}

### Critical Findings (BLOCK DEPLOYMENT)
| # | Category          | File                    | Finding                              |
|---|-------------------|-------------------------|--------------------------------------|
| 1 | Hardcoded Secret  | src/lib/email.ts:8      | API key in source code               |

### High Findings (Fix Before Next Deploy)
| # | Category          | File                    | Finding                              |
|---|-------------------|-------------------------|--------------------------------------|
| 1 | No Rate Limit     | src/app/api/foo/route.ts| Public endpoint without rate limiting|

### Medium Findings (Track and Plan)
| # | Category          | File                    | Finding                              |
|---|-------------------|-------------------------|--------------------------------------|
| 1 | Missing CSP       | next.config.ts          | No Content-Security-Policy header    |

### Passed Checks
- [x] No hardcoded secrets in source
- [x] All API routes have auth checks (or documented exceptions)
- [x] Input validation on all endpoints accepting user data
- [x] Rate limiting on auth and generation endpoints
- [x] No data exposure in API responses
- [x] Security headers configured
- [x] No critical dependency vulnerabilities
- [x] Cryptographic practices follow standards
- [x] Session security configured correctly

Result: {PASS / BLOCK} — {critical_count} critical, {high_count} high, {medium_count} medium
```

## Severity Levels

| Severity | Meaning | Action |
|---|---|---|
| **CRITICAL** | Exploitable vulnerability, data exposure, or secret leak | **Block deployment.** Fix immediately. |
| **HIGH** | Security gap that could be exploited with moderate effort | Fix before next deployment. |
| **MEDIUM** | Defense-in-depth gap, missing best practice | Track and plan fix within 1-2 sessions. |
| **LOW** | Minor improvement, hardening opportunity | Address when convenient. |

## Integration

This skill runs AFTER code changes and BEFORE deployment:

```
code changes → env-config-auditor → pre-deploy-security-scanner → deploy → deployment-validator
```
