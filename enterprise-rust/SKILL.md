---
name: enterprise-rust
description: Explains how to create, design, modify, or optimize Rust code with enterprise standards. Trigger on ANY mention of rust, cargo, crate, workspace, Cargo.toml, Cargo.lock, rustc, rustup, wasm, wasmtime, wasm-bindgen, wasm-pack, biscuit, biscuit-auth, tonic, grpc, hyper, ed25519, ed25519-dalek, tokio, tracing, thiserror, anyhow, serde, zeroize, sha2, aes-gcm, constant-time, unsafe, cdylib, rlib, proc-macro, build.rs, tonic-build, prost, protobuf, cross-compilation, target triple, cargo audit, cargo test, cargo build, cargo check, cargo clippy, cargo fmt, rustfmt, clippy, lifetimes, ownership, borrow checker, async rust, futures, tokio runtime, axum, actix, or any request to build Rust libraries, binaries, WASM modules, gRPC services, cryptographic primitives, or sandboxed runtimes. Also trigger when a Cargo.toml or Cargo.lock file is mentioned, when a crate is being added or updated, or when the project contains a rust-toolchain.toml file.
---

# Enterprise Rust Development Skill

Every Rust crate created or modified using this skill must meet enterprise-grade standards for security, memory safety, data integrity, and performance — in that priority order. Rust's ownership model eliminates entire classes of bugs, but it does not eliminate logic errors, insecure key handling, or protocol vulnerabilities. Apply the same rigor as any other enterprise skill.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) before writing code:

- `references/cargo-workspace.md` — Cargo workspace layout, hybrid TS/Rust monorepos, CI integration, version bump workflow
- `references/common-crates.md` — Curated crate reference: serialization, async, crypto, auth, WASM, error handling, logging

Read this SKILL.md first for architecture decisions and standards, then consult the reference files for implementation specifics.

---

## Decision Framework: Crate Architecture

Before writing any code, classify the compilation target and role of each crate:

### Crate Type Selection

| Crate Role | `crate-type` | Why |
|---|---|---|
| WASM module (browser/JS interop) | `["cdylib"]` | Produces `.wasm` + JS glue via wasm-bindgen |
| Library used by both Rust and WASM | `["cdylib", "rlib"]` | cdylib for WASM, rlib for Rust-to-Rust |
| Pure Rust library | `["rlib"]` (default) | No need for cdylib overhead |
| Native binary (gRPC server, CLI) | `[[bin]]` + optional `[lib]` | Binary entrypoint + testable lib core |
| Proc-macro crate | `["proc-macro"]` | Required for derive macros |

**Pattern: separate the library core from the binary entrypoint.** Always define a `[lib]` section alongside `[[bin]]` so that business logic is unit-testable without spawning a process.

```toml
# Correct: lib + bin in one crate (constitutional-supervisor pattern)
[[bin]]
name = "constitutional-supervisor"
path = "src/main.rs"

[lib]
name = "constitutional_supervisor"
path = "src/lib.rs"
```

### Error Handling Strategy

| Context | Crate | Pattern |
|---|---|---|
| Library crate | `thiserror` | Typed enum variants with `#[derive(Error)]` |
| Binary / application | `anyhow` | Ergonomic `?` propagation, context chaining |
| Mixed (lib + bin) | `thiserror` in lib, `anyhow` in `main.rs` | Public API stays typed; internal main uses context |

Never use `unwrap()` or `expect()` in library code. In binary entrypoints, `expect()` is acceptable for startup validation where the process should not continue. Panic in a library is never acceptable.

---

## Priority 1: Security

### Cryptographic Key Handling

Keys are the most sensitive data in a Rust program. Treat them with extreme care:

- **Zeroize secrets on drop.** Use `zeroize` crate with `#[derive(Zeroize, ZeroizeOnDrop)]` for all types that hold private keys, seeds, or plaintext secrets.
- **Never log private key material.** Even at DEBUG level. Implement `Debug` manually or use a wrapper that redacts the secret.
- **Use constant-time comparison for MACs, HMACs, and tokens.** Never compare authentication tags with `==` — use `subtle::ConstantTimeEq` or a crate that wraps it (e.g., `hmac::Mac::verify_slice`).
- **Ed25519 signing:** Use `ed25519-dalek` v2. Keys implement `ZeroizeOnDrop`. Verify signatures before acting on them.

