# Biome Reference — Lint, Format, CI Integration

Biome is the all-in-one linter + formatter that replaces ESLint + Prettier. Zero config for most projects; fast (Rust-based); one tool for both concerns.

---

## Installation

```bash
pnpm add -D @biomejs/biome -w
```

## Initialization

```bash
pnpm exec biome init
```

This generates `biome.json` in the project root.

---

## Standard `biome.json`

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "files": {
    "ignore": ["node_modules", "dist", ".turbo", "coverage", "*.d.ts"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true
    }
  },
  "organizeImports": {
    "enabled": true
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double",
      "trailingCommas": "all",
      "semicolons": "always"
    }
  }
}
```

---

## Commands — Safe vs Unsafe Fixes

This distinction is critical. **CI runs `biome ci` (read-only). Pre-push must run `biome check --write --unsafe`.**

| Command | What it does | When to use |
|---|---|---|
| `biome ci .` | Read-only check — reports errors, exits non-zero on any error or warning-as-error. **No files modified.** | CI gate |
| `biome check --write .` | Applies **safe** fixes only. Unsafe fixes are skipped silently. | Quick pre-save |
| `biome check --write --unsafe .` | Applies ALL fixes including unsafe ones (`useLiteralKeys`, `noConsoleLog`, etc.) | **Pre-push gate** |
| `biome format --write .` | Formatting only, no lint | Not recommended — use `check` |
| `biome lint --write .` | Lint + safe fixes only | Not recommended — use `check` |

### Why `--unsafe` is needed

Biome classifies fixes as "safe" (guaranteed to not change runtime behavior) and "unsafe" (might change behavior in edge cases). Common **unsafe** rules that fire in TypeScript:

| Rule | Example | Safe? |
|---|---|---|
| `useLiteralKeys` | `obj["key"]` → `obj.key` | Unsafe (type narrowing edge case) |
| `noConsoleLog` | removes `console.log(...)` | Unsafe (removes code) |
| `noUnusedVariables` | prefix with `_` | Unsafe (renames) |
| `useConst` | `let x = 1` → `const x = 1` | Safe |
| `noVar` | `var x` → `let x` | Safe |

**If CI shows errors from these rules, `biome check --write` will NOT fix them.** You must run `biome check --write --unsafe .`.

### Pre-push gate command

```bash
# The correct pre-push sequence for Biome:
pnpm exec biome check --write --unsafe .
git add -A  # Re-stage any files Biome modified
# Then commit and push
```

**Critical:** After `biome check --write --unsafe .`, always `git add` and commit the changed files before pushing. Files modified by Biome but not committed cause CI to fail with the same errors you just fixed locally.

---

## CI Integration

```yaml
- name: Biome check (lint + format)
  run: pnpm exec biome ci .
```

`biome ci` is the CI-specific command:
- Treats all warnings as errors
- Never modifies files (read-only)
- Exits non-zero on any issue

---

## Rule Suppression

### Inline suppression

```typescript
// biome-ignore lint/suspicious/noExplicitAny: gRPC service constructor is dynamically loaded
type JudgeClientCtor = new (addr: string, creds: grpc.ChannelCredentials) => any;
```

Format: `// biome-ignore lint/<group>/<rule>: <rationale>`

### Config-level suppression (use sparingly)

```json
{
  "linter": {
    "rules": {
      "suspicious": {
        "noExplicitAny": "off"
      },
      "complexity": {
        "useLiteralKeys": "off"
      }
    }
  }
}
```

**Prefer inline suppression** — it's explicit about WHY and limits scope to the exact line.

---

## Common Errors and Fixes

### `useLiteralKeys` — `obj["key"]` flagged

```typescript
// Before (Biome flags)
process.env["JUDGE_GRPC_ADDR"]

// After (Biome prefers)
process.env.JUDGE_GRPC_ADDR
```

Fix: `biome check --write --unsafe .`

### `noConsoleLog` — `console.log` flagged

```typescript
// Before
console.log("PASS");

// After (use console.info for intentional output)
console.info("PASS");
```

Fix: `biome check --write --unsafe .` (removes the line entirely — review before committing)

### `noUnusedVariables` — unused parameter

```typescript
// Before — Biome flags `intentId` as unused
export async function submitForJudgement(
  intentId: string,
  actionPayload: ActionPayload,
): Promise<JudgementResponse>

// After — prefix with _ to signal intentional unused
export async function submitForJudgement(
  _intentId: string,
  actionPayload: ActionPayload,
): Promise<JudgementResponse>
```

Fix: `biome check --write --unsafe .`

---

## Monorepo Configuration

For monorepos, one `biome.json` at the root covers all packages. No per-package config needed unless a package has different rules.

```json
{
  "files": {
    "ignore": [
      "node_modules",
      "dist",
      ".turbo",
      "coverage",
      "**/pkg/**",
      "**/*.d.ts"
    ]
  }
}
```

**Include `**/pkg/**` to exclude wasm-pack output directories from linting.**

---

## Integration Checklist

- [ ] `biome.json` at monorepo root
- [ ] `pnpm exec biome ci .` in CI lint job (not `check`, not `format`)
- [ ] Pre-push gate runs `biome check --write --unsafe .` (not just `--write`)
- [ ] After `biome check --write --unsafe .`, files are re-staged and committed before push
- [ ] `**/pkg/**` excluded (wasm-pack output)
- [ ] `coverage`, `dist`, `.turbo` excluded
- [ ] `// biome-ignore` comments include rationale
