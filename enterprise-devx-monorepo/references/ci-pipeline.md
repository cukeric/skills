# CI Pipeline Standard

GitHub Actions job matrix, caching, secrets, job dependencies, and canary-scan
false-positive prevention.

## 6 Required Jobs

Every project's `ci.yml` must include these jobs with these names:

| Job | Tool | Must Pass Before |
|-----|------|-----------------|
| `lint` | Biome | typecheck, test, build |
| `typecheck` | tsc --noEmit / turbo typecheck | test, build |
| `test` | vitest / turbo test | build |
| `build` | turbo build | — |
| `audit` | pnpm audit --audit-level=high | — |
| `ci-gate` | needs: [lint, typecheck, test, build, audit] | deployment |

**Caching:** Always cache `~/.pnpm-store` and `.turbo` between jobs.

**Lockfile:** Always use `pnpm install --frozen-lockfile`. Never `pnpm install` in CI
without `--frozen-lockfile`.

**pnpm version in CI:** Use pnpm **10.4.1+** in all CI jobs that run `pnpm audit`. The
npm v1 security advisories endpoint was retired April 2026 and returns `410 Gone` —
pnpm 9.x and earlier hit that endpoint and fail hard. pnpm 10+ uses the
`bulk-advisory` endpoint. Always bump `PNPM_VERSION` in `ci.yml` AND `security.yml` AND
`engines.pnpm` AND `packageManager` in root `package.json` together — partial bumps
leave the matrix broken. Add `--prod` to `pnpm audit` in scheduled security scans to
skip dev-only noise.

## Service containers for integration tests

When the test job needs a real service (PostgreSQL, Redis), add a `services:` block.
The integration suite gates on an env var (`describe.skipIf(!process.env.DB_URL)`):

```yaml
test:
  services:
    postgres:
      image: postgres:16-alpine            # match the tag the app/runbook uses
      env: { POSTGRES_DB: app_ci, POSTGRES_USER: app, POSTGRES_PASSWORD: ci_not_a_secret }
      ports: ["5432:5432"]
      options: >-
        --health-cmd "pg_isready -U app -d app_ci"
        --health-interval 10s --health-timeout 5s --health-retries 5
  steps:
    - run: pnpm turbo run test
      env: { DB_URL: postgresql://app:ci_not_a_secret@localhost:5432/app_ci }
```

Pitfalls (see `ci-local-parity.md` for the full failure analysis):
- A setup script that runs `node ./dist/x.js` fails if the package is not built yet —
  there is no `^build` outside turbo. Build first, or let the test self-set-up.
- Service-gated tests **skip silently** on a dev machine without Docker — CI is the
  first place they run. Verify them against a real service before pushing.
- Match the service image tag exactly (`postgres:16-alpine` ≠ `postgres:16`).

## Canary Scan — False Positive Prevention

If the project uses canary token detection (regex patterns in source), the CI scan
must exclude the detector file itself:

```yaml
- name: Canary token scan
  run: |
    grep -r "canary-SOUL\|canary-IDENTITY" . \
      --include="*.ts" \
      --exclude-dir=".git" \
      --exclude-dir="node_modules" \
      --exclude="schemas.ts" \   # ← the detector file
    && echo "LEAK DETECTED" && exit 1 || echo "Clean"
```

## Common CI failure patterns

| Failure | Root Cause | Prevention |
|---------|-----------|------------|
| `--frozen-lockfile` fails | `pnpm install` never run locally | Pre-push gate step 1 |
| Biome CI diff | Manual formatting bypassed | Pre-push gate step 2 (`--unsafe`) |
| `tsc --noEmit` on Rust stub | tsconfig.json missing | Pre-push gate step 5 |
| vitest exits 1 on empty suite | Missing `--passWithNoTests` | Package script standard |
| Canary scan false positive | Detector file included in grep | Exclude detector file |
| Multiple fix commits | Piecemeal debugging | `gh run view --log-failed` once, fix all |
| HTTPS push blocked on workflow files | OAuth token missing `workflow` scope | Set SSH remote on repo init |
| code-reviewer not dispatched pre-push | Skipped step 6 of pre-push gate | Dispatch is mandatory |
| Dead release job | `outputs.published` not mapped from step | Wire `id:` + `outputs:` on changesets jobs |
| test job runs on broken code | Missing `needs:` gate | test must depend on lint + typecheck |
| Passes locally, fails CI | Local state CI lacks (`dist/`, key files) | `ci-local-parity.md` clean-checkout sim |
