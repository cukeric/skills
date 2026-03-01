# Enterprise DevX & Monorepo Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | ~290 | Decision frameworks (monorepo vs polyrepo, tool selection, Git workflow), monorepo structure, code quality gates, verification checklist |
| `references/turborepo-nx.md` | ~150 | Turborepo setup + turbo.json, Nx setup + nx.json, commands, remote caching, comparison table |
| `references/shared-packages.md` | ~140 | Internal package setup, consuming packages, workspace config, shared tsconfig, version management rules |
| `references/linting-formatting.md` | ~150 | ESLint flat config, Biome, Prettier, Husky + lint-staged, commitlint, pre-commit hooks |
| `references/git-workflows.md` | ~150 | Trunk-based development, GitFlow, conventional commits, semantic versioning, branch protection rules |
| `references/pr-templates-changelog.md` | ~200 | PR template, issue templates (bug/feature), Changesets setup + workflow, GitHub Actions release |
| `references/developer-onboarding.md` | ~200 | Setup script, CONTRIBUTING.md template, ADR template, VS Code workspace settings |

**Total: ~1,280+ lines of enterprise DevX patterns.**

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-devx-monorepo/references
cp SKILL.md ~/.claude/skills/enterprise-devx-monorepo/
cp references/* ~/.claude/skills/enterprise-devx-monorepo/references/
```

### Option B: Project-Level

```bash
mkdir -p .claude/skills/enterprise-devx-monorepo/references
cp SKILL.md .claude/skills/enterprise-devx-monorepo/
cp references/* .claude/skills/enterprise-devx-monorepo/references/
```

---

## Trigger Keywords

> monorepo, Turborepo, Nx, pnpm workspaces, ESLint, Biome, Prettier, lint-staged, husky, Git workflow, trunk-based, GitFlow, conventional commits, changelog, changesets, PR template, developer onboarding, ADR

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-frontend` | Frontend apps in `apps/web`, shared UI in `packages/ui` |
| `enterprise-backend` | API apps in `apps/api`, shared types and utils |
| `enterprise-mobile` | Mobile app in `apps/mobile`, shared business logic |
| `enterprise-deployment` | CI/CD uses Turborepo's affected detection |
| `enterprise-testing` | Shared test config in `packages/config-jest` |
