---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-R1-EXECUTION-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.711966+00:00
---

# Phase R1 Execution Prompt — Package Restructure

**Hand this to a fresh Claude Code session.** It contains everything needed.

---

## Context

You are working on `semantos-core`, a TypeScript + Zig/WASM monorepo. Read `docs/prd/PHASE-R1-PACKAGE-RESTRUCTURE.md` for the full PRD — it explains WHY we're doing this.

The short version: the repo's `src/` directory bundles five unrelated concerns into one `@semantos/core` package, inter-package deps use fragile `file:` paths that break in worktrees, and the cell-engine name is overloaded (TypeScript operations in `src/cell-engine/` vs Zig kernel in `packages/cell-engine/`). We're extracting packages, adding workspace protocol, and cleaning up.

## MANDATORY: Git Safety Protocol

Before writing ANY code:

```bash
# 1. Ensure clean state
git status  # must be clean
git stash   # if needed

# 2. Tag the safe point
git tag pre-restructure-r1

# 3. Create working branch
git checkout -b phase-r1-package-restructure

# 4. Verify tests pass BEFORE changes
bun run check 2>&1 | head -20     # note any pre-existing errors
bun test packages/__tests__/ 2>&1 | tail -20  # note any pre-existing failures
```

**After EVERY deliverable commit**, run:
```bash
bun run check 2>&1 | head -20
bun test packages/__tests__/ 2>&1 | tail -20
```

If new errors appear that weren't in the pre-existing set, FIX THEM before moving on. Do not accumulate debt.

**If something goes catastrophically wrong:**
```bash
git checkout main
git branch -D phase-r1-package-restructure  # only if truly unrecoverable
```

The `pre-restructure-r1` tag is your safety net.

## Deliverable Execution Order

### D-R1.1: Workspace Configuration

**Goal:** Enable `workspace:*` protocol so packages resolve without `file:` paths.

1. Edit root `package.json` — add:
   ```json
   "workspaces": ["packages/*"]
   ```

2. Create `packages/constants/package.json`:
   ```json
   {
     "name": "@semantos/constants",
     "version": "0.3.0",
     "private": true,
     "scripts": {
       "generate": "bun generate.ts"
     }
   }
   ```

3. In `packages/protocol-types/package.json`, change:
   ```json
   "@semantos/core": "file:../../"
   ```
   to:
   ```json
   "@semantos/core": "workspace:*"
   ```

4. In `packages/cell-engine/package.json`, change both `file:` deps to `workspace:*`.

5. Run `bun install` to regenerate the lockfile with workspace links.

6. Verify: `bun run check` should behave identically to before.

**Commit:** `git commit -m "D-R1.1: enable workspace protocol, formalize constants package"`

---

### D-R1.2: Extract `@semantos/cell-ops`

**Goal:** Move TypeScript cell operations out of `src/` into their own package.

1. Create directory: `packages/cell-ops/src/`

2. Create `packages/cell-ops/package.json`:
   ```json
   {
     "name": "@semantos/cell-ops",
     "version": "0.3.0",
     "private": true,
     "main": "src/index.ts",
     "types": "src/index.ts",
     "dependencies": {
       "@semantos/core": "workspace:*"
     }
   }
   ```

3. Move files:
   ```bash
   git mv src/cell-engine/cellPacker.ts packages/cell-ops/src/
   git mv src/cell-engine/merkleEnvelope.ts packages/cell-ops/src/
   git mv src/cell-engine/typeHashRegistry.ts packages/cell-ops/src/
   git mv src/cell-engine/opcodes.ts packages/cell-ops/src/
   git mv src/cell-engine/wasm-interface.ts packages/cell-ops/src/
   git mv src/cell-engine/index.ts packages/cell-ops/src/
   ```

4. Remove the now-empty `src/cell-engine/` directory.

5. Update `src/index.ts`:
   - REMOVE: `export * from './cell-engine/index.js';`
   - The core package no longer re-exports cell operations.

6. Create `packages/cell-ops/tsconfig.json`:
   ```json
   {
     "extends": "../../tsconfig.base.json",
     "compilerOptions": {
       "rootDir": "src",
       "outDir": "dist",
       "paths": {
         "@semantos/core": ["../../src"],
         "@semantos/core/*": ["../../src/*"]
       }
     },
     "include": ["src/**/*.ts"]
   }
   ```

