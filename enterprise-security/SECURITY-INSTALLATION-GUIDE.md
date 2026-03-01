# Enterprise Security Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | ~320 | Security-first decision framework, threat modeling, security tiers, OWASP summary, security headers, input validation, encryption (AES-256-GCM), database field encryption, security review workflow, verification checklist |
| `references/owasp-top10.md` | ~300 | All 10 OWASP categories with attack vectors, defense code (access control, crypto, injection, XSS, SSRF), and testing procedures |
| `references/dependency-scanning.md` | ~250 | npm audit, Snyk, Trivy, SBOM generation, secret detection (git-secrets, TruffleHog), vulnerability triage, Dependabot config |
| `references/csp-cors-headers.md` | ~230 | CSP construction (with nonces), CORS deep dive (common mistakes), complete security headers setup, verification tools |
| `references/pentesting-checklist.md` | ~200 | 7-phase methodology (recon → auth → authz → injection → business logic → config → file upload), pen test report template |
| `references/compliance-soc2-hipaa.md` | ~230 | SOC2 Type II controls, HIPAA technical safeguards, PCI-DSS requirements, evidence collection checklist, audit prep timeline |
| `references/secrets-rotation.md` | ~250 | Doppler, Vault, env validation, zero-downtime rotation (JWT, DB, API keys), CI/CD secrets, emergency rotation procedure |

**Total: ~1,800+ lines of enterprise security patterns.**

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-security/references
cp SKILL.md ~/.claude/skills/enterprise-security/
cp references/* ~/.claude/skills/enterprise-security/references/
```

### Option B: Project-Level

```bash
mkdir -p .claude/skills/enterprise-security/references
cp SKILL.md .claude/skills/enterprise-security/
cp references/* .claude/skills/enterprise-security/references/
```

---

## Trigger Keywords

> security, OWASP, vulnerability, pen test, Snyk, Trivy, CSP, CORS, XSS, CSRF, SQL injection, SSRF, IDOR, SOC2, HIPAA, PCI-DSS, compliance, secrets rotation, Vault, Doppler, security headers, HSTS, encryption, SBOM

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-backend` | Auth middleware, rate limiting, CORS — security adds OWASP depth |
| `enterprise-frontend` | CSP affects script loading, XSS prevention |
| `enterprise-deployment` | Security scanning in CI/CD, WAF, secrets infra |
| `enterprise-database` | SQL injection prevention, encryption at rest, access control |
| `enterprise-search-messaging` | Webhook signatures, event payload encryption |
