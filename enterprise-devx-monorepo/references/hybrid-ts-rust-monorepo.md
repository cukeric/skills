# Hybrid TypeScript/Rust Monorepo Patterns

Applies when a single repo hosts both pnpm workspaces (TypeScript) and a Cargo workspace (Rust). Both toolchains coexist under the same `packages/` directory. Each has its own workspace manifest at the repo root.

---

## 1. Directory Structure

```
repo/
├── packages/
│   ├── core/                        # TypeScript — shared types, schemas, utilities
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── src/
│   ├── circuit-breaker/             # TypeScript — resilience primitives
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── src/
│   ├── identity/                    # Rust → WASM (wasm-bindgen)
│   │   ├── Cargo.toml
│   │   ├── package.json             # ← stub required for Turbo
│   │   └── src/
│   ├── cage/                        # Rust — wasmtime runtime host
│   │   ├── Cargo.toml
│   │   ├── package.json             # ← stub required for Turbo
│   │   └── src/
│   ├── semantic-firewall/           # Rust — hyper reverse proxy
│   │   ├── Cargo.toml
│   │   ├── package.json             # ← stub required for Turbo
│   │   └── src/
│   └── constitutional-supervisor/   # Rust — tonic gRPC service
│       ├── Cargo.toml
│       ├── package.json             # ← stub required for Turbo
│       └── src/
├── Cargo.toml                       # Cargo workspace root
├── Cargo.lock                       # MUST be committed (binary/application workspace)
├── pnpm-workspace.yaml              # Lists ALL packages (TS + Rust stubs)
├── turbo.json                       # Runs typecheck/test/build across all packages
├── package.json                     # Root devDependencies and scripts
└── tsconfig.base.json               # Shared TS config extended by TS packages
```

---

## 2. Dual Workspace Configuration

### pnpm-workspace.yaml

Lists **all** packages, including Rust crates. Rust crates only participate via their `package.json` stubs — pnpm never touches their Cargo manifests.

```yaml
packages:
  - "packages/*"
```

This single glob picks up all subdirectories under `packages/`, whether they are TypeScript or Rust packages.

### Cargo.toml (root workspace)

Lists **only Rust crates**. TypeScript packages are invisible to Cargo.