7. **CRITICAL — update all consumers:**

   Search for every file that imports from `@semantos/core` and uses cell-engine exports (computeTypeHash, buildCellHeader, packCell, unpackCell, CellHeader, PipelinePhase, Dimension, Linearity, cellPacker functions, merkle functions, etc.):

   ```bash
   grep -rn "from.*@semantos/core" packages/ --include="*.ts" --include="*.tsx"
   grep -rn "from.*cell-engine" packages/ --include="*.ts" --include="*.tsx"
   ```

   Change those imports to `from "@semantos/cell-ops"` or `from "@semantos/cell-ops/src/typeHashRegistry"` as appropriate.

   Key files to check:
   - `packages/protocol-types/src/index.ts` — re-exports from @semantos/core
   - `packages/cell-engine/bindings/bun/cell-engine.ts` — imports cell ops
   - `packages/cell-engine/tests-bun/*.test.ts` — test imports
   - `packages/loom/src/**` — loom imports
   - `packages/__tests__/*.test.ts` — gate tests

8. Update `packages/loom/vite.config.ts` — add alias:
   ```typescript
   '@semantos/cell-ops': path.resolve(__dirname, '../cell-ops/src'),
   ```

9. Update `packages/loom/tsconfig.json` — add path:
   ```json
   "@semantos/cell-ops": ["../cell-ops/src"],
   "@semantos/cell-ops/*": ["../cell-ops/src/*"]
   ```

10. Update any `package.json` that needs `@semantos/cell-ops` as a dependency.

11. Run `bun install && bun run check && bun test packages/__tests__/`.

**Commit:** `git commit -m "D-R1.2: extract @semantos/cell-ops from src/cell-engine/"`

---

### D-R1.3: Extract `@semantos/metering` and `@semantos/recovery`

**Goal:** Move metering and recovery out of `src/`.

Same pattern as D-R1.2 but simpler — these have fewer consumers.

1. Create `packages/metering/` with package.json, tsconfig, and move `src/metering/*.ts`.
2. Create `packages/recovery/` with package.json, tsconfig, and move `src/recovery/*.ts`.
3. Update `src/index.ts` — remove metering and recovery re-exports.
4. Search for consumers and update their imports.
5. Run tests.

**Commit:** `git commit -m "D-R1.3: extract @semantos/metering and @semantos/recovery"`

---

### D-R1.4: Rename Zig Source Directory

**Goal:** `packages/cell-engine/src/` (Zig) → `packages/cell-engine/zig/` to avoid confusion with TypeScript `src/` convention.

1. ```bash
   git mv packages/cell-engine/src packages/cell-engine/zig
   ```

2. Update `packages/cell-engine/build.zig`:
   - Every reference to `"src/"` becomes `"zig/"`
   - The `b.path(...)` calls need updating
   - Search for string `"src/` in build.zig and replace with `"zig/`

3. Update any test files that reference the zig source path.

4. Update `.gitignore` if it has cell-engine/src specific entries.

5. Verify zig build still works (if zig is installed):
   ```bash
   cd packages/cell-engine && zig build 2>&1 | head -5
   ```

**Commit:** `git commit -m "D-R1.4: rename cell-engine Zig source dir src/ → zig/"`

---

### D-R1.5: Consolidate TypeScript Configuration

**Goal:** Single base tsconfig, packages extend it, remove duplicated paths.

1. Create `tsconfig.base.json` at repo root:
   ```json
   {
     "compilerOptions": {
       "target": "ES2022",
       "module": "ESNext",
       "moduleResolution": "bundler",
       "lib": ["ES2022"],
       "types": ["node"],
       "strict": true,
       "esModuleInterop": true,
       "skipLibCheck": true,
       "forceConsistentCasingInFileNames": true,
       "resolveJsonModule": true,
       "isolatedModules": true,
       "declaration": true,
       "declarationMap": true,
       "sourceMap": true
     }
   }
   ```

2. Update root `tsconfig.json`:
   ```json
   {
     "extends": "./tsconfig.base.json",
     "compilerOptions": {
       "outDir": "dist",
       "rootDir": "src"
     },
     "include": ["src/**/*.ts"],
     "exclude": ["node_modules", "dist"]
   }
   ```

3. Update each package tsconfig to extend `../../tsconfig.base.json` and only specify package-specific options.

4. With workspace protocol, `@semantos/*` packages should resolve via node_modules symlinks. Test whether tsconfig `paths` are still needed for type checking. If yes, keep them. If not, remove them (vite aliases are still needed for the dev server).

5. Run `bun run check`.

**Commit:** `git commit -m "D-R1.5: consolidate tsconfig with shared base"`

---

### D-R1.6: Update Remaining Import Paths

**Goal:** Ensure no stale imports remain.

