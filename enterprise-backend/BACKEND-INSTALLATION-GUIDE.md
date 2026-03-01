# Enterprise Backend Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | 359 | Main skill: decision framework (stack selection, monolith vs microservices, REST vs GraphQL), security/data integrity/performance standards, project structure, env config, error handling, testing requirements |
| `references/auth-sso-mfa.md` | 766 | **Two-environment auth architecture:** Enterprise (Azure AD/Entra ID, SAML 2.0, SCIM provisioning, IdP-managed MFA, group-to-role mapping) vs Consumer (local auth, Argon2id, OAuth social login, app-managed TOTP/2FA, recovery codes). Hybrid B2B SaaS pattern. RBAC for both. |
| `references/payments-stripe.md` | 447 | Stripe: checkout sessions, subscriptions (create/upgrade/cancel), customer portal, webhook handling (all event types), idempotency, subscription access control middleware, PCI compliance |
| `references/realtime-websockets.md` | 342 | WebSockets (ws library, authenticated connections, Redis pub/sub scaling), SSE (Fastify + FastAPI), BullMQ/Celery background jobs, scheduled tasks, multi-server architecture |
| `references/email-notifications.md` | 352 | Resend/SendGrid/AWS SES integration, HTML email templates (glassmorphic-themed), template system architecture, push notifications, notification preferences, deliverability checklist |
| `references/api-design.md` | 435 | REST conventions, URL naming, status codes, response formats, cursor pagination, Zod validation, API versioning + deprecation, OpenAPI/Swagger, rate limiting, CORS, health checks, file uploads, request logging |
| `references/nodejs-frameworks.md` | 315 | Fastify (recommended), NestJS, Hono: setup, route modules, service layer, middleware patterns, error handling, testing |
| `references/python-frameworks.md` | 337 | FastAPI (recommended), Django: setup, routers, Pydantic schemas, async SQLAlchemy, dependency injection, testing |

**Total: ~3,350 lines of enterprise backend patterns and implementation code.**

---

## Auth Environment Distinction (Key Feature)

This skill explicitly separates two auth architectures:

### Environment A — Enterprise / Corporate
- Azure AD / Entra ID with MSAL library
- SAML 2.0 for Okta, OneLogin, PingFederate, ADFS
- SCIM 2.0 auto-provisioning from IdP directory
- MFA enforced at the IdP via Conditional Access — **your app never implements MFA**
- Group-to-role mapping (Azure AD groups → app roles)
- No local password storage

### Environment B — Consumer / Public
- Local email + password auth with Argon2id hashing
- OAuth 2.0 social login (Google, GitHub, Apple, etc.) via arctic library
- Application-managed TOTP/2FA with QR code setup
- Recovery codes (hashed, single-use)
- Account lockout, progressive rate limiting
- Password reset flow with email verification

### Hybrid (B2B SaaS)
- Domain-based auth routing: `@enterprise.com` → SSO redirect, others → local login
- Per-tenant SSO configuration (admin self-service)

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-backend/references
cp SKILL.md ~/.claude/skills/enterprise-backend/
cp references/* ~/.claude/skills/enterprise-backend/references/
ls -R ~/.claude/skills/enterprise-backend/
```

### Option B: From .skill Package

```bash
mkdir -p ~/.claude/skills
tar -xzf enterprise-backend.skill -C ~/.claude/skills/
ls -R ~/.claude/skills/enterprise-backend/
```

### Option C: Project-Level

```bash
mkdir -p .claude/skills/enterprise-backend/references
cp SKILL.md .claude/skills/enterprise-backend/
cp references/* .claude/skills/enterprise-backend/references/
```

---

## Trigger Keywords

> API, endpoint, route, REST, GraphQL, auth, authentication, SSO, SAML, OAuth, MFA, 2FA, payment, Stripe, webhook, middleware, rate limiting, backend, Node.js, Express, Fastify, NestJS, Python, FastAPI, Django, email, notification, WebSocket, real-time, background job, queue

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-database` | Database design, ORMs, migrations, cloud DB deployment |
| `enterprise-frontend` | UI/UX, glassmorphic design system, dashboard patterns |
| `enterprise-deployment` (coming) | VPS setup, Docker, CI/CD, nginx, SSL, monitoring |