```rust
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct PrivateKeyMaterial {
    bytes: [u8; 32],
}

// Manual Debug that never leaks key bytes
impl std::fmt::Debug for PrivateKeyMaterial {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("PrivateKeyMaterial([REDACTED])")
    }
}
```

### Biscuit Token Patterns (v6 API)

Biscuit-auth v6 uses a **consuming builder API** — each builder method takes `self` and returns `Self`. The authorizer is also consuming. This is a breaking change from v5.

```rust
use biscuit_auth::{Biscuit, KeyPair, macros::biscuit, macros::authorizer};

// Token creation — consuming builder
let root_keypair = KeyPair::new();
let token = biscuit!(
    r#"
    user({user_id});
    check if operation({operation});
    "#,
    user_id = "user-123",
    operation = "read",
)
.build(&root_keypair)?;

// Serialization for transport
let token_bytes = token.to_vec()?;
let token_b64 = token.to_base64()?;

// Verification — consuming authorizer
let public_key = root_keypair.public();
let parsed = Biscuit::from_base64(&token_b64, public_key)?;

let result = authorizer!(
    r#"
    operation("read");
    allow if user($u), operation("read");
    "#
)
.add_token(&parsed)?
.authorize();

match result {
    Ok(_) => { /* authorized */ }
    Err(e) => { /* log, deny */ }
}
```

**Common mistake:** Calling `.build()` or `.authorize()` on a builder and then reusing it. The v6 API consumes the builder — capture the result or clone before the call if you need multiple tokens.

#### biscuit-auth v6 WASM — Lazy Symbol Table Warmup

The WASM build of biscuit-auth v6 has an internal symbol table that is **lazily bootstrapped** on the first `authorize` call that parses a valid token. Before bootstrap, `authorize` returns `Prohibit` (or the equivalent deny result) regardless of policy — even if the policy should match `Permit`.

This manifests as intermittent CI failures on fresh runners (Ubuntu, macOS) where the first authorize call returns wrong results. Local dev may work because the WASM module stays warm in Node's require cache.

**Warmup pattern (TypeScript host loading WASM via wasm-pack nodejs target):**

```typescript
// At module load time — before any real calls
let _warmupOk = false;
try {
  const _kp = wasmPkg.generate_keypair();
  const parsed = JSON.parse(typeof _kp === "string" ? _kp : JSON.stringify(_kp));
  const privKey = new Uint8Array(parsed.private_key);
  const pubKey = new Uint8Array(parsed.public_key);
  const warmupToken = wasmPkg.issue_root_token_with_key(privKey, JSON.stringify(['warmup("true")']));

  for (let i = 0; i < 3; i++) {
    const state = wasmPkg.authorize_token(warmupToken, pubKey, 'allow if warmup("true")');
    if (state === PERMIT_CODE) { _warmupOk = true; break; }
  }
  privKey.fill(0); // zero private key bytes
} catch (e) {
  process.stderr.write(`[identity] WASM warmup failed (non-fatal): ${e}\n`);
}
```

**Key points:**
- Warmup must issue a REAL token and authorize against a policy that SHOULD return Permit — `allow if false` does NOT exercise the bootstrap path.
- Retry 2-3 times — on some platforms the table needs multiple attempts.
- Non-fatal if warmup fails — module still loads, but first few authorize calls may be incorrect until table boots naturally.
- Zero private key material after warmup — no key leakage in module scope.

**`std::time::SystemTime::now()` panics in wasm32 nodejs target.** Use `js_sys::Date::now()` for timestamps in WASM builds:

```rust
#[cfg(target_arch = "wasm32")]
fn now_ms() -> f64 { js_sys::Date::now() }

#[cfg(not(target_arch = "wasm32"))]
fn now_ms() -> f64 {
    use std::time::SystemTime;
    SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_millis() as f64
}
```

### `unsafe` Policy