1. Full scan:
   ```bash
   grep -rn "from.*@semantos/core.*cell" packages/ src/ --include="*.ts" --include="*.tsx"
   grep -rn "from.*@semantos/core.*metering" packages/ src/ --include="*.ts" --include="*.tsx"
   grep -rn "from.*@semantos/core.*recovery" packages/ src/ --include="*.ts" --include="*.tsx"
   grep -rn "file:../../" packages/ --include="*.json"
   ```

2. Each grep should return zero hits. Fix any remaining.

3. Run full verification:
   ```bash
   bun install
   bun run check
   bun test packages/__tests__/
   ```

**Commit:** `git commit -m "D-R1.6: clean up remaining stale imports"`

---

### D-R1.7: Clean Up Stale Artifacts

1. Check worktrees for uncommitted work:
   ```bash
   for d in .claude/worktrees/*/; do
     echo "=== $d ==="
     git -C "$d" status --short 2>/dev/null || echo "(not a valid worktree)"
   done
   ```

2. For any worktree with NO uncommitted changes, remove it:
   ```bash
   git worktree list
   git worktree remove .claude/worktrees/<name> --force
   ```

3. Clean up stale remote-tracking branches:
   ```bash
   git branch -a | grep "claude/" | head -20  # review first
   # Only delete local branches that have been merged
   git branch --merged main | grep "claude/" | xargs -r git branch -d
   ```

4. Fix PRD docs — search and replace:
   ```bash
   grep -rn "sibling.*semantos" docs/
   ```
   Replace all mentions of "sibling `semantos` repo" with the correct location (`packages/cell-engine/` in this repo).

**Commit:** `git commit -m "D-R1.7: remove stale worktrees, fix PRD references"`

---

### D-R1.8: Final Verification

This is the acceptance gate. ALL must pass:

```bash
# 1. Clean install from workspace
rm -rf node_modules packages/*/node_modules
bun install

# 2. Type check
bun run check

# 3. Build
bun run build

# 4. All gate tests
bun test packages/__tests__/

# 5. Loom dev server starts
cd packages/loom && timeout 10 bun run dev 2>&1 | head -5
cd ../..

# 6. Worktree smoke test
git worktree add .claude/worktrees/r1-verify phase-r1-package-restructure
cd .claude/worktrees/r1-verify
bun install
cd packages/loom && timeout 10 bun run dev 2>&1 | head -5
cd ../../../..
git worktree remove .claude/worktrees/r1-verify --force

# 7. No stale references
echo "--- Stale file: deps ---"
grep -rn "file:../../" packages/ --include="*.json" || echo "PASS: no file: deps"
echo "--- Sibling repo refs ---"
grep -rn "sibling.*semantos" docs/ || echo "PASS: no sibling refs"
echo "--- Core cell-engine imports ---"
grep -rn "from.*@semantos/core.*cell-engine" packages/ src/ --include="*.ts" || echo "PASS: no core/cell-engine imports"
```

If all pass:
```bash
git tag post-restructure-r1
```

**Commit (if any final fixes):** `git commit -m "D-R1.8: final verification fixes"`

---

## Important Notes for the Executing Session

### Things That Will Break (and How to Fix Them)

1. **Gate tests import from `@semantos/core`.** Many Phase 9/9.5 tests use source-scanning patterns (reading .ts files as strings and checking for patterns). After D-R1.2, the file paths change. You'll need to update the path constants in those test files.

2. **Protocol-types re-exports.** `packages/protocol-types/src/index.ts` line ~38 does `from "@semantos/core"` which previously pulled in cell-engine exports. After D-R1.2, it'll need to import cell-ops separately or be refactored.

3. **Workbench EngineProvider.** `packages/loom/src/engine/EngineProvider.tsx` and `useEngine.ts` import from `@semantos/cell-engine/browser` — this is the Zig WASM bindings, NOT the TypeScript cell-ops. Make sure this import stays pointed at `packages/cell-engine/bindings/`, not the new `packages/cell-ops/`.

4. **The root `bun run build` script.** Currently `"build": "tsc"` which compiles `src/` → `dist/`. After removing cell-engine, metering, and recovery from `src/`, the build output shrinks. This is intentional — `@semantos/core` becomes leaner.

5. **Bun lockfile.** `bun install` will regenerate `bun.lock` / `bun.lockb`. This is expected. Commit the new lockfile.

### What NOT to Do

- Do NOT rename `@semantos/core`. It stays as-is, just becomes smaller.
- Do NOT move or rename `packages/cell-engine/`. It keeps its name — the Zig kernel is the "cell engine." The TypeScript operations become `@semantos/cell-ops`.
- Do NOT change any Zig source code. Only the directory name changes (D-R1.4) and `build.zig` paths.
- Do NOT delete the `pre-restructure-r1` tag until the branch is merged and verified on main.
- Do NOT run `git push --force` under any circumstances.
