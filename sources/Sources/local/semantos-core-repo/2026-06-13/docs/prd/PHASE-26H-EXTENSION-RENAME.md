---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26H-EXTENSION-RENAME.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.687630+00:00
---

# Phase 26H — Vertical → Extension Rename (Terminology Alignment)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1–2 days (with half-day buffer)
**Prerequisites**: Phase 26F complete (VerticalManifest, VerticalLoader, VerticalRegistry)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch**: `phase-26h-extension-rename`

---

## Context

The Semantos codebase uses "vertical" and "vertical grammar" throughout — in type names, service classes, configuration files, CLI commands, PRDs, and documentation. This was the correct internal architecture term during design: vertical grammars describe domain-specific taxonomies loaded into the kernel.

But from a user and marketplace perspective, "vertical" is developer jargon. Nobody "installs a vertical." People install **extensions**. The mental model is immediately intuitive: a Semantos node is a sovereign unit, and extensions add capabilities to it. This matches the browser extension model, VS Code extension model, and app extension patterns that users already understand.

This phase renames all user-facing and internal references from "vertical" to "extension" across:

1. **TypeScript source** — interfaces, classes, functions, properties, variables, imports
2. **Configuration files** — directory names, JSON keys, config schemas
3. **CLI commands** — `semantos install vertical X` → `semantos install extension X`
4. **PRD documents** — all Phase 26 PRDs and the master PRD
5. **README** — document tree, design decisions, dependency graph

The rename is mechanical but comprehensive. The kernel architecture does not change — only the terminology.

### Why Now (Before 26G Packaging)

Phase 26G packages the node for deployment: Docker images, install scripts, CLI, admin API, and user-facing documentation. If "vertical" ships in the CLI and docs, it's a breaking rename later. Renaming before packaging means the public-facing API uses "extension" from day one.

### Commercial Context

The three-product strategy (OddJobTodd, Property Management, Dispatch Envelope) ships as three extensions on the Semantos marketplace. The $500 node product ships with a CLI that says `semantos install extension trades`. The open-source kernel under OpenBSV uses "extension" in its public API surface. Third-party developers build and sell extensions, not "vertical grammars." The BSVA markets "Semantos extensions for [industry]" to enterprise prospects.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `CFG:VERTICAL` | `packages/loom/src/config/verticalConfig.ts` | VerticalConfig interface — primary rename target (232 lines, 50+ references) |
| `CFG:VPROVIDER` | `packages/loom/src/config/VerticalProvider.tsx` | React context provider — rename to ExtensionProvider |
| `SVC:CONFIG` | `packages/loom/src/services/ConfigStore.ts` | Config loading — 51 "vertical" references |
| `SVC:TAXONOMY` | `packages/loom/src/services/IntentTaxonomy.ts` | Vertical registration — 28 references |
| `SVC:FLOW` | `packages/loom/src/services/FlowRegistry.ts` | Flow registry — 11 references |
| `SHELL:CHAT` | `packages/shell/src/chat.ts` | Chat shell — 20 references |
| `SHELL:REPL` | `packages/shell/src/repl.ts` | REPL — 11 references, CLI help text |
| `SHELL:CONFIG` | `packages/shell/src/config.ts` | Shell config — 6 references |
| `SHELL:ROUTER` | `packages/shell/src/router.ts` | Router — 4 references |
| `CMD:EXEC` | `packages/loom/src/commands/executor.ts` | Command executor — 10 references |
| `SERVER:INDEX` | `packages/loom/server/index.ts` | Server entry — 10 references |
| `TYPES:MANIFEST` | `packages/protocol-types/src/vertical-manifest.ts` | VerticalManifest — rename file + all types |
| `TYPES:LOADER` | `packages/protocol-types/src/vertical-loader.ts` | VerticalLoader — rename file + all types |
| `TYPES:REGISTRY` | `packages/protocol-types/src/vertical-registry.ts` | VerticalRegistry — rename file + all types |
| `TYPES:NODECONFIG` | `packages/protocol-types/src/node-config.ts` | NodeConfig — verticalPaths, verticalCapabilities fields |
| `TYPES:INTENT` | `packages/loom/src/types/intent-types.ts` | ClassificationContext.verticalName |
| `CFG:JSON` | `configs/extensions/` | Directory rename → `configs/extensions/` |
| `TEST:TAXONOMY` | `packages/__tests__/intent-taxonomy.test.ts` | 43 references |
| `TEST:PHASE9` | `packages/__tests__/phase9-gate.test.ts` | 30 references |
| `TEST:CLASSIFIER` | `packages/__tests__/intent-classifier-hierarchy.test.ts` | 26 references |
| `TEST:PHASE26F` | `packages/__tests__/phase26f-vertical-loading.test.ts` | All 20 tests |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Rename Map

