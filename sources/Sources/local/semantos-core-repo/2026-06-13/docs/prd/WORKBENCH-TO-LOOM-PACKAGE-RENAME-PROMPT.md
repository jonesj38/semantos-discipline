---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/WORKBENCH-TO-LOOM-PACKAGE-RENAME-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.670488+00:00
---

# Workbench → Loom Package Rename — Execution Prompt

**Hand this to Claude. This is the follow-up to PR #68 (terminology rename).**
**Merge PR #68 first before running this.**

---

## Context

PR #68 renamed all `Workbench*` types, interfaces, variables, comments,
and docs to `Loom*`. But the package directory and npm package name were
intentionally left as `@semantos/loom` and `packages/loom/` to
avoid breaking workspace resolution in that same PR.

This PR finishes the job: rename the package itself so imports read
`from '@semantos/loom'` instead of `from '@semantos/loom'`.

Read `docs/design/LOOM-SELF-HOSTING.md` for architectural rationale.

## Git Setup

```bash
git checkout main
git pull origin main
git checkout -b rename/workbench-package-to-loom
```

All work happens on `rename/workbench-package-to-loom`. **No worktrees.**
**No force pushes.** If you mess up, make a fixup commit.

## Phase 1: Rename the Package Directory (one commit)

```bash
git mv packages/loom packages/loom
```

This will break everything. That's expected — Phase 2 fixes it.

Commit: `rename: git mv packages/loom to packages/loom`

## Phase 2: Update package.json Files (one commit)

### Root package.json

The root `package.json` has a `workspaces` field. Update it:

```
// Old
"workspaces": ["packages/*"]
```

If workspaces is `["packages/*"]` it will auto-resolve and no change is
needed. But if `packages/loom` is listed explicitly anywhere in root
`package.json`, update it to `packages/loom`.

### packages/loom/package.json

Update the package name:

```json
{
  "name": "@semantos/loom",
  ...
}
```

Also check and update any self-referencing paths in the `exports` field,
`main` field, `types` field, or `files` field. These are relative paths
within the package so they should still work, but verify.

### All other packages that depend on @semantos/loom

Search every `package.json` under `packages/` for `@semantos/loom`
in `dependencies`, `devDependencies`, or `peerDependencies`:

```bash
grep -r "@semantos/loom" packages/*/package.json
```

Replace each occurrence with `@semantos/loom`.

Known consumers (verify this list against grep results):
- `packages/shell/package.json`
- `packages/extraction/package.json`
- Any other package that imports from `@semantos/loom`

Commit: `rename: update package.json @semantos/loom → @semantos/loom`

## Phase 3: Update All Import Paths (one commit)

This is the big one. Every `from '@semantos/loom'` import across the
entire codebase needs to become `from '@semantos/loom'`.

```bash
# Find all files with the old import
grep -r "@semantos/loom" --include="*.ts" --include="*.tsx" packages/ src/
```

Replace in all `.ts` and `.tsx` files:

| Find | Replace |
|------|---------|
| `from '@semantos/loom'` | `from '@semantos/loom'` |
| `from "@semantos/loom"` | `from "@semantos/loom"` |
| `import('@semantos/loom')` | `import('@semantos/loom')` |
| `require('@semantos/loom')` | `require('@semantos/loom')` |

Also check for path-based imports within the package itself:
- `from '@semantos/loom/browser'` → `from '@semantos/loom/browser'`
- Any other sub-path exports

**After all replacements, run `tsc --noEmit` and fix any errors before
committing.**

Commit: `rename: update all imports @semantos/loom → @semantos/loom`

## Phase 4: Update Config Files (one commit)

Check and update any references in:

- `tsconfig.json` and `tsconfig.base.json` — path mappings, references
- `packages/loom/vite.config.ts` — any package name references
- `docker-compose*.yml` — if any reference the package path
- `.github/` or CI configs — if any reference `packages/loom`
- `bun.lock` or `pnpm-lock.yaml` — these will regenerate, but check
  for hardcoded references

```bash
# Broad check for anything still referencing the old path or name
grep -r "packages/loom\|@semantos/loom" \
  --include="*.json" --include="*.yaml" --include="*.yml" \
  --include="*.toml" --include="*.ts" --include="*.tsx" \
  --include="*.js" --include="*.mjs" \
  . | grep -v node_modules | grep -v dist | grep -v ".lock"
```

Fix anything that comes back.

Commit: `rename: update config files workbench → loom`

## Phase 5: Update Documentation (one commit)

Search docs for any remaining references to `@semantos/loom` or
`packages/loom/`:

```bash
grep -r "packages/loom\|@semantos/loom" docs/ README.md
```

Update to `packages/loom` and `@semantos/loom` respectively.

Commit: `docs: update package references workbench → loom`

## Phase 6: Reinstall Dependencies and Remove Backward Compat

### Reinstall

```bash
rm -rf node_modules packages/*/node_modules
bun install
```

This forces workspace resolution to pick up the new package name.
If `bun.lock` changes, stage it.

### Remove backward compat aliases

In `packages/loom/src/services/index.ts`, remove the deprecated aliases
that PR #68 added:

```typescript
// REMOVE THESE:
/** @deprecated Use LoomObject */
export type WorkbenchObject = LoomObject;
/** @deprecated Use LoomStore */
export { LoomStore as WorkbenchStore };
// ... etc
```

These were a bridge for external consumers during the transition. Now
that the package name itself has changed, anyone importing from the old
name will get a module-not-found error anyway — the aliases don't help.

Also remove the `SEMANTOS_FACET` backward compat fallback in the shell
config if it's still there — same reasoning. The hat rename is done.

Commit: `cleanup: remove backward compat aliases and reinstall deps`

## Phase 7: Verify

```bash
# Must pass clean
npx tsc --noEmit

# Must match pre-rename results (no new failures)
bun test

# Nothing should reference the old package name or path
grep -r "packages/loom\|@semantos/loom" \
  --include="*.ts" --include="*.tsx" --include="*.json" \
  --include="*.md" --include="*.yaml" --include="*.yml" \
  . | grep -v node_modules | grep -v dist | grep -v ".lock"
```

The final grep should return **nothing**. If it returns anything, you
missed a reference.

## Phase 8: Push and PR

```bash
git push -u origin rename/workbench-package-to-loom
```

Create a PR with title: `rename: @semantos/loom → @semantos/loom`

Body should reference PR #68 as the prerequisite and note that this
completes the workbench→loom rename.

## Rules

- **Merge PR #68 first.** This PR builds on that work.
- **No worktrees.** Normal branch only.
- **No force pushes.** Fixup commits if you mess up.
- **No squashing.** Keep phase commits separate.
- **Run `tsc --noEmit` after Phases 3 and 6.** Don't stack broken commits.
- **Run `bun install` after Phase 2 and again in Phase 6.** Workspace
  resolution won't work until the package.json names are consistent.
- **If `bun install` fails**, check that every package.json referencing
  the old name has been updated. The lockfile may need regenerating
  (`rm bun.lock && bun install`).
