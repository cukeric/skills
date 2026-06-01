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

**Permanent fix — set the default once (`gh repo set-default`).** A third trigger of the
same wrong-repo symptom (2026-05-31): with **no default repo set at all**, an unqualified
`gh run list` resolved to a completely unrelated repo (showed foreign workflow names —
"ClawSweeper", "Mantis Telegram", a `codex/*` branch — none belonging to the project). It
briefly looked like a CI catastrophe; it was just gh guessing. Fix at the source so you
don't have to remember `--repo` every call:
```bash
gh repo set-default cukeric/<repo>      # run once per clone; binds unqualified gh to this repo
gh repo set-default --view              # confirm what's bound
```
Until that's set, `gh repo set-default --view` prints "no default remote repository has been
set" — treat that as the signal to either set it or pass `--repo OWNER/REPO` on every call.

**Also applies to non-submodule repos with multiple remotes.** A repo can have
`origin` (e.g. `cukeric/aigist`) AND `upstream` (e.g. a fork's source like
`openclaw/openclaw`). `gh` may resolve to `upstream` rather than `origin`,
returning a confusing 404 ("HTTP 404: not found … openclaw/openclaw"). The fix
is the same: `--repo OWNER/REPO` explicitly. Verify with `git remote -v` before
debugging.

```bash
# Wrong (resolves to upstream remote — wrong repo)
gh run view 25830161611

# Right
gh run view 25830161611 --repo cukeric/aigist
```

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

---

## 7. Changesets does not bump the root `package.json` when root is private and outside the workspace

**Symptom:**

```bash
$ pnpm changeset version
🦋  error Error: Found changeset v0-21-0 for package aigist which is not in the workspace
```

**Cause:** A typical pnpm workspace lists `packages/*` (and maybe `examples/*`, `website`) in `pnpm-workspace.yaml` but does NOT include the workspace root. The root `package.json` carries `"private": true` and a top-level project name used only as the project identifier, not a published artefact. Changesets rejects any name in the frontmatter that is not in the workspace.

**Why this hits:** Older changesets in the same repo sometimes listed the root name (e.g. `"aigist": minor`) and worked because the workspace config differed at the time. After a workspace reorganisation the same shape breaks. The root version is now decoupled from the changeset-driven workspace bump.

**Fix:**

1. **Remove the root name from the changeset frontmatter.** Only list real workspace packages.
2. **Bump the root `package.json` version manually** to match the headline release version.
3. **Re-run the version-badge script** — the `version-packages` npm script typically chains `changeset version && node scripts/update-version-badge.js`; the badge reads the root `package.json` so it now picks up the manual bump.

```bash
# 1. Edit .changeset/<name>.md: remove "<root-name>": minor line
# 2. Manually edit package.json: "version": "0.21.0"
# 3. Run badge update
node scripts/update-version-badge.js
```

**Alternative — add root to the workspace** by listing `.` in `pnpm-workspace.yaml`:

```yaml
packages:
  - "."
  - "packages/*"
```

Requires the root to have a valid `name` (most already do) and no name collision with a package. Test with a throwaway changeset before relying on it.

---

## 8. Workspace package versions drift across releases

**Symptom:** After running `pnpm changeset version`, different packages report different versions even though all received `minor` in the changeset (e.g. cli at 0.22.0, core at 0.21.0).

**Cause:** Packages had pre-existing drift from earlier non-uniform changesets. A minor bump applied to a package already at 0.21.0 produces 0.22.0; the same bump on a package still at 0.20.5 produces 0.21.0. Changesets doesn't reconcile — it bumps from each package's current version.

**Fix options:**

- **Accept the drift** for non-published packages (private workspace utilities). Consumers don't see the version number.
- **Synchronise via Changesets `fixed`** in `.changeset/config.json` for packages that must release together:
  ```json
  { "fixed": [["@app/core", "@app/cli", "@app/dashboard"]] }
  ```
  Packages in a `fixed` group always bump to the same version. Removes the option to release independent patches, so use sparingly.
- **One-time manual reset** before the next release: edit all `package.json` versions to match, commit, continue with `pnpm changeset` as normal.

First option is correct for internal monorepos. Second is correct for public package suites where consumer trust depends on version coherence (e.g. a CLI + runtime + UI library shipped together).

---

