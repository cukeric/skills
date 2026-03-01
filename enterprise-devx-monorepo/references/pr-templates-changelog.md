# PR Templates & Changelog Automation Reference

## PR Template

```markdown
<!-- .github/pull_request_template.md -->
## What does this PR do?

<!-- Brief description of the change -->

## Type of Change

- [ ] 🐛 Bug fix
- [ ] ✨ New feature
- [ ] 💥 Breaking change
- [ ] 📝 Documentation
- [ ] 🔧 Refactor
- [ ] ⚡ Performance
- [ ] 🧪 Tests

## How has this been tested?

<!-- Describe how you tested -->
- [ ] Unit tests
- [ ] Integration tests
- [ ] Manual testing

## Checklist

- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review
- [ ] I have added tests for my changes
- [ ] All tests pass locally
- [ ] I have updated documentation (if applicable)
- [ ] I have added a changeset (if applicable): `pnpm changeset`

## Screenshots (if UI change)

<!-- Add screenshots or screen recordings -->
```

---

## Issue Templates

```yaml
# .github/ISSUE_TEMPLATE/bug_report.yml
name: Bug Report
description: Report a bug
labels: ['bug', 'triage']
body:
  - type: textarea
    id: description
    attributes:
      label: Describe the bug
      placeholder: A clear description of the bug
    validations:
      required: true
  - type: textarea
    id: steps
    attributes:
      label: Steps to Reproduce
      value: |
        1. Go to '...'
        2. Click on '...'
        3. See error
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
    validations:
      required: true
  - type: dropdown
    id: severity
    attributes:
      label: Severity
      options:
        - Critical (app crash / data loss)
        - High (feature broken)
        - Medium (degraded experience)
        - Low (cosmetic / minor)
    validations:
      required: true
```

```yaml
# .github/ISSUE_TEMPLATE/feature_request.yml
name: Feature Request
description: Suggest a new feature
labels: ['enhancement']
body:
  - type: textarea
    id: problem
    attributes:
      label: Problem
      placeholder: What problem does this solve?
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: Proposed Solution
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives Considered
```

---

## Changesets (Changelog Automation)

### Setup

```bash
npm install -D @changesets/cli
npx changeset init
```

### Configuration

```json
// .changeset/config.json
{
  "$schema": "https://unpkg.com/@changesets/config@3.0.0/schema.json",
  "changelog": "@changesets/cli/changelog",
  "commit": false,
  "fixed": [],
  "linked": [],
  "access": "restricted",
  "baseBranch": "main",
  "updateInternalDependencies": "patch",
  "ignore": []
}
```

### Workflow

```bash
# 1. Developer creates changeset after making changes
pnpm changeset
# Prompts: which packages changed? major/minor/patch? description?

# 2. Changeset file created (committed with PR)
# .changeset/brave-dogs-laugh.md
# ---
# '@myproject/ui': minor
# '@myproject/utils': patch
# ---
# Added new Button variant and fixed date formatting

# 3. CI/release pipeline versions and publishes
pnpm changeset version  # Updates package.json versions + CHANGELOG.md
pnpm changeset publish  # Publishes to npm
```

### GitHub Action for Automated Releases

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: pnpm install --frozen-lockfile
      - name: Create Release PR or Publish
        uses: changesets/action@v1
        with:
          publish: pnpm release
          version: pnpm version-packages
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

---

## Generated CHANGELOG.md

```markdown
# @myproject/ui

## 1.3.0

### Minor Changes
- Added `ButtonGroup` component for grouping related actions
- Added `variant="ghost"` to Button component

### Patch Changes
- Fixed focus ring not showing on keyboard navigation
- Updated `@myproject/utils` to 2.1.1

## 1.2.0
...
```

---

## PR & Changelog Checklist

- [ ] PR template in `.github/pull_request_template.md`
- [ ] Issue templates for bugs and features
- [ ] Changesets configured for version management
- [ ] Changelog generated automatically from changesets
- [ ] CI creates release PRs via changesets action
- [ ] Release notes include all changes since last release
