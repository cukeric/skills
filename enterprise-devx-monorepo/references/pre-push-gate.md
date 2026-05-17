# The Pre-Push Gate — MANDATORY Before Every First Push

**This is the single most important rule in this skill. It is not optional. It is not
skippable.**

Before the FIRST `git push` on any new monorepo, or after ANY change to
`.github/workflows/`, run this exact sequence locally. Do not push until all steps
pass with zero errors.

```bash
# 1. Generate lockfile (CI uses --frozen-lockfile; missing lockfile = total failure)
pnpm install

# 2. Fix ALL lint + format issues — MUST use --unsafe to catch useLiteralKeys, noConsoleLog, etc.
#    biome check --write (without --unsafe) silently skips unsafe rules — CI will still fail!
pnpm exec biome check --write --unsafe .
git add -A  # ← RE-STAGE files Biome modified (critical — Biome changes must be committed)

# 3. Catch all type errors before CI
pnpm turbo run typecheck

# 4. Confirm tests pass (catches missing --passWithNoTests on stub packages)
pnpm turbo run test

# 5. Audit stub packages for script correctness
# Any package with "typecheck": "tsc --noEmit" MUST have a tsconfig.json
# Rust/native stubs must use "echo 'N/A — [lang] build in M[n]'" instead

# 6. Dispatch code-reviewer agent to audit CI config BEFORE pushing
# Dispatch: code-reviewer with prompt:
#   "Review all .github/workflows/*.yml for: job dependency graph, caching,
#    --frozen-lockfile usage, secret references, branch triggers, turbo.json
#    pipeline completeness, and package script correctness. Report issues with
#    severity CRITICAL/HIGH/MEDIUM/LOW."
# Fix ALL issues reported at HIGH or above before pushing.
```

**All 6 must complete before pushing.** One clean push beats five fix commits.

> **Step 2 note:** `biome check --write` (without `--unsafe`) only applies safe fixes.
> Rules like `useLiteralKeys`, `noConsoleLog`, and `noUnusedVariables` are "unsafe" and
> silently skipped. Always use `--unsafe` in the pre-push gate. After Biome runs, always
> `git add -A` to re-stage its changes — Biome-modified files that aren't committed will
> cause CI to fail with the exact errors you just "fixed" locally.

## Build / CI / infra changes — also run the clean-checkout simulation

Steps 1–6 verify code. They do **not** catch "passes locally, fails CI" failures caused
by local machine state CI lacks (stale `dist/`, turbo cache, `~/.config` key files,
ambient env). For any change to build scripts, CI workflows, Dockerfiles, or
service-dependent tests, additionally run the clean-checkout simulation in
`ci-local-parity.md` before pushing.

## SSH Remote — Always Use for Repos with Workflow Files

GitHub HTTPS OAuth tokens require the `workflow` scope to push `.github/workflows/`.
Unless that scope is confirmed, always use SSH:

```bash
git remote set-url origin git@github.com:owner/repo.git
```

Set this when initializing the repo. Do not wait until a push is rejected.

## After the push

Watch the run to its conclusion — `gh run watch <id> --exit-status`. Note that
`gh run watch --exit-status` returns 0 on `ci-gate` success even if a *later* deploy
job fails; confirm the deploy job's own conclusion separately.