### TypeScript Identifiers

| Old Name | New Name | Locations |
|----------|----------|-----------|
| `VerticalConfig` | `ExtensionConfig` | verticalConfig.ts, ConfigStore.ts, IntentTaxonomy.ts, chat.ts, + 20 files |
| `VerticalProvider` | `ExtensionProvider` | VerticalProvider.tsx → ExtensionProvider.tsx |
| `VerticalContextValue` | `ExtensionContextValue` | VerticalProvider.tsx |
| `VerticalManifest` | `ExtensionManifest` | vertical-manifest.ts → extension-manifest.ts |
| `VerticalLoader` | `ExtensionLoader` | vertical-loader.ts → extension-loader.ts |
| `VerticalLoadError` | `ExtensionLoadError` | vertical-loader.ts |
| `VerticalRegistry` | `ExtensionRegistry` | vertical-registry.ts → extension-registry.ts |
| `validateVerticalManifest` | `validateExtensionManifest` | vertical-manifest.ts |
| `validateVerticalConfig` | `validateExtensionConfig` | verticalConfig.ts |
| `registerVertical` | `registerExtension` | IntentTaxonomy.ts |
| `unregisterVertical` | `unregisterExtension` | IntentTaxonomy.ts |
| `hasVerticals` | `hasExtensions` | IntentTaxonomy.ts |
| `switchVertical` | `switchExtension` | ConfigStore.ts |
| `loadVertical` | `loadExtension` | vertical-loader.ts |
| `loadAllVerticals` | `loadAllExtensions` | vertical-loader.ts |
| `mergeVerticals` | `mergeExtensions` | vertical-loader.ts |
| `loadVerticalPrompts` | `loadExtensionPrompts` | chat.ts |
| `buildSystemPromptFromVerticals` | `buildSystemPromptFromExtensions` | chat.ts |
| `loadPricingPolicy(verticalConfig)` | `loadPricingPolicy(extensionConfig)` | chat.ts |
| `useVertical` | `useExtension` | VerticalProvider.tsx |
| `verticalId` | `extensionId` | 38+ locations |
| `verticalName` | `extensionName` | intent-types.ts, ClassificationContext |
| `verticalPath` | `extensionPath` | verticalConfig.ts, loader |
| `verticalRegistrations` | `extensionRegistrations` | IntentTaxonomy.ts |
| `activeVerticalId` | `activeExtensionId` | VerticalProvider.tsx |
| `defaultVertical` | `defaultExtension` | shell config |
| `verticalPaths` | `extensionPaths` | node-config.ts |
| `verticalCapabilities` | `extensionCapabilities` | node-config.ts |
| `activeVerticals` | `activeExtensions` | node-config.ts |

### File Renames

| Old Path | New Path |
|----------|----------|
| `packages/loom/src/config/verticalConfig.ts` | `packages/loom/src/config/extensionConfig.ts` |
| `packages/loom/src/config/verticalConfig.d.ts` | `packages/loom/src/config/extensionConfig.d.ts` |
| `packages/loom/src/config/VerticalProvider.tsx` | `packages/loom/src/config/ExtensionProvider.tsx` |
| `packages/protocol-types/src/vertical-manifest.ts` | `packages/protocol-types/src/extension-manifest.ts` |
| `packages/protocol-types/src/vertical-loader.ts` | `packages/protocol-types/src/extension-loader.ts` |
| `packages/protocol-types/src/vertical-registry.ts` | `packages/protocol-types/src/extension-registry.ts` |
| `configs/extensions/` | `configs/extensions/` |

