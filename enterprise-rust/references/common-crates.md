# Common Crates Reference

Curated reference sheet for the Rust crate ecosystem used in enterprise Rust development. Includes recommended versions, feature flags, usage patterns, and known gotchas.

---

## Serialization

### serde + serde_json

The universal serialization layer. Used everywhere.

```toml
[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

**Key attributes:**

```rust
use serde::{Deserialize, Serialize};

// Standard derive — covers 90% of cases
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentIntent {
    pub agent_id: String,
    pub operation: String,
}

// Strict deserialization for trust-boundary types
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IncomingRequest {
    pub token: String,
    pub action: String,
}

// JS interop — camelCase JSON keys, snake_case Rust fields
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenPayload {
    pub user_id: String,
    pub expires_at: u64,
}

// Skip fields from serialization (e.g., internal state)
#[derive(Serialize)]
pub struct AuditRecord {
    pub event: String,
    #[serde(skip)]
    pub internal_state: Vec<u8>,
}

// Flatten nested structs into parent
#[derive(Serialize, Deserialize)]
pub struct FullRecord {
    #[serde(flatten)]
    pub base: BaseRecord,
    pub extra_field: String,
}

// Optional fields — omit None from JSON output
#[derive(Serialize, Deserialize)]
pub struct Partial {
    pub required: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub optional: Option<String>,
}
```

**Gotchas:**
- `#[serde(deny_unknown_fields)]` breaks struct flattening with `#[serde(flatten)]` — these cannot be combined.
- `serde_json::Value` is useful for dynamic JSON but loses type safety. Use typed structs at trust boundaries.

### postcard

Compact binary serialization. Use for inter-service messages, WASM payloads, or embedded contexts where JSON overhead is unacceptable.

```toml
postcard = { version = "1", features = ["alloc"] }
```

```rust
// Serialize to bytes
let bytes = postcard::to_allocvec(&my_struct)?;

// Deserialize from bytes
let value: MyStruct = postcard::from_bytes(&bytes)?;
```

**When to use over serde_json:** When message size matters (IoT, WASM boundary, high-frequency inter-service calls). Uses roughly 40-70% less bytes than JSON for typical structs.

---

## Async Runtime

### tokio

The standard async runtime for Rust production services.

```toml
[workspace.dependencies]
tokio = { version = "1" }

# In crates that need it
[dependencies]
tokio = { workspace = true, features = ["full"] }

# Minimal features for a library that just needs a handle
tokio = { workspace = true, features = ["rt", "macros"] }
```

**Feature flag guide:**

| Feature | What it enables |
|---|---|
| `full` | All features (use in binaries/servers) |
| `rt-multi-thread` | Multi-threaded runtime |
| `rt` | Single-threaded runtime |
| `macros` | `#[tokio::main]`, `#[tokio::test]` |
| `sync` | `Mutex`, `RwLock`, `Semaphore`, channels |
| `time` | `sleep`, `timeout`, `Interval` |
| `io-util` | `AsyncRead`, `AsyncWrite` extensions |
| `net` | TCP/UDP listeners |
| `fs` | Async file I/O |

**Patterns:**

```rust
// Binary entry point
#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> anyhow::Result<()> {
    Ok(())
}

// Spawn CPU-heavy work off the async thread
let result = tokio::task::spawn_blocking(|| {
    heavy_crypto_operation()
}).await?;

// Timeouts
use tokio::time::{timeout, Duration};
let result = timeout(Duration::from_secs(5), async_operation()).await
    .map_err(|_| MyError::Timeout)?;

// Async mutex — only when shared across await points
use tokio::sync::Mutex;
let shared = Arc::new(Mutex::new(State::new()));
let guard = shared.lock().await;
// guard is held across potential await points — OK with tokio::sync::Mutex
// NOT OK with std::sync::Mutex
```

**Gotcha:** Never hold `std::sync::MutexGuard` across an `.await` — this deadlocks. Use `tokio::sync::Mutex` if the guard must be held across await points.

---

## Web / Network

### hyper (v1)

