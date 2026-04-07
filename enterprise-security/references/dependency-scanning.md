# Dependency & Supply Chain Security Reference

## Scanning Tools

| Tool | Type | Best For | Cost |
|---|---|---|---|
| **npm audit** | Built-in | Node.js projects, fast check | Free |
| **Snyk** | SaaS + CLI | Deep analysis, fix PRs, license scanning | Free tier |
| **Trivy** | OSS CLI | Container images, IaC, SBOM | Free |
| **Socket.dev** | SaaS | Supply chain attacks, typosquatting | Free tier |
| **pip audit** | Built-in | Python projects | Free |
| **Dependabot** | GitHub | Automated update PRs | Free |
| **Semgrep Supply Chain** | SaaS + CLI | SAST + supply chain, reachability analysis, SARIF | Free tier |
| **cargo audit** | CLI | Rust crate vulnerability scanning (RustSec DB) | Free |

---

## npm audit

```bash
# Check for vulnerabilities
npm audit

# Auto-fix where possible
npm audit fix

# Only fix non-breaking (patch/minor)
npm audit fix --only=prod

# JSON output for CI
npm audit --json
```

### CI Integration

```yaml
# .github/workflows/security.yml
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm audit --audit-level=high
        # Fails CI if high or critical vulnerabilities found
```

---

## Snyk

### Setup

```bash
npm install -g snyk
snyk auth  # Authenticate with Snyk account
```

### Commands

```bash
# Test for vulnerabilities
snyk test

# Monitor project (continuous)
snyk monitor

# Test container image
snyk container test my-app:latest

# Test IaC (Terraform, CloudFormation)
snyk iac test

# Fix vulnerabilities
snyk fix
```

### CI Integration

```yaml
jobs:
  snyk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: snyk/actions/node@master
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          args: --severity-threshold=high
```

### .snyk Policy File

```yaml
# .snyk — ignore specific vulnerabilities with justification
version: v1.25.0
ignore:
  SNYK-JS-LODASH-1234567:
    - '*':
        reason: 'Not exploitable in our usage — lodash.get only used server-side'
        expires: '2025-06-01T00:00:00.000Z'
```

---

## Trivy

### Container Scanning

```bash
# Scan container image
trivy image my-app:latest

# Scan with severity filter
trivy image --severity HIGH,CRITICAL my-app:latest

# Scan filesystem (project dependencies)
trivy fs --scanners vuln .

# Generate SBOM
trivy image --format spdx-json -o sbom.json my-app:latest

# Scan IaC
trivy config ./terraform/
```

### CI Integration

```yaml
jobs:
  trivy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          severity: 'HIGH,CRITICAL'
          exit-code: '1'  # Fail CI on findings
```

---

## Semgrep Supply Chain

Semgrep Supply Chain combines SAST (static analysis) with dependency vulnerability scanning. It maps CVEs to your actual codebase and provides reachability analysis (does your code actually call the vulnerable function?).

### Setup

1. Create account at semgrep.dev, connect your GitHub org
2. Generate an API token: Settings → Tokens → API tokens
3. Add `SEMGREP_APP_TOKEN` as a GitHub Actions secret

### CI Integration

```yaml
# .github/workflows/security.yml
jobs:
  semgrep:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - name: Install Semgrep
        run: pip install semgrep
      - name: Run Semgrep SAST
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}
        run: |
          semgrep scan \
            --config p/typescript \
            --config p/security-audit \
            --config p/owasp-top-ten \
            --sarif --output semgrep.sarif \
            || true  # Don't fail before SARIF is written
      - name: Upload SARIF results
        uses: github/codeql-action/upload-sarif@v4
        if: always() && hashFiles('semgrep.sarif') != ''
        with:
          sarif_file: semgrep.sarif
```

**Key gotchas (learned from 5AF3Claw):**
- Never use `--error` flag with `--sarif` — if Semgrep exits non-zero before writing the SARIF file, the upload step fails with nothing to upload
- Use `|| true` to ensure the SARIF file is always created, then parse it separately for error counting
- `upload-sarif@v3` is deprecated — use `@v4`
- Private repos need `SEMGREP_APP_TOKEN` to fetch rule configs
- Add `contents: read` permission for the job

### Triage Supply Chain Findings

Semgrep exports supply chain findings as CSV from semgrep.dev. Triage workflow:

