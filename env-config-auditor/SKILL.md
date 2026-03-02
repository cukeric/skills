---
name: env-config-auditor
description: Audits environment variable configuration across codebase, local .env, and production VPS. Trigger when adding new env vars, before deployment, when debugging "undefined" env errors, when switching providers (e.g., Brevo to Resend), or when the user says "check env vars", "audit environment", "missing env", "env config", "are all variables set", or any request to verify environment variable completeness and consistency.
---

# Environment Config Auditor

Scans the entire codebase for `process.env.*` references, cross-checks against `.env.local` and VPS environment, and flags missing, unused, or mismatched variables. Prevents deployment failures caused by missing or stale env vars.

## When to Use

- Before every deployment (part of pre-deploy checklist)
- After adding a new `process.env.SOMETHING` reference in code
- After switching providers (e.g., Brevo → Resend, Stripe test → live)
- When debugging "undefined" or empty env var errors
- After rsync (which may overwrite or skip `.env.local`)

## Audit Process

### Step 1: Extract All Env Var References from Code

```bash
# Find all process.env references in the codebase
grep -rh "process\.env\.\w\+" src/ --include="*.ts" --include="*.tsx" -o | sort -u
```

This produces the **Required Set** — every env var the code expects.

### Step 2: Extract All Defined Env Vars

```bash
# Local .env.local
grep -E "^[A-Z_]+=" .env.local | cut -d= -f1 | sort

# VPS .env.local (via SSH)
ssh -i {key} {user}@{host} "grep -E '^[A-Z_]+=' /path/to/.env.local | cut -d= -f1 | sort"
```

This produces the **Defined Set** — what's actually configured.

### Step 3: Diff Analysis

| Finding | Severity | Action |
|---|---|---|
| In code but NOT in `.env.local` | **CRITICAL** | Will cause runtime errors. Must add before deploy. |
| In code but NOT on VPS | **CRITICAL** | Production will fail. Must SSH and add. |
| In `.env.local` but NOT in code | **LOW** | Stale variable. Safe to remove (after confirming). |
| `NEXT_PUBLIC_*` prefix missing | **HIGH** | Client-side code can't access server-only vars. |
| Different values local vs VPS | **INFO** | Expected for URLs, API keys. Flag for review. |

### Step 4: Value Validation

For known env var patterns, validate format:

| Variable Pattern | Expected Format | Validation |
|---|---|---|
| `*_API_KEY` | Non-empty string | Length > 10, no placeholder text |
| `*_SECRET` | Non-empty string | Length > 20, not "changeme" or "xxx" |
| `DATABASE_URL` | `postgresql://...` | Starts with `postgresql://` |
| `NEXTAUTH_URL` | `https://...` | Starts with `https://` in production |
| `NEXT_PUBLIC_*` | Any | Must be set at build time (COPY in Dockerfile) |
| `*_DSN` | URL format | Valid URL |

### Step 5: Docker Build-Time vs Runtime

For Next.js with standalone output:

- **Build-time vars** (baked into image via `COPY .env.local`): `NEXT_PUBLIC_*`, `SENTRY_AUTH_TOKEN`
- **Runtime vars** (read at startup): `DATABASE_URL`, `NEXTAUTH_SECRET`, API keys

> **Critical rule:** Changing a build-time var requires `docker compose build --no-cache`, not just restart.

Flag any build-time vars that changed since last deploy.

## Output Format

```
## Environment Config Audit — {date}

### Code References vs Local Config
| Variable                      | In Code | In .env.local | In VPS | Status   |
|-------------------------------|---------|---------------|--------|----------|
| DATABASE_URL                  | Yes     | Yes           | Yes    | OK       |
| RESEND_API_KEY                | Yes     | Yes           | Yes    | OK       |
| NEXT_PUBLIC_SENTRY_DSN        | Yes     | Yes           | Yes    | OK       |
| NEW_FEATURE_FLAG              | Yes     | No            | No     | MISSING  |

### Stale Variables (defined but not referenced)
| Variable          | Location    | Recommendation           |
|-------------------|-------------|--------------------------|
| BREVO_API_KEY     | VPS         | Remove (switched to Resend) |

### Build-Time Variable Changes
| Variable                 | Last Build Value | Current Value | Rebuild Needed? |
|--------------------------|------------------|---------------|-----------------|
| NEXT_PUBLIC_SENTRY_DSN   | (same)           | (same)        | No              |

Result: {N} issues found. {critical_count} critical, {high_count} high.
```

## Integration

This skill is part of the pre-deploy verification:

```
code changes → env-config-auditor → pre-deploy-security-scanner → deploy → deployment-validator
```
