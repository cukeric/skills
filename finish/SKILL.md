---
name: finish
description: End-of-session protocol. Chains env audit, security scan, code review, deploy, validation, and self-improve in order. Skips steps intelligently based on what changed. Trigger on /finish, "finish", "finish up", "wrap up", "wrap it up", "end the session", "we're done", "done for today", "close out the session", "ship and wrap", or any request to properly close a coding session.
user_invocable: true
---

# End-of-Session Protocol

Run the full verification and deployment chain. Each step is conditional based on what changed during the session.

## Step 1: Determine Scope

Check `git diff --name-only` to categorize changes:

- **has_api_changes**: files matching `src/app/api/`, `middleware.ts`, `src/lib/auth.ts`, `src/lib/crypto.ts`, `src/lib/rate-limit.ts`
- **has_env_changes**: files containing new `process.env.` references (compare with `git diff` content)
- **has_schema_changes**: `prisma/schema.prisma` modified
- **has_i18n_changes**: files in `src/i18n/messages/` modified
- **has_code_changes**: any `.ts` or `.tsx` files modified
- **cosmetic_only**: only CSS, copy, or layout changes (no logic changes)

## Step 2: Environment Audit (if has_env_changes)

Invoke the `env-config-auditor` skill. Cross-check:
- All `process.env.*` references have corresponding entries in `.env.local`
- VPS `.env.local` has the same keys (remind user if new vars need manual VPS setup)

Skip if: no new env var references.

## Step 3: Security Scan (if has_api_changes)

Invoke the `pre-deploy-security-scanner` skill on changed files. Check for:
- OWASP Top 10 vulnerabilities
- Missing auth/rate-limit on new endpoints
- Hardcoded secrets
- Input validation gaps

Skip if: cosmetic_only changes.

## Step 4: Code Review (always, unless cosmetic_only)

Launch the `code-reviewer` agent on all changed files. This covers:
- Bugs, logic errors, type safety
- Security review
- i18n completeness (if has_i18n_changes)
- Performance and accessibility

Wait for the agent's verdict. If FAIL, stop and fix before proceeding.

## Step 5: Build Verification (always)

```bash
cd frontend && npm run build
```

Must pass cleanly. Redis connection errors during SSG are expected and not failures.

## Step 6: Deploy (if user approves)

Ask the user: "Build passes. Ready to deploy to VPS?"

If yes, invoke the `deploy` skill which handles rsync + Docker rebuild.

If has_schema_changes, remind: "Prisma schema changed — run `db-migrate` after deploy."

## Step 7: Post-Deploy Validation (if deployed)

Invoke the `deployment-validator` skill. Run smoke tests against production.

## Step 8: Self-Improve (always)

Invoke the `self-improve` skill. Evaluate what worked, what didn't, and update skills/agents if needed.

## Quick Reference

| Condition | Steps Run |
|---|---|
| Cosmetic only (CSS/copy) | Build → Deploy → Validate |
| Code changes (no API) | Review → Build → Deploy → Validate → Self-Improve |
| API/auth changes | Security Scan → Review → Build → Deploy → Validate → Self-Improve |
| New env vars | Env Audit → Security Scan → Review → Build → Deploy → Validate → Self-Improve |
| Schema changes | Full chain + db-migrate reminder |
