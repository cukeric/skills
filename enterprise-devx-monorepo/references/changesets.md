# Changesets — Version Management & Release

## Bump types

- `MAJOR` — constitutional / breaking changes
- `MINOR` — new capabilities
- `PATCH` — bug fixes

Every PR that changes user-facing behavior needs a changeset: `pnpm changeset`.

## Release flow

CI `release.yml` uses `changesets/action` — it creates a "Version Packages" PR
automatically and publishes on merge to `main`. Wire `id:` + `outputs:` on the
changesets job, or the downstream publish step reads an empty `outputs.published` and
silently no-ops.

## `pnpm changeset version` — consuming changesets

`pnpm changeset version` consumes every pending changeset at once: it bumps each listed
package's version, writes per-package CHANGELOGs, and deletes the consumed changeset
files. Run it once when a release is cut. Multiple unconsumed changesets (e.g. several
feature slices deferred to ride together) are all consumed in that single run.

After running it:

- **Re-run Biome.** Changesets' JSON writer reformats `package.json` (e.g. collapses or
  expands the `files` array) in a way Biome may reject — `biome ci .` then fails the
  pre-push gate. Run `pnpm exec biome check --write .` after `changeset version`.
- **Sync the lockfile** — `pnpm install` to reconcile workspace version references.
- Internal-dependency-only bumps appear too (a package whose dep bumped gets a `patch`).

## Private-root and multi-package gotchas

See `submodule-release-gotchas.md` for: the changesets error when the private root
package is listed in changeset frontmatter (root version + README badge must be bumped
manually), workspace package version drift, and `fixed` groups for keeping a package
set on a single version line.
