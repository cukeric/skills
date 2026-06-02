---
name: babysit-ci
description: "Autonomously watch the current branch's CI after a push and drive it to green without you hand-watching it. On failure, dispatch the ci-debugger agent, apply the fix, re-push — stopping after 2 strikes on the same job. Trigger on 'babysit ci', 'watch ci', 'babysit prs', 'watch the deploy', 'drive ci to green', or /babysit-ci. Designed to run under /loop or self-paced."
---

# Babysit CI

Stop hand-watching `gh run watch`. This skill watches CI after a push and fixes failures
agentically, the way a senior dev pipelines work — push, walk away, come back to green.

> **Lean first.** Never pull full CI logs into the main context. The `ci-debugger` agent reads
> logs in its **own** window and returns only the diagnosis. You hold the loop state (which run,
> which job, strike count) — not the logs.

## Loop

1. **Find the run** for the current branch:
   ```bash
   gh run list --branch "$(git branch --show-current)" --limit 1 \
     --json databaseId,status,conclusion,workflowName,headSha
   ```
   Confirm `headSha` matches your latest pushed commit (else the run hasn't registered — wait).

2. **Still running** (`status != completed`): do NOT block. Re-check later.
   - Under `/loop` dynamic mode, `ScheduleWakeup` with a delay matched to the pipeline: poll a
     ~8-min CI at ~270s (stays inside the prompt-cache TTL), not every 60s. Longer if CI is slow.
   - Pass the SAME `/babysit-ci` prompt back so the next firing resumes the loop.

3. **Success** (`conclusion == success`): report ✅ (version/deploy if the run deploys), then
   **STOP** — do not reschedule. If the run includes a deploy job, do an independent live
   smoke (healthz + the changed surface) per the run-and-observe rule.

4. **Failure** (`conclusion == failure`): drive it to green —
   a. **Dispatch the `ci-debugger` agent** with the run id. It diagnoses in its own context
      (the 5 local-vs-CI root causes) and returns a file:line fix list — no logs in your window.
   b. **Remediate inline** (remediation is inline by default), then run the **pre-push gate**
      locally (it must pass before any push — the `pre-push-gate.sh` hook enforces this anyway).
   c. **Push** (route the mutating git through the `git-ci-lifecycle` agent if mid-orchestration).
      Increment the strike count **for that job**.
   d. Loop back to step 1 for the new run.

## The 2-strike bailout (non-negotiable)

If the **same CI job** fails again after a fix attempt — i.e. 2 failed pushes on one job — **STOP**.
Do not push attempt #3 unilaterally. Surface the ci-debugger diagnosis + both attempts to the
founder and ask for direction. (Config-fights burn CI minutes and tokens; a human decides.)
This mirrors the standing feedback rules: *fix-all-at-once* (one `--log-failed`, fix everything,
push once) and *CI config-fight bailout — 2 strikes*.

## Permissions / running unattended

Under default `ask` mode the loop will prompt on push/fix. For a truly hands-off overnight run,
launch the session in auto-mode **for that session only** — do not flip global `defaultMode`. The
2-strike bailout is the safety rail; auto-mode adds ~30–40% token cost, so use it for the babysit
loop, not everywhere.

## Ties into

- `ci-debugger` agent (diagnosis, own context) · `git-ci-lifecycle` agent (push/PR) ·
  `pre-push-gate.sh` hook · `/loop` (interval) · the `_wiki/gotchas.md` CI traps.