- **No `unsafe` blocks without documented justification.** Every `unsafe` block must have a comment explaining: (1) why it is necessary, (2) why it is sound (what invariants the caller must uphold), (3) what was considered as a safe alternative.
- **FFI boundaries are the primary legitimate use** of `unsafe`. WASM host calls, system calls, and C interop are expected.
- **Never use `unsafe` to bypass the borrow checker** for convenience. Restructure the code instead.
- **CI must run `cargo clippy -- -D unsafe_code`** on crates that should have no unsafe. Add `#![forbid(unsafe_code)]` to the crate root for libraries that have no legitimate unsafe needs.

### Dependency Security

- Run `cargo audit` in CI on every PR. Block merges on any `RUSTSEC` advisory with HIGH or CRITICAL severity.
- Pin transitive cryptographic dependencies explicitly in `[workspace.dependencies]` to prevent silent upgrades.
- Review `cargo tree` output when adding new dependencies — check for yanked crates, unaudited versions, and unexpected transitive deps.

---

## Priority 2: Data Integrity

### Error Handling — thiserror for Libraries

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum IdentityError {
    #[error("token is invalid or expired")]
    InvalidToken(#[from] biscuit_auth::error::Token),

    #[error("signature verification failed")]
    SignatureVerification,

    #[error("key material is missing or corrupted")]
    KeyMaterial,

    #[error("serialization failed: {0}")]
    Serialization(#[from] serde_json::Error),
}

// Result type alias — always define this in lib.rs
pub type Result<T, E = IdentityError> = std::result::Result<T, E>;
```

**Rules:**
- Every public function in a library returns `Result<T, YourErrorType>`.
- Use `#[from]` only for conversion errors that are unambiguous. If a type can map to multiple variants, implement `From` manually.
- Never use `Box<dyn Error>` in a public library API — callers cannot match on it.

### Serialization Safety

- **All wire types must derive `Serialize` and `Deserialize`** with explicit field names. Never rely on positional struct ordering for serialization.
- **Use `#[serde(deny_unknown_fields)]`** on types that cross trust boundaries (network input, WASM boundary, file storage) to catch schema drift early.
- **Use `#[serde(rename_all = "camelCase")]`** when interoperating with JavaScript/JSON APIs to match JS conventions without renaming fields in Rust.

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct AgentIntent {
    pub agent_id: String,
    pub operation: String,
    pub payload: serde_json::Value,
    pub signature: String,
}
```

### WASM Boundary Safety

Data crossing the WASM boundary (JS ↔ Rust) must be validated on the Rust side regardless of JS-side validation:

```rust
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn verify_token(token_b64: &str, operation: &str) -> Result<bool, JsError> {
    // Validate inputs before any processing
    if token_b64.is_empty() {
        return Err(JsError::new("token must not be empty"));
    }
    if operation.is_empty() {
        return Err(JsError::new("operation must not be empty"));
    }
    // ... actual logic
    Ok(true)
}
```

**Rule:** All `#[wasm_bindgen]` public functions return `Result<T, JsError>` — never panic at the WASM boundary (panics abort the WASM module with a non-descriptive error).

---

## Priority 3: Performance

### Async Runtime (tokio)

- **Use `tokio::main` for binary entrypoints.** Use `tokio::test` for async tests.
- **Prefer `tokio::spawn` over blocking in async context.** Use `tokio::task::spawn_blocking` for CPU-heavy or synchronous I/O work.
- **Do not hold `MutexGuard` across `.await` points.** Use `tokio::sync::Mutex` for async-aware locking, or restructure to drop the guard before awaiting.
- **Set `flavor = "multi_thread"` for production servers.** Single-threaded is only for specialized use.

```rust
#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> anyhow::Result<()> {
    // startup
    Ok(())
}
```

### Structured Logging (tracing)

- **Use `tracing` for all logging — not `println!` or `log`.** Tracing integrates with async spans and tokio.
- **Initialize `tracing_subscriber` in `main.rs` only**, never in library code. Libraries call `tracing::info!()` etc.; the subscriber is the binary's concern.
- **Use structured fields, not format strings**, for machine-parseable logs.
- **Use JSON output in production** via `tracing_subscriber::fmt().json()`.

```rust
// In main.rs
tracing_subscriber::fmt()
    .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
    .json()
    .init();

// In library code
use tracing::{info, warn, error, instrument};

#[instrument(skip(secret_key), fields(agent_id = %agent_id))]
pub fn sign_action(agent_id: &str, payload: &[u8], secret_key: &SecretKey) -> Result<Vec<u8>> {
    info!("signing action");
    // ... signing logic
}
```

**Note:** `skip(secret_key)` in `#[instrument]` prevents the key from appearing in trace output. Always skip sensitive parameters.

### gRPC with tonic

- **Define protos in a `proto/` directory** at the crate root. Compile with `tonic-build` in `build.rs`.
- **Use `tonic::Status` for all service errors** — map domain errors to appropriate gRPC status codes.
- **Add request timeouts** via tower middleware or per-call deadlines. Never leave gRPC calls with no timeout.

```rust
// build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(&["proto/supervisor.proto"], &["proto"])?;
    Ok(())
}
```

```rust
// Service implementation
use tonic::{Request, Response, Status};

impl SupervisorService for ConstitutionalSupervisor {
    async fn evaluate(
        &self,
        request: Request<EvaluateRequest>,
    ) -> Result<Response<EvaluateResponse>, Status> {
        let req = request.into_inner();
        
        self.evaluate_inner(&req)
            .await
            .map(Response::new)
            .map_err(|e| match e {
                SupervisorError::InvalidInput(_) => Status::invalid_argument(e.to_string()),
                SupervisorError::Unauthorized => Status::permission_denied("action denied"),
                _ => {
                    error!("internal supervisor error: {e}");
                    Status::internal("internal error")
                }
            })
    }
}
```

---

## Workspace Structure

### Recommended Layout (Cargo workspace in a pnpm monorepo)

```
project-root/
├── Cargo.toml              # Workspace root — workspace.dependencies here
├── Cargo.lock              # ALWAYS commit — even for libraries in a workspace
├── rust-toolchain.toml     # Pin Rust version for reproducibility
├── packages/
│   ├── identity/           # Library + WASM target
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   └── token.rs
│   │   └── tests/
│   │       └── integration.rs
│   ├── cage/               # Library — native only (wasmtime host)
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   └── sandbox.rs
│   │   └── tests/
│   │       └── sandbox_test.rs
│   └── constitutional-supervisor/  # gRPC binary + lib
│       ├── Cargo.toml
│       ├── build.rs
│       ├── proto/
│       │   └── supervisor.proto
│       └── src/
│           ├── main.rs
│           ├── lib.rs
│           └── service.rs
├── pnpm-workspace.yaml     # pnpm workspace (TS packages)
├── turbo.json              # Turborepo task graph
└── package.json            # Root package.json
```

### rust-toolchain.toml

Always pin the Rust toolchain. Unpinned toolchains cause silent breakage when Rust updates:

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
targets = ["wasm32-unknown-unknown"]  # include if any crate compiles to WASM
```

### Workspace Cargo.toml Pattern

Centralize all shared dependency versions. Individual crates inherit via `{ workspace = true }`:

```toml
[workspace]
members = ["packages/identity", "packages/cage", "packages/constitutional-supervisor"]
resolver = "2"  # Always resolver = "2" for feature flag correctness

[workspace.dependencies]
# Auth
biscuit-auth = "6"

# Crypto
ed25519-dalek = { version = "2", features = ["rand_core"] }
sha2 = "0.10"
aes-gcm = "0.10"
zeroize = { version = "1", features = ["derive"] }

# WASM
wasm-bindgen = "0.2"
wasmtime = "43"
wasmtime-wasi = "43"

# Async
tokio = { version = "1", features = ["full"] }

# gRPC
tonic = { version = "0.12", features = ["transport", "codegen"] }
prost = "0.13"

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Error handling
thiserror = "1"
anyhow = "1"

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "fmt", "json"] }

