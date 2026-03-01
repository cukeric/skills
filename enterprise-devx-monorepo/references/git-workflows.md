# Git Workflows Reference

## Trunk-Based Development (Recommended for SaaS)

### Model

```
main ─────●────●────●────●────●─────▶
           \  /      \  /      \
        feat-A    feat-B    feat-C
       (1-2 days) (hours)  (1 day)
```

### Rules

1. **`main` is always deployable** — CI/CD deploys on every merge
2. **Short-lived branches** — max 2 days, ideally hours
3. **Feature flags** for incomplete features (not long branches)
4. **Squash merge** to main (clean history)
5. **No release branches** — tag releases from main

### Branch Naming

```
feat/add-user-search
fix/login-validation-error
chore/update-dependencies
docs/api-endpoint-guide
refactor/extract-auth-service
```

---

## GitFlow (For Mobile / Versioned Releases)

### Model

```
main      ─────●──────────────────●────▶
                \                /
release/1.2  ────●──●──●───────●
                  \           /
develop   ──●──●──●──●──●──●──●──●──▶
              \  /    \      /
           feat-A   feat-B
```

### Branches

| Branch | Purpose | Merges To |
|---|---|---|
| `main` | Production releases | Tags only |
| `develop` | Integration branch | — |
| `feature/*` | New features | → develop |
| `release/*` | Release prep | → main + develop |
| `hotfix/*` | Emergency fixes | → main + develop |

---

## Conventional Commits

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | When |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting (no code change) |
| `refactor` | Code restructuring |
| `perf` | Performance improvement |
| `test` | Adding/fixing tests |
| `chore` | Build, CI, deps |
| `ci` | CI/CD changes |
| `revert` | Revert previous commit |

### Examples

```
feat(auth): add Google OAuth social login
fix(api): prevent race condition in order processing
docs(readme): update installation instructions
chore(deps): update eslint to v9
feat(web)!: redesign dashboard layout

BREAKING CHANGE: Dashboard API response format changed
```

---

## Semantic Versioning

```
MAJOR.MINOR.PATCH
2.1.3
```

| Part | Increment When | Example |
|---|---|---|
| MAJOR | Breaking changes | API response format changed |
| MINOR | New features (backward compatible) | New endpoint added |
| PATCH | Bug fixes | Fixed validation error |

### Pre-release Versions

```
1.0.0-alpha.1
1.0.0-beta.1
1.0.0-rc.1
```

---

## Protected Branch Rules

```yaml
# Branch protection for main
main:
  required_status_checks:
    - lint
    - test
    - build
  required_reviews: 1
  dismiss_stale_reviews: true
  require_up_to_date: true
  require_linear_history: true  # Squash merge only
  restrict_pushes: true         # No direct push
```

---

## Git Workflow Checklist

- [ ] Branching strategy documented (trunk-based or GitFlow)
- [ ] Branch naming convention enforced
- [ ] Conventional commits enforced (commitlint)
- [ ] Protected branch rules configured
- [ ] PR merge strategy set (squash for trunk-based)
- [ ] CI required to pass before merge
- [ ] Minimum 1 review required
- [ ] Stale reviews dismissed on push