Low-level HTTP library. Use directly for proxies or custom HTTP handling (semantic-firewall pattern). For application servers, prefer `axum` which builds on hyper.

```toml
hyper = { version = "1", features = ["full"] }
hyper-util = { version = "0.1", features = ["full"] }
http-body-util = "0.1"
bytes = "1"
```

```rust
use hyper::{Request, Response, body::Incoming};
use hyper_util::rt::TokioIo;
use http_body_util::Full;
use bytes::Bytes;

// Minimal hyper v1 server
async fn handle(req: Request<Incoming>) -> Result<Response<Full<Bytes>>, hyper::Error> {
    Ok(Response::new(Full::new(Bytes::from("hello"))))
}
```

**v1 breaking changes from v0.14:**
- `Body` is now `Incoming` for requests, generic for responses.
- `http-body-util` provides `Full`, `Empty`, `BodyExt` — these were in hyper v0.
- `hyper-util` provides `TokioExecutor`, `TokioIo`, and `client::legacy::Client` (replaces old `Client`).

### axum

Application-level HTTP framework built on hyper + tower. Use for REST APIs.

```toml
axum = "0.8"
tower = "0.5"
tower-http = { version = "0.6", features = ["cors", "trace", "timeout"] }
```

```rust
use axum::{Router, routing::get, extract::State, Json};
use tower_http::trace::TraceLayer;

async fn health(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "ok" }))
}

let app = Router::new()
    .route("/health", get(health))
    .layer(TraceLayer::new_for_http())
    .with_state(state);
```

### tonic (gRPC)

gRPC framework built on hyper + prost. Use for internal service-to-service communication.

```toml
tonic = { version = "0.12", features = ["transport", "codegen"] }
prost = "0.13"

[build-dependencies]
tonic-build = "0.12"
```

**build.rs:**
```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(
            &["proto/supervisor.proto"],
            &["proto"],
        )?;
    Ok(())
}
```

**Status code mapping — always map domain errors explicitly:**

```rust
fn to_status(e: &DomainError) -> tonic::Status {
    match e {
        DomainError::NotFound(id) => tonic::Status::not_found(format!("{id} not found")),
        DomainError::Unauthorized => tonic::Status::permission_denied("access denied"),
        DomainError::InvalidInput(msg) => tonic::Status::invalid_argument(msg.clone()),
        DomainError::RateLimit => tonic::Status::resource_exhausted("rate limit exceeded"),
        // Log internal errors — do NOT expose their messages to clients
        DomainError::Internal(e) => {
            tracing::error!("internal error: {e}");
            tonic::Status::internal("internal error")
        }
    }
}
```

---

## Cryptography

### ed25519-dalek (v2)

Ed25519 digital signatures. Use for signing and verifying agent actions, tokens, and attestations.

```toml
ed25519-dalek = { version = "2", features = ["rand_core"] }
rand = "0.8"
```

```rust
use ed25519_dalek::{SigningKey, VerifyingKey, Signer, Verifier};
use rand::rngs::OsRng;

// Key generation
let mut csprng = OsRng;
let signing_key = SigningKey::generate(&mut csprng);
let verifying_key: VerifyingKey = signing_key.verifying_key();

// Signing
let message = b"action: approve-deployment";
let signature = signing_key.sign(message);

// Verification
verifying_key.verify(message, &signature)?;  // Err if invalid

// Serialization
let signing_bytes: [u8; 32] = signing_key.to_bytes();
let verifying_bytes: [u8; 32] = verifying_key.to_bytes();

// Deserialization
let restored_key = SigningKey::from_bytes(&signing_bytes);
let restored_verifying = VerifyingKey::from_bytes(&verifying_bytes)?;
```

**v2 breaking changes from v1:**
- `Keypair` is replaced by `SigningKey`.
- `PublicKey` is now `VerifyingKey`.
- Batch verification API changed.
- `SigningKey` implements `ZeroizeOnDrop` automatically in v2.

### sha2

SHA-2 family hash functions. Use SHA-256 for content hashing, Merkle trees, and token fingerprinting.

```toml
sha2 = "0.10"
```

