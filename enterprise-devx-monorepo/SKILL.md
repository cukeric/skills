---
name: enterprise-devx-monorepo
description: Explains how to set up and manage monorepo tooling, developer experience, code quality automation, and Git workflows with enterprise standards. Trigger on ANY mention of monorepo, Turborepo, Nx, pnpm workspaces, npm workspaces, yarn workspaces, shared packages, internal packages, ESLint, Biome, Prettier, lint-staged, husky, pre-commit hook, Git workflow, trunk-based development, GitFlow, conventional commits, semantic versioning, changelog, changesets, PR template, issue template, developer onboarding, contribution guide, ADR, architecture decision record, code review, linting, formatting, CI pipeline, build system, remote caching, or any request requiring monorepo setup, code quality tooling, or developer workflow automation.
---

# Enterprise DevX & Monorepo Skill

Developer experience (DevX) is a force multiplier. Fast feedback loops, consistent tooling, and automated quality gates let teams move quickly without sacrificing code quality. This skill covers monorepo architecture, code quality automation, Git workflows, and developer onboarding — the infrastructure that makes everything else faster.

## Reference Files

### Monorepo Tooling

- `references/turborepo-nx.md` — Turborepo setup, Nx generators, remote caching, task orchestration, affected commands, migration guide

### Shared Packages

- `references/shared-packages.md` — Internal packages, tsconfig paths, version management, publishable vs buildable libraries, dependency management

### Linting & Formatting

- `references/linting-formatting.md` — ESLint flat config, Biome, Prettier, lint-staged, husky, monorepo-wide config, custom rules

### Git Workflows

- `references/git-workflows.md` — Trunk-based development, GitFlow, release branches, conventional commits, semantic versioning

### PR Templates & Changelog

- `references/pr-templates-changelog.md` — PR templates, issue templates, changelog automation (changesets), release notes

### Developer Onboarding

- `references/developer-onboarding.md` — Setup scripts, dev environment bootstrap, contribution guide, ADRs

---

## Decision Framework

### Monorepo vs Polyrepo

| Signal | Monorepo | Polyrepo |
|---|---|---|
| Shared code between apps | ✅ | ❌ |
| Teams work on multiple packages | ✅ | ❌ |
| Independent deploy schedules needed | ❌ | ✅ |
| Different tech stacks per service | ❌ | ✅ |
| Strong code ownership boundaries | ❌ | ✅ |
| Atomic cross-package changes | ✅ | ❌ |
| < 5 developers | Either works | Either works |
| > 20 developers with ownership | Consider split | ✅ |

**Default: Monorepo** for most product teams. Only go polyrepo when services are truly independent.

### Monorepo Tool Selection

| Requirement | Best Choice | Why |
|---|---|---|
| Simple, fast, TypeScript focus | **Turborepo** | Minimal config, remote caching, fast |
| Code generation, migrations | **Nx** | Generators, affected commands, powerful plugins |
| Minimal tooling, just workspaces | **pnpm workspaces** | Package manager-native, zero extra deps |
| Full-featured, large org | **Nx** | Computation caching, distributed execution |

**Default: Turborepo** for most teams. Switch to Nx when you need code generation or complex task orchestration.

### Git Workflow Selection

| Signal | Trunk-Based | GitFlow |
|---|---|---|
| CI/CD with feature flags | ✅ | ❌ |
| Release-based deployment | ❌ | ✅ |
| Small team, fast iteration | ✅ | ❌ |
| Multiple versions in production | ❌ | ✅ |
| Mobile app (app store releases) | ❌ | ✅ |
| SaaS with continuous deploy | ✅ | ❌ |

**Default: Trunk-based development** for web/SaaS. GitFlow for mobile apps or versioned software.

---

## Monorepo Structure

