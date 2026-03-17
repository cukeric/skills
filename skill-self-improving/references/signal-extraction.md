# Signal Extraction Reference — Phase 1.5

Detailed guide for detecting, attributing, and logging performance signals from conversation history into `~/.claude/skills/skill-performance.tsv`.

---

## Signal Detection Patterns

### Correction Signals (event_type: `correction`)

These indicate a skill gave wrong or incomplete guidance.

| Pattern | How to Detect | Severity | Example |
|---|---|---|---|
| Direct rejection | User says "no", "wrong", "not that", "instead do..." | medium | "No, use Hono not Express" |
| Code rewrite | User manually rewrites code Claude produced | medium-high | User replaces entire auth middleware |
| Architecture override | User overrides a pattern/architecture choice | high | "We don't use Redux here, use Zustand" |
| Extended back-and-forth | Task required 4+ messages to get right | low | 6 messages to get a DB migration correct |
| Convention miss | User says "that's not how we do it" | medium | "We always use snake_case for DB columns" |
| Self-debugging | Claude hit an error in its own output and had to fix it | low | Build failed, Claude fixed import path |

### Success Signals (event_type: `success`)

These indicate a skill performed well.

| Pattern | How to Detect | Severity |
|---|---|---|
| Silent acceptance | User accepted output without requesting changes | low |
| Explicit praise | User said "perfect", "great", "exactly", "that's it" | low |
| First-try acceptance | Complex task completed in 1-2 messages | low |

### Gap Signals (event_type: `gap`)

These indicate missing skill coverage.

| Pattern | How to Detect | Severity |
|---|---|---|
| Web search needed | Claude needed to search for something a skill should cover | medium |
| No skill triggered | A task clearly needed guidance but no skill was relevant | high |
| User provided guidance | User had to explain a pattern/approach from scratch | medium |

---

## Attribution Rules

For each detected signal, determine which skill should have covered it:

### Step 1: Identify the Domain

What technology/framework/pattern was the task about?

- API route handling → `enterprise-backend`
- React components → `enterprise-frontend`
- Database schemas/queries → `enterprise-database`
- Docker/deployment → `enterprise-deployment`
- Tests → `enterprise-testing`
- LLM/AI integration → `enterprise-ai-foundations` or `enterprise-ai-applications`

### Step 2: Check Specificity

If multiple skills could apply, attribute to the **most specific** one:

- "Auth middleware in Express" → `enterprise-backend` (not `enterprise-security`)
- "OAuth PKCE flow" → `enterprise-security` (auth protocol, not just backend code)
- "React component testing" → `enterprise-testing` (not `enterprise-frontend`)

### Step 3: Handle Missing Coverage

If **no skill** covers the domain:
- Set `event_type` to `gap` (not `correction`)
- Set `skill` to the closest skill or `none` if truly uncovered
- This signals Phase 2 to create a new skill or reference

---

## What NOT to Log

These patterns are **not** skill failures — do not create entries for them:

| Pattern | Why It's Not a Signal |
|---|---|
| User taste/preference ("make it blue not red") | Aesthetic choice, not skill guidance failure |
| Ambiguous request needing clarification | Normal conversation flow |
| One-off task with no generalizable pattern | No skill could or should cover it |
| Trivial typos or copy-paste errors | Human error, not skill deficiency |
| User changed their mind mid-task | Requirements shift, not guidance failure |
| User exploring options ("what if we tried...") | Brainstorming, not correction |

### The Generalizability Test

Before logging a signal, ask: **"Would improving a skill prevent this from happening again in a future session?"**

- **Yes** → Log it
- **No** → Skip it

---

## Session ID Assignment

1. Read `~/.claude/skills/skill-performance.tsv`
2. Find the last `session_id` value
3. Increment: `ses_001` → `ses_002` → `ses_003`
4. If file has only the header, start with `ses_001`
5. All events from this session share the same `session_id`

---

## TSV Format

```
date	session_id	skill	event_type	detail	severity
```

| Column | Type | Description |
|---|---|---|
| `date` | `YYYY-MM-DD` | Date of the session |
| `session_id` | `ses_NNN` | Sequential session identifier |
| `skill` | string | Skill name (e.g., `enterprise-backend`) or `none` |
| `event_type` | enum | `correction`, `success`, `gap`, or `skill_change` |
| `detail` | string | Brief description of what happened (< 100 chars) |
| `severity` | enum | `low`, `medium`, `medium-high`, `high` |

### Example Entries

```
2026-03-16	ses_001	enterprise-backend	correction	user said "no, use Hono not Express"	medium
2026-03-16	ses_001	enterprise-frontend	success	component pattern accepted first try	low
2026-03-16	ses_001	none	gap	no skill covered WebAssembly deployment	high
2026-03-16	ses_001	enterprise-backend	skill_change	added Hono edge framework reference	medium
```

---

## Edge Cases

### Multiple Corrections on Same Topic

If the user corrects the same type of mistake multiple times in one session, log **one** correction with severity bumped up one level. Don't flood the TSV with duplicates.

### Corrections During Brainstorming

If the session was primarily brainstorming/planning (not coding), only log corrections that relate to **technical recommendations**, not ideation back-and-forth.

### Self-Corrections Before User Sees

If Claude catches and fixes its own mistake before the user responds, log as `correction` with `low` severity. The skill still led to a wrong initial approach.

### Correction vs. Iteration

If the user says "try a different approach" after seeing a working solution, this is **iteration** (not correction) — do not log. But if they say "this is wrong because..." then it's a correction.