```rust
use sha2::{Sha256, Digest};

let mut hasher = Sha256::new();
hasher.update(b"content to hash");
hasher.update(more_bytes); // can call update multiple times
let hash: [u8; 32] = hasher.finalize().into();

// One-shot
let hash = Sha256::digest(b"content");
let hex_hash = hex::encode(hash);
```

### aes-gcm

AES-256-GCM authenticated encryption. Use for encrypting secrets at rest and encrypted payloads.

```toml
aes-gcm = "0.10"
rand = "0.8"
```

```rust
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};

// Encryption
let key = Aes256Gcm::generate_key(OsRng);  // 256-bit key
let cipher = Aes256Gcm::new(&key);
let nonce = Aes256Gcm::generate_nonce(&mut OsRng);  // 96-bit nonce — NEVER reuse
let ciphertext = cipher.encrypt(&nonce, plaintext_bytes.as_ref())?;

// Decryption — returns Err if authentication tag fails
let plaintext = cipher.decrypt(&nonce, ciphertext.as_ref())?;
```

**Critical:** Nonces must never be reused with the same key. Use `Aes256Gcm::generate_nonce(&mut OsRng)` for random nonces, or a counter for deterministic nonces. Store nonce alongside ciphertext (it is not secret).

### zeroize

Secure memory erasure. Use for all types that hold key material, passwords, or plaintext secrets.

```toml
zeroize = { version = "1", features = ["derive"] }
```

```rust
use zeroize::{Zeroize, ZeroizeOnDrop};

// Derive on struct — bytes zeroed when dropped
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct SecretKey {
    bytes: [u8; 32],
    expanded: Vec<u8>,
}

// Manual zeroize for types you don't own
let mut secret_bytes: Vec<u8> = derive_key();
// ... use secret_bytes ...
secret_bytes.zeroize();  // Explicitly zero before drop

// Protect sensitive data in custom Drop
impl Drop for CustomSecret {
    fn drop(&mut self) {
        self.inner.zeroize();
    }
}
```

**Gotcha:** `#[derive(Zeroize)]` only zeros on explicit `.zeroize()` call. `#[derive(ZeroizeOnDrop)]` zeros automatically when dropped. Use `ZeroizeOnDrop` for key types that should always zero.

### hmac + subtle (constant-time comparison)

```toml
hmac = "0.12"
sha2 = "0.10"
subtle = "2"
```

```rust
use hmac::{Hmac, Mac};
use sha2::Sha256;
use subtle::ConstantTimeEq;

type HmacSha256 = Hmac<Sha256>;

// Create HMAC
let mut mac = HmacSha256::new_from_slice(key_bytes)?;
mac.update(message);
let result = mac.finalize().into_bytes();

// Verify HMAC — use verify_slice for constant-time comparison
let mut mac = HmacSha256::new_from_slice(key_bytes)?;
mac.update(message);
mac.verify_slice(&expected_tag)?;  // Constant-time — use this, not == comparison

// Manual constant-time comparison when needed
let a: [u8; 32] = compute_a();
let b: [u8; 32] = expected_b;
if a.ct_eq(&b).into() {
    // match
}
```

---

## Auth

### biscuit-auth (v6)

Decentralized authorization tokens with Datalog-based policy language. The **v6 API uses a consuming builder** — methods take `self` and return `Self`. This is the major breaking change from v5.

```toml
biscuit-auth = "6"
```

**Token creation:**

```rust
use biscuit_auth::{Biscuit, KeyPair, macros::biscuit};

let root_keypair = KeyPair::new();

// Builder macros — consuming API
let token: Biscuit = biscuit!(
    r#"
    user({user_id});
    role({role});
    "#,
    user_id = "user-abc",
    role = "operator",
)
.build(&root_keypair)?;  // .build() consumes the builder

// Serialize for transport
let b64 = token.to_base64()?;
let bytes = token.to_vec()?;
```

**Token attenuation (add a check to restrict what an existing token can do):**

```rust
use biscuit_auth::macros::block;

let attenuated = token.append(
    block!(r#"check if operation({op});"#, op = "read")
)?;
// The attenuated token is weaker — it can only be used for "read"
```

