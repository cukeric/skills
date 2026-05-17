# CI / Local Parity — "Passes Locally, Fails CI"

The single most expensive failure class in a monorepo: a change passes every local
gate, gets pushed, and CI fails. Each cycle costs a full CI run (~8 min) plus a
context switch. This reference exists because one session burned **three consecutive
CI cycles** on the same root cause — local machine state that CI does not have.

> **The rule:** Local "green" is not evidence CI will be green. CI runs from a
> **clean checkout**. Before pushing a build/CI/infra change, reproduce the clean
> state locally and re-run the gates there.

---

## 1. Why local lies

A developer machine accumulates state that a fresh CI runner never has:

| Local-only state | How it masks a failure |
|---|---|
| `dist/` build artifacts (gitignored) | An import resolves locally because a stale `dist/` exists; CI has none. |
| `.turbo/` cache | `turbo test` replays a cached "pass" instead of re-running. |
| `~/.config/<app>/*`, OS keychain entries | A key/credential file from a prior run satisfies a load-only lookup; CI has nothing. |
| Ambient env vars in your shell profile | Code reads a var that is set on your machine and unset in CI. |
| `node_modules/` resolved from a prior `pnpm install` | Lockfile drift hidden until CI runs `--frozen-lockfile`. |
| A package built once by hand (`tsc`, `wasm-pack`) | A dependent resolves it; CI never ran that manual build. |

Each of these produced a real CI failure. They share one fix: **test from clean.**

---

## 2. The clean-checkout simulation (run before pushing build/CI/infra changes)

```bash
# 1. Purge every build artifact + cache the repo gitignores.
rm -rf packages/*/dist packages/*/.turbo .turbo
rm -rf packages/*/coverage

# 2. Move aside any ambient state the code might read (key files, configs).
#    Example — an app that loads a key from ~/.config:
mv ~/.config/<app>/<key-file> /tmp/keyfile.bak 2>/dev/null || true

# 3. Reproduce CI's build order EXACTLY (see §3) — do not rely on turbo `^build`
#    if any package has a non-emitting build script.

# 4. Run the gates with --force so turbo cannot replay a cached pass:
pnpm turbo run typecheck
pnpm turbo run test --force
pnpm exec biome ci .          # `biome ci` is stricter than `biome check`

# 5. Restore the ambient state you moved aside.
mv /tmp/keyfile.bak ~/.config/<app>/<key-file> 2>/dev/null || true
```

If a DB / service is involved, also do §5.

---

## 3. The non-emitting `build` script trap

A workspace package whose `build` script is a **no-op** (common for Rust/WASM
packages where the real build is `wasm-pack` in a separate CI step):

```jsonc
// packages/identity/package.json
"scripts": { "build": "echo 'wasm-pack runs in CI'", "build:ts": "tsc -p tsconfig.json" }
```

Turbo's `^build` runs the no-op `build`, so the package's `dist/` is **never
produced** in the turbo graph. Anything that imports a *subpath* of that package
(`@scope/pkg/submodule` resolving to `./dist/submodule.js` via the `exports` map)
then fails in CI with `TS2307: Cannot find module`. It passes locally only because
a stale `dist/` is sitting there from a manual build weeks ago.

**Fixes, best first:**

1. **Make `build` actually emit** — if `tsc` does not need the WASM artifact
   (verify: does any compiled file `import` the WASM bindings at type-check time?),
   set `build` to the real `tsc` build so turbo's `^build` produces `dist/`.
2. **Build it explicitly in CI**, in dependency order, before the gate that needs it
   — mirror what the Dockerfile already does:
   ```yaml
   - name: Build identity TS (turbo `build` is a no-op; needs core first)
     run: |
       pnpm --filter @scope/core build
       pnpm --filter @scope/identity build:ts
   ```
   Build the dependency *before* the dependent — a manual filtered build does **not**
   get turbo's topological ordering.
3. Point the `exports` subpath at **source** (`./src/x.ts`) so no build is needed —
   only if every consumer transpiles source (most monorepo dev paths do; a
   `serverExternalPackages` runtime `require()` does not).

Whatever you choose, **a package consumed as `dist/` must have its `dist/` produced
by the same command CI runs** — not by a developer's ambient filesystem.

---

## 4. Migration / setup scripts that need a build

A `package.json` script like `"migrate": "node ./dist/apply-migration.js"` fails in
CI if it runs **before** the package is built. CI step ordering is explicit — there
is no `^build`. Either:

- build the package first in the same step (`pnpm turbo run build --filter=@scope/pkg && pnpm --filter @scope/pkg migrate`), or
- run the equivalent from source (`tsx`/`vitest`), or
- **let the test suite do its own setup** — if the integration suite already applies
  the migration in `beforeAll()`, a separate CI migrate step is redundant *and* a
  failure surface. Delete it.

---

## 5. Service-dependent tests (DB, queue, cache)

Integration tests gated on a real service (`describe.skipIf(!process.env.DB_URL)`)
**silently skip** locally when the dev machine has no Docker — so a local "all green"
proves nothing about them. CI runs them via a service container, so CI is the first
place they actually execute.

Before pushing a change that touches such tests, run them against a real service
yourself — do not let CI be the first run:

```bash
# Spin a throwaway service (here: on a remote host with Docker; tunnel it back).
ssh host 'docker run -d --name verify -e POSTGRES_PASSWORD=test -p 127.0.0.1:55432:5432 postgres:16-alpine'
ssh -fNL 55432:127.0.0.1:55432 host
DB_URL='postgresql://...@localhost:55432/...' pnpm --filter @scope/pkg test
ssh host 'docker rm -f verify'   # clean up
```

Match the CI service's image tag exactly (`postgres:16-alpine` ≠ `postgres:16`).
Never point a self-migrating test suite at a database with real data — its
`beforeAll()` will `DROP` tables.

---

## 6. Tests must not depend on ambient machine state

A test that "passes" because of a file in `~/.config`, an OS keychain entry, or a
shell env var is not passing — it is **deferring its failure to CI**. When a
function is changed to **fail-closed** (e.g. a key loader that used to auto-generate
now throws if the key is absent), every test that relied on the old lenient
behaviour breaks — but only in a clean environment.

**Rule:** a test provisions everything it needs, in-process, and tears it down:

```ts
beforeEach(() => { process.env.APP_KEY = "test-fixed-value"; });
// biome-ignore lint/performance/noDelete: unset an env var (assigning undefined stores "undefined")
afterEach(() => { delete process.env.APP_KEY; });
```

Verify by running the suite with the ambient state removed (§2 step 2). If a test
fails only then, it was never self-contained.

---

## 7. Checklist — before pushing a build / CI / infra change

- [ ] `rm -rf` all `dist/` + `.turbo/` caches; ambient key/config files moved aside
- [ ] CI's exact build order reproduced locally (esp. packages with no-op `build`)
- [ ] `pnpm turbo run typecheck` + `test --force` + `biome ci .` green from clean
- [ ] Service-dependent tests run against a real service matching the CI image tag
- [ ] No test relies on `~/.config`, keychain, or shell env not set by the test itself
- [ ] CI step ordering checked: every script runs *after* the build it depends on
- [ ] After push: watch the run to conclusion — `gh run watch <id> --exit-status`
