# Shared Packages Reference

## Internal Package Setup

### Package Structure

```
packages/
├── ui/
│   ├── src/
│   │   ├── Button.tsx
│   │   ├── Input.tsx
│   │   └── index.ts          # Re-exports
│   ├── package.json
│   └── tsconfig.json
├── utils/
│   ├── src/
│   │   ├── date.ts
│   │   ├── format.ts
│   │   └── index.ts
│   ├── package.json
│   └── tsconfig.json
└── config-typescript/
    ├── base.json
    ├── nextjs.json
    ├── react-native.json
    └── package.json
```

### Internal Package package.json

```json
{
  "name": "@myproject/ui",
  "version": "0.0.0",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "scripts": {
    "lint": "eslint src/",
    "type-check": "tsc --noEmit"
  },
  "peerDependencies": {
    "react": "^18.0.0",
    "react-dom": "^18.0.0"
  },
  "devDependencies": {
    "@myproject/config-typescript": "workspace:*",
    "typescript": "^5.3.0"
  }
}
```

### Consuming Packages

```json
// apps/web/package.json
{
  "dependencies": {
    "@myproject/ui": "workspace:*",
    "@myproject/utils": "workspace:*"
  }
}
```

```typescript
// apps/web/src/app/page.tsx
import { Button } from '@myproject/ui'
import { formatDate } from '@myproject/utils'
```

### pnpm Workspace Config

```yaml
# pnpm-workspace.yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

---

## Shared TypeScript Config

```json
// packages/config-typescript/base.json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "compilerOptions": {
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "exclude": ["node_modules", "dist"]
}

// packages/config-typescript/nextjs.json
{
  "extends": "./base.json",
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "module": "esnext",
    "moduleResolution": "bundler",
    "jsx": "preserve",
    "plugins": [{ "name": "next" }],
    "paths": {
      "@/*": ["./src/*"],
      "@myproject/ui": ["../../packages/ui/src"],
      "@myproject/utils": ["../../packages/utils/src"]
    }
  }
}
```

---

## Version Management

### Internal (Non-Published) Packages

- Use `"version": "0.0.0"` and `"private": true`
- Always reference with `workspace:*`
- Changes are instant (no publish step)

### Published Packages

- Use Changesets for version management
- Semantic versioning enforced
- Changelog generated automatically

---

## Dependency Management Rules

1. **Shared dependencies in root** — TypeScript, ESLint, Prettier at root level
2. **App-specific deps in app** — Next.js in web, Fastify in API
3. **Use `workspace:*`** for internal packages
4. **Single lockfile** — pnpm-lock.yaml at root only
5. **Peer dependencies** for shared React packages
