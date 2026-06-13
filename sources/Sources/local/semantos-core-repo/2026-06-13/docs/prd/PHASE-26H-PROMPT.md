---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26H-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.677696+00:00
---

# Phase 26H Execution Prompt — Vertical → Extension Rename

> Paste this prompt into a fresh session to execute Phase 26H.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes (npm: `@semantos/core`). The kernel (cell engine, linearity, capability validation) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, protocol adapters, conversational shell, and loom UI.

Phases 26A–G built the kernel isolation stack: four adapter interfaces, node bootstrap, filesystem-based vertical loading, and deployment packaging. Phase 26H renames all "vertical" terminology to "extension" across the entire codebase before Phase 26G ships the public-facing CLI and documentation.

**Why this matters**: The Semantos node ships as a $500 product with a marketplace of installable capabilities. Users install **extensions**, not "vertical grammars." The CLI says `semantos install extension trades`. The marketplace lists extensions. Third-party developers build extensions. The BSVA markets "Semantos extensions for [industry]." If "vertical" ships in the 26G packaging, it becomes a breaking rename later.

Your task is Phase 26H: comprehensive rename of "vertical" → "extension" across TypeScript source, configs, CLI commands, tests, and documentation.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are renaming. If you haven't read them, you will miss references.

**Read first** (the PRD and architecture):
- `docs/prd/PHASE-26H-EXTENSION-RENAME.md` — Phase 26H spec with complete rename map, deliverables D26H.1–D26H.6, gate tests, completion criteria
- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Context on the four adapters, node architecture, where "vertical" appears in architectural descriptions
- `docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** The three products (OddJobTodd, Property Management Suite, Dispatch Envelope) ship as three **extensions** on the Semantos marketplace. Every mention of "vertical" in this doc must become "extension." The shared taxonomy concept stays the same — extensions share taxonomy paths that enable cross-extension dispatch. The dispatch envelope object type belongs in a shared base extension, not in either product extension.

**Read second** (the primary rename targets — these have the most references):
- `packages/loom/src/config/verticalConfig.ts` — **51+ references**. VerticalConfig interface, ObjectTypeDefinition, validation. This is the heaviest file.
- `packages/loom/src/services/ConfigStore.ts` — **51 references**. Config loading, subscription, switchVertical(). Second heaviest.
- `packages/loom/src/services/IntentTaxonomy.ts` — **28 references**. registerVertical(), verticalRegistrations Map.
- `packages/shell/src/chat.ts` — **20 references**. Prompt building, loadVerticalPrompts, buildSystemPromptFromVerticals.
- `packages/loom/src/config/VerticalProvider.tsx` — **17 references**. React context, useVertical hook.

**Read third** (secondary rename targets):
- `packages/protocol-types/src/vertical-manifest.ts` — VerticalManifest, validateVerticalManifest()
- `packages/protocol-types/src/vertical-loader.ts` — VerticalLoader, VerticalLoadError, loadVertical()
- `packages/protocol-types/src/vertical-registry.ts` — VerticalRegistry
- `packages/protocol-types/src/node-config.ts` — verticalPaths, verticalCapabilities, activeVerticals
- `packages/shell/src/repl.ts` — CLI help text
- `packages/shell/src/config.ts` — defaultVertical
- `packages/shell/src/router.ts` — routing references
- `packages/loom/src/services/FlowRegistry.ts` — flow-per-vertical tracking
- `packages/loom/src/commands/executor.ts` — command execution vertical refs
- `packages/loom/server/index.ts` — server entry

**Read fourth** (test files — high reference counts):
- `packages/__tests__/intent-taxonomy.test.ts` — 43 references
- `packages/__tests__/phase9-gate.test.ts` — 30 references
- `packages/__tests__/intent-classifier-hierarchy.test.ts` — 26 references
- `packages/__tests__/phase26f-vertical-loading.test.ts` — 20 tests to rename

**Read fifth** (config files and branching policy):
- `configs/extensions/core.json` — base config
- `configs/extensions/trades-services.json` — reference implementation
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26h-extension-rename`, commits as `phase-26h/D26H.N:`

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO PARTIAL RENAMES

Every single instance of "vertical" in the context of vertical grammars/configs must be renamed. A half-renamed codebase is worse than the original. Gate tests T1–T6 scan the entire codebase for stragglers — if they find any, you have failed.

Exceptions — these are NOT renamed:
- The word "vertical" in CSS (e.g., `vertical-align`) — not our terminology
- The word "vertical" in comments that describe the *rename itself* (e.g., "renamed from vertical to extension")
- The word "vertical" in git history or changelog entries describing what was renamed

### 2. FILE RENAMES USE GIT MV

All file renames must use `git mv` to preserve Git history. Do not `cp` + `rm`. Do not create new files and delete old ones. Use:

