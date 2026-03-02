---
name: deployment-validator
description: Post-deployment smoke test and production verification. Trigger when code has been deployed to production or staging, after docker compose up, after rsync + build, or when the user says "validate deployment", "smoke test", "verify production", "check deployment", "test the deploy", "is the site working", or any request to confirm a deployment is healthy. Also trigger proactively as part of the end-of-session protocol after deploying code.
---

# Deployment Validator — Post-Deploy Smoke Test

Performs a comprehensive production smoke test after every deployment. This is not a unit test — it validates the live system from the outside, the way a user or attacker would encounter it.

## When to Use

- After every `docker compose up -d` or deployment command
- After env var changes + rebuild
- After DNS/SSL configuration changes
- As part of the end-of-session protocol (code-review → deploy → **validate** → self-improve)
- When the user says "is the site working" or "check production"

## Validation Checklist

Execute ALL checks in order. Report results as a table with PASS/FAIL/WARN status.

### 1. Core Pages (HTTP Status)

Hit every user-facing page and verify 200 OK (or expected redirect):

```bash
# Public pages — expect 200
curl -s -o /dev/null -w "%{http_code}" https://{domain}/
curl -s -o /dev/null -w "%{http_code}" https://{domain}/login
curl -s -o /dev/null -w "%{http_code}" https://{domain}/register
curl -s -o /dev/null -w "%{http_code}" https://{domain}/demo
curl -s -o /dev/null -w "%{http_code}" https://{domain}/contact
curl -s -o /dev/null -w "%{http_code}" https://{domain}/privacy
curl -s -o /dev/null -w "%{http_code}" https://{domain}/terms

# Protected pages — expect 307 redirect to /login
curl -s -o /dev/null -w "%{http_code}" https://{domain}/dashboard
curl -s -o /dev/null -w "%{http_code}" https://{domain}/dashboard/generate
curl -s -o /dev/null -w "%{http_code}" https://{domain}/dashboard/settings
```

### 2. Security Headers

Every response must include these headers:

```bash
curl -sI https://{domain}/ | grep -iE "strict-transport|x-content-type|x-frame|referrer-policy|permissions-policy"
```

| Header | Expected Value |
|---|---|
| `Strict-Transport-Security` | `max-age=...` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | Present |

### 3. Auth Protection

Verify unauthenticated requests to protected endpoints return 401/403/307:

```bash
# API endpoints — expect 401
curl -s -o /dev/null -w "%{http_code}" https://{domain}/api/listings
curl -s -o /dev/null -w "%{http_code}" https://{domain}/api/billing/credits

# Cron endpoint — expect 401 without bearer token
curl -s -o /dev/null -w "%{http_code}" https://{domain}/api/cron/cleanup
```

### 4. SEO Assets

```bash
# Expect 200
curl -s -o /dev/null -w "%{http_code}" https://{domain}/robots.txt
curl -s -o /dev/null -w "%{http_code}" https://{domain}/sitemap.xml

# Verify robots.txt points to sitemap
curl -s https://{domain}/robots.txt | grep -i sitemap

# Verify JSON-LD is present on landing page
curl -s https://{domain}/ | grep -c 'application/ld+json'
```

### 5. SSL/TLS

```bash
# Verify SSL certificate is valid
curl -sI https://{domain}/ | head -1  # Should be HTTP/2 200

# Check certificate expiry (if direct, not behind Cloudflare)
echo | openssl s_client -connect {domain}:443 -servername {domain} 2>/dev/null | openssl x509 -noout -dates
```

### 6. API Functionality Spot-Check

Test a non-destructive API endpoint with valid payload:

```bash
# Leads API — should accept valid data
curl -s -X POST https://{domain}/api/leads \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"test@example.com","message":"Smoke test"}' \
  -w "\n%{http_code}"
```

### 7. Error Handling

Verify error pages render correctly:

```bash
# 404 page
curl -s -o /dev/null -w "%{http_code}" https://{domain}/nonexistent-page-12345
```

## Output Format

Present results as:

```
## Deployment Validation Report — {domain} — {date}

| Check                    | Status | Details                          |
|--------------------------|--------|----------------------------------|
| Landing page             | PASS   | 200 OK                           |
| Login page               | PASS   | 200 OK                           |
| Dashboard auth guard     | PASS   | 307 → /login                     |
| Security headers         | PASS   | 5/5 present                      |
| API auth protection      | PASS   | 401 on /api/listings             |
| SEO assets               | PASS   | robots.txt + sitemap + JSON-LD   |
| SSL certificate          | PASS   | Valid, Cloudflare proxy          |
| API spot-check           | PASS   | /api/leads returns 200           |
| 404 handling             | PASS   | Returns custom error page        |

Result: ALL CHECKS PASSED — deployment is healthy.
```

If any check fails, flag it as **FAIL** with specific details and recommend immediate action.

## Integration

This skill runs AFTER deployment and BEFORE `/self-improve` in the session protocol:

```
code-reviewer → deploy → deployment-validator → /self-improve
```
