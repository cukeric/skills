# Skill Audit Patterns Reference

This guide defines systematic patterns for evaluating existing skills and detecting gaps, staleness, inconsistencies, and quality issues.

---

## Gap Detection Methodology

### Step 1: Technology Mapping

Map every technology, pattern, and tool used in the session to existing skills:

```
Session Technology → Expected Skill → Coverage Status
─────────────────────────────────────────────────────
Next.js 15         → enterprise-frontend    → ✅ Covered in references/react-nextjs.md
Prisma ORM         → enterprise-database    → ✅ Covered in references/orm-guide.md
WebSocket auth     → enterprise-backend     → ⚠️ Partially (auth covers JWT, not WS-specific)
k6 custom metrics  → enterprise-testing     → ❌ Missing (load-testing.md is basic)
Hono edge runtime  → enterprise-backend     → ❌ Missing (no reference file for Hono)
```

### Step 2: Guidance Accuracy Check

For each skill that was relevant, compare what the skill recommended vs. what actually worked:

| Skill Recommendation | Session Reality | Status |
|---|---|---|
| Use Argon2id for password hashing | Used Argon2id, worked correctly | ✅ Accurate |
| Use `node:22-alpine` Docker base | `node:22-alpine` had architecture issues on M1 | ⚠️ Needs update |
| Configure CORS with explicit origins | `CORS *` was initially used, skill caught it | ✅ Accurate |
| Use cursor-based pagination | OFFSET was used due to simple use case | ⚠️ Needs nuance |

### Step 3: Missing Trigger Analysis

Check if skill descriptions (YAML frontmatter) would have triggered for the session's tasks:

- Were there tasks the user asked about that no skill would have caught?
- Are there missing keywords in existing skill descriptions?
- Would the correct skill have been found based on the user's actual phrasing?

---

## Freshness Audit

### Version Checks

For each skill, verify that recommended versions are current:

```markdown
## Version Freshness Check

| Skill | Technology | Recommended Version | Latest Stable | Status |
|---|---|---|---|---|
| enterprise-frontend | Next.js | 14 | 15.x | ⚠️ Update needed |
| enterprise-backend | Fastify | 4.x | 5.x | ⚠️ Update needed |
| enterprise-testing | Vitest | 1.x | 2.x | ⚠️ Update needed |
| enterprise-database | Prisma | 5.x | 6.x | ⚠️ Update needed |
| enterprise-deployment | Docker | node:22-alpine | node:22-alpine | ✅ Current |
```

**How to check versions:**

1. Use web search for `[technology] latest stable version [current year]`
2. Check official documentation / release pages
3. Verify LTS status for Node.js, Python, etc.
4. Note breaking changes between the recommended and latest versions

### API and Pattern Currency

Beyond version numbers, check if recommended API patterns are still the standard approach:

- **Deprecated APIs**: Search for `[technology] deprecated [feature]` when uncertain
- **New recommended patterns**: Search for `[technology] best practices [current year]`
- **Security advisories**: Search for `[technology] security advisory` for recently reported CVEs
- **Migration guides**: If a major version jump exists, reference the official migration guide

---

## Completeness Audit

### Reference File Depth Assessment

Each reference file should be evaluated on a 4-level scale:

| Level | Description | Action |
|---|---|---|
| **Complete** | Covers common patterns, edge cases, code examples, troubleshooting | None |
| **Adequate** | Covers common patterns with examples, missing edge cases | Add edge cases section |
| **Thin** | Mentions the topic but lacks actionable detail or examples | Expand with working code and patterns |
| **Missing** | The topic should be covered but has no reference file | Create new reference file |

### Coverage Matrix Template

For each enterprise skill, assess coverage across its sub-topics:

```markdown
## enterprise-backend Coverage Assessment

| Sub-Topic | Reference File | Depth Level | Gap Description |
|---|---|---|---|
| Express setup | nodejs-frameworks.md | Complete | — |
| Fastify setup | nodejs-frameworks.md | Adequate | Missing plugin patterns |
| Hono / edge | — | Missing | No reference file exists |
| REST API design | api-design.md | Complete | — |
| GraphQL | api-design.md | Thin | Only mentioned, no schema patterns |
| gRPC | — | Missing | May not be needed unless session used it |
| File uploads | — | Missing | Only mentioned in passing in api-design.md |
```

---

## Consistency Audit

### Cross-Skill Contradictions

Check for contradictions between skills. Common areas of conflict:

1. **Auth patterns**: Does the backend skill and frontend skill agree on token storage strategy?
2. **Database access**: Does the frontend skill say "never access DB directly" while the backend skill implies otherwise?
3. **Testing requirements**: Do coverage targets in enterprise-testing match requirements stated in other skills?
4. **Deployment patterns**: Does the backend skill's Docker example match the deployment skill's Dockerfile recommendations?
5. **Technology choices**: If one skill recommends Tool A and another recommends Tool B for the same purpose, document which is the canonical choice.

### Naming Convention Alignment

All skills should use consistent terminology:

| Concept | Standard Term | Non-Standard Variants to Fix |
|---|---|---|
| Environment variables | `env vars` or `environment variables` | `env config`, `config vars`, `secrets` (only for actual secrets) |
| API validation | `input validation` | `request validation`, `payload validation` |
| Background work | `background jobs` | `async tasks`, `queued work`, `workers` |
| Error handling | `error handling` | `exception handling`, `error management` |

---

## Quality Scoring

For each audited skill, assign a quality score:

### Scoring Rubric (out of 10)

| Criterion | Weight | Score Range |
|---|---|---|
| **Security guidance** | 25% | 0-10 (correct, complete, current OWASP alignment) |
| **Data integrity** | 20% | 0-10 (transaction patterns, validation, constraints) |
| **Code examples** | 20% | 0-10 (working, modern, copy-pasteable) |
| **Completeness** | 15% | 0-10 (covers common + edge cases) |
| **Freshness** | 10% | 0-10 (versions current, APIs not deprecated) |
| **Consistency** | 10% | 0-10 (no contradictions with other skills) |

### Score Interpretation

| Score | Assessment | Action |
|---|---|---|
| 9-10 | Excellent | No changes needed |
| 7-8 | Good | Minor updates, add edge cases |
| 5-6 | Adequate | Needs refresh — update examples, add missing sections |
| 3-4 | Below standard | Significant rewrite needed in underperforming areas |
| 1-2 | Critical | Major revision or replacement required |

---

## Web Research Integration

When auditing, use targeted web searches to validate and update skill content:

### Search Templates

```
Latest [framework] best practices [current year]
[framework] [version] migration guide
[technology] security best practices [current year]
[library] changelog latest release
[pattern name] alternatives [current year]
OWASP [topic] cheat sheet
[technology] deprecated features
```

### Research Rules

1. **Prioritize official documentation** over blog posts
2. **Check dates** on all sources — ignore content older than 18 months for fast-moving technologies
3. **Verify against multiple sources** before updating a skill based on research
4. **Note the source** in any changes made (add a comment in the skill file)
5. **Focus on consensus** — if the industry hasn't converged on a new approach, note the debate rather than picking a side