```toml
[workspace]
members = [
  "packages/identity",
  "packages/cage",
  "packages/semantic-firewall",
  "packages/constitutional-supervisor",
]
resolver = "2"

# Shared dependency versions across all Rust crates
[workspace.dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
anyhow = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

**Rule:** Never add TypeScript packages as Cargo workspace members. Never add Rust crate paths to `pnpm-workspace.yaml` with a different glob that would exclude them — the `packages/*` glob applies to both.

---

## 3. package.json Stubs for Rust Crates

Every Rust crate needs a `package.json` so Turborepo can include it in the task graph. These stubs must exit 0 on every script — they delegate real work to Cargo in a separate CI job.

**Stub format for a Rust crate:**

```json
{
  "name": "@scope/identity",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "typecheck": "echo 'Rust crate — typecheck runs via cargo check in CI'",
    "test": "echo 'Rust crate — tests run via cargo test in CI'",
    "build": "echo 'Rust crate — wasm-pack build runs in CI'",
    "clean": "echo 'Rust crate — cargo clean runs in CI'"
  }
}
```

**Per-crate build script variations:**

| Crate | Build stub | Reason |
|-------|-----------|--------|
| `identity` (WASM) | `echo 'wasm-pack build runs in CI'` | Needs wasm32 target + wasm-pack |
| `cage` (wasmtime host) | `echo 'cargo build runs in CI'` | Native binary |
| `semantic-firewall` (hyper proxy) | `echo 'cargo build runs in CI'` | Native binary |
| `constitutional-supervisor` (gRPC) | `echo 'cargo build runs in CI'` | Native binary, needs protoc |

**Rules:**
- All stubs must exit 0 — never `exit 1` or call `cargo` directly from the stub.
- Keep `"private": true` on all Rust crate stubs — they are never published to npm.
- Version must match the crate's `Cargo.toml` version for tracking purposes.
- Never run `pnpm install` inside a Rust crate directory — stubs have no npm dependencies.

---

## 4. Turborepo Integration

Turborepo orchestrates the full task graph across all packages, using echo stubs for Rust crates. This keeps Turbo from failing while preserving dependency ordering.

### turbo.json

```json
{
  "$schema": "https://turbo.build/schema.json",
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", "*.wasm", "pkg/**"]
    },
    "typecheck": {
      "dependsOn": ["^build"]
    },
    "test": {
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"]
    },
    "clean": {
      "cache": false
    }
  }
}
```

**Key decisions:**
- `outputs` includes `*.wasm` and `pkg/**` so wasm-pack artifacts are cached by Turbo (when real build runs).
- `typecheck` depends on `^build` because TypeScript packages may import from other packages' `dist/`.
- Rust stub tasks produce no real outputs — Turbo will warn about empty outputs. This is harmless.
- Never add `cargo-test` or `cargo-check` as a Turbo pipeline task. Rust CI runs outside Turbo.

### Turbo output warnings on Rust stubs

When Turbo runs a stub `build` task, it may log:

```
• packages/cage:build: cache miss, executing...
• packages/cage:build: echo 'Rust crate — cargo build runs in CI'
• packages/cage:build: WARNING: no outputs were cached
```

This is expected and harmless. Do not add suppression flags — the warnings confirm the stubs ran.

---

## 5. CI Patterns

Split CI into two independent jobs: one for TypeScript (pnpm + Turbo), one for Rust (cargo). Both must pass before merge. They run in parallel.

### GitHub Actions — TypeScript job

```yaml
jobs:
  ts-ci:
    name: TypeScript CI
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: "pnpm"

      - name: Restore Turbo cache
        uses: actions/cache@v4
        with:
          path: .turbo
          key: turbo-${{ runner.os }}-${{ github.sha }}
          restore-keys: turbo-${{ runner.os }}-

      - run: pnpm install --frozen-lockfile

      - run: pnpm turbo run typecheck
      - run: pnpm turbo run test
      - run: pnpm turbo run build
```

### GitHub Actions — Rust job

```yaml
  rust-ci:
    name: Rust CI
    runs-on: ubuntu-latest
    timeout-minutes: 20   # wasmtime cold compile: ~3-5 min; full tree: up to 12 min
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown   # required for identity crate

      - name: Cache cargo registry + build artifacts
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target/
          key: cargo-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}
          restore-keys: cargo-${{ runner.os }}-

      - name: Install wasm-pack
        run: curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

      - name: Install protoc (for tonic/gRPC crates)
        run: sudo apt-get install -y protobuf-compiler

      - name: cargo check (all crates)
        run: cargo check --workspace

      - name: cargo test (all crates)
        run: cargo test --workspace
        timeout-minutes: 15

      - name: wasm-pack build (identity crate)
        run: wasm-pack build packages/identity --target web

  ci-gate:
    name: CI Gate
    needs: [ts-ci, rust-ci]
    runs-on: ubuntu-latest
    steps:
      - run: echo "All CI jobs passed"
```

**Timeout rationale:**
- `wasmtime` has 160+ transitive dependencies. A cold compile (empty cache) takes 8–12 minutes on `ubuntu-latest`.
- Set `timeout-minutes: 20` on the Rust job, `timeout-minutes: 15` on the `cargo test` step.
- GitHub Actions default timeout is 6 hours — always set explicit timeouts for Rust jobs.
- Cache hit on `target/` reduces subsequent runs to 2–3 minutes.

**Required secrets / env for Rust CI:**
- No secrets needed for pure cargo test runs.
- If `constitutional-supervisor` tests make network calls, mock them in tests — never require external services in CI.

---

## 6. Dependency Management

TypeScript and Rust dependencies are fully independent systems. Never cross-reference them.

### TypeScript packages

- Dependencies declared in each package's `package.json`
- Shared devDependencies (TypeScript, Vitest, Biome) in root `package.json`
- Workspace protocol for cross-package TS deps: `"@scope/core": "workspace:*"`

**`@types/node` — Required for Node built-ins in strict ESM TypeScript packages:**

New packages that use `node:crypto`, `node:fs`, `process.env`, or other Node.js built-ins in strict TypeScript mode (`"moduleResolution": "bundler"` or `"node16"`) will fail `tsc --noEmit` with:

```
error TS2307: Cannot find module 'node:crypto' or its corresponding type declarations.
error TS2304: Cannot find name 'process'.
```

Fix: add `@types/node` to the package's own `devDependencies` (not just the root):

```json
// packages/compliance/package.json
{
  "devDependencies": {
    "@types/node": "^20.0.0"
  }
}
```

Then run `pnpm install` to update the lockfile before attempting `pnpm turbo typecheck`.

### Rust crates

- Crate-specific dependencies in each `packages/<crate>/Cargo.toml`
- **Workspace dependency pattern** — declare shared versions in root `Cargo.toml` `[workspace.dependencies]`, then inherit in crates:

```toml
# packages/cage/Cargo.toml
[package]
name = "cage"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { workspace = true }          # version inherited from workspace
serde = { workspace = true }
wasmtime = "20"                       # crate-specific, not shared
```

```toml
# packages/constitutional-supervisor/Cargo.toml
[package]
name = "constitutional-supervisor"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { workspace = true }
tonic = "0.11"                        # crate-specific
prost = "0.12"                        # crate-specific
```

**Rules:**
- Use `{ workspace = true }` for any dependency shared by 2+ crates.
- Never pin exact versions in individual `Cargo.toml` when the version is managed in `[workspace.dependencies]`.
- Crate-specific dependencies use standard semver ranges in the crate's own `Cargo.toml`.

---

## 7. Changesets and Version Management

Two separate versioning systems. They must stay synchronized manually.

### TypeScript packages — Changesets

Changesets manages TypeScript package versions automatically:

```bash
# Add a changeset for a TS package change
pnpm changeset

# CI release.yml runs this to bump versions and generate CHANGELOG
pnpm changeset version

# Publish to npm (or internal registry)
pnpm changeset publish
```

Only include TypeScript packages in changesets. Never add Rust crates to `.changeset/*.md` files.

### Rust crates — Manual versioning

Rust crate versions are managed manually in each crate's `Cargo.toml`. There is no equivalent of Changesets for Cargo workspaces in this setup.

**Synchronization rule:** When a Rust crate reaches a version milestone, update its `package.json` stub version to match:

```toml
# packages/identity/Cargo.toml
[package]
version = "0.3.1"
```

```json
// packages/identity/package.json
{
  "version": "0.3.1"
}
```

This is for tracking only — the stub is never published to npm. Keep them in sync to avoid confusion when reading `pnpm list` or Turbo dependency graphs.

**CHANGELOG for Rust crates:** Maintain a manual `CHANGELOG.md` per crate, or use `git-cliff` (`cargo install git-cliff`) to generate it from conventional commits filtered to each crate's path.

---

## 8. Common Gotchas

### Cargo.lock must be committed

This repo is a **workspace of binaries and applications**, not a library. Cargo.lock captures the exact resolved dependency tree including `wasmtime`, `tonic`, and other large crate trees. Committing it:
- Makes CI reproducible
- Prevents supply-chain surprises from upstream yanks or breaking changes
- Speeds up CI cache restoration (known exact versions)

Never add `Cargo.lock` to `.gitignore`. If it was previously ignored, remove it:

```bash
git rm --cached Cargo.lock
# Remove Cargo.lock from .gitignore
git add Cargo.lock .gitignore
git commit -m "chore: track Cargo.lock (binary workspace)"
```

### Turbo output warnings for Rust stub tasks

When Turbo runs stub `build`/`typecheck`/`test` tasks on Rust crates, it logs warnings about no cached outputs. This is expected — the stubs produce nothing for Turbo to cache. Do not attempt to suppress these with `"cache": false` on every Rust task unless you want to prevent Turbo from ever caching those task nodes.

### wasm-pack build needs separate CI step with wasm32 target

The `identity` crate compiles to WASM via `wasm-bindgen`. This requires:
1. The `wasm32-unknown-unknown` target installed: `rustup target add wasm32-unknown-unknown`
2. `wasm-pack` installed (not available by default on `ubuntu-latest`)
3. A separate CI step — do not fold this into `cargo build --workspace` (that will fail for the wasm32 target without explicit `--target` flags)

Keep the wasm-pack step separate and after `cargo test --workspace`.

### cargo test timeout for large crate trees

`wasmtime` brings in 160+ transitive dependencies. On a cold CI runner (no cache):
- `cargo check --workspace`: 3–5 minutes
- `cargo test --workspace` (including compile): 8–12 minutes
- With warm cache: 1–2 minutes

Always set `timeout-minutes: 20` on the Rust CI job and `timeout-minutes: 15` on the `cargo test` step. GitHub's default 6-hour timeout will not help you diagnose hangs.

### pnpm install picks up Rust package.json stubs

Running `pnpm install` at the repo root will install dependencies for all `package.json` files it finds, including Rust stubs. Since stubs have no `dependencies` or `devDependencies`, this is harmless — pnpm creates a symlink in `node_modules/@scope/<crate-name>` pointing to the stub directory. This symlink is used by Turbo for task graph resolution and can be safely ignored.

### protoc required for tonic (gRPC) crates

The `constitutional-supervisor` crate uses `tonic` + `prost` for gRPC, which requires the Protocol Buffers compiler (`protoc`) at build time. This is **not** installed by default on `ubuntu-latest`. Always add:

```yaml
- name: Install protoc
  run: sudo apt-get install -y protobuf-compiler
```

Before any `cargo build` or `cargo test` step that touches gRPC crates.

### AI agent config files must not be committed (`CLAUDE.md`, `.claude/`)

`CLAUDE.md` and `.claude/` are AI agent configuration — session memory, hooks, project context. They are **not part of the public codebase** and must never be committed.

Add to every project's `.gitignore` at init time:

```gitignore
# AI agent configuration — not part of the public codebase
CLAUDE.md
.claude/
```

If `CLAUDE.md` was already committed, untrack it without deleting it:

```bash
git rm --cached CLAUDE.md
git rm --cached -r .claude/   # if .claude/ was also committed
git add .gitignore
git commit -m "chore: exclude AI agent config from repo"
```

**Why:** CLAUDE.md contains project-specific AI instructions and may reference internal systems, credentials patterns, or architectural details that should not be public. The `.claude/` directory contains session state and hook scripts specific to the developer's local environment.

**CLAUDE.md filename is preserved** — Claude Code requires this exact filename to discover project context. Only its git tracking is removed, not the file itself.

### tsconfig.json must not exist in Rust crate directories

Rust crate package.json stubs use `echo` for `typecheck`. If a `tsconfig.json` accidentally exists in a Rust crate directory (e.g., copied from a TS package), Turbo may attempt `tsc --noEmit` if scripts are misconfigured. Verify no `tsconfig.json` files exist in Rust package directories:

```bash
# Should return no results for Rust crate dirs
ls packages/identity/tsconfig.json packages/cage/tsconfig.json 2>&1
```

---

## WASM Build — getrandom js Feature

Any Rust crate compiled to `wasm32-unknown-unknown` with `wasm-pack` that uses `rand`, `biscuit-auth`, `ed25519-dalek`, or any other crate that transitively depends on `getrandom 0.2` **MUST** include:

```toml
# In the WASM crate's Cargo.toml
[target.'cfg(target_arch = "wasm32")'.dependencies]
getrandom = { version = "0.2", features = ["js"] }
```

Without this, `wasm-pack build --target nodejs` fails with a `RuntimeError: unreachable` or linker error. The `js` feature enables `getrandom` to use Node.js `crypto` module for entropy on `wasm32-unknown-unknown` targets.

---

## CI Canary Scan — Adding Authorized Exclusions

If a project uses canary token patterns for integrity checking (e.g., `5af3-canary-SOUL-{uuid}`), any CI canary grep scan may false-positive on:
- E2E smoke tests that send a known canary UUID to verify detection works
- Unit test fixtures that contain canary patterns as test data

**To add an authorized exclusion**, append `--exclude="<filename>"` to the grep command in the CI canary scan step:

```yaml
# Before — will flag e2e-smoke.ts
SOUL_CANARY=$(grep -r "5af3-canary-SOUL" . \
  --include="*.ts" \
  --exclude="schemas.ts" \
  --exclude="schemas.test.ts" \
  -l 2>/dev/null || true)

# After — e2e-smoke.ts is an authorized test fixture
SOUL_CANARY=$(grep -r "5af3-canary-SOUL" . \
  --include="*.ts" \
  --exclude="schemas.ts" \
  --exclude="schemas.test.ts" \
  --exclude="e2e-smoke.ts" \    # ← authorized: sends known UUID to verify detection
  -l 2>/dev/null || true)
```

**Document the exclusion** in the CI YAML with a comment explaining WHY the file is authorized to contain canary patterns.

---

## Quick Reference: Hybrid Monorepo Checklist

```
□ pnpm-workspace.yaml uses "packages/*" glob (covers TS + Rust stubs)
□ Cargo.toml [workspace] lists only Rust crate paths
□ Every Rust crate has a package.json stub with echo scripts
□ Rust stub scripts all exit 0 (no cargo invocations)
□ turbo.json outputs include *.wasm and pkg/** for WASM crate
□ Cargo.lock is committed (not in .gitignore)
□ CI has separate ts-ci and rust-ci jobs running in parallel
□ rust-ci job has timeout-minutes: 20
□ rust-ci installs wasm32-unknown-unknown target
□ rust-ci installs wasm-pack before wasm-pack build step
□ rust-ci installs protoc before building gRPC crates
□ cargo test --workspace step has timeout-minutes: 15
□ ci-gate job depends on both ts-ci and rust-ci
□ [workspace.dependencies] in root Cargo.toml for shared dep versions
□ Rust crate Cargo.toml versions match package.json stub versions
□ No tsconfig.json files exist in Rust crate directories
□ WASM crate has getrandom = { features = ["js"] } for wasm32 target
□ biome check --write --unsafe run before push (not just --write)
□ Biome-modified files re-staged and committed before git push
```
