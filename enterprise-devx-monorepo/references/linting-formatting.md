# Linting & Formatting Reference

## ESLint Flat Config (v9+)

```javascript
// eslint.config.js (root)
import eslint from '@eslint/js'
import tseslint from 'typescript-eslint'
import reactPlugin from 'eslint-plugin-react'
import reactHooks from 'eslint-plugin-react-hooks'

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    plugins: { react: reactPlugin, 'react-hooks': reactHooks },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/consistent-type-imports': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  {
    ignores: ['**/dist/**', '**/node_modules/**', '**/.next/**', '**/coverage/**'],
  }
)
```

---

## Biome (Alternative to ESLint + Prettier)

```bash
npm install --save-dev @biomejs/biome
npx biome init
```

```json
// biome.json
{
  "$schema": "https://biomejs.dev/schemas/1.5.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": { "noUnusedVariables": "warn" },
      "suspicious": { "noExplicitAny": "warn" },
      "style": { "useConst": "error" }
    }
  },
  "formatter": {
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "javascript": {
    "formatter": { "quoteStyle": "single", "trailingComma": "all", "semicolons": "asNeeded" }
  }
}
```

---

## Prettier

```json
// .prettierrc
{
  "semi": false,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "all",
  "printWidth": 100,
  "bracketSpacing": true,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

```
# .prettierignore
node_modules
dist
.next
coverage
pnpm-lock.yaml
```

---

## Git Hooks (Husky + lint-staged)

```bash
# Install
npm install -D husky lint-staged
npx husky init
```

```bash
# .husky/pre-commit
pnpm lint-staged
```

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx,js,jsx}": ["eslint --fix --max-warnings=0", "prettier --write"],
    "*.{json,md,yaml,yml,css}": ["prettier --write"]
  }
}
```

---

## Commit Linting

```bash
npm install -D @commitlint/cli @commitlint/config-conventional
```

```javascript
// commitlint.config.js
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', ['web', 'api', 'mobile', 'ui', 'utils', 'db', 'ci', 'docs']],
    'subject-case': [2, 'always', 'lower-case'],
  },
}
```

```bash
# .husky/commit-msg
npx commitlint --edit $1
```

---

## Linting Checklist

- [ ] ESLint or Biome configured with TypeScript support
- [ ] Prettier (or Biome formatter) configured
- [ ] lint-staged runs on pre-commit (husky)
- [ ] Commit messages validated (commitlint)
- [ ] CI runs lint check (fails on errors)
- [ ] IDE settings shared (.vscode/settings.json)
- [ ] No `eslint-disable` without comment explaining why