**Token verification:**

```rust
use biscuit_auth::{Biscuit, PublicKey, macros::authorizer};

let public_key: PublicKey = root_keypair.public();
let token = Biscuit::from_base64(&b64, public_key)?;

// Authorizer — also consuming
let result = authorizer!(
    r#"
    operation("read");
    resource("/api/data");
    allow if user($u), operation("read"), resource($r);
    deny if true;
    "#
)
.add_token(&token)?
.authorize();

match result {
    Ok(_) => { /* authorized */ }
    Err(e) => { /* denied — log e */ }
}
```

**Common mistakes:**
1. Calling `.build()` then reusing the builder variable — it was moved.
2. Calling `.authorize()` then inspecting world state — the authorizer is consumed.
3. Not calling `.deny if true` — without a deny-all rule, the authorizer may default to allowing. Always end with `deny if true` and explicit `allow` rules.
4. Embedding private keys in the token — the `KeyPair` is only used to sign; it never goes in the token.

---

## WASM

### wasmtime + wasmtime-wasi (native host)

Use when Rust code is the HOST that runs WASM modules (the cage pattern).

```toml
wasmtime = "43"
wasmtime-wasi = "43"
```

```rust
use wasmtime::{Config, Engine, Linker, Module, Store};
use wasmtime_wasi::{WasiCtxBuilder, WasiCtx, add_to_linker_sync};

struct HostState {
    wasi: WasiCtx,
}

pub fn run_module(wasm_bytes: &[u8]) -> anyhow::Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(false);  // Use classic WASM unless using components
    config.async_support(false);

    let engine = Engine::new(&config)?;
    let module = Module::new(&engine, wasm_bytes)?;

    let wasi_ctx = WasiCtxBuilder::new()
        .inherit_stdout()
        .inherit_stderr()
        // Do NOT inherit_env() or inherit_args() unless required — capability-based
        .build();

    let mut store = Store::new(&engine, HostState { wasi: wasi_ctx });
    let mut linker: Linker<HostState> = Linker::new(&engine);

    add_to_linker_sync(&mut linker, |s: &mut HostState| &mut s.wasi)?;

    let instance = linker.instantiate(&mut store, &module)?;
    let func = instance.get_typed_func::<(), ()>(&mut store, "_start")?;
    func.call(&mut store, ())?;

    Ok(())
}
```

**Capability restriction rules (cage pattern):**
- Never grant filesystem access unless the module explicitly needs it and the scope is documented.
- Never use `inherit_env()` — pass only required env vars explicitly.
- Set fuel limits to prevent infinite loops: `store.add_fuel(1_000_000)?`.
- Set memory limits via `Config` to prevent memory exhaustion.

### wasm-bindgen (WASM library for JS)

Use when the Rust crate is compiled TO WASM and called FROM JavaScript.

```toml
wasm-bindgen = "0.2"
serde-wasm-bindgen = "0.6"  # For complex type passing

[dev-dependencies]
wasm-bindgen-test = "0.3"
```

```rust
use wasm_bindgen::prelude::*;

// Simple scalar types pass directly
#[wasm_bindgen]
pub fn add(a: u32, b: u32) -> u32 {
    a + b
}

// Complex types: use JsValue + serde-wasm-bindgen
#[derive(serde::Serialize, serde::Deserialize)]
pub struct TokenResult {
    pub token: String,
    pub issued_at: u64,
}

#[wasm_bindgen]
pub fn issue_token(user_id: &str) -> Result<JsValue, JsError> {
    let result = internal_issue(user_id)
        .map_err(|e| JsError::new(&e.to_string()))?;

    serde_wasm_bindgen::to_value(&result)
        .map_err(|e| JsError::new(&e.to_string()))
}

// Expose a struct to JS
#[wasm_bindgen]
pub struct TokenStore {
    inner: Vec<String>,
}

#[wasm_bindgen]
impl TokenStore {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        Self { inner: Vec::new() }
    }

    pub fn add(&mut self, token: String) {
        self.inner.push(token);
    }

    pub fn len(&self) -> usize {
        self.inner.len()
    }
}
```