```bash
git mv packages/protocol-types/src/vertical-manifest.ts packages/protocol-types/src/extension-manifest.ts
```

### 3. IMPORTS MUST ALL RESOLVE

After renaming files, every import path that referenced the old filename must be updated. This includes:
- Relative imports within the same package
- Cross-package imports via barrel exports
- Type-only imports
- Dynamic imports
- Test file imports

If `bun run check` shows unresolved import errors, you missed imports.

### 4. NO SEMANTIC CHANGES

This is a rename, not a refactor. Do not change logic, signatures, algorithms, or behavior. The only changes should be:
- Identifier names (vertical → extension)
- File names (vertical → extension)
- String literals in CLI help text, error messages, log messages
- Documentation text

If you find yourself changing `if` conditions, loop structures, or method signatures beyond the rename, STOP — you are going off-script.

### 5. TESTS MUST PASS AS-IS (AFTER RENAME)

All existing tests must pass with only the rename applied. If a test fails after renaming, the rename is wrong — not the test. Do not modify test assertions or expected values beyond the terminology change.

### 6. BARREL EXPORTS MUST BE CLEAN

After renaming, the barrel exports in `packages/protocol-types/src/index.ts` must export from the new file names. Check every `export * from './vertical-*'` line.

### 7. PRD RENAMES ARE COMPREHENSIVE

Every Phase PRD mentioning "vertical grammar," "vertical config," or "vertical loading" must be updated. There are approximately 57 PRD files that mention "vertical." Use grep to find them all.

### 8. CONFIG DIRECTORY RENAME IS ATOMIC

`configs/extensions/` → `configs/extensions/` via `git mv`. All code paths that reference `configs/extensions/` must be updated in the same commit as the directory rename.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

Phase 26F (VerticalManifest, VerticalLoader, VerticalRegistry) must be complete.

```bash
# These files must exist (they are the primary rename targets)
ls packages/protocol-types/src/vertical-manifest.ts
ls packages/protocol-types/src/vertical-loader.ts
ls packages/protocol-types/src/vertical-registry.ts
ls packages/loom/src/config/verticalConfig.ts
ls packages/loom/src/config/VerticalProvider.tsx
ls packages/loom/src/services/ConfigStore.ts
ls packages/loom/src/services/IntentTaxonomy.ts
ls configs/extensions/
```

All files must exist. If any are missing, Phase 26F is incomplete — STOP and report.

### 0.4 Create Phase 26H branch

```bash
git checkout -b phase-26h-extension-rename
```

---

## Step 1: Protocol-Types File Renames + Type Updates (D26H.1)

### 1.1 Rename files with git mv

```bash
git mv packages/protocol-types/src/vertical-manifest.ts packages/protocol-types/src/extension-manifest.ts
git mv packages/protocol-types/src/vertical-loader.ts packages/protocol-types/src/extension-loader.ts
git mv packages/protocol-types/src/vertical-registry.ts packages/protocol-types/src/extension-registry.ts
```

### 1.2 Find and replace in renamed files

In `extension-manifest.ts`:
- `VerticalManifest` → `ExtensionManifest`
- `validateVerticalManifest` → `validateExtensionManifest`
- All JSDoc references to "vertical" → "extension"

In `extension-loader.ts`:
- `VerticalLoader` → `ExtensionLoader`
- `VerticalLoadError` → `ExtensionLoadError`
- `loadVertical` → `loadExtension`
- `loadAllVerticals` → `loadAllExtensions`
- `mergeVerticals` → `mergeExtensions`
- `verticalPath` parameter → `extensionPath`
- All JSDoc and error messages

In `extension-registry.ts`:
- `VerticalRegistry` → `ExtensionRegistry`
- `activeVerticals` → `activeExtensions`
- `verticalId` → `extensionId`
- All method names: `getVertical` → `getExtension`, `isActive` stays (not vertical-specific)
- All JSDoc references

In `node-config.ts`:
- `verticalPaths` → `extensionPaths`
- `verticalCapabilities` → `extensionCapabilities`
- `activeVerticals` → `activeExtensions`
- All JSDoc references

### 1.3 Update barrel exports

In `packages/protocol-types/src/index.ts`:
- `export * from './vertical-manifest'` → `export * from './extension-manifest'`
- `export * from './vertical-loader'` → `export * from './extension-loader'`
- `export * from './vertical-registry'` → `export * from './extension-registry'`

### 1.4 Verify

```bash
# No TypeScript errors in protocol-types
bun run check 2>&1 | grep -i "extension\|vertical" | head -20
```

Commit: `phase-26h/D26H.1: rename protocol-types vertical → extension (files + types)`

---

## Step 2: Loom Config + Service Renames (D26H.2)

### 2.1 Rename files

