# Cargo Workspace Reference

Deep reference for Cargo workspace patterns, hybrid TS/Rust monorepos, CI integration in polyglot repos, and dependency version management.

---

## Workspace Cargo.toml Patterns

### Minimal Workspace Root

```toml
[workspace]
members = [
    "packages/identity",
    "packages/semantic-firewall",
    "packages/constitutional-supervisor",
    "packages/cage",
]
resolver = "2"  # Mandatory — resolver v2 fixes feature flag unification bugs from v1

[workspace.dependencies]
# Pin all shared deps here. Crates inherit with { workspace = true }.
# Never specify a version in a member Cargo.toml if it's in workspace.dependencies.
biscuit-auth = "6"
ed25519-dalek = { version = "2", features = ["rand_core"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
```

**Key rules:**
- `resolver = "2"` is mandatory for any workspace with conditional features. Resolver v1 has known bugs where enabling a feature in one crate silently enables it in unrelated crates.
- Define a dependency in `[workspace.dependencies]` as soon as two crates share it. Single-crate deps can stay in the member `Cargo.toml`.
- Members reference workspace deps with `{ workspace = true }`:

```toml
# packages/identity/Cargo.toml
[dependencies]
biscuit-auth = { workspace = true }
ed25519-dalek = { workspace = true }
serde = { workspace = true }

# Crate-local dep — not in workspace (only this crate uses it)
wasm-bindgen-test = "0.3"  # dev-dependency, not shared
```

### Workspace-Level Feature Flags

Some dependencies need different features per crate. The workspace can define the base, and members add extras:

```toml
# Workspace: define base (no features to avoid enabling for all crates)
[workspace.dependencies]
tokio = { version = "1" }

# Member that needs full tokio
[dependencies]
tokio = { workspace = true, features = ["full"] }

# Member that only needs rt-multi-thread
[dependencies]
tokio = { workspace = true, features = ["rt-multi-thread", "macros"] }
```

### Exclude from Workspace

Generated code directories (wasmtime-compiled modules, wasm-pack output) must be excluded:

```toml
[workspace]
members = ["packages/*"]
exclude = [
    "packages/identity/pkg",       # wasm-pack output
    "target",                       # implicit but explicit is clear
]
```

---

## Hybrid TS/Rust Monorepo

### File Structure

```
project-root/
├── Cargo.toml              # Cargo workspace root
├── Cargo.lock              # Committed always
├── rust-toolchain.toml     # Pins Rust version
├── pnpm-workspace.yaml     # pnpm workspace root
├── turbo.json              # Turborepo task graph
├── package.json            # Root TS package
├── packages/
│   ├── identity/           # Rust crate (also pnpm package if exporting WASM)
│   │   ├── Cargo.toml
│   │   ├── package.json    # Optional: if publishing WASM via npm
│   │   └── src/
│   ├── cage/               # Pure Rust crate — NOT a pnpm package
│   │   ├── Cargo.toml
│   │   └── src/
│   └── ui/                 # TypeScript package — NOT a Cargo member
│       ├── package.json
│       └── src/
```

### pnpm-workspace.yaml — Exclude Rust-Only Packages

pnpm should not attempt to install packages from pure Rust crates:

```yaml
packages:
  - 'packages/*'
  # If some packages/ dirs are pure Rust with no package.json, pnpm ignores them automatically.
  # If a Rust crate has a package.json (for WASM npm publishing), include it here.
```

### turbo.json — Rust Tasks

Turborepo does not understand Cargo natively, but you can add Rust tasks as shell commands:

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "typecheck": {
      "dependsOn": ["^typecheck"],
      "outputs": []
    },
    "test": {
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"]
    },
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "pkg/**"]
    },
    "rust:check": {
      "cache": false,
      "outputs": []
    },
    "rust:test": {
      "dependsOn": ["rust:check"],
      "cache": false,
      "outputs": []
    },
    "rust:audit": {
      "cache": false,
      "outputs": []
    }
  }
}
```

Root `package.json` scripts to wire Turborepo to Cargo:

```json
{
  "scripts": {
    "rust:check": "cargo check --workspace",
    "rust:test": "cargo test --workspace",
    "rust:audit": "cargo audit",
    "rust:clippy": "cargo clippy --workspace -- -D warnings",
    "rust:fmt": "cargo fmt --check"
  }
}
```

**Important:** Do not put Rust compile steps in the main `build` Turborepo task — Cargo's own caching is independent of Turborepo's. Run Rust CI as a separate job or as a Turborepo task with `"cache": false`.

---

## CI Patterns for Rust in a Polyglot Monorepo

### Strategy: Separate Cargo Job

Keep Rust CI as a dedicated GitHub Actions job, not embedded in the TS pipeline. Reasons:
- Rust compiles are slow (cold: 5-20 min). They should not block TS tests that finish in 30s.
- `sccache` caching for Rust is orthogonal to Turborepo's remote cache for TS.
- Different matrix (OS, Rust channel) from TS.

### GitHub Actions Workflow

```yaml
# .github/workflows/rust.yml
name: Rust CI

on:
  push:
    paths:
      - 'packages/*/src/**'
      - 'packages/*/Cargo.toml'
      - 'Cargo.toml'
      - 'Cargo.lock'
      - 'rust-toolchain.toml'
      - '.github/workflows/rust.yml'
  pull_request:
    paths:
      - 'packages/*/src/**'
      - 'packages/*/Cargo.toml'
      - 'Cargo.toml'
      - 'Cargo.lock'
      - 'rust-toolchain.toml'

