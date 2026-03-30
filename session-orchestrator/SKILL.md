---
name: session-orchestrator
description: "Full session lifecycle: brainstorm → plan → execute → verify → deploy/document → self-improve → git CI → VPS deploy. Trigger at session start ('start session', 'what's next'), session end ('wrap up', 'deploy'), or when a coding task completes."
---

# Session Orchestrator

Manages the full lifecycle of a coding session through 8 phases. Each phase gates the next.

```
1. BRAINSTORM → 2. PLAN → 3. EXECUTE → 4. VERIFY → 5. DEPLOY & DOCUMENT → 6. SELF-IMPROVE → 7. GIT CI → 8. VPS DEPLOY
```

---

## SESSION START (Phases 1-2)

### Phase 0: Context Recovery

Read the following to understand current state:

```bash
# Project memory
cat ~/.claude/projects/*/memory/MEMORY.md

# Project roadmap
cat next_steps.md 2>/dev/null || cat ../next_steps.md 2>/dev/null

# Project instructions
cat CLAUDE.md 2>/dev/null || cat ../CLAUDE.md 2>/dev/null
```

#### Skill Health Check

Read `~/.claude/skills/skill-performance.tsv` and compute per-skill correction rates over the last 5 sessions:

```
correction_rate = corrections / (corrections + successes)
```

If any skill has a correction rate **> 50%**, display a warning:

```
Skill Health Alert
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
enterprise-backend: 70% correction rate (7/10)
  → Top pattern: "Hono framework" (4 of 7)
  → Recommendation: Review reference before using
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Skip if `skill-performance.tsv` has fewer than 10 total events.

#### Priority Identification

From context gathered, identify:

1. **Blockers** — anything broken in production (SEV-1/SEV-2)
2. **In-progress work** — tasks from prior sessions
3. **Next priority** — highest-impact item from next_steps.md
4. **Quick wins** — low-effort items

Present a prioritized task list. Wait for user confirmation.

### Phase 1: Brainstorm

**Invoke the `brainstorming` skill.** This is mandatory before any creative or implementation work.

- Explore the problem space, alternatives, trade-offs, edge cases
- Consider at least 2-3 approaches before committing
- Identify technical risks and unknowns
- Output: a clear direction with rationale

User confirms before Phase 2.

### Phase 2: Plan

**Invoke `superpowers:writing-plans` skill.**

- Break work into discrete, testable tasks with acceptance criteria
- Identify risks, dependencies, order of operations
- Assign tasks to parallel agents where possible (`superpowers:subagent-driven-development`)
- Output: a written plan (in-conversation or plan file)

User confirms before Phase 3.

---

## DURING SESSION (Phase 3)

### Phase 3: Execute / Code

- Follow the plan task by task
- Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` for parallel work
- Use `superpowers:test-driven-development` where applicable
- Use `superpowers:systematic-debugging` if bugs arise
- Mark tasks complete as you go

---

## SESSION END (Phases 4-8)

### Phase 4: Verify / Test

Run in order — each must pass before the next:

1. **Type-check** — `tsc --noEmit` (if TypeScript)
2. **Lint** — project linter (eslint, etc.)
3. **Build** — `npm run build` or equivalent
4. **Tests** — unit + integration (`npm test` or equivalent)
5. **Environment Audit** (`env-config-auditor` skill) — if new `process.env.*` references added
6. **Security Scan** (`pre-deploy-security-scanner` skill) — if API routes, auth, or input handling changed
7. **Code Review** — spawn `code-reviewer` agent for comprehensive review of ALL changes

Block on any CRITICAL findings. Log HIGH findings for next-session fix.

### Phase 5: Deploy & Document

- Update README / CHANGELOG if behavior changed
- Deploy only after Phase 4 passes with no critical findings
- Run `deployment-validator` skill post-deploy to smoke-test endpoints, headers, auth guards

Deploy command is project-specific. Check project CLAUDE.md or memory for the deploy script.

### Phase 6: Self-Improve

**Run `/self-improve`.** Non-optional for any session that produced code changes.

- Extract performance signals into `skill-performance.tsv`
- Compute per-skill correction rates
- Validate whether previous skill changes helped
- Update skills with new learnings
- Create new reference files if needed

### Phase 7: Git CI

- Stage and commit changes using conventional commits format
- Ensure CI pipeline passes (lint, test, build, type-check)
- Create PR if on a feature branch
- Do NOT force-push or amend without explicit user approval

### Phase 8: Deploy to VPS (if applicable)

Only for projects with VPS deployment targets. Skip for libraries, research, or local-only projects.

- Use project-specific deploy script (typically rsync + docker compose)
- Use `--no-cache` if env vars or dependencies changed
- Run `deployment-validator` post-deploy
- Verify all critical endpoints respond correctly

---

## Skip Rules

| Session Type | Required Phases |
|---|---|
| Feature development | ALL phases (1-8) |
| Bug fix (production) | 1 (brief) → 3 → 4 → 5 → 6 → 7 → 8 |
| UI/CSS only | 3 → 4 (build + review) → 5 → 7 |
| Research/planning only | 1 → 2 → 6 |
| Documentation only | 3 → 7 |

## Session Summary Format

At session end, present:

```
## Session Summary — {date}

### Completed
- {task 1}: {brief description}
- {task 2}: {brief description}

### Pipeline Results
| Phase                   | Status | Notes                          |
|-------------------------|--------|--------------------------------|
| 1. Brainstorm           | DONE   | {direction chosen}             |
| 2. Plan                 | DONE   | {N tasks planned}              |
| 3. Execute              | DONE   | {N tasks completed}            |
| 4. Verify               | PASS   | Type-check, lint, tests, review|
| 5. Deploy & Document    | DONE   | Deployed, docs updated         |
| 6. Self-Improve         | DONE   | Updated {N} skills             |
| 7. Git CI               | DONE   | Committed, PR created          |
| 8. VPS Deploy           | DONE   | All endpoints healthy          |

### Deferred to Next Session
- {item 1}
- {item 2}
```

## Integration

```
SESSION START
  Phase 0: Context recovery + skill health check
  Phase 1: Brainstorm (brainstorming skill)
  Phase 2: Plan (writing-plans skill)
    ↓
DURING SESSION
  Phase 3: Execute (task by task, TDD, subagents)
    ↓
SESSION END
  Phase 4: Verify (type-check → lint → build → test → env-audit → security-scan → code-review)
  Phase 5: Deploy & Document
  Phase 6: Self-Improve (/self-improve)
  Phase 7: Git CI (commit, PR)
  Phase 8: VPS Deploy (if applicable)
```
