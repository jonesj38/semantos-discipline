---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/WORKBENCH-TO-LOOM-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.670235+00:00
---

# Workbench → Loom Rename — Execution Prompt

**Hand this to Claude. It's a complete instruction set.**

---

## Instructions

You are renaming the "workbench" terminology to "loom" across the Semantos
codebase. Read `docs/prd/WORKBENCH-TO-LOOM-RENAME.md` first — it has the
full rename map, file list, and rationale. Read `docs/design/LOOM-SELF-HOSTING.md`
for architectural context.

**Do NOT use git worktrees.** Work on a normal branch.

## Git Setup

```bash
git checkout main
git pull origin main
git checkout -b rename/workbench-to-loom
```

All work happens on `rename/workbench-to-loom`. Commit in logical chunks
(file renames, then type renames, then consumer updates, then docs). Do
NOT squash into one commit — keep the history readable.

## Phase 1: File Renames (one commit)

Use `git mv` for each file rename. This preserves git history.

```
git mv packages/loom/src/types/workbench.ts packages/loom/src/types/loom.ts
git mv packages/loom/src/types/workbench.d.ts packages/loom/src/types/loom.d.ts
git mv packages/loom/src/services/WorkbenchStore.ts packages/loom/src/services/LoomStore.ts
git mv packages/loom/src/services/WorkbenchStore.d.ts packages/loom/src/services/LoomStore.d.ts
git mv packages/loom/src/state/WorkbenchProvider.tsx packages/loom/src/state/LoomProvider.tsx
git mv packages/loom/src/WorkbenchApp.tsx packages/loom/src/LoomApp.tsx
git mv packages/loom/src/canvas/WorkbenchCard.tsx packages/loom/src/canvas/LoomCard.tsx
git mv packages/loom/src/state/workbenchReducer.ts packages/loom/src/state/loomReducer.ts
git mv packages/loom/src/state/workbenchReducer.d.ts packages/loom/src/state/loomReducer.d.ts
```

Commit: `rename: git mv workbench files to loom`

## Phase 2: Type and Interface Renames (one commit)

In every `.ts` and `.tsx` file under `packages/` and `src/`, replace:

| Find | Replace |
|------|---------|
| `WorkbenchObject` | `LoomObject` |
| `WorkbenchStore` | `LoomStore` |
| `WorkbenchState` | `LoomState` |
| `WorkbenchCard` | `LoomCard` |
| `WorkbenchApp` | `LoomApp` |
| `WorkbenchProvider` | `LoomProvider` |
| `workbenchStore` | `loomStore` |
| `workbenchReducer` | `loomReducer` |

Also update import paths that reference the old filenames:

| Find | Replace |
|------|---------|
| `from '../types/workbench'` | `from '../types/loom'` |
| `from './WorkbenchStore'` | `from './LoomStore'` |
| `from './workbenchReducer'` | `from './loomReducer'` |
| `from '../WorkbenchApp'` | `from '../LoomApp'` |
| `from './WorkbenchProvider'` | `from './LoomProvider'` |

**Do this methodically.** Start with the barrel export in
`packages/loom/src/services/index.ts` — most consumers import
through there. Then update each consumer package:
- `packages/shell/src/**`
- `packages/extraction/src/**`
- `packages/__tests__/**`
- `packages/loom/src/**` (internal refs)

After all renames, run `tsc --noEmit` and fix any import errors before
committing. Do NOT commit broken code.

Commit: `rename: WorkbenchObject→LoomObject and all workbench types to loom`

## Phase 3: Backward Compatibility Aliases (one commit)

Add deprecated type aliases to `packages/loom/src/services/index.ts`
so external consumers don't break:

```typescript
// ── Backward compat aliases (remove after all consumers migrate) ──

/** @deprecated Use LoomObject */
export type WorkbenchObject = LoomObject;
/** @deprecated Use LoomStore */
export { LoomStore as WorkbenchStore };
/** @deprecated Use LoomState */
export type WorkbenchState = LoomState;
/** @deprecated Use LoomCard */
export type WorkbenchCard = LoomCard;
/** @deprecated Use loomStore */
export { loomStore as workbenchStore };
```

Commit: `rename: add backward compat aliases for workbench→loom`

## Phase 4: Comments and Strings (one commit)

Update JSDoc comments, string literals, and code comments that reference
"workbench" as the service layer. Use judgment:

- `"WorkbenchStore"` in a comment → `"LoomStore"`
- `"the workbench service layer"` → `"the loom service layer"`
- `"stored in the WorkbenchStore"` → `"stored in the LoomStore"`
- Historical references in docs like `"Phase 8.5 added the workbench"`
  → leave as-is or add `"(now: loom)"`

Do NOT rename:
- The `packages/loom/` directory
- The `@semantos/loom` package name in any `package.json`
- Any `tsconfig.json` or `vite.config.ts` path references
- Anything in `dist/` (stale build artifacts)
- Anything in `node_modules/`

Commit: `rename: update comments and strings from workbench to loom`

## Phase 5: Documentation (one commit)

Update forward-looking references to "workbench" in:
- `README.md` (root)
- `docs/design/*.md`
- `docs/prd/*.md` (selectively — current/forward refs only)

Leave historical references like "Phase 8.5 introduced the workbench"
alone, or annotate with "(now: loom)".

Commit: `docs: update workbench→loom terminology`

## Phase 6: Verify

```bash
# Must pass clean
npx tsc --noEmit

# Must match pre-rename results (1099 pass, 25 fail — same pre-existing)
bun test

# Check nothing was missed
grep -r "WorkbenchObject\|WorkbenchStore\|WorkbenchState\|WorkbenchCard" \
  --include="*.ts" --include="*.tsx" \
  packages/ src/ \
  | grep -v "dist/" \
  | grep -v "node_modules/" \
  | grep -v "@deprecated"
```

The grep should return only the backward compat alias lines. If it returns
anything else, you missed a rename.

## Phase 7: Push and PR

```bash
git push -u origin rename/workbench-to-loom
```

Create a PR with title: `rename: Workbench → Loom`

Body should summarize: what was renamed, why (link to LOOM-SELF-HOSTING.md),
the backward compat strategy, and verification results.

## Rules

- **No worktrees.** Normal branch only.
- **No force pushes.** If you mess up a commit, make a fixup commit.
- **No squashing.** Keep the phase commits separate for reviewability.
- **No renaming the package directory or package name.** That's a follow-up PR.
- **Run tsc --noEmit after every phase.** Don't stack broken commits.
- **If tests fail with NEW failures** (not the pre-existing 25), stop and fix before continuing.