```
my-project/
├── apps/
│   ├── web/                    # Next.js frontend
│   │   ├── package.json
│   │   └── ...
│   ├── api/                    # Backend API
│   │   ├── package.json
│   │   └── ...
│   └── mobile/                 # React Native app
│       ├── package.json
│       └── ...
├── packages/
│   ├── ui/                     # Shared UI components
│   │   ├── src/
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── utils/                  # Shared utilities
│   │   ├── src/
│   │   └── package.json
│   ├── config-eslint/          # Shared ESLint config
│   │   └── package.json
│   ├── config-typescript/      # Shared tsconfig
│   │   ├── base.json
│   │   ├── nextjs.json
│   │   └── react-native.json
│   └── database/               # Prisma schema + client
│       ├── prisma/
│       └── package.json
├── turbo.json                  # Turborepo pipeline
├── pnpm-workspace.yaml         # Workspace definition
├── package.json                # Root package.json
├── .eslintrc.js                # Root ESLint config
├── .prettierrc                 # Shared Prettier config
├── .husky/                     # Git hooks
├── .changeset/                 # Changesets config
└── docs/
    ├── CONTRIBUTING.md
    ├── ADR/                    # Architecture Decision Records
    └── SETUP.md                # Onboarding guide
```

### Root package.json

```json
{
  "name": "my-project",
  "private": true,
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "lint": "turbo lint",
    "test": "turbo test",
    "format": "prettier --write .",
    "check-format": "prettier --check .",
    "prepare": "husky",
    "changeset": "changeset",
    "version-packages": "changeset version",
    "release": "turbo build --filter='./packages/*' && changeset publish"
  },
  "devDependencies": {
    "@changesets/cli": "^2.27.0",
    "husky": "^9.0.0",
    "lint-staged": "^15.0.0",
    "prettier": "^3.2.0",
    "turbo": "^2.0.0"
  },
  "lint-staged": {
    "*.{ts,tsx,js,jsx}": ["eslint --fix", "prettier --write"],
    "*.{json,md,yaml,yml}": ["prettier --write"]
  }
}
```

---

## Code Quality Gates

### Pre-Commit (Instant Feedback)

```bash
# .husky/pre-commit
pnpm lint-staged
```

### Pre-Push (Comprehensive Check)

```bash
# .husky/pre-push
pnpm turbo lint test --filter='...[HEAD~1]'
```

### CI Pipeline (Full Verification)

```yaml
jobs:
  quality:
    steps:
      - run: pnpm install --frozen-lockfile
      - run: pnpm turbo lint
      - run: pnpm turbo test
      - run: pnpm turbo build
      - run: pnpm check-format
```

---

## Testing Requirements

- [ ] All shared packages have unit tests
- [ ] Lint and format checks pass in CI
- [ ] Build succeeds for all apps and packages
- [ ] Changesets required for package modifications
- [ ] PR template completed for all merge requests
- [ ] ADRs created for significant architecture decisions

---

## Integration with Other Enterprise Skills

- **enterprise-frontend**: Frontend apps live in `apps/web`, consume shared packages from `packages/ui`.
- **enterprise-backend**: API apps live in `apps/api`, share types and utilities via packages.
- **enterprise-mobile**: Mobile app in `apps/mobile`, shares business logic packages.
- **enterprise-deployment**: CI/CD pipelines use Turborepo's affected detection for efficient builds.
- **enterprise-testing**: Test configuration shared via `packages/config-jest` or similar.

---

## Verification Checklist

- [ ] Monorepo tool selected with documented rationale
- [ ] Workspace configuration correct (pnpm-workspace.yaml / nx.json)
- [ ] Shared packages properly configured (exports, tsconfig paths)
- [ ] Turborepo/Nx pipeline caches tasks correctly
- [ ] ESLint + Prettier configured monorepo-wide
- [ ] Git hooks installed (husky + lint-staged)
- [ ] Conventional commits enforced or documented
- [ ] PR template in use for all merge requests
- [ ] Changeset automation configured
- [ ] Developer onboarding script works on fresh machine
- [ ] CI pipeline runs lint, test, build for affected packages
- [ ] CONTRIBUTING.md up to date
