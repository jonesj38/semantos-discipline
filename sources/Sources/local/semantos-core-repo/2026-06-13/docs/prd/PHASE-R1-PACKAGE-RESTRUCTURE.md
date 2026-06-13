---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-R1-PACKAGE-RESTRUCTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.678562+00:00
---

# Phase R1: Package Restructure

**Status:** Draft
**Risk:** HIGH — touches every import path, every tsconfig, every package.json
**Prerequisite:** All feature branches merged to main, clean working tree

## Problem Statement

The `semantos-core` monorepo has accumulated structural debt across 14+ phases of development. The result is a directory layout that confuses every new session, breaks in worktrees, and contradicts its own PRD documentation. Specifically:

1. **Dual cell-engine locations.** TypeScript cell operations live in `src/cell-engine/` (published as part of `@semantos/core`), while the Zig/WASM kernel AND its TypeScript bindings live in `packages/cell-engine/`. The name collision means "cell-engine" refers to two different things depending on context.

2. **`src/` is a grab-bag.** The root `src/` directory serves as the `@semantos/core` npm package, but it contains five unrelated concerns: semantic types, a compiler, cell-engine operations, metering FSM, and recovery protocol. These have different consumers, different stability levels, and different dependency needs.

3. **`protocol-types` is a leaky bridge.** It re-exports from `@semantos/core` and adds generated constants + cell-header utilities. Its purpose is to sit between the loom and the core, but it also re-exports core types wholesale, creating circular-feeling imports. The loom's vite config must manually alias `@semantos/core`, `@semantos/protocol-types`, AND `@semantos/cell-engine` to source directories — and until today, was missing the `@semantos/core` alias entirely, breaking every worktree.

4. **No workspace protocol.** The root `package.json` has no `workspaces` field. Inter-package deps use `"file:../../"` which relies on `npm install` having run to create symlinks in `node_modules`. Worktrees don't get these symlinks, so Vite can't resolve bare specifiers like `from "@semantos/core"`.

5. **PRDs reference a nonexistent sibling repo.** Multiple phase prompts say "the Zig/WASM cell engine lives in the sibling `semantos` repo." This is false — it's at `packages/cell-engine/` in this repo. Every new session that reads these PRDs gets confused.

6. **Constants package has no package.json.** `packages/constants/` is a codegen utility but isn't a formal workspace member.

7. **Stale worktrees.** `.claude/worktrees/` has accumulated 7+ worktree directories from previous sessions.

## Target State

After this phase, the repo should look like this:

```
semantos-core/
├── package.json              ← workspaces: ["packages/*"]
├── tsconfig.base.json        ← shared compiler options
├── tsconfig.json             ← extends base, rootDir: src (for @semantos/core build)
│
├── src/                      ← @semantos/core (types + compiler ONLY)
│   ├── index.ts
│   ├── types/                ← semantic object types, capability, GIP, etc.
│   └── compiler/             ← consumption rule validation
│
├── packages/
│   ├── constants/            ← codegen utility (gets a package.json)
│   │   ├── package.json
│   │   ├── generate.ts
│   │   └── constants.json
│   │
│   ├── protocol-types/       ← @semantos/protocol-types (constants + cell-header)
│   │   ├── package.json      ← deps: @semantos/core (workspace:*)
│   │   └── src/
│   │
│   ├── cell-engine/          ← @semantos/cell-engine (Zig kernel + TS bindings)
│   │   ├── package.json      ← deps: @semantos/core, @semantos/protocol-types
│   │   ├── build.zig
│   │   ├── zig/              ← renamed from src/ to avoid confusion with TS src/
│   │   ├── bindings/         ← TypeScript WASM loader + host functions
│   │   ├── tests/            ← Zig conformance tests
│   │   └── tests-bun/        ← TypeScript integration tests
│   │
│   ├── cell-ops/             ← NEW: @semantos/cell-ops (moved from src/cell-engine/)
│   │   ├── package.json      ← deps: @semantos/core
│   │   └── src/
│   │       ├── index.ts
│   │       ├── typeHashRegistry.ts
│   │       ├── cellPacker.ts
│   │       ├── merkleEnvelope.ts
│   │       ├── opcodes.ts
│   │       └── wasm-interface.ts
│   │
│   ├── metering/             ← NEW: @semantos/metering (moved from src/metering/)
│   │   ├── package.json      ← deps: @semantos/core
│   │   └── src/
│   │
│   ├── recovery/             ← NEW: @semantos/recovery (moved from src/recovery/)
│   │   ├── package.json      ← deps: @semantos/core
│   │   └── src/
│   │
│   ├── workbench/            ← @semantos/loom (React UI)
│   │   ├── package.json
│   │   ├── vite.config.ts    ← aliases resolve via workspace, not relative paths
│   │   └── ...
│   │
│   └── __tests__/            ← integration gate tests
│       └── ...
│
├── configs/                  ← extension config JSON
├── proofs/                   ← Lean formal verification
├── docs/                     ← PRDs, design docs
└── scripts/                  ← utilities
```

### Key Changes