1. **Sort by severity** — Critical/High first
2. **Check EPSS score** — Low EPSS (< 0.1%) means low exploitability in the wild
3. **Check reachability** — "Reachable" findings are higher priority than "No Reachability Analysis"
4. **Check available fix** — `cargo search <crate>` or `npm view <pkg> version` for latest
5. **Assess breaking changes** — Major version bumps may require API migration
6. **Parallel fix** — Independent packages can be upgraded in parallel by separate agents

---

## cargo audit (Rust)

```bash
# Install
cargo install cargo-audit

# Scan for vulnerabilities
cargo audit

# JSON output for CI
cargo audit --json

# Fix by bumping Cargo.lock (non-breaking only)
cargo audit fix
```

### CI Integration

```yaml
jobs:
  cargo-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Install cargo-audit
        run: cargo install cargo-audit
      - name: Run audit
        run: cargo audit
```

### Rust Dependency Upgrade Strategy

When `cargo audit` or Semgrep flags a Rust crate CVE:

1. Check latest version: `cargo search <crate> --limit 1`
2. Check if it's a major bump (breaking API changes expected)
3. Read the crate's CHANGELOG for migration guide
4. Update version in `Cargo.toml` (workspace root for workspace deps)
5. Run `cargo check -p <package>` to find compilation errors
6. Fix API breakage — common patterns:
   - Builder pattern changes (consuming vs mutating)
   - New required parameters on existing functions
   - Module renames or reorganization
   - Error type changes
7. Run `cargo test -p <package>` to verify
8. Run `cargo test --workspace` to catch cross-package issues

---

## SBOM (Software Bill of Materials)

### Why SBOM?

- Required by many compliance frameworks (SOC2, FedRAMP)
- Enables rapid response to new CVEs (know exactly which versions you use)
- Supply chain transparency

### Generation

```bash
# Generate CycloneDX SBOM from npm
npx @cyclonedx/cyclonedx-npm --output-file sbom.json

# Generate SPDX SBOM with Trivy
trivy fs --format spdx-json -o sbom.spdx.json .

# Generate from Docker image
docker sbom my-app:latest --format spdx-json > sbom.json
```

---

## Secret Detection

### Pre-commit (Prevent Secrets from Being Committed)

```bash
# Install git-secrets
brew install git-secrets

# Configure for AWS patterns
git secrets --register-aws

# Add custom patterns
git secrets --add 'API_KEY\s*=\s*["\x27]\w+'
git secrets --add 'sk_live_\w+'
git secrets --add 'ghp_\w+'

# Install hook
git secrets --install
```

### CI Secret Scanning

```yaml
jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }  # Full history for scanning

      - name: TruffleHog scan
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: main
          extra_args: --only-verified
```

---

## Vulnerability Triage

### Severity Handling

| Severity | Action | Timeline |
|---|---|---|
| **Critical** | Fix immediately, emergency deploy | < 24 hours |
| **High** | Fix in current sprint | < 1 week |
| **Medium** | Schedule for next sprint | < 1 month |
| **Low** | Track, fix when convenient | < 3 months |

### Triage Questions

1. Is the vulnerable code path reachable in our app?
2. What's the attack vector? (network, adjacent, local, physical)
3. Does our configuration mitigate the vulnerability?
4. Is there a published exploit?
5. What data is at risk?

---

## Dependency Update Strategy

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
      day: monday
    open-pull-requests-limit: 10
    reviewers:
      - security-team
    labels:
      - dependencies
      - security
    ignore:
      # Don't auto-update major versions
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
```

---

## Dependency Security Checklist

- [ ] `npm audit` / `pip audit` / `cargo audit` runs in CI (blocks on high/critical)
- [ ] Snyk, Trivy, or Semgrep Supply Chain integrated for deep scanning
- [ ] Secret detection in pre-commit hooks
- [ ] SBOM generated for each release
- [ ] Dependabot or Renovate configured for automated updates
- [ ] Lockfiles committed and reviewed in PRs (including Cargo.lock)
- [ ] New dependencies reviewed before adding (check downloads, maintainers, last update)
- [ ] Critical vulnerabilities have < 24h fix SLA
- [ ] Vulnerability exceptions documented with expiration dates
- [ ] Semgrep SARIF upload configured correctly (use `|| true`, not `--error`)
- [ ] Rust crates scanned alongside npm packages in CI
