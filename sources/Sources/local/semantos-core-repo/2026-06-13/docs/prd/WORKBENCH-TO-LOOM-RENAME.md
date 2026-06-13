---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/WORKBENCH-TO-LOOM-RENAME.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.710544+00:00
---

# Workbench → Loom Rename

## Context

The service layer currently called "workbench" is being renamed to **loom**.
A loom holds warp threads (type system, taxonomy, identity, governance) under
tension while the shuttle (user intent) weaves through. The helm and shell are
renderers — two ways of throwing the shuttle. The Paskian graph is the pattern
that emerges in the cloth. See `docs/design/LOOM-SELF-HOSTING.md` for the
full architectural rationale.

This rename follows the same pattern as the Facet→Hat rename (commit f0c3a71).

## Scope

682 occurrences of "workbench" across ~100 files (source, tests, docs, configs).
64 source files reference `WorkbenchObject`, `WorkbenchStore`, `WorkbenchState`,
`WorkbenchCard`, or `WorkbenchApp`.

**The `packages/loom/` directory itself is NOT renamed in this pass.**
The package stays at `@semantos/loom` and `packages/loom/` for now —
renaming the package would break workspace resolution, import paths across every
consumer, and CI. That's a separate PR. This rename targets the *terminology
inside* the package and across the repo.

## Rename Map

### Type / Interface Renames (source files)

| Old | New | Notes |
|-----|-----|-------|
| `WorkbenchObject` | `LoomObject` | Core type, ~64 files |
| `WorkbenchStore` | `LoomStore` | Service singleton |
| `WorkbenchState` | `LoomState` | Reducer state |
| `WorkbenchCard` | `LoomCard` | Canvas card |
| `WorkbenchApp` | `LoomApp` | React root component |
| `WorkbenchProvider` | `LoomProvider` | React context provider |
| `workbenchStore` | `loomStore` | Singleton instance |
| `workbenchReducer` | `loomReducer` | State reducer |

### File Renames

| Old | New |
|-----|-----|
| `packages/loom/src/types/workbench.ts` | `packages/loom/src/types/loom.ts` |
| `packages/loom/src/types/workbench.d.ts` | `packages/loom/src/types/loom.d.ts` |
| `packages/loom/src/services/WorkbenchStore.ts` | `packages/loom/src/services/LoomStore.ts` |
| `packages/loom/src/services/WorkbenchStore.d.ts` | `packages/loom/src/services/LoomStore.d.ts` |
| `packages/loom/src/state/WorkbenchProvider.tsx` | `packages/loom/src/state/LoomProvider.tsx` |
| `packages/loom/src/WorkbenchApp.tsx` | `packages/loom/src/LoomApp.tsx` |
| `packages/loom/src/canvas/WorkbenchCard.tsx` | `packages/loom/src/canvas/LoomCard.tsx` |
| `packages/loom/src/state/workbenchReducer.ts` | `packages/loom/src/state/loomReducer.ts` |
| `packages/loom/src/state/workbenchReducer.d.ts` | `packages/loom/src/state/loomReducer.d.ts` |

### Singleton / Variable Renames

| Old | New | File |
|-----|-----|------|
| `workbenchStore` | `loomStore` | `packages/loom/src/services/index.ts` |
| `WorkbenchStore()` constructor calls | `LoomStore()` | same |

### Import Path Updates

Every file that imports from the renamed files needs its import path updated.
The barrel export in `packages/loom/src/services/index.ts` re-exports
most types — update the re-exports there and most consumers just work.

Key barrel updates in `packages/loom/src/services/index.ts`:
```
// Old
export type { WorkbenchObject, WorkbenchCard, WorkbenchState, ... } from '../types/workbench';
export { WorkbenchStore } from './WorkbenchStore';
export const workbenchStore = new WorkbenchStore();

// New
export type { LoomObject, LoomCard, LoomState, ... } from '../types/loom';
export { LoomStore } from './LoomStore';
export const loomStore = new LoomStore();
```

### Backward Compatibility Aliases

Add backward compat type aliases in the barrel export (same pattern as
`SEMANTOS_FACET` env var fallback for hats):

```typescript
// Backward compat — remove after all consumers migrate
/** @deprecated Use LoomObject */
export type WorkbenchObject = LoomObject;
/** @deprecated Use LoomStore */
export type WorkbenchStore = LoomStore;
/** @deprecated Use LoomState */
export type WorkbenchState = LoomState;
/** @deprecated Use LoomCard */
export type WorkbenchCard = LoomCard;
/** @deprecated Use loomStore */
export const workbenchStore = loomStore;
```

### Consumer Packages to Update

These packages import workbench types and need their references updated:

1. **`packages/shell/src/types.ts`** — `ShellContext` references `WorkbenchStore`, `FlowRunner`, etc.
2. **`packages/shell/src/**`** — all shell commands that reference `WorkbenchObject`
3. **`packages/extraction/src/**`** — extraction pipeline references `WorkbenchObject`
4. **`packages/__tests__/**`** — gate tests reference workbench types
5. **`packages/loom/src/helm/**`** — helm components reference `WorkbenchObject`
6. **`packages/loom/src/canvas/**`** — canvas components
7. **`packages/loom/src/panels/**`** — panel components
8. **`packages/loom/src/commands/**`** — command executor

### Documentation Updates

All docs referencing "workbench" as the service layer should be updated
to "loom". This includes:

- `README.md` (root) — update the architecture diagram and descriptions
- `docs/prd/*.md` — ~50 files with "workbench" references
- `docs/design/*.md` — architecture docs
- `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` — key architecture doc

**Judgment call for docs:** "workbench" in historical context (e.g.,
"Phase 8.5 added the workbench service layer") can stay as-is or get a
parenthetical "(now: loom)". Current/forward-looking references should
use "loom".

### What NOT to Rename

| Keep as-is | Reason |
|------------|--------|
| `packages/loom/` directory | Package rename is a separate PR |
| `@semantos/loom` package name | Same — breaks workspace resolution |
| `package.json` name field | Same |
| `vite.config.ts` references | Points to package path, not terminology |
| `tsconfig.json` path mappings | Same |
| `dist/` files | Build artifacts, will regenerate |

## Execution Order

1. **Rename source files** (git mv) — type files, store files, component files
2. **Update type/interface names** — WorkbenchObject→LoomObject etc. across all .ts/.tsx
3. **Update variable names** — workbenchStore→loomStore, workbenchReducer→loomReducer
4. **Update import paths** — every file importing from renamed files
5. **Add backward compat aliases** — in barrel export
6. **Update docs** — README, PRDs, design docs (forward-looking refs only)
7. **Verify** — `tsc --noEmit` clean, `bun test` same results as before

## Verification

Same standard as the Facet→Hat rename:
- `tsc --noEmit` must pass clean
- Test results must be identical to pre-rename (currently 1099 pass, 25 fail — same pre-existing failures)
- No runtime behavior changes — this is purely a terminology rename
- Backward compat aliases ensure no breaking changes for any external consumers

## Post-Rename Follow-up (Separate PR)

- Rename `packages/loom/` → `packages/loom/`
- Update `@semantos/loom` → `@semantos/loom` in all package.json files
- Update all workspace resolution and import paths
- Remove backward compat aliases