| What | From | To | Why |
|------|------|----|-----|
| Cell packer, type hashes, merkle, opcodes, wasm-interface | `src/cell-engine/` | `packages/cell-ops/src/` | Separate from core types; own package with own deps |
| Metering FSM | `src/metering/` | `packages/metering/src/` | Independent concern, rarely changes |
| Recovery protocol | `src/recovery/` | `packages/recovery/src/` | Independent concern, rarely changes |
| Zig source dir | `packages/cell-engine/src/` | `packages/cell-engine/zig/` | Disambiguate from TypeScript `src/` convention |
| Root `src/` | Types + compiler + cell-engine + metering + recovery | Types + compiler ONLY | `@semantos/core` becomes lean and stable |
| Inter-package deps | `"file:../../"` | `"workspace:*"` | Works in worktrees without npm install |
| Shared tsconfig | Duplicated paths in 4 tsconfigs | `tsconfig.base.json` | Single source of truth for paths |

### What `@semantos/core` Exports After Restructure

```typescript
// src/index.ts — lean and stable
export * from './types/index.js';
export * as Compiler from './compiler/index.js';
```

The cell operations, metering, and recovery move to their own packages. Any consumer that needs them imports from `@semantos/cell-ops`, `@semantos/metering`, or `@semantos/recovery` directly.

## Deliverables

### D-R1.1: Workspace Configuration
- Add `"workspaces": ["packages/*"]` to root `package.json`
- Add `package.json` to `packages/constants/`
- Change all `"file:../../"` deps to `"workspace:*"`

### D-R1.2: Extract `@semantos/cell-ops`
- Create `packages/cell-ops/` with `package.json`
- Move `src/cell-engine/*.ts` → `packages/cell-ops/src/`
- Update `src/index.ts` to remove cell-engine re-export
- Add `@semantos/cell-ops` dep where needed (protocol-types, workbench, tests)

### D-R1.3: Extract `@semantos/metering` and `@semantos/recovery`
- Create `packages/metering/` and `packages/recovery/` with `package.json`
- Move `src/metering/*.ts` and `src/recovery/*.ts`
- Update `src/index.ts`

### D-R1.4: Rename Zig Source Directory
- Rename `packages/cell-engine/src/` → `packages/cell-engine/zig/`
- Update `build.zig` to reference `zig/` instead of `src/`
- Update any test imports

### D-R1.5: Consolidate TypeScript Configuration
- Create `tsconfig.base.json` with shared `compilerOptions`
- All package `tsconfig.json` files extend `tsconfig.base.json`
- Workspace protocol means paths resolve automatically — remove manual path aliases where possible
- Keep vite `resolve.alias` for dev server (vite doesn't read tsconfig paths natively)

### D-R1.6: Update All Import Paths
- `@semantos/core` consumers that import cell-engine ops → change to `@semantos/cell-ops`
- `@semantos/core` consumers that import metering → change to `@semantos/metering`
- `@semantos/core` consumers that import recovery → change to `@semantos/recovery`
- Loom vite config: update aliases to match new locations
- Protocol-types: update re-exports

### D-R1.7: Clean Up Stale Artifacts
- Remove `.claude/worktrees/` directories (after confirming no uncommitted work)
- Update PRD docs: replace "sibling `semantos` repo" with correct paths
- Update root README.md if needed

### D-R1.8: Gate Tests
- All existing Phase 0, 9, 9.5, 11, 14 gate tests must pass
- `bun run check` (tsc --noEmit) must pass with zero errors
- `bun run build` must succeed
- Workbench dev server must start (`bun run dev` in packages/loom)
- New test: import from each new package resolves correctly

## Risk Mitigation

This is the riskiest phase so far because it touches every import in the project. The execution prompt below enforces strict git hygiene.

### Safety Rules

1. **Branch from main.** All work on a dedicated branch. Main stays untouched until merge.
2. **One deliverable per commit.** Each D-R1.x is a separate commit. If anything breaks, bisect finds the exact commit.
3. **Test after every commit.** Run `bun run check && bun test packages/__tests__/` after each commit. If it fails, fix before moving on.
4. **No force pushes.** Ever.
5. **Checkpoint tags.** Tag `pre-restructure` on main before starting. Tag `post-restructure` after all tests pass.
6. **Worktree-safe.** After restructure, verify a fresh worktree can `bun install && bun run dev` without manual path fixups.

## Success Criteria

- [ ] `bun install` from a fresh clone resolves all workspace deps
- [ ] `bun run check` returns zero errors
- [ ] `bun run build` succeeds
- [ ] `bun test packages/__tests__/` — all gates pass (Phase 0 gates skip gracefully if zig/lean not installed)
- [ ] `cd packages/loom && bun run dev` starts without errors
- [ ] Fresh git worktree: `bun install && cd packages/loom && bun run dev` works
- [ ] `grep -rn "sibling.*semantos" docs/` returns zero hits
- [ ] `grep -rn "file:../../" packages/` returns zero hits (all using workspace:*)
- [ ] No TypeScript file in `src/` imports from `packages/` or vice versa (clean dependency direction)