### CLI Commands

| Old | New |
|-----|-----|
| `semantos install vertical trades` | `semantos install extension trades` |
| `load <vertical>` | `load <extension>` |
| REPL help text referencing "vertical" | Updated to "extension" |

### Configuration JSON

| Old Key | New Key |
|---------|---------|
| `config.verticals` array in NodeConfig | `config.extensions` |
| `semantos-vertical-trades/` package name | `semantos-extension-trades/` |
| `verticalPath` in manifest | `extensionPath` (internal consistency) |

### Error Codes

| Old | New |
|-----|-----|
| `MANIFEST_MISSING` | unchanged (not vertical-specific) |
| `MANIFEST_INVALID` | unchanged |
| `TAXONOMY_MISSING` | unchanged |
| `TAXONOMY_INVALID` | unchanged |
| `VerticalLoadError` class name | `ExtensionLoadError` |

---

## Deliverables

### D26H.1 — Protocol-Types File Renames + Type Updates

Rename files and update all type names in `packages/protocol-types/`:

- `vertical-manifest.ts` → `extension-manifest.ts`: `ExtensionManifest`, `validateExtensionManifest()`
- `vertical-loader.ts` → `extension-loader.ts`: `ExtensionLoader`, `ExtensionLoadError`, `loadExtension()`, `loadAllExtensions()`, `mergeExtensions()`
- `vertical-registry.ts` → `extension-registry.ts`: `ExtensionRegistry`
- `node-config.ts`: `extensionPaths`, `extensionCapabilities`, `activeExtensions`
- Update barrel exports in `index.ts`

### D26H.2 — Loom Config + Service Renames

Rename files and update all references in `packages/loom/`:

- `verticalConfig.ts` → `extensionConfig.ts`: `ExtensionConfig`, `validateExtensionConfig()`
- `VerticalProvider.tsx` → `ExtensionProvider.tsx`: `ExtensionProvider`, `ExtensionContextValue`, `useExtension()`
- `ConfigStore.ts`: `switchExtension()`, all `vertical*` properties
- `IntentTaxonomy.ts`: `registerExtension()`, `unregisterExtension()`, `hasExtensions()`, `extensionRegistrations`
- `FlowRegistry.ts`: all vertical references
- `executor.ts`: all vertical references
- `server/index.ts`: all vertical references
- Update all import paths

### D26H.3 — Shell + CLI Renames

Update all references in `packages/shell/`:

- `chat.ts`: `buildSystemPromptFromExtensions()`, `loadExtensionPrompts()`, `loadPricingPolicy(extensionConfig)`
- `repl.ts`: CLI help text `load <extension>`, all vertical references
- `config.ts`: `defaultExtension`, all vertical references
- `router.ts`: all vertical references
- `taxonomy.ts`: `registerExtension()` calls

### D26H.4 — Configuration Directory Rename

- Rename `configs/extensions/` → `configs/extensions/`
- Update all code that references `configs/extensions/` path
- Update package structure docs: `semantos-vertical-trades/` → `semantos-extension-trades/`

### D26H.5 — Test Updates

Update all test files:

- `intent-taxonomy.test.ts` (43 references)
- `phase9-gate.test.ts` (30 references)
- `intent-classifier-hierarchy.test.ts` (26 references)
- `phase26f-vertical-loading.test.ts` (20 tests — rename file to `phase26f-extension-loading.test.ts`)
- All test descriptions, variable names, assertions

### D26H.6 — PRD + Documentation Updates

Update all PRD files with "vertical" → "extension":