**Do not use `JsValue::from_serde` / `JsValue::into_serde`** — these are deprecated in newer wasm-bindgen. Use `serde-wasm-bindgen` instead.

### getrandom — WASM random number generation

`getrandom` is a transitive dependency of `rand`, `biscuit-auth`, `ed25519-dalek`, and most crypto crates. On `wasm32-unknown-unknown`, it cannot use OS entropy by default — it needs the `js` feature to use `Web Crypto API` (browsers) or Node.js `crypto` module.

**Without this, `wasm-pack build --target nodejs` fails with a linker or panic error.**

```toml
# In the WASM crate's Cargo.toml — target-specific so it only applies to WASM builds
[target.'cfg(target_arch = "wasm32")'.dependencies]
getrandom = { version = "0.2", features = ["js"] }
```

**When you need this:** Any crate compiled with `wasm-pack` that has `rand`, `ed25519-dalek`, `biscuit-auth`, or any other crate that uses `getrandom` as a transitive dependency. This is almost every cryptographic WASM crate.

**getrandom version alignment:**
- `rand 0.8` → `getrandom 0.2` → use `getrandom = { version = "0.2", features = ["js"] }`
- `rand 0.9` → `getrandom 0.3` → use `getrandom = { version = "0.3", features = ["js"] }`

**Diagnosis:** If `wasm-pack build` fails with:
- `error[E0463]: can't find crate for 'core'` on a wasm32 target — missing `wasm32-unknown-unknown` rustup target
- `RuntimeError: unreachable` or `getrandom: this target is not supported` at runtime — missing `js` feature

---

## Error Handling

### thiserror (libraries)