```bash
git mv packages/loom/src/config/verticalConfig.ts packages/loom/src/config/extensionConfig.ts
git mv packages/loom/src/config/verticalConfig.d.ts packages/loom/src/config/extensionConfig.d.ts 2>/dev/null || true
git mv packages/loom/src/config/VerticalProvider.tsx packages/loom/src/config/ExtensionProvider.tsx
```

### 2.2 Find and replace in all loom files

In `extensionConfig.ts` (232 lines, 50+ references):
- `VerticalConfig` → `ExtensionConfig`
- `validateVerticalConfig` → `validateExtensionConfig`
- `verticalPath` → `extensionPath`
- All JSDoc references

In `ExtensionProvider.tsx`:
- `VerticalProvider` → `ExtensionProvider`
- `VerticalContextValue` → `ExtensionContextValue`
- `useVertical` → `useExtension`
- `activeVerticalId` → `activeExtensionId`

In `ConfigStore.ts` (51 references):
- `switchVertical` → `switchExtension`
- All `vertical*` property accesses and method names
- All string literals mentioning "vertical"

In `IntentTaxonomy.ts` (28 references):
- `registerVertical` → `registerExtension`
- `unregisterVertical` → `unregisterExtension`
- `hasVerticals` → `hasExtensions`
- `verticalRegistrations` → `extensionRegistrations`

In `FlowRegistry.ts` (11 references):
- All vertical → extension

In `executor.ts` (10 references):
- All vertical → extension

In `server/index.ts` (10 references):
- All vertical → extension

### 2.3 Update all import paths

Every file that imports from `./verticalConfig`, `./VerticalProvider`, or the old protocol-types paths must be updated. Use grep to find them all:

```bash
grep -rn "verticalConfig\|VerticalProvider\|vertical-manifest\|vertical-loader\|vertical-registry" packages/ --include="*.ts" --include="*.tsx" | grep -v node_modules | grep -v ".js:"
```

Update every hit.

### 2.4 Verify

```bash
bun run check 2>&1 | head -30
```

Commit: `phase-26h/D26H.2: rename loom vertical → extension (configs + services)`

---

## Step 3: Shell + CLI Renames (D26H.3)

### 3.1 Update shell source files

In `chat.ts` (20 references):
- `buildSystemPromptFromVerticals` → `buildSystemPromptFromExtensions`
- `loadVerticalPrompts` → `loadExtensionPrompts`
- `verticalConfig` parameter names → `extensionConfig`
- All JSDoc and comments

In `repl.ts` (11 references):
- Help text: `"load <vertical>"` → `"load <extension>"`
- All vertical references in command descriptions

In `config.ts` (6 references):
- `defaultVertical` → `defaultExtension`
- All config key references

In `router.ts` (4 references):
- All vertical → extension

In `taxonomy.ts`:
- `taxonomy.registerVertical(...)` → `taxonomy.registerExtension(...)`

### 3.2 Verify

```bash
grep -rn "vertical" packages/shell/src/ --include="*.ts" | grep -v node_modules
# Should return zero hits (or only false positives like CSS "vertical-align")
```

Commit: `phase-26h/D26H.3: rename shell vertical → extension (CLI + chat + config)`

---

## Step 4: Configuration Directory Rename (D26H.4)

### 4.1 Rename directory

```bash
git mv configs/extensions configs/extensions
```

### 4.2 Update all references to configs/extensions

```bash
grep -rn "configs/extensions" . --include="*.ts" --include="*.tsx" --include="*.json" --include="*.md" | grep -v node_modules | grep -v ".git/"
```

Update every hit to `configs/extensions`.

### 4.3 Update package structure documentation

In Phase 26F PRD and any other docs that reference the vertical package structure:
- `semantos-vertical-trades/` → `semantos-extension-trades/`
- `configs/extensions/` → `configs/extensions/`

Commit: `phase-26h/D26H.4: rename configs/extensions → configs/extensions`

---

## Step 5: Test Updates (D26H.5)

### 5.1 Rename test files

```bash
git mv packages/__tests__/phase26f-vertical-loading.test.ts packages/__tests__/phase26f-extension-loading.test.ts 2>/dev/null || true
```

### 5.2 Update all test references

In `intent-taxonomy.test.ts` (43 references):
- All `registerVertical` → `registerExtension`
- All `verticalId` → `extensionId`
- All test descriptions mentioning "vertical"

In `phase9-gate.test.ts` (30 references):
- All vertical → extension

In `intent-classifier-hierarchy.test.ts` (26 references):
- All vertical → extension

In `phase26f-extension-loading.test.ts` (all 20 tests):
- All type names, variable names, descriptions
- Import paths

### 5.3 Write Phase 26H gate tests

Create `packages/__tests__/phase26h-extension-rename.test.ts` with tests T1–T16 as specified in the PRD.

