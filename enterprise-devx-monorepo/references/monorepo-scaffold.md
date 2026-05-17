# Monorepo Scaffold — pnpm Workspaces + Turborepo

Structure, package script standards, and tsconfig inheritance for a pnpm + Turborepo
monorepo.

## Directory structure

```
repo/
├── apps/                    # Deployable applications
│   └── [app]/
├── packages/                # Shared packages
│   ├── core/                # Foundation types, schemas, utilities
│   └── [domain]/            # Feature packages
├── .github/
│   └── workflows/
│       ├── ci.yml           # Primary CI (lint, typecheck, test, build, security)
│       ├── release.yml      # Changesets release automation
│       ├── security.yml     # Nightly SAST + secret scan
│       └── drift-check.yml  # Integrity checks (if applicable)
├── turbo.json               # Turborepo task graph
├── biome.json               # Biome lint + format config
├── pnpm-workspace.yaml      # Workspace package globs
├── package.json             # Root scripts + devDependencies
└── tsconfig.base.json       # Shared TS config (extended by packages)
```

## Package script standards

Every package's `package.json` must have these scripts and they must exit 0 on a clean
repo:

```json
{
  "scripts": {
    "build": "tsc --project tsconfig.json",
    "typecheck": "tsc --noEmit",
    "test": "vitest run --passWithNoTests",
    "clean": "rm -rf dist coverage"
  }
}
```

**Critical rules:**

- `vitest run` (without `--passWithNoTests`) exits 1 if there are no test files — always
  use `--passWithNoTests` for new/stub packages.
- `tsc --noEmit` requires a `tsconfig.json` in the package root — if the package is a
  non-TS stub (Rust, Python), use `echo 'N/A — [lang] in M[n]'` instead.
- Never use `npm run` in CI — always `pnpm run`.
- **`build` must actually emit `dist/`.** A no-op `build` script (e.g.
  `echo 'wasm-pack runs in CI'`) means turbo's `^build` produces nothing — any package
  importing a `dist/`-pointed subpath of it then fails on a clean checkout. If the real
  build is a separate step (`build:ts`, `wasm-pack`), either make `build` run it, or
  build the package explicitly in CI in dependency order. See `ci-local-parity.md` §3.

## tsconfig inheritance

`tsconfig.base.json` at the root holds shared compiler options; each package's
`tsconfig.json` extends it and sets only `outDir` / `rootDir` / `include`:

```jsonc
// packages/<pkg>/tsconfig.json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": { "outDir": "./dist", "rootDir": "./src" },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "**/*.test.ts"]
}
```

## turbo.json task graph

`build`, `typecheck`, and `test` should declare `dependsOn: ["^build"]` so dependencies
build first. Caveat: `^build` only runs *dependencies'* `build` — a package's own
`dist/` is not produced by its `test`/`typecheck` task. Scripts that need the package's
own `dist/` (a `migrate` entrypoint) must build it explicitly.
