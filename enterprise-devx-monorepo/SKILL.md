---
name: enterprise-devx-monorepo
description: "Governs all monorepo setup, CI/CD pipeline construction, Turborepo configuration, pnpm workspaces, Biome linting, Git workflows, PR templates, branch protection, and Changesets version management. Trigger on ANY mention of: monorepo, turborepo, pnpm workspace, CI, CD, GitHub Actions, workflow, pipeline, .github, Changesets, Biome, ESLint, Prettier, lint, typecheck, vitest, test runner, package scaffold, git workflow, PR template, branch protection, pre-push, lockfile, husky, commitlint, or any request to set up a multi-package repo, wire a new project to GitHub, or create/fix CI jobs."
---

# Enterprise DevX — Monorepo & CI/CD Skill

All monorepo setups and CI pipelines must follow this skill. No exceptions.

## Reference Files

- `references/monorepo-scaffold.md` — pnpm workspaces + Turborepo setup, package structure, tsconfig inheritance
- `references/ci-pipeline.md` — GitHub Actions job matrix, caching, secrets, job dependencies
- `references/pre-push-gate.md` — **MANDATORY** local validation before any git push
- `references/changesets.md` — Version management, CHANGELOG generation, release workflow
- `references/biome.md` — Biome config, format/lint rules, CI integration
- `references/hybrid-ts-rust-monorepo.md` — Hybrid TypeScript + Rust monorepos: dual workspace config, Rust package.json stubs, Turbo integration, split CI jobs, Cargo workspace dependencies, Changesets/Cargo version sync, and Rust-specific gotchas (Cargo.lock, wasmtime timeouts, wasm-pack, protoc)

Read this SKILL.md first, then the relevant reference files.

---

## The Pre-Push Gate — MANDATORY Before Every First Push

**This is the single most important rule in this skill. It is not optional. It is not skippable.**

Before the FIRST `git push` on any new monorepo, or after ANY change to `.github/workflows/`, run this exact sequence locally. Do not push until all steps pass with zero errors.

```bash
# 1. Generate lockfile (CI uses --frozen-lockfile; missing lockfile = total failure)
pnpm install

# 2. Fix all formatting (Biome CI job fails on any diff)
pnpm exec biome format --write .

# 3. Catch all type errors before CI
pnpm turbo run typecheck

# 4. Confirm tests pass (catches missing --passWithNoTests on stub packages)
pnpm turbo run test

# 5. Audit stub packages for script correctness
# Any package with "typecheck": "tsc --noEmit" MUST have a tsconfig.json
# Rust/native stubs must use "echo 'N/A — [lang] build in M[n]'" instead

# 6. Dispatch code-reviewer agent to audit CI config BEFORE pushing
# Dispatch: code-reviewer with prompt:
#   "Review all .github/workflows/*.yml for: job dependency graph, caching,
#    --frozen-lockfile usage, secret references, branch triggers, turbo.json
#    pipeline completeness, and package script correctness. Report issues with
#    severity CRITICAL/HIGH/MEDIUM/LOW."
# Fix ALL issues reported at HIGH or above before pushing.
```

**All 6 must complete before pushing.** One clean push beats five fix commits.

### SSH Remote — Always Use for Repos with Workflow Files

GitHub HTTPS OAuth tokens require the `workflow` scope to push `.github/workflows/`. Unless that scope is confirmed, always use SSH:

```bash
git remote set-url origin git@github.com:owner/repo.git
```

Set this when initializing the repo. Do not wait until a push is rejected.

---

## Monorepo Structure

```
repo/
├── apps/                    # Deployable applications
│   └── [app]/
├── packages/                # Shared packages
│   ├── core/                # Foundation types, schemas, utilities
│   └── [domain]/            # Feature packages
├── .github/
│   └── workflows/
│       ├── ci.yml           # Primary CI (lint, typecheck, test, build, security)
│       ├── release.yml      # Changesets release automation
│       ├── security.yml     # Nightly SAST + secret scan
│       └── drift-check.yml  # Integrity checks (if applicable)
├── turbo.json               # Turborepo task graph
├── biome.json               # Biome lint + format config
├── pnpm-workspace.yaml      # Workspace package globs
├── package.json             # Root scripts + devDependencies
└── tsconfig.base.json       # Shared TS config (extended by packages)
```

