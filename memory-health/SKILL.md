---
name: memory-health
description: Audits the LLM-compiled knowledge wiki (_memory/<project>/_wiki/ and _memory/_wiki/) for drift, contradictions, staleness, orphaned links, unsourced claims, coverage gaps, and new-article/connection candidates. Auto-fixes the low-risk class; routes claim-changing findings to the founder. Trigger on /memory-health, "memory health", "audit memory", "audit the wiki", "knowledge base health check", "kb health", "check the wiki", monthly scheduled runs, or after a milestone recompile.
---

# Memory Health — Knowledge Wiki Audit

Quality-control for the synthesis layer described in `_dev/_docs/KB-SYNTHESIS-DESIGN.md`.
The wiki is LLM-maintained and compounds over time, so a slow-burning wrong fact gets
quietly built on. This skill is the monthly + milestone audit that keeps it honest.

**Scope:** one target per run — a single project wiki (`_memory/<project>/_wiki/`) or the
top-level cross-project wiki (`_memory/_wiki/`). Default to the project named by the user;
if none, ask which. Do **not** sweep every project in one run (cost — a full audit can burn
a large fraction of a session).

## Phase 0 — Load

1. Read the target `_wiki/index.md` (topic map, freshness table, open questions).
2. Read every article in the target `_wiki/` + each article's `sources:` frontmatter.
3. Read the raw session logs **newer than** the most recent article `last_compiled` date
   (these are the un-synthesised changes the wiki may be missing).
4. Read `.health/last-check.md` if present (what the last run flagged/fixed).

## Phase 1 — Seven-stage audit (report only)

For each, record finding + severity + **class: `auto` | `ask`**:

1. **Contradictions** — articles (or an article vs. a newer log) that disagree on a fact
   (a port, a version, a decision reversed). `ask`.
2. **Stale** — `last_verified` > 90 days on an active project. Flag for re-check; **never
   auto-delete a fact**. `ask`.
3. **Orphaned `[[links]]`** — links whose `name:` slug matches no existing memory/article.
   Repairable (fix target / drop link) → `auto`.
4. **Unsourced claims** — a wiki statement with no traceable `sources:` log behind it
   (anti-hallucination enforcement). Flag the claim; adding/removing it is `ask`.
5. **Coverage gaps** — raw logs newer than `last_compiled` whose content never reached the
   wiki. Recompiling an article is content change → `ask` (unless trivially additive).
6. **New-article candidates** — recurring themes across logs deserving their own article. `ask`.
7. **New connections** — `[[link]]` suggestions between existing articles not yet
   cross-referenced. Adding a backlink → `auto`.

Also run the **band-word / American-spelling / AI-slop** pass over wiki prose (project
writing rules) — cleanup → `auto`.

## Phase 2 — Action

- **Auto-fix the `auto` class without asking:** orphaned-link repair/removal, adding
  cross-reference backlinks, band-word/spelling cleanup, bumping `last_verified` on
  articles confirmed still-accurate. Each auto-fix is git-tracked (revertable) and **must
  be listed individually** in the report.
- **Everything `ask`** (contradictions, stale-fact rewrites, deletions, new articles,
  unsourced-claim resolution, non-trivial recompiles) → present via `AskUserQuestion`
  with a concrete action per finding. Apply only what's approved.

## Report

Write `_memory/<target>/_wiki/.health/last-check.md` (create `.health/` if missing):

```markdown
# Memory health — <target> — YYYY-MM-DD
**Verdict:** clean | N issues (X auto-fixed, Y need decisions)

## Auto-fixed (this run)
- <each fix, with file>

## Needs decision
- <each finding + proposed action>

## Stage summary
contradictions: n · stale: n · orphaned-links: n · unsourced: n · coverage-gaps: n · new-articles: n · new-connections: n
```

Update the target `index.md` freshness table + Open Questions. Lead your chat reply with
the verdict line.

## Cadence (both, per the design doc)
- **Milestone-triggered** recompile via `/self-improve` after a shipped slice.
- **Monthly scheduled**, staggered one project per run (`CronCreate` / the `schedule`
  skill; precedent: `env-config-auditor`). Off-peak.

## Guardrails
- Never delete a raw session log — the wiki is the lens, logs are the record.
- Never auto-resolve a contradiction or rewrite a claim — that's always `ask`.
- Every auto-fix goes in the report and in git history, so any wrong call is revertable.
- One target per run. State the target up front.
