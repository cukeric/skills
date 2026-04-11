---
name: skill-self-improving
description: Invoke this skill when the user triggers /self-improve at the end of a coding session. This skill analyses all work completed during the session — code changes, patterns used, decisions made, errors encountered, debugging steps, technology choices — and then systematically audits, updates, creates, or removes skills to capture learnings and improve the entire skill library. Trigger on /self-improve, self-improve, skill improvement, skill audit, skill gap, session review, improve skills, update skills, skill maintenance, meta-skill, skill creation, skill optimization, or any request to review and improve the agent's skill library based on recent work. This is a meta-skill that operates on ALL other skills.
---

# Skill Self-Improving — Meta-Skill for Continuous Skill Evolution

This is a **meta-skill** — it does not build applications. It builds and maintains the skills that build applications. When invoked at the end of a coding session, it systematically analyses the session's work and improves the entire skill library to be smarter, more accurate, and more complete for future sessions.

## Reference Files

Read this SKILL.md first for the overall process, then consult references as needed during each phase:

### Phase-Specific Guides

1. `references/session-analysis.md` — **Phase 1**: How to audit a coding session — what to scan, what to extract, what matters
2. `references/skill-audit-patterns.md` — **Phases 2 & 3**: Patterns for detecting skill gaps, evaluating existing skills, identifying staleness and inconsistencies
3. `references/skill-creation-guide.md` — **Phase 4**: Standards for creating new skills or extending existing ones — templates, naming, structure
4. `references/change-log.md` — **Phase 5**: Change documentation format, impact assessment, rollback guidance

---

## When to Use This Skill

**Primary trigger:** User invokes `/self-improve` at the end of a coding session.

**What "end of session" means:** The user has completed meaningful work — building features, fixing bugs, deploying, designing architecture, debugging, or any substantive coding activity. The session produced learnings worth capturing.

**Do NOT trigger when:**

- The session was trivial (answered a question, made a single typo fix)
- No coding or technical work was done
- The user explicitly says they don't want skill improvements

---

## The 5-Phase Self-Improvement Process