# Utilities
uuid = { version = "1", features = ["v4"] }
hex = "0.4"
rand = "0.8"
```

---

## Testing Requirements

### Test Pyramid for Rust

- **Unit tests (70%):** In-module `#[cfg(test)]` blocks. Test every public function, error path, and edge case.
- **Integration tests (25%):** In `tests/` directory. Test cross-module interactions and full flows.
- **Doc tests (5%):** `///` examples that compile and run. Keep them accurate and minimal.

### Unit Test Pattern

```rust
// Inside src/token.rs
#[cfg(test)]
mod tests {
    use super::*;
    use biscuit_auth::KeyPair;

    fn make_keypair() -> KeyPair {
        KeyPair::new()
    }

    #[test]
    fn valid_token_verifies_successfully() {
        let kp = make_keypair();
        let token = build_token(&kp, "user-1", "read").expect("token build failed");
        let result = verify_token(&token, kp.public(), "read");
        assert!(result.is_ok(), "expected Ok, got: {:?}", result);
    }

    #[test]
    fn invalid_operation_is_rejected() {
        let kp = make_keypair();
        let token = build_token(&kp, "user-1", "read").expect("token build failed");
        let result = verify_token(&token, kp.public(), "write");
        assert!(result.is_err(), "expected Err for wrong operation");
    }

    #[test]
    fn empty_token_returns_error() {
        let kp = make_keypair();
        let result = verify_token("", kp.public(), "read");
        assert!(matches!(result, Err(IdentityError::InvalidToken(_))));
    }
}
```

