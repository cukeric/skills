# Session Analysis Reference

This guide covers how to systematically audit a coding session to extract learnings that improve the skill library.

---

## What to Scan

### 1. Conversation Flow

Trace the entire conversation from start to finish:

- **User requests**: What did the user ask for? What was the real intent behind the request?
- **Clarification exchanges**: Where was ambiguity? What required follow-up questions?
- **Decision points**: Where did you choose between approaches? What factors drove the choice?
- **Pivots and backtracking**: Where did an approach fail, requiring a change of direction?

### 2. Code Changes

Catalogue every file touched:

| What to Record | Why it Matters |
|---|---|
| Languages used | Maps to language-specific skills (TypeScript, Python, Solidity, etc.) |
| Frameworks/libraries used | Maps to framework-specific references |
| Architecture patterns applied | Validates or challenges skill recommendations |
| Configuration files created/modified | Reveals deployment and tooling patterns |
| New dependencies added | Identifies ecosystem choices worth documenting |

### 3. Errors and Debugging

Errors are the most valuable learning source. For each error encountered:

```
Error Category: [Build / Runtime / Configuration / Deployment / Logic]
Error Detail: [The specific error message or symptom]
Root Cause: [What actually caused it]
Resolution: [How it was fixed]
Time to Resolve: [Quick fix or extended debugging?]
Skill Relevance: [Which skill should have prevented or addressed this?]
Preventable?: [Could better skill guidance have avoided this entirely?]
```

### 4. Commands and Tools Used

Track terminal commands, web searches, and browser interactions:

- **Terminal commands that failed** — indicate tooling gaps or configuration issues
- **Web searches performed** — directly reveal knowledge gaps in skills
- **Browser debugging sessions** — complex issues that required visual inspection
- **External documentation consulted** — topics where skills were insufficient

### 5. Patterns and Anti-Patterns

Identify both positive patterns and anti-patterns from the session:

**Positive patterns worth capturing:**

- Elegant solutions to complex problems
- Efficient debugging strategies
- Reusable code patterns not yet in skills
- Infrastructure configurations that worked well

**Anti-patterns to document:**

- Approaches that seemed right but failed
- Common mistakes that consumed debugging time
- Configuration traps (works locally, breaks in production)
- Library version incompatibilities discovered

---

## Session Summary Template

After scanning, produce a structured summary:

```markdown
## Session Summary

### Overview
- **Session Goal**: [What the user set out to accomplish]
- **Session Outcome**: [What was actually accomplished]
- **Duration Estimate**: [Short / Medium / Long session]
- **Primary Domain**: [Backend / Frontend / Database / Deployment / AI / Other]

### Technologies Used
- **Languages**: [list]
- **Frameworks**: [list with versions if known]
- **Infrastructure**: [Docker, cloud services, CI/CD]
- **Databases**: [list]
- **External Services**: [APIs, SaaS tools]

### Key Decisions Made
1. [Decision]: [Chosen approach] because [rationale]
2. [Decision]: [Chosen approach] because [rationale]

### Errors Encountered
1. [Error summary] — resolved by [fix] — skill relevance: [which skill]
2. [Error summary] — resolved by [fix] — skill relevance: [which skill]

### Patterns Applied
- [Pattern name]: [where/how it was used]

### Knowledge Gaps Identified
- [Topic that required web search or external docs]
- [Area where skill guidance was missing or insufficient]

### Reusable Learnings
- [Specific learning that should be captured in a skill]
```

---

## Analysis Depth Guidelines

Not every session deserves deep analysis. Match depth to session significance:

| Session Type | Analysis Depth | Time Budget |
|---|---|---|
| Simple bug fix, single file change | **Light** — scan errors only, check if any skill should have caught this | 2-3 minutes |
| Feature implementation with known patterns | **Standard** — full scan, focus on gaps and edge cases discovered | 5-10 minutes |
| Complex debugging across multiple systems | **Deep** — detailed error chain analysis, pattern extraction, search for updated practices | 10-15 minutes |
| New technology integration or architecture decision | **Deep + Research** — full scan plus web search for latest best practices | 15-20 minutes |
| Deployment or infrastructure work | **Deep + Security** — full scan plus security-focused audit of all changes | 15-20 minutes |

---

## Extracting Reusable Knowledge

The goal is not to document the session itself but to extract **generalizable knowledge**:

### From a specific bug fix → General debugging guidance

- Bad: "Fixed the PostgreSQL connection timeout by setting `idle_in_transaction_session_timeout`"
- Good: "PostgreSQL connections in containerized environments require explicit timeout configuration — add `idle_in_transaction_session_timeout`, `statement_timeout`, and `connect_timeout` to prevent hanging connections"

### From a specific implementation → Reusable pattern

- Bad: "Used BullMQ for the email queue"
- Good: "For background job queues in Node.js, BullMQ with Redis is the standard — include retry with exponential backoff, dead letter queue, and job event logging"

### From a specific error → Prevention checklist item

- Bad: "Got CORS error when calling API from frontend"
- Good: "Add to deployment verification: test cross-origin requests from the actual frontend domain, not just localhost"
