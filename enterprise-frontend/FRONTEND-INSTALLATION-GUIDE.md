# Enterprise Frontend Skill — Installation Guide

## What's Inside

| File | Purpose |
|---|---|
| `SKILL.md` | Main skill: decision framework, security/performance/UX standards, project structure, verification checklist |
| `references/glassmorphic-design-system.md` | Default design system: color tokens (light+dark), glass effects, Tailwind config, component patterns (buttons, inputs, cards, modals, sidebar), animations, typography, accessibility |
| `references/react-nextjs.md` | React & Next.js: App Router patterns, providers, middleware, API client, TanStack Query hooks, WebSocket hook, error boundaries, testing |
| `references/vue-nuxt.md` | Vue & Nuxt 3: directory structure, composables, Pinia stores, route middleware, TanStack Vue Query, Superforms |
| `references/svelte-sveltekit.md` | Svelte & SvelteKit: server hooks, load functions, stores, form handling, adapter selection |
| `references/dashboard-patterns.md` | Dashboard layouts: sidebar shell, widget grid, data tables, real-time indicators, empty states, toast system, command palette |
| `references/data-visualization.md` | Charts: library selection matrix, glassmorphic chart styling, real-time streaming patterns, sparklines, accessibility |
| `references/responsive-accessibility.md` | Mobile-first breakpoints, responsive patterns, WCAG 2.1 AA full checklist, ARIA patterns, skip nav, testing |

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
# 1. Create the skills directory
mkdir -p ~/.claude/skills/enterprise-frontend/references

# 2. Copy all files
cp SKILL.md ~/.claude/skills/enterprise-frontend/
cp references/* ~/.claude/skills/enterprise-frontend/references/

# 3. Verify
ls -R ~/.claude/skills/enterprise-frontend/
```

Claude Code will auto-detect the skill and trigger it when you mention anything related to frontend, UI, components, dashboards, etc.

### Option B: Claude Code — Project-Level Skills

```bash
# Inside your project root
mkdir -p .claude/skills/enterprise-frontend/references
cp SKILL.md .claude/skills/enterprise-frontend/
cp references/* .claude/skills/enterprise-frontend/references/
```

This makes the skill available only within that project.

### Option C: From .skill Package

```bash
# Extract the package
mkdir -p ~/.claude/skills
tar -xzf enterprise-frontend.skill -C ~/.claude/skills/

# Verify
ls -R ~/.claude/skills/enterprise-frontend/
```

### Option D: Copilot CLI / Other AI Agents

Point the agent's skill or context directory to the extracted folder. The SKILL.md file is self-contained with references to the sub-files — any agent that reads SKILL.md first and then follows its reference file instructions will work correctly.

---

## How It Works

When you ask Claude Code (or any compatible agent) to build UI — whether it's a dashboard, landing page, component, or full app — the skill triggers and:

1. **Reads SKILL.md** for architecture decisions (which framework, SSR vs SPA, etc.)
2. **Reads the relevant reference file(s)** based on the chosen stack and requirements
3. **Follows the decision framework** to pick the best tools for the job
4. **Applies the glassmorphic design system** by default (warm colors, glass effects, Tailwind)
5. **Enforces enterprise standards** — security, performance budgets, accessibility, TypeScript strict mode
6. **Runs the verification checklist** before marking work complete

---

## Trigger Keywords

The skill activates on any of these terms (and many more — see the description in SKILL.md):

> UI, UX, component, dashboard, layout, chart, responsive, CSS, Tailwind, glassmorphic, frontend, React, Next.js, Vue, Nuxt, Svelte, SvelteKit, widget, sidebar, navbar, modal, form, table, theme, dark mode, animation, page, design system, accessibility, a11y

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-database` | Database design, ORMs, cloud deployment |
| `enterprise-backend` (coming) | API architecture, auth, payments, real-time |
| `enterprise-deployment` (coming) | VPS setup, Docker, CI/CD, nginx, SSL |
