# Skill Creation Guide Reference

This guide defines when and how to create entirely new skills, extend existing ones, and structure all skill content to match enterprise patterns.

---

## Decision: Create New Skill vs. Extend Existing

### Create a New Skill When

1. **Distinct domain**: The topic doesn't logically belong in any existing skill's scope
   - Example: A session involved extensive Solidity/smart contract work → no existing skill covers blockchain development → create `enterprise-blockchain`
2. **Multiple sub-topics**: The gap has enough depth for a SKILL.md + at least 2-3 reference files
   - Example: Mobile development (React Native + Expo) with patterns for navigation, state, native modules → create `enterprise-mobile`
3. **Unique priority ordering**: The topic has domain-specific priorities that differ from existing skills
   - Example: IoT/embedded has reliability > power efficiency > security ordering that differs from web patterns
4. **Recurring need**: The topic came up in multiple sessions or is likely to recur frequently

### Extend an Existing Skill When

1. **Related domain**: The missing content is a natural extension of an existing skill
   - Example: Hono edge runtime → add to `enterprise-backend/references/` as `hono-edge.md`
2. **Single sub-topic**: The gap is narrow enough for one reference file or section addition
3. **Shared priorities**: The topic follows the same priority ordering as the parent skill
4. **Cross-cutting concern**: The gap affects multiple skills but one is the primary owner
   - Example: API rate limiting spans backend + deployment, but primarily belongs in backend

### Do NOT Create a New Skill When

- The content could fit as a section in an existing reference file (add it there)
- The topic is too narrow for more than a few paragraphs (add to closest skill)
- It would duplicate guidance already in another skill (cross-reference instead)

---

## New Skill Template

Every new skill must follow this exact structure:

### Directory Structure

```
skill-name/
├── SKILL.md                    # Main skill file (required)
└── references/                 # Detailed reference guides (required if >1 sub-topic)
    ├── [topic-1].md
    ├── [topic-2].md
    └── [topic-n].md
```

### SKILL.md Template

```markdown
---
name: skill-name-here
description: [Exhaustive trigger description. List EVERY keyword, technology name, synonym, related concept, user phrasing, and adjacent topic that should trigger this skill. Be very verbose — trigger false positives are better than false negatives. Include the main keywords AND their variations (e.g., both "database" and "DB", both "deploy" and "deployment"). Mention when NOT to trigger if there's a closely related skill.]
---

# [Skill Title — Full Name with Context]

[Opening paragraph: What this skill covers, why it matters, what quality standards apply. Reference the enterprise priority order if applicable.]

## Reference Files

[List all reference files with brief descriptions and when to consult each one.]

---

## Decision Framework: [Choosing the Right X]

[A structured decision matrix or table helping the user/agent select the right approach based on requirements.]

### [Option A vs Option B vs Option C]

| Requirement | Best Choice | Why |
|---|---|---|
| [Scenario 1] | **[Choice]** | [Rationale] |
| [Scenario 2] | **[Choice]** | [Rationale] |

---

## Priority 1: [Highest Priority for This Domain]

[Detailed guidance on the most important aspect — usually Security for web, Reliability for infrastructure, etc.]

## Priority 2: [Second Priority]

[Next most important.]

## Priority 3: [Third Priority]

[And so on.]

## Priority 4: [Fourth Priority]

[Lowest priority but still required.]

---

## Project Structure

[Standard directory structure with clear file organization.]

---

## Integration with Other Enterprise Skills

[Table or list mapping how this skill connects to every relevant enterprise skill.]

---

## Verification Checklist

Before considering any [domain] work complete, verify:

- [ ] [Specific, actionable verification item]
- [ ] [Another item]
- [ ] [8-15 items covering all priority areas]
```

---

## Naming Conventions

### Skill Directory Names

- Use kebab-case: `skill-name-here`
- Prefix with `enterprise-` for enterprise-grade skills: `enterprise-mobile`
- Prefix with `skill-` for meta/utility skills: `skill-self-improving`
- Keep names descriptive but concise (2-3 words max)