---

## CI Pipeline Standard — 6 Required Jobs

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

**Lockfile:** Always use `pnpm install --frozen-lockfile`. Never `pnpm install` in CI without `--frozen-lockfile`.

---

## Package Script Standards

Every package's `package.json` must have these scripts and they must exit 0 on a clean repo:

```json
{
  "scripts": {
    "build": "tsc --project tsconfig.json",
    "typecheck": "tsc --noEmit",
    "test": "vitest run --passWithNoTests",
    "clean": "rm -rf dist coverage"
  }
}
```

**Critical rules:**
- `vitest run` (not `vitest run --passWithNoTests`) will exit 1 if there are no test files — always use `--passWithNoTests` for new/stub packages
- `tsc --noEmit` requires a `tsconfig.json` in the package root — if the package is a non-TS stub (Rust, Python), use `echo 'N/A — [lang] in M[n]'` instead
- Never use `npm run` in CI — always `pnpm run`

---

## Biome Configuration

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": { "recommended": true }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  },
  "javascript": {
    "formatter": { "quoteStyle": "double" }
  }
}
```

Run `pnpm exec biome check --write .` to fix all issues. Run `pnpm exec biome check .` in CI (read-only, fails on diff).

---

## Changesets Version Management

- `MAJOR` — constitutional/breaking changes
- `MINOR` — new capabilities
- `PATCH` — bug fixes

CI `release.yml` uses `changesets/action` — creates "Version Packages" PR automatically, publishes on merge to main.

Every PR that changes user-facing behavior needs a changeset: `pnpm changeset`

---

## Canary Scan — False Positive Prevention

If the project uses canary token detection (regex patterns in source):

```yaml
# In CI canary scan step — exclude the detector file itself
- name: Canary token scan
  run: |
    grep -r "canary-SOUL\|canary-IDENTITY" . \
      --include="*.ts" \
      --exclude-dir=".git" \
      --exclude-dir="node_modules" \
      --exclude="schemas.ts" \   # ← the detector file
    && echo "LEAK DETECTED" && exit 1 || echo "Clean"
```

---

## Agent Dispatch — When to Use Agents

For large monorepo scaffolds (>4 independent packages), dispatch in parallel:

- `full-stack-architect` — architecture decisions, package dependency graph, API contracts
- `code-reviewer` — review CI config before push (catches job dependency errors, missing caches)
- `feature-dev:code-architect` — individual package implementations

Never serialize work that can run in parallel.

---

## Common Failure Patterns (from skill-performance.tsv)

| Failure | Root Cause | Prevention |
|---------|-----------|------------|
| `--frozen-lockfile` fails | `pnpm install` never run locally | Pre-push gate step 1 |
| Biome CI diff | Manual formatting bypassed | Pre-push gate step 2 |
| `tsc --noEmit` on Rust stub | tsconfig.json missing | Pre-push gate step 5 |
| vitest exits 1 on empty suite | Missing `--passWithNoTests` | Package script standard |
| Canary scan false positive | Detector file included in grep | Exclude detector file |
| Multiple fix commits | Piecemeal debugging | `gh run view --log-failed` once, fix all |
| HTTPS push blocked on workflow files | OAuth token missing `workflow` scope | Set SSH remote on repo init |
| code-reviewer not dispatched pre-push | Skipped step 6 of pre-push gate | Dispatch is mandatory, not optional |
| Dead release job | `outputs.published` not mapped from step | Always wire `id:` + `outputs:` on changesets jobs |
| test job runs on broken code | Missing `needs:` gate | test must always depend on lint + typecheck |