```toml
thiserror = "1"
```

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CageError {
    // Simple message
    #[error("WASM module failed to compile")]
    Compilation(#[source] wasmtime::Error),

    // Dynamic message
    #[error("sandbox limit exceeded: {kind}")]
    LimitExceeded { kind: String },

    // Transparent forwarding (same message as inner error)
    #[error(transparent)]
    Io(#[from] std::io::Error),

    // Multiple fields
    #[error("intent rejected: agent={agent_id}, reason={reason}")]
    IntentRejected { agent_id: String, reason: String },
}

pub type Result<T> = std::result::Result<T, CageError>;
```

**Rules:**
- Use `#[from]` only when the conversion is unambiguous (one source type maps to one variant).
- Use `#[source]` to expose the underlying cause without using `#[from]` (when you want a custom message).
- Use `#[error(transparent)]` sparingly — it loses the variant's contextual information for callers.
- Always define a `type Result<T> = std::result::Result<T, YourError>;` alias in `lib.rs`.

### anyhow (binaries and scripts)

```toml
anyhow = "1"
```

```rust
use anyhow::{Context, Result, bail, ensure};

fn start_server() -> Result<()> {
    let port = std::env::var("PORT")
        .context("PORT env var not set")?
        .parse::<u16>()
        .context("PORT must be a valid port number")?;

    ensure!(port > 1024, "port must be > 1024, got {port}");

    if !config_file_exists() {
        bail!("config file not found at {}", config_path());
    }

    Ok(())
}
```

**When to use:** `main.rs`, CLI tools, integration tests, scripts. Never in public library APIs.

---

## Logging

### tracing + tracing-subscriber

```toml
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "fmt", "json"] }
```

**Initialization in main.rs:**

```rust
use tracing_subscriber::{EnvFilter, fmt, prelude::*};

fn init_tracing() {
    tracing_subscriber::registry()
        .with(EnvFilter::from_default_env())  // RUST_LOG=info,my_crate=debug
        .with(fmt::layer().json())             // JSON output for production
        .init();
}
```

**In library code — instruments and events only:**

```rust
use tracing::{debug, error, info, instrument, warn, Span};

// Auto-instrument a function — all log calls inside get this span's fields
#[instrument(
    skip(secret_key, payload),      // NEVER include secrets in spans
    fields(agent_id = %agent_id, operation = %op)
)]
pub async fn process_intent(
    agent_id: &str,
    op: &str,
    payload: &[u8],
    secret_key: &SecretKey,
) -> Result<Verdict> {
    info!("processing intent");
    
    let verdict = evaluate(payload).await?;
    
    if verdict == Verdict::Deny {
        warn!(reason = "policy violation", "intent denied");
    }
    
    Ok(verdict)
}

// Structured fields — prefer this over format strings
error!(
    agent_id = %agent_id,
    error_code = %e.code(),
    "intent evaluation failed"
);
```

**Log levels:**
- `error!` — operation failed, requires attention
- `warn!` — unexpected but handled (denied request, rate limit, retry)
- `info!` — business events (token issued, intent approved, service started)
- `debug!` — detailed diagnostic (step-by-step execution, state transitions)
- `trace!` — extremely verbose (byte-level, per-loop iteration)

**Default `RUST_LOG` for production:** `info`. For development: `debug,hyper=warn,tonic=warn`.

---

## Testing Utilities

### tempfile

Temporary files and directories for tests. Automatically cleaned up on drop.

```toml
[dev-dependencies]
tempfile = "3"
```

```rust
use tempfile::{NamedTempFile, TempDir};
use std::io::Write;

#[test]
fn test_with_temp_file() {
    let mut file = NamedTempFile::new().unwrap();
    writeln!(file, "test content").unwrap();
    
    let result = process_file(file.path());
    assert!(result.is_ok());
    // File auto-deleted when `file` drops
}

#[test]
fn test_with_temp_dir() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("output.json");
    
    write_output(&file_path).unwrap();
    assert!(file_path.exists());
    // Dir and all contents auto-deleted when `dir` drops
}
```

### assert_cmd

Test CLI binaries. Use for integration tests of `[[bin]]` targets.

```toml
[dev-dependencies]
assert_cmd = "2"
predicates = "3"
```

```rust
use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn cli_returns_error_on_missing_token() {
    Command::cargo_bin("constitutional-supervisor")
        .unwrap()
        .arg("evaluate")
        .arg("--intent")
        .arg("drop table users")
        .assert()
        .failure()
        .stderr(predicate::str::contains("token required"));
}

#[test]
fn cli_succeeds_with_valid_token() {
    Command::cargo_bin("constitutional-supervisor")
        .unwrap()
        .env("SUPERVISOR_KEY", "test-key")
        .arg("health")
        .assert()
        .success()
        .stdout(predicate::str::contains("ok"));
}
```

### tokio-test

Utilities for testing async code without a full tokio runtime in some scenarios.

```toml
[dev-dependencies]
tokio-test = "0.4"
```

```rust
// For testing async streams and channels in unit tests
use tokio_test::task::spawn;
use tokio_test::assert_ready;

// Most async tests just use #[tokio::test] — tokio-test is for lower-level stream testing
#[tokio::test]
async fn simple_async_test() {
    let result = my_async_fn().await;
    assert!(result.is_ok());
}
```

---

## Quick Selection Guide

| Need | Crate(s) |
|---|---|
| JSON serialization | `serde` + `serde_json` |
| Binary serialization | `serde` + `postcard` |
| Async runtime | `tokio` |
| HTTP server (app level) | `axum` |
| HTTP proxy / low-level | `hyper` + `hyper-util` + `http-body-util` |
| gRPC server/client | `tonic` + `prost` + `tonic-build` |
| Ed25519 signatures | `ed25519-dalek` v2 |
| AES-256-GCM encryption | `aes-gcm` |
| SHA-256 hashing | `sha2` |
| HMAC / constant-time | `hmac` + `subtle` |
| Zeroize secrets | `zeroize` |
| Authorization tokens | `biscuit-auth` v6 |
| WASM runtime (host) | `wasmtime` + `wasmtime-wasi` |
| WASM library (JS target) | `wasm-bindgen` + `serde-wasm-bindgen` |
| Library errors | `thiserror` |
| Binary errors | `anyhow` |
| Structured logging | `tracing` + `tracing-subscriber` |
| Test temp files | `tempfile` |
| Test CLI binaries | `assert_cmd` + `predicates` |