## 9. Post-`changeset version` biome-format violations on touched `package.json` files

After `pnpm changeset version` rewrites `package.json` files, Biome may flag whitespace/format differences on the bumped files:

```
✘ Formatter would have printed the following content
  ./packages/cli/package.json
  ./packages/identity/package.json
```

This is harmless but fails CI / pre-push gate. Run `pnpm exec biome check --write .` immediately after `version-packages` and commit the format fixes as either a follow-up `style(biome):` commit or fold them into the release commit. Add this to the standard release runbook.

---

## 10. Renaming a project / brand changeover across a monorepo

A full project rename (a rebrand, a scope change) is mostly a scripted bulk
find/replace, but four mechanics break silently if done naïvely. Verified on a
real `aigist → eloryn` zero-residual rebrand (358 files, git submodule of a
`_dev` superproject).

### 10.1 Renaming a submodule folder — do it from the superproject

A submodule's folder is **not** renamed with a plain `mv` — that leaves the
superproject with a deleted submodule at the old path and an untracked dir at
the new path (broken state). Rename it from the **superproject**:

```bash
cd /path/to/superproject
git mv _projects/oldname _projects/newname
```

`git mv` moves the working tree, the gitlink, and rewrites the submodule's
`.git` file pointer. The submodule's own history (`.git/modules/.../`) is
untouched and the submodule keeps working at the new path.

### 10.2 `git mv` updates the submodule `path` but NOT the section header

After `git mv _projects/old _projects/new`, `.gitmodules` ends up with:

```ini
[submodule "_projects/old"]      # ← section header NOT renamed
	path = _projects/new          # ← path WAS updated
	url = git@github.com:org/old.git
```

The stale section header is cosmetically wrong and inconsistent. **Fix it by
hand** (edit `.gitmodules`: `[submodule "_projects/new"]`).

### 10.3 `.git/config` keeps the old submodule section → `git submodule status` shows `-`

`git mv` does not touch the **local** `_dev/.git/config`, which still has
`[submodule "_projects/old"]`. Symptom: `git submodule status _projects/new`
shows a leading `-` (reads as "not initialized") even though the submodule
works fine. Fix the local config:

```bash
git config --rename-section 'submodule._projects/old' 'submodule._projects/new'
```

Then `git submodule status` shows `+<sha> _projects/new` — healthy. (The `+`
just means the submodule HEAD is ahead of the recorded gitlink, normal after
committing inside the submodule.)

> The submodule `url` stays pointed at the old GitHub repo until the GitHub
> repo itself is renamed — keep them in step. GitHub keeps a permanent redirect
> on a repo rename, so an out-of-date `url` still fetches; update it for
> cleanliness when the repo is renamed.

### 10.4 Claude Code project memory is keyed to the cwd path

`~/.claude/projects/<encoded-cwd>/memory/` is keyed to the project's absolute
path (encoding: every `/` and `_` → `-`). Renaming the project folder orphans
that memory dir — the next session opens at the new path, derives a new dir
name, and finds no `project_status.md` / `MEMORY.md`. **Carry the memory
across** as part of the rename:

```bash
cp -r ~/.claude/projects/-...-projects-oldname/memory \
      ~/.claude/projects/-...-projects-newname/memory
```

Copy (don't move) — the old dir holds the live session transcript. Also rename
`~/.claude/scratchpads/oldname` and any `_dev/_memory/oldname` session-memory dir.

### 10.5 Dual-read env shim — rename env vars without a downtime window

Renaming an env var (`OLD_FOO` → `NEW_FOO`) that a running production server
already has set is a deploy hazard: ship the renamed code and it reads `NEW_FOO`
(undefined on the un-migrated server) → breakage. The fix is a **dual-read
shim** — the code reads the new name and falls back to the old:

```ts
/** Reads NEW_<suffix>, falling back to the legacy OLD_<suffix>. Remove the
 *  fallback one release after the production env is renamed. */
export function envVar(suffix: string, env = process.env): string | undefined {
  return env[`NEW_${suffix}`] ?? env[`OLD_${suffix}`];
}
```

Ship the rename + shim; rename the production env values on the next deploy
window; then, **one release later**, delete the fallback. Flag every shim
call-site with a removal comment so the cleanup is greppable. This decouples the
code rename from the production-env rename — neither has to be atomic with a
deploy.

