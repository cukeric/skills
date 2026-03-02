---
name: session-orchestrator
description: Session lifecycle orchestrator that runs at session start and end. At start, reads MEMORY.md + next_steps.md, identifies priorities, and creates a task list. At end, enforces the mandatory protocol pipeline (code-review → deploy → self-improve). Trigger at the beginning of every coding session, when the user says "start session", "what should we work on", "what's next", or at the end when the user says "wrap up", "end session", "deploy", or when a coding task is complete.
---

# Session Orchestrator

Manages the full lifecycle of a coding session — from context recovery and task planning at the start, through to the mandatory verification and improvement pipeline at the end.

## Session Start Protocol

### Step 1: Context Recovery

Read the following files to understand current state:

```bash
# Project memory (decisions, patterns, deployment info)
cat ~/.claude/projects/*/memory/MEMORY.md

# Project roadmap (what's done, what's next)
cat next_steps.md 2>/dev/null || cat ../next_steps.md 2>/dev/null

# Project instructions
cat CLAUDE.md 2>/dev/null || cat ../CLAUDE.md 2>/dev/null
```

### Step 2: Priority Identification

From the context gathered, identify:

1. **Blockers** — anything broken in production (SEV-1/SEV-2)
2. **In-progress work** — tasks started but not finished in prior sessions
3. **Next priority** — the highest-impact item from next_steps.md
4. **Quick wins** — low-effort items that can be knocked out alongside main work

### Step 3: Task List Creation

Present a prioritized task list to the user:

```
## Session Plan — {date}

### Priority Tasks
1. [BLOCKER] {description} — {why it's urgent}
2. [IN-PROGRESS] {description} — {what remains}
3. [NEXT] {description} — {from next_steps.md}

### Quick Wins (if time permits)
- {small task 1}
- {small task 2}

### Deferred (not this session)
- {future items for awareness}
```

Wait for user confirmation before proceeding.

## Session End Protocol

When a coding task is complete, enforce the mandatory verification pipeline in order:

### Pipeline

```
code changes → env-config-auditor → pre-deploy-security-scanner → code-reviewer → deploy → deployment-validator → /self-improve
```

### Step 1: Environment Audit (env-config-auditor)

If any new `process.env.*` references were added or providers changed:

- Run the env-config-auditor skill
- Verify all new env vars exist in local `.env.local` and on VPS
- Flag any missing variables as CRITICAL blockers

Skip if no env var changes were made.

### Step 2: Security Scan (pre-deploy-security-scanner)

If any API routes, auth logic, or input handling was modified:

- Run the pre-deploy-security-scanner skill
- Block deployment on any CRITICAL findings
- Log HIGH findings for next-session fix

Skip if changes were cosmetic only (CSS, copy, layout).

### Step 3: Code Review (code-reviewer agent)

Spawn the `code-reviewer` agent to review all changes made during the session:

- Review against the original task requirements
- Check for common pitfalls, bugs, and security issues
- Verify enterprise coding standards compliance
- Confirm no regressions introduced

### Step 4: Deploy

Execute the standard deployment:

```bash
# From project root
rsync -avz -e "ssh -i ../vps_deploy_key" \
  --exclude node_modules --exclude .next --exclude .env.local --exclude .git \
  ./frontend/ root@77.42.18.40:/root/saas/listinglaunch/frontend/

ssh -i ../vps_deploy_key root@77.42.18.40 \
  "cd /root/saas/listinglaunch && docker compose build --no-cache && docker compose up -d"
```

**Important:** Use `--no-cache` if any env vars or dependencies changed. Otherwise `docker compose build` (with cache) is sufficient.

### Step 5: Deployment Validation (deployment-validator)

After deployment completes:

- Run the deployment-validator skill
- Hit all critical endpoints
- Verify security headers
- Confirm auth protection
- Check SSL and SEO assets

### Step 6: Self-Improve (/self-improve)

Run the self-improvement skill to:

- Analyze what was built during the session
- Identify skill gaps or outdated patterns
- Update existing skills with new learnings
- Create new reference files if needed

## Decision: What to Skip

Not every session needs the full pipeline. Use judgment:

| Session Type | Required Steps |
|---|---|
| Feature development (new routes, logic) | ALL steps |
| Bug fix (production issue) | Security scan → Code review → Deploy → Validate |
| UI/CSS only changes | Code review → Deploy → Validate |
| Documentation/config only | Deploy (if needed) → Self-improve |
| Research/planning only | Self-improve only |

## Output Format

At session end, present a summary:

```
## Session Summary — {date}

### Completed
- {task 1}: {brief description}
- {task 2}: {brief description}

### Pipeline Results
| Step                    | Status | Notes                          |
|-------------------------|--------|--------------------------------|
| Env Config Audit        | PASS   | No new env vars                |
| Security Scan           | PASS   | 0 critical, 0 high            |
| Code Review             | PASS   | No issues found                |
| Deployment              | DONE   | Built and running              |
| Deployment Validation   | PASS   | All endpoints healthy          |
| Self-Improve            | DONE   | Updated 2 skills               |

### Deferred to Next Session
- {item 1}
- {item 2}
```

## Integration

This skill wraps the entire session lifecycle:

```
SESSION START: session-orchestrator (context recovery + task planning)
    ↓
DURING SESSION: coding work guided by task list
    ↓
SESSION END: session-orchestrator (verification pipeline)
    code changes → env-config-auditor → pre-deploy-security-scanner
    → code-reviewer → deploy → deployment-validator → /self-improve
```