The completeness tests (T1–T6) are critical — they scan the codebase with regex to catch any remaining "vertical" identifiers.

### 5.4 Run all tests

```bash
bun test
```

ALL tests must pass. If any fail, the rename is incomplete or incorrect.

Commit: `phase-26h/D26H.5: update tests for extension rename + add Phase 26H gate tests`

---

## Step 6: PRD + Documentation Updates (D26H.6)

### 6.1 Find all PRD files with "vertical"

```bash
grep -rl "vertical" docs/prd/ --include="*.md" | sort
```

### 6.2 Rename Phase 26F PRD file

```bash
git mv docs/prd/PHASE-26F-VERTICAL-LOADING.md docs/prd/PHASE-26F-EXTENSION-LOADING.md
```

### 6.3 Update all PRD files

For each file from 6.1:
- "vertical grammar" → "extension"
- "vertical config" → "extension config"
- "vertical loading" → "extension loading"
- "VerticalManifest" → "ExtensionManifest" (in code blocks)
- "VerticalLoader" → "ExtensionLoader" (in code blocks)
- "VerticalRegistry" → "ExtensionRegistry" (in code blocks)
- "VerticalConfig" → "ExtensionConfig" (in code blocks)
- "vertical package" → "extension package"
- `semantos install vertical` → `semantos install extension`
- File path references: `vertical-manifest.ts` → `extension-manifest.ts`, etc.

### 6.4 Update README.md

- Document tree: `PHASE-26F-VERTICAL-LOADING.md` → `PHASE-26F-EXTENSION-LOADING.md`
- Add Phase 26H entry to document tree
- Design decisions table: "Vertical grammars as config" → "Extensions as config"
- Dependency graph: add 26H between 26F and 26G

### 6.5 Update master PRD

- `PHASE-26-KERNEL-ISOLATION-MASTER.md` — all "vertical" terminology → "extension"
- Add Phase 26H to sub-phase overview

### 6.6 Verify

```bash
grep -rn "vertical grammar\|vertical config\|VerticalManifest\|VerticalLoader\|VerticalRegistry\|VerticalConfig" docs/prd/ --include="*.md"
# Should return zero hits (except in PHASE-26H docs that describe the rename itself)
```

Commit: `phase-26h/D26H.6: update all PRDs and documentation — vertical → extension`

---

## Step 7: Final Verification

### 7.1 Full codebase scan

```bash
# Scan for any remaining vertical identifiers (excluding false positives)
grep -rn "\bVertical\(Config\|Manifest\|Loader\|Registry\|Provider\|LoadError\)\b" packages/ --include="*.ts" --include="*.tsx" | grep -v node_modules
grep -rn "\bvertical\(Id\|Name\|Path\|Registrations\|Capabilities\)\b" packages/ --include="*.ts" --include="*.tsx" | grep -v node_modules
grep -rn "configs/extensions" . --include="*.ts" --include="*.tsx" --include="*.json" --include="*.md" | grep -v node_modules | grep -v ".git/"
```

All three must return zero results.

### 7.2 Type check and build

```bash
bun run check
bun run build
```

Both must succeed.

### 7.3 Full test suite

```bash
bun test
```

All tests must pass, including the new Phase 26H gate tests.

---

## Step 8: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every renamed file — check for missed references
2. Check that import paths all resolve
3. Check that barrel exports reference new file names
4. Check that CLI help text uses "extension" everywhere
5. Check that error messages say "extension" not "vertical"
6. Check that JSDoc comments are updated
7. Grep the entire repo one more time for stragglers
8. Write errata doc as `docs/prd/PHASE-26H-ERRATA.md`

---

## Completion Criteria

- [ ] All files renamed per the Rename Map (7 file renames, 1 directory rename)
- [ ] All TypeScript identifiers renamed (30+ identifier patterns across 63 files)
- [ ] `configs/extensions/` renamed to `configs/extensions/`
- [ ] CLI help text says "extension" not "vertical"
- [ ] Zero remaining "Vertical" type names in TypeScript source (T1)
- [ ] Zero remaining "verticalId" etc. identifiers in TypeScript source (T2)
- [ ] All barrel exports updated
- [ ] All import paths updated
- [ ] All 57 PRD files updated
- [ ] README.md updated with Phase 26H entry and new terminology
- [ ] Tests T1–T16 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-26h/D26H.N:` naming convention
- [ ] Branch is `phase-26h-extension-rename`
- [ ] Errata sprint complete with `docs/prd/PHASE-26H-ERRATA.md`

---

## Next Phase

Phase 26G packages the kernel for deployment with "extension" terminology baked in from day one: Docker image, install script, `semantos` CLI (`semantos install extension trades`), admin API, marketplace integration, and user-facing documentation.
