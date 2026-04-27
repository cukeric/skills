# Submodule + Release Gotchas

Applies when the monorepo is itself a git submodule inside a parent repo (GEMS-style `_projects/<name>/` layout), or when orchestrating a coordinated release across a hybrid TS + Rust workspace. These are the failure modes that burn the most time in practice.

---

## 1. macOS `sed -i.bak` truncates files — prefer the Edit tool

**Symptom:** `sed -i.bak 's/foo/bar/g' FILE` runs with exit 0 on macOS, the `.bak` file is not created, and `FILE` is empty afterward. Happens when the replacement pattern contains characters `sed` interprets in a way that hits an undocumented edge in BSD sed's in-place rewrite.

**Do not** use this for bulk text swaps inside files you care about:

```bash
# Looks innocent. Has wiped entire files in the wild.
sed -i.bak 's/| 0\.8\.0 |/| 0.9.5 |/g' CHANGELOG.md && rm CHANGELOG.md.bak
```

**Do** use the Edit tool with `replace_all: true`:

```
Edit(file_path=".../CHANGELOG.md", old_string="| 0.8.0 |", new_string="| 0.9.5 |", replace_all=true)
```

The Edit path is atomic, requires the file to have been read first (catches bad paths), reports the count of replacements, and cannot truncate. When the edit must run outside Claude Code, use `perl -i -pe 's/foo/bar/g' FILE` instead — perl's `-i` is saner on macOS than BSD sed's.

**If you've already been burned:** `git restore FILE` recovers it immediately if the file was tracked and the damage isn't committed. The `.bak` file may or may not exist. Git is the more reliable recovery path.

---

## 2. `gh` commands inside a submodule hit the parent repo by default

**Symptom:** `gh run list` or `gh pr view` inside `_dev/_projects/PR1M3Claw/` returns results for `cukeric/_dev`, not `cukeric/PR1M3Claw`. The commands key off the directory's tracked git repo, and submodule directories inherit the parent's context in ambiguous tool chains.

**Always pass `--repo` inside a submodule:**

```bash
gh run list --repo cukeric/PR1M3Claw --limit 5
gh run view 24645153762 --repo cukeric/PR1M3Claw --log-failed
gh pr view --repo cukeric/PR1M3Claw
```

**Detection pattern:** if the first `gh run list` result has an unfamiliar workflow name, stop and re-run with `--repo`. Don't debug CI based on the wrong repo's output.

---

## 3. Coordinated version bumps across hybrid TS + Rust workspaces

Hybrid workspaces carry the version number in at least two places:

- Every `packages/*/package.json` → `"version": "0.9.5"`
- Every `packages/*/Cargo.toml` → `version = "0.9.5"`
- Root `package.json` and `Cargo.lock`
- Often duplicated in README badges, `IMPLEMENTATION_PLAN.md`, `CHANGELOG.md` milestone tables, and `CLAUDE.md` state lines

**Do not** try to sed all of these at once. The risk is exactly the failure in §1 plus the probability of one miss poisoning a release.

**Do** split the bump into three passes:

1. **Programmatic bump for workspace manifests only.** Use a tool that understands the manifests — `pnpm changeset version` (which also handles `pnpm-workspace.yaml`) for the TS side, and `cargo set-version --workspace 0.9.5` for the Rust side. Never hand-edit version fields across ≥3 files.
2. **Edit-tool pass for version mentions in prose docs** (README, CHANGELOG milestone tables, IMPLEMENTATION_PLAN status line, CLAUDE.md version line). Use `replace_all: true`. One file at a time so you can audit each diff.
3. **Script-regenerated badges.** If you have a `scripts/update-version-badge.js` or equivalent, run it after passes 1–2. Do not hand-edit shields.io badge URLs.

**Verify in order:** `grep -rn "0\.8\.0" --include="*.json" --include="*.toml"` must be empty before committing. Then `grep -rn "0\.8\.0" --include="*.md"` should only return archive/changelog entries referencing the *previous* version.

---

## 4. Single source of truth for roadmap / status / milestones

