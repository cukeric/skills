# Change Log Reference

This guide defines how to document skill changes made during each self-improvement cycle, ensuring traceability, impact awareness, and rollback capability.

---

## Change Entry Format

Every change made during a self-improvement cycle must be documented using this format:

```markdown
## [DATE] — Self-Improvement Cycle

**Session Context**: [Brief description of what work drove this improvement]

### Change [N]: [Short Title]

- **Type**: UPDATE | CREATE | REMOVE | DEPRECATE
- **Skill**: [skill-name]
- **File(s)**: [path(s) relative to skills directory]
- **What Changed**: [Specific description of the modification]
- **Why**: [Rationale linked to session learnings or freshness check]
- **Impact**: LOW | MEDIUM | HIGH
- **Verification**: [How to verify this change is correct]
- **Rollback**: [How to revert if needed — original content or previous state]
```

---

## Change Types

### UPDATE

Modification to an existing skill file. This is the most common change type.

**Sub-categories:**

- **Content Update**: New section, expanded guidance, added code example
- **Version Bump**: Updated framework/library versions in recommendations
- **Bug Fix**: Corrected an error in code examples, configuration, or guidance
- **Enhancement**: Added edge cases, troubleshooting steps, anti-patterns
- **Trigger Expansion**: Added keywords to YAML description for better matching

**Impact assessment:**

- **LOW**: Minor wording changes, added keywords, small clarifications
- **MEDIUM**: New code examples, new sections, version updates with no breaking changes
- **HIGH**: Changed security recommendations, modified architecture patterns, version updates with breaking changes

### CREATE

Addition of a new file — either a new skill directory or a new reference file.

**Threshold for creation:**

- New skill directory: Only when the gap covers a distinct domain with 3+ sub-topics
- New reference file: When existing references don't cover a sub-topic that arose in multiple sessions or is clearly important

**Required documentation:**

- Full rationale for why this content is needed
- Which session(s) revealed the gap
- How it integrates with existing skills

### REMOVE

Deletion of a skill file or content section. **Rare and requires explicit user confirmation.**

**When to remove:**

- Technology is genuinely dead (no active users, no maintenance, no future)
- Content is factually incorrect and cannot be corrected
- Content duplicates another skill and causes confusion

**When NOT to remove:**

- Technology is "old" but still in production use
- Content is outdated but could be updated instead
- You're unsure if anyone relies on this content

### DEPRECATE

Mark content as outdated without removing it. **Preferred over REMOVE.**

**How to deprecate:**
Add a deprecation notice at the top of the affected content:

```markdown
> [!WARNING]
> **Deprecated**: This section references [old approach]. The current recommended
> approach is [new approach] — see [link to updated content]. This section is
> preserved for reference when maintaining legacy systems.
```

---

## Change Report Template

After each self-improvement cycle, generate a report using this structure:

```markdown
# Self-Improvement Report — [YYYY-MM-DD]

## Session Context

**Session Goal**: [What did the user set out to do?]
**Technologies Used**: [Frameworks, languages, tools involved]
**Session Outcome**: [What was accomplished?]

---

## Changes Summary

| # | Type | Skill | File | Impact | Description |
|---|---|---|---|---|---|
| 1 | UPDATE | enterprise-backend | SKILL.md | LOW | Added Hono to framework matrix |
| 2 | CREATE | enterprise-backend | references/hono-edge.md | MEDIUM | New reference for edge runtime patterns |
| 3 | UPDATE | enterprise-testing | references/e2e-testing.md | LOW | Updated Playwright to v1.50 patterns |

---

## Detailed Changes

### Change 1: Added Hono to Backend Framework Matrix

[Full change entry using the format above]

### Change 2: Created Hono Edge Runtime Reference

[Full change entry]

### Change 3: Updated Playwright Patterns

[Full change entry]

---

## Freshness Updates

| Skill | Technology | Previous Version | Updated Version | Breaking Changes? |
|---|---|---|---|---|
| enterprise-frontend | Next.js | 14 | 15.x | Yes — see migration notes in reference |

---

## Deferred Recommendations

Items identified but not actioned in this cycle:

1. **[Topic]**: [Why deferred — needs user input / too large / needs more data]
2. **[Topic]**: [Why deferred]

---

## Metrics

- **Skills audited**: [N]
- **Changes made**: [N] (updates: X, creates: Y, removes: Z)
- **Web searches performed**: [N]
- **Freshness updates**: [N]
```

---

## Rollback Guidance

### For Content Updates

When updating skill content, the change report must include the original text so it can be restored:

```markdown
**Rollback — Original Content:**
\`\`\`
[exact original text that was replaced]
\`\`\`
```

### For New Files

Rollback is simple: delete the created file and remove any SKILL.md references to it.

### For Removed/Deprecated Content

Removed content must be preserved in the change report. If deprecation is used instead of removal, the original content is still in the file with a deprecation notice.

---

## Cumulative Change History

Over time, the change reports build a history of skill evolution. Store reports in a known location (e.g., conversation artifacts) so future self-improvement cycles can reference past changes to:

1. **Avoid flip-flopping**: Don't change something back to what it was two cycles ago without good reason
2. **Track improvement trends**: Which skills get updated most often? (indicates a fast-moving domain)
3. **Detect decay**: Which skills haven't been updated in many cycles? (may need proactive freshness review)
4. **Measure impact**: Did past changes actually help in subsequent sessions?

---

## Quality Rules for Change Documentation

1. **Every change must have a "Why"** — no changes without rationale
2. **Every HIGH impact change must include rollback instructions** — so the user can revert if needed
3. **Security changes must cite their source** — OWASP guideline, CVE, or official security advisory
4. **Version bumps must note breaking changes** — if the new version has breaking changes, the skill must address migration
5. **Never document a change you didn't make** — the report must exactly match the actual modifications
6. **Use present tense for descriptions** — "Adds edge case handling" not "Added edge case handling"
