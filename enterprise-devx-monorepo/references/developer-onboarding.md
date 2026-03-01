# Developer Onboarding Reference

## Setup Script

```bash
#!/bin/bash
# scripts/setup.sh — Run once on fresh machine

set -e

echo "🚀 Setting up development environment..."

# Check prerequisites
command -v node >/dev/null 2>&1 || { echo "❌ Node.js required. Install from https://nodejs.org"; exit 1; }
command -v pnpm >/dev/null 2>&1 || { echo "📦 Installing pnpm..."; npm install -g pnpm; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker required. Install from https://docker.com"; exit 1; }

# Verify versions
echo "Node.js: $(node -v)"
echo "pnpm: $(pnpm -v)"
echo "Docker: $(docker -v)"

# Install dependencies
echo "📦 Installing dependencies..."
pnpm install

# Setup git hooks
echo "🪝 Setting up git hooks..."
pnpm prepare

# Copy environment files
echo "⚙️ Setting up environment..."
for app in apps/*/; do
  if [ -f "$app/.env.example" ]; then
    cp -n "$app/.env.example" "$app/.env.local" 2>/dev/null || true
    echo "  Created $(basename $app)/.env.local"
  fi
done

# Start infrastructure
echo "🐳 Starting Docker services..."
docker compose up -d postgres redis

# Wait for services
echo "⏳ Waiting for database..."
sleep 3

# Run database migrations
echo "🗃️ Running database migrations..."
pnpm --filter=database db:migrate

# Seed development data
echo "🌱 Seeding development data..."
pnpm --filter=database db:seed

echo ""
echo "✅ Setup complete! Run 'pnpm dev' to start development."
echo ""
echo "Available commands:"
echo "  pnpm dev          - Start all apps in development"
echo "  pnpm build        - Build all apps"
echo "  pnpm lint         - Lint all packages"
echo "  pnpm test         - Run all tests"
echo "  pnpm dev --filter=web  - Start only the web app"
```

---

## CONTRIBUTING.md Template

```markdown
# Contributing

## Getting Started

1. Clone the repository
2. Run `./scripts/setup.sh`
3. Run `pnpm dev` to start development

## Development Workflow

1. Create a branch: `git checkout -b feat/my-feature`
2. Make changes
3. Add a changeset: `pnpm changeset`
4. Commit using conventional commits: `feat(web): add user search`
5. Push and create a PR

## Project Structure

```

apps/       → Applications (web, api, mobile)
packages/   → Shared libraries (ui, utils, database)
docs/       → Documentation and ADRs

```

## Commands

| Command | Description |
|---|---|
| `pnpm dev` | Start all apps in dev mode |
| `pnpm build` | Build all apps and packages |
| `pnpm lint` | Lint all code |
| `pnpm test` | Run all tests |
| `pnpm changeset` | Create a changeset |
| `pnpm format` | Format all files |

## Code Style

- TypeScript strict mode
- ESLint + Prettier (auto-fixed on commit)
- Conventional commits (enforced)
- Test coverage: ≥80% on new code

## PR Guidelines

- Fill out the PR template completely
- Add tests for new features
- Include screenshots for UI changes
- Create a changeset for user-facing changes
- Request review from at least 1 team member
```

---

## Architecture Decision Records (ADRs)

```markdown
<!-- docs/ADR/001-use-turborepo.md -->
# ADR-001: Use Turborepo for Monorepo Management

## Status
Accepted

## Date
2024-06-15

## Context
We need a monorepo tool to manage shared packages across web, API, and mobile apps.
Options considered: Turborepo, Nx, pnpm workspaces alone.

## Decision
Use Turborepo with pnpm workspaces.

## Rationale
- Minimal configuration (single turbo.json)
- Free remote caching via Vercel
- Fast incremental builds
- Our use case doesn't require Nx's code generation

## Consequences
- Turborepo manages task orchestration and caching
- pnpm manages dependency resolution
- No code generation — we create packages manually
- May migrate to Nx if code generation becomes needed
```

### ADR Template

```markdown
# ADR-NNN: [Title]

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-NNN]

## Date
[YYYY-MM-DD]

## Context
[What is the issue? Why is a decision needed?]

## Decision
[What was decided]

## Rationale
[Why this option over alternatives]

## Consequences
[What follows from this decision — positive and negative]
```

---

## VS Code Workspace Settings

```json
// .vscode/settings.json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "explicit"
  },
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "files.exclude": {
    "**/node_modules": true,
    "**/.next": true,
    "**/dist": true
  }
}

// .vscode/extensions.json
{
  "recommendations": [
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "bradlc.vscode-tailwindcss",
    "prisma.prisma"
  ]
}
```

---

## Onboarding Checklist

- [ ] Setup script runs successfully on fresh machine
- [ ] CONTRIBUTING.md covers workflow, structure, and commands
- [ ] ADR template available for architecture decisions
- [ ] VS Code settings shared for consistent editor setup
- [ ] .env.example files documented for every app
- [ ] README includes quick start (< 5 steps to running)