**The failure mode:** README claims M9 complete, CHANGELOG claims M10 complete, IMPLEMENTATION_PLAN claims M12 complete, PHILOSOPHY says the Cage is shipping, threat-model says Qubes is M10, ADR-007 says Qubes is M13. Every doc drifted from every other doc at a different rate. Any claim a new contributor reads is potentially wrong.

**Pattern:** elect one authoritative document per fact-type. Example split:

| Fact type | Authoritative source | Everywhere else |
|---|---|---|
| What has shipped | `CHANGELOG.md` | README badges auto-derived; all other docs say "see CHANGELOG" |
| What is planned | `IMPLEMENTATION_PLAN.md` | All other docs say "see IMPLEMENTATION_PLAN"; no milestone list duplicated elsewhere |
| Architecture principles | `PHILOSOPHY.md` or equivalent "why" doc | Referenced, never restated |
| API / tool contracts | Source code + generated docs | Never duplicated in prose |

**Make the invariant explicit in the authoritative doc itself:**

```markdown
> This document is the single source of truth for <X>. Other docs
> (README, PHILOSOPHY, etc.) must not contradict it. When in conflict,
> this document wins and the others are updated.
```

**Drift audit command:** for any milestone/version fact `X`, run:

```bash
grep -rn "$X" --include="*.md" . | grep -v CHANGELOG.md | grep -v IMPLEMENTATION_PLAN.md
```

Every hit is a potential drift site. Reconcile before shipping.

---

## 5. Project-level CLAUDE.md drifts silently

`CLAUDE.md` is loaded into every new session's context. Lines like `Version: 0.8.0` or `Current state: M1–M9 complete` baked into it mean every session starts with wrong context after a release — and nothing complains, because CLAUDE.md is human-edited, not generated.

**Rule:** treat CLAUDE.md's `Version:` / `Current state:` / `Next:` lines as part of the release artifact. Bump them in the same commit as `CHANGELOG.md`. Add a pre-push check:

```bash
# Pre-push gate addition
CURRENT_VERSION=$(jq -r .version package.json)
if ! grep -q "Version:.*$CURRENT_VERSION" CLAUDE.md 2>/dev/null; then
  echo "✗ CLAUDE.md Version: line out of sync with package.json ($CURRENT_VERSION)"
  exit 1
fi
```

If `CLAUDE.md` is gitignored (hidden-mode repos), keep the check locally but don't enforce in CI. The drift still matters for session context — it just can't be enforced centrally.

---

## 6. Doc claims code that doesn't exist — audit pattern

Long-lived projects accumulate doc prose that describes packages, binaries, or features that were never implemented or got removed in a refactor. Every such reference is a trust-debt liability: readers take the doc at face value, try to use the feature, find nothing, and lose confidence in all the other claims.

**Audit command:** for any package/binary/directory name `N` mentioned in prose docs, verify it exists:

```bash
# For each claimed package:
for name in qubes-bridge agent-host-openclaw; do
  if ! test -d "packages/$name"; then
    echo "❗ docs claim packages/$name — does not exist on disk"
    grep -rn "$name" --include="*.md" .
  fi
done
```

Run this before any release. It catches "Qubes bridge" / "agent-host" / any aspirational reference that leaked into shipping docs. Either delete the claim or implement the code — never both vague.

---

## 7. Recovery recipe cheat-sheet

```bash
# Accidentally truncated a tracked file:
git restore FILE

# Accidentally committed a bulk-edit disaster (not yet pushed):
git reset --soft HEAD~1   # keep changes staged for re-do
git reset --hard HEAD~1   # discard entirely — USE WITH CARE

# Wrong repo's CI runs returned by gh (inside a submodule):
gh run list --repo <owner>/<submodule-repo>  # always pass --repo

# Hybrid workspace version left half-bumped (some files at 0.9.5, some at 0.8.0):
grep -rn "\"version\":" packages/*/package.json       # spot the misses
grep -rn "^version = " packages/*/Cargo.toml           # spot the misses
```