```
┌─────────────────────────────────────────────────────────────┐
│                    /self-improve invoked                      │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  Phase 1: SESSION ANALYSIS                                   │
│  Scan conversation, code changes, tools, errors, patterns    │
│  Output: Session Summary + Learnings List                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  Phase 2: SKILL GAP DETECTION                                │
│  What did the session need that skills didn't provide?        │
│  Output: Gap Report (missing patterns, thin coverage areas)  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  Phase 3: EXISTING SKILL AUDIT                               │
│  Do current skills have outdated/incorrect/incomplete info?   │
│  Output: Audit Report (stale items, contradictions, gaps)    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  Phase 4: ACTION EXECUTION                                   │
│  Update existing skills, create new ones, remove obsolete    │
│  Output: Modified/created/deleted skill files                │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  Phase 5: CHANGE REPORT                                      │
│  Document what changed, why, and impact assessment           │
│  Output: Self-Improvement Report (presented to user)         │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 0: Cross-Session Context Recovery (MANDATORY FIRST STEP)

**Goal:** Before analyzing the current session, understand what happened in ALL previous sessions so you don't repeat known issues or miss recurring patterns.

**Read these files in order:**

1. `~/.claude/memory/global/reference/improvement-backlog.md` — Persistent backlog of unresolved skill gaps, agent issues, hook problems. Check if any open items were addressed this session.
2. `~/.claude/skills/skill-performance.tsv` — Full history of corrections, gaps, successes, and skill changes across ALL sessions. Look for patterns: recurring gaps, skills that keep getting corrected, areas with zero coverage.
3. `_dev/_memory/<project>/` — Session memory files for the current project. Scan recent entries for blockers, next actions, and self-improve signals from previous sessions.

**Output:** A brief "Cross-Session Context" section noting:
- How many prior sessions exist for this project
- Any open backlog items that were addressed this session
- Any recurring patterns (same skill corrected 3+ times = systemic issue)
- New items to add to the backlog from this session

---

## Phase 1: Session Analysis

**Goal:** Understand what happened during the session so you can identify what the skill library should learn from it.

**What to scan:**

1. **Conversation history** — All user requests, your responses, decisions made
2. **Files modified** — What code was written, in what languages, using what frameworks
3. **Errors encountered** — Build failures, runtime errors, debugging sessions
4. **Tools and commands used** — Terminal commands, browser interactions, searches performed
5. **Patterns applied** — Architecture decisions, design patterns, configuration choices
6. **Technology decisions** — Framework selection, library choices, infrastructure decisions
7. **Web searches performed** — What information was sought (indicates knowledge gaps)

**Output:** A structured session summary. See `references/session-analysis.md` for the full template.

---

## Phase 2: Skill Gap Detection

**Goal:** Identify what the session needed that the current skill library doesn't cover — or covers poorly.

### Gap Categories

| Gap Type | Description | Example |
|---|---|---|
| **Missing Skill** | An entire domain not covered by any skill | Session used WebAssembly but no skill exists for it |
| **Missing Reference** | A skill exists but lacks a reference for the specific tech used | enterprise-backend exists but no reference for Hono edge framework |
| **Thin Coverage** | A reference file mentions a topic but lacks actionable detail | Auth reference mentions OAuth but doesn't cover PKCE flow |
| **Outdated Pattern** | A skill recommends an approach that the session proved suboptimal | A skill recommends a deprecated API pattern |
| **Missing Edge Case** | A skill's guidance failed in a specific scenario | Database skill didn't cover concurrent migration conflicts |

### Detection Process

1. **Map session technologies** to existing skills — which skills should have covered what was done?
2. **Compare session reality vs. skill guidance** — did the skills' recommendations match what actually worked?
3. **Identify workarounds** — anywhere you had to deviate from skill guidance is a potential gap
4. **Check for missing triggers** — would the skill descriptions have triggered for the session's tasks?
5. **Search for latest practices** — use web search to verify current best practices match skill content

---

## Phase 3: Existing Skill Audit

**Goal:** Check if current skills need updates based on what the session revealed AND based on latest industry knowledge.

### Audit Checklist

For each relevant skill touched by the session:

- [ ] **Accuracy**: Do code examples still work? Are API patterns current?
- [ ] **Completeness**: Are there important scenarios the skill doesn't address?
- [ ] **Freshness**: Are library versions, framework versions, and tooling recommendations current?
- [ ] **Consistency**: Does this skill contradict any other skill? Are naming conventions aligned?
- [ ] **Priority order**: Does the skill follow security → data integrity → performance → scalability?
- [ ] **Verification checklist**: Is the skill's verification checklist comprehensive?
- [ ] **Cross-references**: Are integration links to other skills accurate?

### Freshness Check (Web Search Required)

For skills relevant to the session, **search the web** for:

- Latest stable versions of referenced frameworks/libraries
- Any deprecated APIs or patterns used in skill examples
- New security advisories affecting recommended approaches
- Industry shifts in best practices (e.g., new consensus on state management, auth flows)

See `references/skill-audit-patterns.md` for detailed audit procedures.

---

## Phase 4: Action Execution

**Goal:** Make the actual improvements. Every change must meet enterprise-grade quality standards.

### Decision Framework: What Action to Take

```
Is there a gap?
├── Yes → Is it covered by an existing skill's domain?
│         ├── Yes → UPDATE the existing skill
│         │         ├── Add a new section to SKILL.md
│         │         ├── Add a new reference file to references/
│         │         ├── Update an existing reference file
│         │         └── Add items to the verification checklist
│         └── No  → Is the gap significant enough for a new skill?
│                   ├── Yes (covers a distinct domain with multiple patterns)
│                   │     → CREATE a new skill directory
│                   └── No (one-off, narrow topic)
│                         → Add to the closest existing skill as a reference
│
Is something outdated?
├── Yes → Is the outdated content still partially valid?
│         ├── Yes → UPDATE with current information, preserving valid parts
│         └── No  → REPLACE the outdated section entirely
│
Is something wrong or contradictory?
├── Yes → FIX the incorrect content, add a note about what changed and why
│
Is something obsolete?
└── Yes → DEPRECATE or REMOVE
          ├── If the skill/reference covers a dead technology → REMOVE
          └── If partially obsolete → DEPRECATE specific sections with notes