env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: 1

jobs:
  rust-ci:
    name: Check / Clippy / Test
    runs-on: ubuntu-latest
    timeout-minutes: 30   # Cold compiles on CI can be slow — set a hard limit

    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy
          targets: wasm32-unknown-unknown

      - name: Cache Cargo
        uses: Swatinem/rust-cache@v2
        with:
          shared-key: "rust-ci"

      - name: Cargo fmt check
        run: cargo fmt --all --check

      - name: Cargo check
        run: cargo check --workspace --all-targets

      - name: Cargo clippy
        run: cargo clippy --workspace --all-targets -- -D warnings

      - name: Cargo test
        run: cargo test --workspace
        timeout-minutes: 15   # Individual step timeout inside job timeout

      - name: Cargo audit
        run: |
          cargo install cargo-audit --locked 2>/dev/null || true
          cargo audit

  wasm-build:
    name: WASM Build
    runs-on: ubuntu-latest
    timeout-minutes: 20

    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown

      - name: Install wasm-pack
        run: curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

      - name: Cache Cargo
        uses: Swatinem/rust-cache@v2
        with:
          shared-key: "wasm-ci"

      - name: Build WASM (identity crate)
        run: wasm-pack build packages/identity --target web --release
```

### Caching Notes

- **`Swatinem/rust-cache`** is the standard. It caches `~/.cargo/registry`, `~/.cargo/git`, and `target/`. Invalidates on `Cargo.lock` changes.
- **Cold compile baseline:** ~8-15 min for a workspace with tokio, tonic, wasmtime. Cached: ~2-4 min.
- **Do not use `actions/cache` manually for Rust.** `Swatinem/rust-cache` handles the invalidation logic correctly; manual caching leads to stale `target/` artifacts causing subtle breakage.
- **`timeout-minutes: 30` on the job** prevents runaway compile hangs from consuming all CI minutes.

### Path Filters (Optimization)

Use `on.push.paths` and `on.pull_request.paths` to skip the Rust job when only TS files changed. This is important: a Rust cold compile for a commit that only changes a README is wasteful.

```yaml
on:
  push:
    paths:
      - '**/*.rs'
      - '**/Cargo.toml'
      - 'Cargo.lock'
      - 'rust-toolchain.toml'
```

---

## Dependency Version Bumping Workflow

Rust dependencies require manual major-version bumps because `cargo update` only updates within the semver-compatible range (patch + minor). Major bumps require editing `Cargo.toml`.

### Step-by-Step Major Version Bump

1. **Check current vs latest:**
   ```bash
   cargo search biscuit-auth          # shows latest on crates.io
   cargo outdated                     # requires: cargo install cargo-outdated
   ```

2. **Read the changelog before bumping.** Major versions always have breaking changes. Check `CHANGELOG.md` or the GitHub releases page.

3. **Update the workspace dep:**
   ```toml
   # Before
   biscuit-auth = "5"
   # After
   biscuit-auth = "6"
   ```

4. **Run cargo check and fix API breakage:**
   ```bash
   cargo check --workspace 2>&1 | head -50
   ```
   Fix compilation errors before running tests. Major API changes often involve:
   - Renamed types or methods
   - Consuming vs. borrowed API changes (e.g., biscuit-auth v6 consuming builders)
   - Feature flag renames
   - Error type restructuring

5. **Run the full test suite:**
   ```bash
   cargo test --workspace
   ```

6. **Run clippy** — new crate versions sometimes add new lints:
   ```bash
   cargo clippy --workspace -- -D warnings
   ```

7. **Commit `Cargo.toml` and `Cargo.lock` together** in a single commit:
   ```
   chore(deps): bump biscuit-auth 5 → 6
   ```

### Patch/Minor Updates (Cargo.lock Only)

```bash
# Update all deps within semver range
cargo update

# Update a specific dep
cargo update -p tokio

# Commit Cargo.lock after reviewing the diff
git diff Cargo.lock  # review what changed
git add Cargo.lock
git commit -m "chore(deps): cargo update $(date +%Y-%m-%d)"
```

### Security Advisory Response

When `cargo audit` flags a vulnerability:

1. **Identify the scope:** Is it in a direct dep or a transitive dep?
2. **If direct dep:** Update the version. If no fix exists, evaluate alternatives.
3. **If transitive dep:** Check if the parent dep has released a fix. Use `cargo update -p <vulnerable-crate>` to pull the patch if it's semver-compatible.
4. **If no fix exists:** Add to `audit.toml` with documented justification and a review date:
   ```toml
   # audit.toml
   [ignore]
   id = "RUSTSEC-2024-XXXX"
   reason = "Only triggered in features we don't use. Review by 2025-01-01."
   ```
5. **Never ignore CRITICAL advisories** without escalation and documentation.

### Cargo.lock Commit Policy

**Always commit `Cargo.lock`** — even for libraries. This is different from the npm ecosystem convention. Rationale:
- Reproducible builds in CI without `cargo update` surprises.
- Security: a CI job that runs `cargo update` implicitly could silently pull a compromised transitive dep.
- `Cargo.lock` is the single source of truth for what was tested and shipped.
