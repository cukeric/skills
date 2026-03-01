# Enterprise Database Skill — Installation Guide

## Option 1: Claude Code (Recommended — Global Skill)

This makes the skill available in **every project** you open with Claude Code.

### Steps:

```bash
# 1. Create the global skills directory (if it doesn't exist)
mkdir -p ~/.claude/skills/enterprise-database/references

# 2. Copy the SKILL.md and all reference files
#    (from wherever you downloaded/extracted them)
cp enterprise-database/SKILL.md ~/.claude/skills/enterprise-database/
cp enterprise-database/references/*.md ~/.claude/skills/enterprise-database/references/
```

### Verify:
```bash
# You should see this structure:
tree ~/.claude/skills/enterprise-database/

# Expected output:
# ~/.claude/skills/enterprise-database/
# ├── SKILL.md
# └── references/
#     ├── aws-database.md
#     ├── azure-database.md
#     ├── dynamodb.md
#     ├── gcp-database.md
#     ├── mongodb.md
#     ├── orm-guide.md
#     ├── postgresql.md
#     └── redis.md
```

### How it works:
- Claude Code automatically detects skills in `~/.claude/skills/`
- The skill's description tells Claude **when** to use it (any mention of databases, schemas, etc.)
- Claude reads the SKILL.md first, then pulls in the relevant reference file(s) based on the task
- You never need to invoke it manually — just mention database work and it triggers

### Alternative: Project-Level Skill

If you only want this skill in a specific project:

```bash
# Place it in the project's .claude directory instead
mkdir -p /path/to/your-project/.claude/skills/enterprise-database/references
cp enterprise-database/SKILL.md /path/to/your-project/.claude/skills/enterprise-database/
cp enterprise-database/references/*.md /path/to/your-project/.claude/skills/enterprise-database/references/
```

> **Note:** Project-level skills override global skills with the same name.

---

## Option 2: Copilot CLI (or any CLI using Opus 4.6)

CLI tools typically use system prompts or appended instructions rather than skills. There are a few approaches:

### Approach A: Append as System Prompt (Best for CLI)

If your CLI supports a system prompt file or append flag:

```bash
# Claude Code's print mode example:
claude -p --append-system-prompt-file ~/.claude/skills/enterprise-database/SKILL.md "design a database for my e-commerce app"
```

### Approach B: Reference in CLAUDE.md (Works Everywhere)

Add a reference to the skill in your project's `CLAUDE.md` file:

```markdown
# CLAUDE.md

## Database Standards
When working with databases, follow the enterprise database standards:
See @.claude/skills/enterprise-database/SKILL.md for full database development standards.
```

The `@` import syntax pulls the file contents into context. Claude Code supports recursive imports, so the SKILL.md can reference its own reference files.

### Approach C: CLAUDE.md with Inline Reference (for CLIs without @ imports)

If your CLI copilot doesn't support `@` imports, add a condensed version directly in your CLAUDE.md. The full reference files would live in the repo and you'd instruct the model to read them:

```markdown
# CLAUDE.md

## Database Standards
For ALL database work, read and follow the instructions in:
- `.claude/skills/enterprise-database/SKILL.md` (main standards)
- `.claude/skills/enterprise-database/references/` (detailed guides per database/cloud provider)

Always consult these files before creating or modifying any database schema, migration, or configuration.
```

---

## Option 3: Claude.ai (Web Interface)

Upload the `.skill` file to a Claude.ai **Project**:

1. Download `enterprise-database.skill`
2. Open a Claude.ai Project
3. Go to Project Knowledge / Settings
4. Upload the `.skill` file

The skill only applies within that specific project.

---

## Quick Test

After installing, open Claude Code in any project and say:

> "I need a database for a multi-tenant SaaS app with user accounts, subscriptions, and billing"

Claude should automatically pick up the skill and:
- Choose the right database engine (likely PostgreSQL)
- Apply enterprise security standards (RBAC, RLS, encryption)
- Set up proper indexing and constraints
- Include migration files, Docker Compose, and an .env.example
- Follow all the patterns from the skill

If it doesn't reference the skill's standards, try: `/skill enterprise-database` to invoke it directly, then report back so we can tune the description.