```

### Quality Standards for All Changes

Every modification must:

1. **Follow the enterprise pattern:** YAML frontmatter, structured sections, reference files, verification checklist
2. **Maintain security-first priority:** security → data integrity → performance → scalability
3. **Include actionable guidance:** Not just "do X" but "do X using Y because Z, avoiding W"
4. **Provide code examples** where applicable (real, working code, not pseudocode)
5. **Cross-reference** related skills using the Integration section pattern
6. **Be verifiable:** Updated verification checklist items for any new content

### Creating New Skills

When creating a new skill, follow `references/skill-creation-guide.md` exactly:

- Directory structure: `skill-name/SKILL.md` + `skill-name/references/`
- YAML frontmatter with exhaustive trigger keywords
- Decision framework section
- Priority-ordered sections
- Verification checklist
- Integration with Other Enterprise Skills section

### Updating Existing Skills

When updating existing skills:

- **Never remove existing valid content** without explicit justification
- **Add, don't replace** unless the existing content is incorrect
- **Maintain the existing formatting and section structure**
- **Update the verification checklist** if new capabilities were added
- **Keep reference file sizes manageable** — split large files into focused references

---

## Phase 5: Change Report

**Goal:** Document everything that changed and present it to the user for review.

### Report Structure

```markdown
# Self-Improvement Report — [Date]

## Session Context
Brief summary of what work was done in the session.

## Changes Made

### Updates to Existing Skills
For each updated skill:
- **Skill**: [name]
- **File(s) Changed**: [paths]
- **What Changed**: [description]
- **Why**: [rationale linked to session learnings or freshness check]
- **Impact**: Low / Medium / High

### New Skills Created
For each new skill:
- **Skill**: [name]
- **Purpose**: [what gap it fills]
- **Files Created**: [list]
- **Trigger Keywords**: [from YAML description]

### Removals / Deprecations
For each removal:
- **Skill/File**: [name]
- **Reason**: [why it's obsolete]

## Freshness Updates
Summary of any version bumps, deprecated API fixes, or best-practice updates based on web research.

## Recommendations (Deferred)
Items identified but not actioned (too large, needs user input, waiting for more data).
```

Present this report directly to the user for review, listing all changed file paths.

---

## Integration with All Enterprise Skills

This meta-skill operates **on** all other skills. It must understand the structure and content of each:

| Skill | What Self-Improve Checks |
|---|---|
| **enterprise-backend** | API patterns, auth implementations, framework versions, middleware patterns |
| **enterprise-frontend** | Component patterns, framework choices, styling approaches, performance targets |
| **enterprise-database** | Schema patterns, ORM versions, indexing strategies, migration approaches |
| **enterprise-deployment** | Docker practices, CI/CD patterns, cloud service recommendations, monitoring tools |
| **enterprise-testing** | Test framework versions, testing patterns, coverage targets, E2E approaches |
| **enterprise-ai-foundations** | LLM provider APIs, vector DB options, safety patterns, cost governance |
| **enterprise-ai-applications** | RAG patterns, agent architectures, chatbot patterns, multimodal handling |
| **find-skills** | Skill discovery approach, CLI tools, ecosystem awareness |

---

## Safety Rules

> [!CAUTION]
> This skill modifies other skills. The following safety rules are **non-negotiable**:

1. **Never delete a skill without explicit user confirmation.** Deprecate and flag for review instead.
2. **Never modify security-related content** (auth, encryption, secrets management, input validation) without verifying the change against current OWASP guidelines via web search.
3. **Never downgrade a recommendation** (e.g., changing from Argon2id to bcrypt, or removing a security check) without documented justification.
4. **Always preserve the existing priority order** (security → data integrity → performance → scalability).
5. **Always present changes for user review** before considering the improvement cycle complete.
6. **Back up modified files conceptually** — include the original content in the change report so changes can be reverted.
7. **Rate limit changes** — make targeted, high-value improvements. Don't rewrite entire skills unless they are fundamentally broken.

---

## Verification Checklist

Before considering any self-improvement cycle complete:

- [ ] Cross-session context recovered (improvement-backlog.md, skill-performance.tsv, project memory)
- [ ] Improvement backlog updated (new items added, resolved items archived)
- [ ] Session fully analysed (conversation, code changes, errors, patterns)
- [ ] Skill gaps identified and categorized
- [ ] Existing skills audited for accuracy, freshness, and completeness
- [ ] Web search performed for latest best practices on relevant technologies
- [ ] All changes follow enterprise skill patterns (frontmatter, sections, references, checklist)
- [ ] Security-related changes verified against OWASP/industry standards
- [ ] Cross-skill references updated and consistent
- [ ] No valid existing content removed without justification
- [ ] Change report generated with full rationale for every modification
- [ ] User notified and changes presented for review
- [ ] Skills repo pushed to GitHub (`cd ~/.claude/skills && git add -A && git commit -m "chore: self-improve — {brief summary}" && git push origin main`)
