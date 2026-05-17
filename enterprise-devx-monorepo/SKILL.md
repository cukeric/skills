---
name: enterprise-devx-monorepo
description: "Governs all monorepo setup, CI/CD pipeline construction, Turborepo configuration, pnpm workspaces, Biome linting, Git workflows, PR templates, branch protection, and Changesets version management. Trigger on ANY mention of: monorepo, turborepo, pnpm workspace, CI, CD, GitHub Actions, workflow, pipeline, .github, Changesets, Biome, ESLint, Prettier, lint, typecheck, vitest, test runner, package scaffold, git workflow, PR template, branch protection, pre-push, lockfile, husky, commitlint, or any request to set up a multi-package repo, wire a new project to GitHub, or create/fix CI jobs."
---

# Enterprise DevX — Monorepo & CI/CD Skill

All monorepo setups and CI pipelines must follow this skill. No exceptions.

## Reference Files

- `references/monorepo-scaffold.md` — pnpm workspaces + Turborepo: directory structure, package script standards, tsconfig inheritance, turbo.json task graph
- `references/ci-pipeline.md` — GitHub Actions: the 6 required jobs, caching, `--frozen-lockfile`, service containers for integration tests, canary-scan false positives, common CI failure table
- `references/pre-push-gate.md` — **MANDATORY** local validation before any git push — the 6-step sequence, the `--unsafe` Biome rule, SSH-remote requirement
- `references/changesets.md` — Version management, `pnpm changeset version` behavior + post-run Biome/lockfile fixups, release workflow
- `references/biome.md` — Biome config, format/lint rules, CI integration
- `references/ci-local-parity.md` — **"Passes locally, fails CI"** — the clean-checkout simulation before pushing build/CI/infra changes, the non-emitting `build`-script trap, migration scripts that need a build, service tests that skip locally, tests depending on ambient machine state
- `references/hybrid-ts-rust-monorepo.md` — Hybrid TypeScript + Rust monorepos: dual workspace config, Rust package.json stubs, Turbo integration, split CI jobs, Cargo workspace deps, Changesets/Cargo version sync, Rust gotchas (Cargo.lock, wasmtime timeouts, wasm-pack, protoc)
- `references/submodule-release-gotchas.md` — Release failure modes the hard way: macOS `sed -i.bak` truncation, `gh` needs `--repo` in a submodule / multi-remote repo, safe bulk version-bump, single-source-of-truth for multi-doc projects, `CLAUDE.md` drift check

Read this SKILL.md first, then the relevant reference files.

---

## The Pre-Push Gate — MANDATORY Before Every First Push

**The single most important rule in this skill. Not optional. Not skippable.**

Before the FIRST `git push` on a new monorepo, or after ANY change to
`.github/workflows/`, run this sequence locally — push only when every step is clean:

```bash
pnpm install                                  # 1. lockfile (CI uses --frozen-lockfile)
pnpm exec biome check --write --unsafe . && git add -A   # 2. lint+format (--unsafe!), re-stage
pnpm turbo run typecheck                       # 3. type errors
pnpm turbo run test                            # 4. tests (--passWithNoTests on stubs)
# 5. audit stub-package scripts (tsconfig.json present; Rust stubs use echo)
# 6. dispatch code-reviewer to audit .github/workflows/*.yml — fix all HIGH+ before push
```

One clean push beats five fix commits. Full rationale, the `--unsafe` trap, and the
SSH-remote requirement: **`references/pre-push-gate.md`**.

For build / CI / infra / Dockerfile / service-test changes, **also** run the
clean-checkout simulation in **`references/ci-local-parity.md`** — the pre-push gate
verifies code, not environment parity.

---

## CI Pipeline Standard — 6 Required Jobs

Every `ci.yml` must include these jobs with these names:

| Job | Tool | Must Pass Before |
|-----|------|-----------------|
| `lint` | Biome | typecheck, test, build |
| `typecheck` | tsc --noEmit / turbo typecheck | test, build |
| `test` | vitest / turbo test | build |
| `build` | turbo build | — |
| `audit` | pnpm audit --audit-level=high | — |
| `ci-gate` | needs: [lint, typecheck, test, build, audit] | deployment |

Always cache `~/.pnpm-store` + `.turbo`; always `pnpm install --frozen-lockfile`; pnpm
**10.4.1+** in audit jobs. Service containers, caching detail, and the CI failure table:
**`references/ci-pipeline.md`**.

---

## Monorepo Structure & Package Scripts

Standard layout (`apps/`, `packages/`, `.github/workflows/`, `turbo.json`, `biome.json`,
`pnpm-workspace.yaml`, `tsconfig.base.json`), the required package scripts, and tsconfig
inheritance: **`references/monorepo-scaffold.md`**.

Key rule: every package's `build` must actually emit `dist/` — a no-op `build` script
breaks turbo `^build` and any dependent that imports its `dist/` (see `ci-local-parity.md`).

---

## Biome Configuration

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "organizeImports": { "enabled": true },
  "linter": { "enabled": true, "rules": { "recommended": true } },
  "formatter": { "enabled": true, "indentStyle": "space", "indentWidth": 2 },
  "javascript": { "formatter": { "quoteStyle": "double" } }
}
```

`pnpm exec biome check --write .` to fix locally; `pnpm exec biome ci .` in CI
(read-only, fails on diff — stricter than `check`). Detail: `references/biome.md`.

---

## Changesets Version Management

`MAJOR` = breaking/constitutional · `MINOR` = new capability · `PATCH` = bugfix. Every
user-facing change needs a changeset (`pnpm changeset`). `release.yml` automates the
"Version Packages" PR. After `pnpm changeset version`, re-run Biome (its JSON writer can
break formatting) and `pnpm install`. Full flow + private-root gotchas:
**`references/changesets.md`** and `references/submodule-release-gotchas.md`.

---

## Agent Dispatch — When to Use Agents

For large monorepo scaffolds (>4 independent packages), dispatch in parallel:

- `full-stack-architect` — architecture, package dependency graph, API contracts
- `code-reviewer` — review CI config before push (job dependency errors, missing caches)
- `feature-dev:code-architect` — individual package implementations

Never serialize work that can run in parallel. Scope each agent's brief to fit a token
window — an agent cut off mid-task loses its work-in-progress report.
