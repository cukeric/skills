# Turborepo & Nx Reference

## Turborepo Setup

### Initialize

```bash
# New project
npx -y create-turbo@latest ./

# Add to existing project
npm install turbo --save-dev
```

### turbo.json

```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": ["**/.env.*local"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": ["$TURBO_DEFAULT$", ".env*"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "lint": {
      "dependsOn": ["^build"]
    },
    "test": {
      "dependsOn": ["^build"],
      "inputs": ["src/**", "test/**", "*.config.*"]
    },
    "type-check": {
      "dependsOn": ["^build"]
    }
  }
}
```

### Commands

```bash
# Run all
turbo build
turbo dev
turbo lint

# Filter by package
turbo build --filter=web
turbo dev --filter=web --filter=api

# Affected since last commit
turbo build --filter='...[HEAD~1]'

# Dry run (see what would run)
turbo build --dry-run

# Visualize dependency graph
turbo build --graph
```

### Remote Caching

```bash
# Login to Vercel (free remote caching)
npx turbo login
npx turbo link

# Or self-hosted
# turbo.json
{
  "remoteCache": {
    "signature": true,
    "enabled": true
  }
}
```

---

## Nx Setup

### Initialize

```bash
npx -y create-nx-workspace@latest my-project --preset=ts
```

### nx.json

```json
{
  "$schema": "./node_modules/nx/schemas/nx-schema.json",
  "targetDefaults": {
    "build": {
      "dependsOn": ["^build"],
      "cache": true
    },
    "lint": { "cache": true },
    "test": { "cache": true }
  },
  "affected": {
    "defaultBase": "main"
  },
  "namedInputs": {
    "default": ["{projectRoot}/**/*"],
    "production": ["default", "!{projectRoot}/**/*.spec.ts"]
  }
}
```

### Nx Generators

```bash
# Generate application
nx generate @nx/next:application web
nx generate @nx/node:application api

# Generate library
nx generate @nx/js:library utils --directory=packages/utils
nx generate @nx/react:library ui --directory=packages/ui

# Run affected
nx affected -t build
nx affected -t test
nx affected -t lint
```

---

## Comparison

| Feature | Turborepo | Nx |
|---|---|---|
| Setup complexity | Low | Medium |
| Config | Single turbo.json | nx.json + project.json |
| Remote caching | Vercel (free) | Nx Cloud (free tier) |
| Code generation | No | Yes (generators) |
| Dependency graph | Basic | Advanced (visualization) |
| Plugin ecosystem | Limited | Extensive |
| Best for | Simple monorepos | Complex, large orgs |