- `PHASE-26-KERNEL-ISOLATION-MASTER.md` — all "vertical grammar" → "extension"
- `PHASE-26F-VERTICAL-LOADING.md` → rename to `PHASE-26F-EXTENSION-LOADING.md`
- `PHASE-26F-PROMPT.md` — all references
- `PHASE-26G-NODE-PACKAGING.md` + prompt — all references
- `PLATFORM-ARCHITECTURE.md` — all references
- `README.md` — document tree, design decisions table, dependency graph comments
- All other Phase PRDs that mention "vertical" (approximately 50 files)
- Design decisions table: "Vertical grammars as config" → "Extensions as config"

---

## Gate Tests (TDD)

**File**: `packages/__tests__/phase26h-extension-rename.test.ts`

### Completeness Tests (T1–T6)

```typescript
describe("Extension rename completeness", () => {
  // T1: No TypeScript source file in packages/ contains "Vertical" as a type name
  //     (scan all .ts/.tsx files for /\bVertical(?:Config|Manifest|Loader|Registry|Provider|LoadError)\b/)
  // T2: No TypeScript source file contains "verticalId" or "verticalName" as identifier
  //     (scan for /\bvertical(?:Id|Name|Path|Registrations|Capabilities)\b/)
  // T3: No JSON config file in configs/ uses old "verticals" directory path
  // T4: No test file contains old type names (VerticalConfig, VerticalLoader, etc.)
  // T5: configs/extensions/ directory exists, configs/extensions/ does not
  // T6: All barrel exports in protocol-types/index.ts reference extension-*, not vertical-*
});
```

### Functional Tests (T7–T12)

```typescript
describe("Extension system still works after rename", () => {
  // T7: ExtensionManifest validation accepts valid manifest
  // T8: ExtensionManifest validation rejects invalid manifest
  // T9: ExtensionLoader.loadExtension() loads from configs/extensions/trades-services.json
  // T10: ExtensionRegistry.activate() + getExtension() roundtrip works
  // T11: IntentTaxonomy.registerExtension() + hasExtensions() works
  // T12: buildSystemPromptFromExtensions() concatenates prompts in order
});
```

### Anti-Regression Tests (T13–T16)

```typescript
describe("No broken imports or references", () => {
  // T13: bun run check passes (zero TypeScript errors)
  // T14: All Phase 9 gate tests still pass
  // T15: All Phase 26F gate tests still pass (under new file name)
  // T16: Shell REPL help text says "extension" not "vertical"
});
```

---

## Methodology

This is a mechanical rename, not a refactor. The approach:

1. **Rename files first** — `git mv` to preserve history
2. **Find-and-replace identifiers** — systematic, case-sensitive replacement
3. **Update imports** — all import paths that reference old file names
4. **Update barrel exports** — protocol-types/index.ts, loom barrel files
5. **Rename directory** — `git mv configs/extensions configs/extensions`
6. **Update tests** — rename test files, update all references
7. **Update PRDs** — all documentation files
8. **Verify** — `bun run check`, `bun test`, grep for stragglers

The key risk is missed references. Gate tests T1–T6 explicitly scan the codebase for any remaining "vertical" identifiers to catch stragglers.

---

## Completion Criteria

- [ ] All files renamed per the Rename Map table
- [ ] All TypeScript identifiers renamed per the Rename Map table
- [ ] `configs/extensions/` renamed to `configs/extensions/`
- [ ] CLI help text says "extension" not "vertical"
- [ ] No TypeScript source file contains `VerticalConfig`, `VerticalLoader`, `VerticalManifest`, `VerticalRegistry`, `VerticalProvider`, `VerticalLoadError` as type names
- [ ] No TypeScript source file contains `verticalId`, `verticalName`, `verticalPath`, `verticalRegistrations`, `verticalCapabilities` as identifiers
- [ ] All PRD files updated with "extension" terminology
- [ ] README.md design decisions table updated
- [ ] Tests T1–T16 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests (Phase 9, 26F, etc.) still pass
- [ ] All commits follow `phase-26h/D26H.N:` naming convention
- [ ] Branch is `phase-26h-extension-rename`

---

## Next Phase

Phase 26G packages the kernel for deployment with the new "extension" terminology baked in from day one: Docker image, install script, `semantos` CLI, admin API, and user-facing docs all use "extension."