### Reference File Names

- Use kebab-case: `topic-name.md`
- Be specific: `react-nextjs.md` not `frontend-framework.md`
- Group related content: `auth-sso-mfa.md` not separate files for each
- Maximum 8-10 reference files per skill (split the skill if more are needed)

### YAML Name Field

- Always matches the directory name
- Lowercase with hyphens: `name: enterprise-backend`

---

## Description (YAML Frontmatter) Writing Guide

The `description` field is the most critical part — it determines when the skill triggers.

### Rules

1. **Start with the primary action**: "Explains how to...", "Covers...", "Trigger this skill whenever..."
2. **List ALL trigger keywords** — technology names, abbreviations, synonyms, related concepts
3. **Include user phrasing** — how would a non-expert describe this need?
4. **Include negations** — when should this skill NOT trigger? (mention the alternative skill)
5. **Be exhaustive** — a 200+ word description is better than a 50-word one that misses triggers

### Example — Good Description

```yaml
description: Trigger this skill whenever the user mentions testing, tests, test setup, unit test, integration test, end-to-end test, E2E, Vitest, Playwright, test coverage, mocking, test doubles, API testing, load testing, performance testing, k6, stress test, test automation, CI testing, Testcontainers, test database, test fixtures, snapshot testing, regression testing, TDD, test-driven development, coverage gate, test pipeline, AI testing, LLM testing, RAG testing, or any request to add, fix, run, or configure tests. Also trigger when the user asks about quality assurance, code confidence, "how do I test this", or wants to verify that code works correctly.
```

### Example — Bad Description

```yaml
description: Helps with testing code.
```

---

## Reference File Quality Standards

Every reference file must meet these standards:

### Structure

1. **Opening summary** (2-3 sentences): What this reference covers, when to use it
2. **Setup/Prerequisites** (if applicable): What needs to be installed, configured
3. **Core patterns** with working code examples
4. **Edge cases and gotchas**: Things that commonly trip people up
5. **Anti-patterns**: What NOT to do, with explanation
6. **Troubleshooting**: Common errors and their solutions

### Code Examples

- **Must be real, working code** — not pseudocode or abbreviated snippets
- **Include necessary imports** — don't assume the reader knows which package to import from
- **Show both TypeScript and Python** where the skill covers both ecosystems
- **Annotate with comments** explaining non-obvious decisions
- **Include error handling** — never show happy-path-only examples

### Length Guidelines

| Reference Type | Target Length | Max Length |
|---|---|---|
| Setup/configuration guide | 200-400 lines | 500 lines |
| Pattern/architecture reference | 300-600 lines | 800 lines |
| Comprehensive topic (auth, payments) | 500-800 lines | 1000 lines |

If a reference file exceeds 1000 lines, split it into multiple focused files.

---

## Updating Existing Skills

When the self-improvement process modifies an existing skill rather than creating a new one:

### Adding a New Reference File

1. Add the file to the `references/` directory
2. Add an entry in the skill's "Reference Files" section linking to it
3. Ensure the YAML description includes trigger keywords for the new content
4. Update the verification checklist if the new reference introduces verifiable requirements

### Adding Content to an Existing Reference

1. Place new content in the most logical position within the file's existing structure
2. Match the formatting, heading levels, and code style of the surrounding content
3. Never exceed the file length guidelines — split if necessary

### Modifying the SKILL.md

1. Add new sections after existing ones; don't rearrange established ordering
2. Update the decision framework if new options are available
3. Add new verification checklist items at the end (maintain order consistency)
4. Update the "Integration with Other Skills" table if cross-references change

### Updating the YAML Description

1. **Only add keywords — never remove existing ones** without explicit justification
2. Add new technology names, patterns, and user phrasings discovered during the session
3. If the skill's scope expanded, update the opening clause to reflect the broader coverage