### Integration Test Pattern

```rust
// tests/sandbox_integration.rs
use cage::{Sandbox, SandboxConfig, IntentVerdict};
use tempfile::NamedTempFile;
use std::io::Write;

#[test]
fn sandbox_executes_valid_wasm_module() {
    let mut wasm_file = NamedTempFile::new().unwrap();
    wasm_file.write_all(MINIMAL_WASM_BYTES).unwrap();
    
    let config = SandboxConfig::default();
    let sandbox = Sandbox::new(config).expect("sandbox init failed");
    
    let verdict = sandbox
        .execute(wasm_file.path(), "test-agent", &[])
        .expect("execution failed");
    
    assert_eq!(verdict, IntentVerdict::Approved);
}
```

### Async Test Pattern

```rust
#[tokio::test]
async fn grpc_evaluate_returns_deny_on_invalid_intent() {
    let service = ConstitutionalSupervisor::new_for_test();
    let request = tonic::Request::new(EvaluateRequest {
        agent_id: "agent-1".to_string(),
        intent: "drop database".to_string(),
        signature: "invalid".to_string(),
    });
    
    let result = service.evaluate(request).await;
    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), tonic::Code::PermissionDenied);
}
```

### WASM Test Pattern (wasm-bindgen-test)

```rust
use wasm_bindgen_test::*;

wasm_bindgen_test_configure!(run_in_browser);  // or run_in_node_experimental

#[wasm_bindgen_test]
fn wasm_token_round_trip() {
    let token = create_token("user-1", "read").expect("create failed");
    assert!(!token.is_empty());
    let valid = verify_token_js(&token, "read");
    assert!(valid);
}
```

---

## WASM Compilation

### Target Setup

Add the WASM target via `rust-toolchain.toml` (preferred) or manually:

```bash
rustup target add wasm32-unknown-unknown
```

### wasm-pack Workflow

For browser-targeted WASM with JavaScript bindings:

```bash
# Development build
wasm-pack build packages/identity --target web --dev

# Production build
wasm-pack build packages/identity --target web --release

# Node.js target
wasm-pack build packages/identity --target nodejs
```

### wasm-bindgen Patterns

```rust
use wasm_bindgen::prelude::*;
use serde::{Serialize, Deserialize};

// Return complex types as JsValue via serde
#[derive(Serialize, Deserialize)]
pub struct TokenResult {
    pub token: String,
    pub expires_at: u64,
}

#[wasm_bindgen]
pub fn issue_token(user_id: &str, operation: &str) -> Result<JsValue, JsError> {
    let result = internal_issue(user_id, operation)
        .map_err(|e| JsError::new(&e.to_string()))?;
    
    serde_wasm_bindgen::to_value(&result)
        .map_err(|e| JsError::new(&e.to_string()))
}
```

**Prefer `serde_wasm_bindgen` over `wasm_bindgen::JsValue::from_serde`** — the latter is deprecated in newer wasm-bindgen versions.

### wasmtime Host (Native Runtime)

When using wasmtime as a host to execute WASM modules from Rust:

