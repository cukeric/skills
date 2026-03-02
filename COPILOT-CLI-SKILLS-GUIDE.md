# Skills Implementation Guide — Claude Code (Copilot CLI)

> Complete guide to installing and using all enterprise skills from the `cukeric/skills` repo.

---

## Table of Contents

- [How Skills Work](#how-skills-work)
- [Prerequisites](#prerequisites)
- [Quick Install — All Skills at Once](#quick-install--all-skills-at-once)
- [Skill Inventory](#skill-inventory)
- [Installation Methods](#installation-methods)
- [Per-Skill Installation](#per-skill-installation)
- [Project-Level Installation](#project-level-installation)
- [Using .skill Packages](#using-skill-packages)
- [Verification](#verification)
- [Skill Usage & Trigger Keywords](#skill-usage--trigger-keywords)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

---

## How Skills Work

Claude Code loads skills from two locations:

| Scope | Path | Loaded When |
|---|---|---|
| **Global** | `~/.claude/skills/<skill-name>/` | Every session, every project |
| **Project** | `<project>/.claude/skills/<skill-name>/` | Only when working in that project |

Each skill folder must contain at minimum:

- `SKILL.md` — the main instruction file Claude reads
- `references/` — detailed reference docs Claude pulls in when relevant

Claude automatically reads `SKILL.md` when it detects relevant keywords in your prompts, then dives into the `references/` files as needed.

---

## Prerequisites

```bash
# 1. Clone the skills repo (if not already cloned)
git clone git@github.com:cukeric/skills.git ~/Desktop/GEMS/dev/SKILLS

# 2. Ensure the global skills directory exists
mkdir -p ~/.claude/skills
```

---

## Quick Install — All Skills at Once

Run this single script to install **every** enterprise skill globally:

```bash
#!/bin/bash
# install-all-skills.sh
# Run from the SKILLS repo root: bash install-all-skills.sh

REPO_DIR="$(pwd)"
DEST="$HOME/.claude/skills"

echo "📦 Installing all skills to $DEST ..."

# --- Enterprise Skills (14 total) ---
ENTERPRISE_SKILLS=(
  "enterprise-AI-applications"
  "enterprise-AI-foundations"
  "enterprise-AI-fundamentals"
  "enterprise-backend"
  "enterprise-data-analytics"
  "enterprise-database"
  "enterprise-deployment"
  "enterprise-devx-monorepo"
  "enterprise-frontend"
  "enterprise-i18n-accessibility"
  "enterprise-mobile"
  "enterprise-search-messaging"
  "enterprise-security"
  "enterprise-testing"
)

for skill in "${ENTERPRISE_SKILLS[@]}"; do
  echo "  → $skill"
  mkdir -p "$DEST/$skill/references"
  cp "$REPO_DIR/$skill/SKILL.md" "$DEST/$skill/"
  cp "$REPO_DIR/$skill/references/"* "$DEST/$skill/references/" 2>/dev/null
done

# --- Specialty Skills ---
echo "  → skill-self-improving"
mkdir -p "$DEST/skill-self-improving/references"
cp "$REPO_DIR/skill-self-improving/SKILL.md" "$DEST/skill-self-improving/"
cp "$REPO_DIR/skill-self-improving/references/"* "$DEST/skill-self-improving/references/" 2>/dev/null

echo "  → postmark (multi-skill)"
cp -R "$REPO_DIR/postmark" "$DEST/"

# --- Utility Skills ---
UTILITY_SKILLS=(
  "deployment-validator"
  "env-config-auditor"
  "pre-deploy-security-scanner"
  "session-orchestrator"
)

for skill in "${UTILITY_SKILLS[@]}"; do
  if [ -d "$REPO_DIR/$skill" ]; then
    echo "  → $skill"
    mkdir -p "$DEST/$skill"
    cp -R "$REPO_DIR/$skill/"* "$DEST/$skill/" 2>/dev/null
  fi
done

echo ""
echo "✅ All skills installed to $DEST"
echo "📋 Installed $(ls -d $DEST/*/ 2>/dev/null | wc -l | tr -d ' ') skill directories"
```

### Run it

```bash
cd ~/Desktop/GEMS/dev/SKILLS
bash install-all-skills.sh
```

---

## Skill Inventory

### Enterprise Skills (14)

| # | Skill | Refs | .skill pkg | Focus |
|---|---|---|---|---|
| 1 | `enterprise-AI-applications` | 8 | ✅ | RAG, agents, prompt engineering, AI UX patterns |
| 2 | `enterprise-AI-foundations` | 7 | ✅ | Provider abstraction, embeddings, vector DBs, cost governance |
| 3 | `enterprise-AI-fundamentals` | 7 | — | Core AI/ML concepts, model selection, evaluation |
| 4 | `enterprise-backend` | 7 | ✅ | API design, auth (SSO/local), payments, real-time, email |
| 5 | `enterprise-data-analytics` | 5 | — | ETL pipelines, data warehouse, dashboards, tracking |
| 6 | `enterprise-database` | 8 | ✅ | Schema design, ORMs, migrations, cloud DB, optimization |
| 7 | `enterprise-deployment` | 8 | ✅ | Docker, CI/CD, nginx, SSL, VPS, monitoring |
| 8 | `enterprise-devx-monorepo` | 6 | — | Turborepo, Nx, shared packages, workspace tooling |
| 9 | `enterprise-frontend` | 7 | ✅ | Glassmorphic design system, dashboards, component patterns |
| 10 | `enterprise-i18n-accessibility` | 5 | — | i18n, WCAG compliance, RTL support, screen readers |
| 11 | `enterprise-mobile` | 6 | — | React Native, Expo, push notifications, deep linking |
| 12 | `enterprise-search-messaging` | 5 | — | Full-text search, CQRS, background jobs, webhooks |
| 13 | `enterprise-security` | 6 | — | OWASP, secrets management, audit logging, pen testing |
| 14 | `enterprise-testing` | 7 | ✅ | Unit/integration/E2E, CI testing, coverage, mocking |

### Specialty Skills (2)

| Skill | Description |
|---|---|
| `skill-self-improving` | Session-end analysis — auto-improves skills based on work done |
| `postmark` | Multi-skill suite: send email, inbound, webhooks, templates, best practices |

### Utility Skills (4)

| Skill | Description |
|---|---|
| `deployment-validator` | Pre-deployment validation checks |
| `env-config-auditor` | Environment/config file auditing |
| `pre-deploy-security-scanner` | Security scanning before deploy |
| `session-orchestrator` | Session workflow orchestration |

---

## Installation Methods

### Method 1: Copy Files (Recommended)

Best for most users. Copies files so skills work independently of the repo.

```bash
# Single skill example:
SKILL="enterprise-backend"
mkdir -p ~/.claude/skills/$SKILL/references
cp ~/Desktop/GEMS/dev/SKILLS/$SKILL/SKILL.md ~/.claude/skills/$SKILL/
cp ~/Desktop/GEMS/dev/SKILLS/$SKILL/references/* ~/.claude/skills/$SKILL/references/
```

### Method 2: Extract .skill Package

Seven skills ship pre-packaged as `.skill` tarballs:

```bash
# Single skill from .skill package:
SKILL="enterprise-backend"
tar -xzf ~/Desktop/GEMS/dev/SKILLS/$SKILL/$SKILL.skill -C ~/.claude/skills/
```

Available `.skill` packages:

- `enterprise-ai-applications.skill`
- `enterprise-ai-foundations.skill`
- `enterprise-backend.skill`
- `enterprise-database.skill`
- `enterprise-deployment.skill`
- `enterprise-frontend.skill`
- `enterprise-testing.skill`

### Method 3: Symlink (Advanced)

Links directly to the repo — changes to the repo update skills instantly. But you must keep the repo in place.

```bash
SKILL="enterprise-backend"
ln -sf ~/Desktop/GEMS/dev/SKILLS/$SKILL ~/.claude/skills/$SKILL
```

---

## Per-Skill Installation

Use these commands to install individual skills. Run from the repo root:

```bash
cd ~/Desktop/GEMS/dev/SKILLS
```

### Enterprise AI Applications

```bash
mkdir -p ~/.claude/skills/enterprise-AI-applications/references
cp enterprise-AI-applications/SKILL.md ~/.claude/skills/enterprise-AI-applications/
cp enterprise-AI-applications/references/* ~/.claude/skills/enterprise-AI-applications/references/
```

### Enterprise AI Foundations

```bash
mkdir -p ~/.claude/skills/enterprise-AI-foundations/references
cp enterprise-AI-foundations/SKILL.md ~/.claude/skills/enterprise-AI-foundations/
cp enterprise-AI-foundations/references/* ~/.claude/skills/enterprise-AI-foundations/references/
```

### Enterprise AI Fundamentals

```bash
mkdir -p ~/.claude/skills/enterprise-AI-fundamentals/references
cp enterprise-AI-fundamentals/SKILL.md ~/.claude/skills/enterprise-AI-fundamentals/
cp enterprise-AI-fundamentals/references/* ~/.claude/skills/enterprise-AI-fundamentals/references/
```

### Enterprise Backend

```bash
mkdir -p ~/.claude/skills/enterprise-backend/references
cp enterprise-backend/SKILL.md ~/.claude/skills/enterprise-backend/
cp enterprise-backend/references/* ~/.claude/skills/enterprise-backend/references/
```

### Enterprise Data Analytics

```bash
mkdir -p ~/.claude/skills/enterprise-data-analytics/references
cp enterprise-data-analytics/SKILL.md ~/.claude/skills/enterprise-data-analytics/
cp enterprise-data-analytics/references/* ~/.claude/skills/enterprise-data-analytics/references/
```

### Enterprise Database

```bash
mkdir -p ~/.claude/skills/enterprise-database/references
cp enterprise-database/SKILL.md ~/.claude/skills/enterprise-database/
cp enterprise-database/references/* ~/.claude/skills/enterprise-database/references/
```

### Enterprise Deployment

```bash
mkdir -p ~/.claude/skills/enterprise-deployment/references
cp enterprise-deployment/SKILL.md ~/.claude/skills/enterprise-deployment/
cp enterprise-deployment/references/* ~/.claude/skills/enterprise-deployment/references/
```

### Enterprise DevX & Monorepo

```bash
mkdir -p ~/.claude/skills/enterprise-devx-monorepo/references
cp enterprise-devx-monorepo/SKILL.md ~/.claude/skills/enterprise-devx-monorepo/
cp enterprise-devx-monorepo/references/* ~/.claude/skills/enterprise-devx-monorepo/references/
```

### Enterprise Frontend

```bash
mkdir -p ~/.claude/skills/enterprise-frontend/references
cp enterprise-frontend/SKILL.md ~/.claude/skills/enterprise-frontend/
cp enterprise-frontend/references/* ~/.claude/skills/enterprise-frontend/references/
```

### Enterprise i18n & Accessibility

```bash
mkdir -p ~/.claude/skills/enterprise-i18n-accessibility/references
cp enterprise-i18n-accessibility/SKILL.md ~/.claude/skills/enterprise-i18n-accessibility/
cp enterprise-i18n-accessibility/references/* ~/.claude/skills/enterprise-i18n-accessibility/references/
```

### Enterprise Mobile

```bash
mkdir -p ~/.claude/skills/enterprise-mobile/references
cp enterprise-mobile/SKILL.md ~/.claude/skills/enterprise-mobile/
cp enterprise-mobile/references/* ~/.claude/skills/enterprise-mobile/references/
```

### Enterprise Search & Messaging

```bash
mkdir -p ~/.claude/skills/enterprise-search-messaging/references
cp enterprise-search-messaging/SKILL.md ~/.claude/skills/enterprise-search-messaging/
cp enterprise-search-messaging/references/* ~/.claude/skills/enterprise-search-messaging/references/
```

### Enterprise Security

```bash
mkdir -p ~/.claude/skills/enterprise-security/references
cp enterprise-security/SKILL.md ~/.claude/skills/enterprise-security/
cp enterprise-security/references/* ~/.claude/skills/enterprise-security/references/
```

### Enterprise Testing

```bash
mkdir -p ~/.claude/skills/enterprise-testing/references
cp enterprise-testing/SKILL.md ~/.claude/skills/enterprise-testing/
cp enterprise-testing/references/* ~/.claude/skills/enterprise-testing/references/
```

### Skill Self-Improving

```bash
mkdir -p ~/.claude/skills/skill-self-improving/references
cp skill-self-improving/SKILL.md ~/.claude/skills/skill-self-improving/
cp skill-self-improving/references/* ~/.claude/skills/skill-self-improving/references/
```

### Postmark (Multi-Skill Suite)

```bash
cp -R postmark ~/.claude/skills/
```

---

## Project-Level Installation

To scope skills to a specific project instead of globally:

```bash
cd /path/to/your/project

# Install one skill at the project level
SKILL="enterprise-backend"
mkdir -p .claude/skills/$SKILL/references
cp ~/Desktop/GEMS/dev/SKILLS/$SKILL/SKILL.md .claude/skills/$SKILL/
cp ~/Desktop/GEMS/dev/SKILLS/$SKILL/references/* .claude/skills/$SKILL/references/

# Add to .gitignore if you don't want skills committed
echo ".claude/skills/" >> .gitignore
```

---

## Verification

After installation, verify everything is in place:

```bash
# List all installed skills
ls ~/.claude/skills/

# Check a specific skill has its files
ls -R ~/.claude/skills/enterprise-backend/

# Expected output:
# ~/.claude/skills/enterprise-backend/:
# SKILL.md  references/
#
# ~/.claude/skills/enterprise-backend/references/:
# api-design.md          email-notifications.md  nodejs-frameworks.md
# auth-sso-mfa.md        payments-stripe.md      python-frameworks.md
# realtime-websockets.md

# Count total reference files across all skills
find ~/.claude/skills -name "*.md" -path "*/references/*" | wc -l

# Quick health check — verify no empty SKILL.md files
find ~/.claude/skills -name "SKILL.md" -empty
```

### Verify in Claude Code

Start a Claude Code session and test with a relevant prompt:

```
> Help me design a REST API for a user management system
```

Claude should automatically pull in patterns from `enterprise-backend` (API design, auth) and `enterprise-database` (schema design).

---

## Skill Usage & Trigger Keywords

Skills activate automatically based on keywords in your prompts. Here are the key triggers:

| Skill | Trigger Keywords |
|---|---|
| **AI Applications** | RAG, agent, prompt, LLM, chatbot, embeddings, vector search |
| **AI Foundations** | AI provider, embeddings, vector database, model cost, chunking |
| **AI Fundamentals** | machine learning, model selection, fine-tuning, evaluation |
| **Backend** | API, endpoint, REST, auth, SSO, Stripe, webhook, WebSocket |
| **Data Analytics** | ETL, pipeline, dashboard, analytics, data warehouse, reporting |
| **Database** | schema, migration, ORM, Prisma, Drizzle, PostgreSQL, query |
| **Deployment** | Docker, CI/CD, nginx, SSL, VPS, monitoring, deploy |
| **DevX/Monorepo** | monorepo, Turborepo, Nx, workspace, shared packages |
| **Frontend** | React, Next.js, component, CSS, glassmorphic, dashboard, UI |
| **i18n/A11y** | internationalization, i18n, accessibility, WCAG, RTL, a11y |
| **Mobile** | React Native, Expo, mobile, iOS, Android, push notification |
| **Search/Messaging** | search, Elasticsearch, message queue, CQRS, background job |
| **Security** | OWASP, secrets, encryption, audit log, vulnerability, pen test |
| **Testing** | unit test, integration test, E2E, Playwright, coverage, mock |
| **Self-Improving** | `/self-improve`, session end, skill update |
| **Postmark** | email, Postmark, SMTP, inbound email, webhook, template |

---

## Maintenance

### Update Skills from Repo

```bash
cd ~/Desktop/GEMS/dev/SKILLS
git pull origin main

# Re-run the install script
bash install-all-skills.sh
```

### Clean Up Broken Symlinks

The repo currently has ~40 broken symlinks pointing to a legacy `../../.agents/skills/` path. To clean them:

```bash
cd ~/Desktop/GEMS/dev/SKILLS
find . -maxdepth 1 -type l ! -exec test -e {} \; -print   # list broken
find . -maxdepth 1 -type l ! -exec test -e {} \; -delete  # remove broken
```

### Create a .skill Package

To package a skill for distribution:

```bash
cd ~/.claude/skills
tar -czf enterprise-backend.skill enterprise-backend/
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Skills not loading | Verify `SKILL.md` exists in `~/.claude/skills/<name>/` |
| Wrong skill activating | Check trigger keywords; be more specific in prompts |
| Stale skills | Re-run `install-all-skills.sh` after `git pull` |
| Broken symlinks | Run the cleanup commands above |
| `.skill` package won't extract | Verify it's a valid gzip: `file <name>.skill` |
| Permission errors | `chmod -R u+rw ~/.claude/skills/` |

---

## Directory Structure Reference

```
~/.claude/skills/
├── enterprise-AI-applications/
│   ├── SKILL.md
│   └── references/
│       ├── rag-architecture.md
│       ├── agent-patterns.md
│       └── ... (8 files)
├── enterprise-backend/
│   ├── SKILL.md
│   └── references/
│       ├── api-design.md
│       ├── auth-sso-mfa.md
│       ├── payments-stripe.md
│       └── ... (7 files)
├── enterprise-database/
│   ├── SKILL.md
│   └── references/ (8 files)
├── ... (11 more enterprise skills)
├── skill-self-improving/
│   ├── SKILL.md
│   └── references/
├── postmark/
│   ├── SKILL.md
│   ├── postmark-send-email/
│   ├── postmark-inbound/
│   ├── postmark-webhooks/
│   ├── postmark-templates/
│   └── postmark-email-best-practices/
├── deployment-validator/
├── env-config-auditor/
├── pre-deploy-security-scanner/
└── session-orchestrator/
```

---

*Generated: 2026-03-02 | Repo: `git@github.com:cukeric/skills.git`*