```rust
use wasmtime::{Engine, Module, Store, Linker};
use wasmtime_wasi::WasiCtxBuilder;

pub fn execute_module(wasm_bytes: &[u8]) -> anyhow::Result<()> {
    let engine = Engine::default();
    let module = Module::new(&engine, wasm_bytes)?;
    
    let wasi_ctx = WasiCtxBuilder::new()
        .inherit_stdout()
        .build();
    
    let mut store = Store::new(&engine, wasi_ctx);
    let mut linker = Linker::new(&engine);
    wasmtime_wasi::add_to_linker_sync(&mut linker, |s| s)?;
    
    let instance = linker.instantiate(&mut store, &module)?;
    let func = instance.get_typed_func::<(), ()>(&mut store, "_start")?;
    func.call(&mut store, ())?;
    
    Ok(())
}
```

---

## Cargo Commands Reference

| Command | Purpose | Notes |
|---|---|---|
| `cargo build` | Debug build | Slow, includes debug symbols |
| `cargo build --release` | Production build | Enable in CI before tests |
| `cargo check` | Type-check only (fast) | Use in watch mode for dev |
| `cargo clippy -- -D warnings` | Lints as errors | Run in CI |
| `cargo fmt --check` | Format check | Fail CI if unformatted |
| `cargo test` | All tests | Unit + integration + doc |
| `cargo test --workspace` | All crates in workspace | Use this in CI |
| `cargo audit` | Security advisory check | Requires `cargo-audit` install |
| `cargo tree` | Dependency tree | Use with `--duplicates` to find version conflicts |
| `cargo update` | Update Cargo.lock | Never updates major versions |
| `cargo outdated` | Show outdated deps | Requires `cargo-outdated` install |

---

## Integration with Other Enterprise Skills

- **enterprise-devx-monorepo:** Cargo workspace coexists with pnpm workspaces and Turborepo. The monorepo skill governs CI orchestration — add Rust-specific jobs (cargo test, cargo audit, wasm-pack build) as separate Turborepo tasks or GitHub Actions jobs. See `references/cargo-workspace.md` for the full CI pattern.
- **enterprise-database:** Rust services connecting to PostgreSQL should use `sqlx` (compile-time query verification) or `diesel`. Connection pooling via `deadpool-postgres` or `sqlx`'s built-in pool. Never use raw `libpq`.
- **enterprise-security:** The `enterprise-security` skill governs threat modeling and compliance. Apply its OWASP checklist to Rust services. Rust eliminates memory-safety vulnerabilities but not logic errors, injection flaws, or insecure token handling.
- **enterprise-deployment:** Rust binaries are compiled in multi-stage Docker builds. Stage 1: `rust:slim` builder. Stage 2: `gcr.io/distroless/cc` or `debian:bookworm-slim`. Run as non-root. Static binaries via `RUSTFLAGS="-C target-feature=+crt-static"` (musl target) simplify the runtime image.

---

## Verification Checklist

Before considering any Rust work complete, verify:

- [ ] All secrets and key material use `zeroize` or `ZeroizeOnDrop`
- [ ] No `unwrap()` / `expect()` in library code (only justified panics in binary startup)
- [ ] All public library functions return `Result<T, TypedError>` — no `Box<dyn Error>` in APIs
- [ ] `#[wasm_bindgen]` functions return `Result<T, JsError>` — no panics at WASM boundary
- [ ] Biscuit tokens use v6 consuming builder API and are verified before action
- [ ] `unsafe` blocks have documented justification + soundness argument
- [ ] `tracing::instrument` skips all sensitive parameters
- [ ] No raw private key material appears in `Debug` output or trace logs
- [ ] Constant-time comparison for all authentication tokens and MACs
- [ ] `cargo clippy -- -D warnings` passes with no suppressions
- [ ] `cargo fmt --check` passes
- [ ] `cargo audit` passes with no HIGH/CRITICAL advisories
- [ ] `cargo test --workspace` passes
- [ ] Workspace `Cargo.lock` is committed
- [ ] `rust-toolchain.toml` pinned to a specific stable channel
- [ ] `serde` types crossing trust boundaries use `#[serde(deny_unknown_fields)]`
- [ ] gRPC services map domain errors to correct `tonic::Status` codes (not `Status::internal` for all)
- [ ] wasmtime guests run with minimal WASI capabilities (capability-based, deny by default)
