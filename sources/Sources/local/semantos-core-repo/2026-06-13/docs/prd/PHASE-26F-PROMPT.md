---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26F-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.703051+00:00
---

# Phase 26F Execution Prompt — Vertical Configuration Loading

> Paste this prompt into a fresh session to execute Phase 26F.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes (npm: `@semantos/core`). The kernel (cell engine, linearity, capability validation) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, protocol adapters, conversational shell, and loom UI.

Phase 26A–E extracted and implemented four adapter interfaces (Identity, Anchor, Network, Storage) and built the NodeConfig bootstrap flow. Phase 26F enables verticals to be loaded from the filesystem at startup, instead of being compiled into the loom bundle. This is the enabler for:

1. Package independence — verticals ship separately
2. Runtime activation — admins enable/disable verticals without rebuilding
3. Multi-node patterns — different nodes load different verticals

Your task is Phase 26F: define VerticalManifest, implement VerticalLoader service, add vertical registry tracking on the node, inject prompt scripts into the kernel shell, and write gate tests.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce code that doesn't integrate.

**Read first** (the PRDs and architecture):
- `docs/prd/PHASE-26F-VERTICAL-LOADING.md` — Phase 26F spec with deliverables D26F.1–D26F.5, gate tests, completion criteria
- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Context on the four adapters, node deployment profiles, the node self-object
- `docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** This is where the three-product strategy becomes concrete. Each product is a vertical grammar: `semantos-vertical-trades/` (OddJobTodd), `semantos-vertical-property/` (PM suite). The shared taxonomy (`services.trades.plumbing` means the same thing in both verticals) is what makes cross-vertical dispatch work. The dispatch envelope object type definition belongs in a shared taxonomy, not in either vertical. The property vertical's MaintenanceRequest FSM and object types are defined in PLATFORM-ARCHITECTURE.md — they become the content of `semantos-vertical-property/config.json`.

**Read second** (the services and types you integrate with):
- `packages/loom/src/config/verticalConfig.ts` — VerticalConfig interface, ObjectTypeDefinition, validation pattern
- `packages/loom/src/services/ConfigStore.ts` — Config loading and subscription pattern
- `packages/loom/src/services/IdentityStore.ts` — Identity store initialization
- `packages/shell/src/chat.ts` — Chat shell, system prompt structure, flow runner integration
- `packages/protocol-types/src/storage.ts` — StorageAdapter interface (read, list, exists)
- `packages/protocol-types/src/semantic-fs.ts` — Path parsing, storage key validation

**Read third** (the existing implementations — your reference):
- `packages/loom/src/services/ConfigStore.ts` — Error handling, subscription pattern
- `packages/protocol-types/src/cell-store.ts` — Service structure
- `configs/extensions/trades-services.json` — Real vertical config (reference implementation)
- `configs/extensions/core.json` — Base vertical with governance types

**Read fourth** (branching and testing):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26f-vertical-loading`, commits as `phase-26f/D26F.N:`

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–26E. Plus:

### 1. NO STUBS OR MOCKS IN CORE SERVICES

Every service method must do real work:
- `VerticalLoader.loadVertical()` reads from storage, validates, merges
- `VerticalRegistry.activate()` actually registers the vertical
- Prompt injection appends markdown content to system prompt

If a function body is `throw new Error("not implemented")` or has hardcoded test data, you have failed.

### 2. FILESYSTEM SEMANTICS ARE CORRECT

- Paths must respect the vertical package structure (config.json in root, flows/, prompts/, taxonomy/)
- Storage operations use StorageAdapter (no `fs` module directly in protocol-types)
- Relative paths in manifest are resolved correctly (e.g., "flows/" + "job-intake.json" = "flows/job-intake.json")

### 3. VALIDATION HAPPENS EARLY

- Manifest must be validated against schema before using it
- Taxonomy JSON must be parseable before merging
- If any required file is missing or corrupt, throw VerticalLoadError with correct code and path

### 4. NO BREAKING CHANGES

- Existing VerticalConfig interface must remain compatible
- Chat.ts system prompt injection must not break existing flows
- ConfigStore pattern must not be modified (this is Phase 26F, not a refactor)
- All Phase 25A–E and Phase 26A–E tests must still pass

### 5. TESTS ARE REAL

Tests must use real vertical configs and verify real behavior:
- T1–T4: Manifest validation with valid and invalid inputs
- T5–T8: VerticalLoader with multi-file loads, error cases
- T9–T16: VerticalRegistry with activation/deactivation, merging
- T17–T20: Backward compatibility with compiled verticals

Tests that check `expect(result).toBeDefined()` are worthless. Delete them and write real tests.

### 6. ERROR CODES ARE CONSISTENT

Use exactly these error codes from VerticalLoadError:
- `MANIFEST_MISSING` — config.json not found
- `MANIFEST_INVALID` — config.json exists but doesn't parse or fails validation
- `TAXONOMY_MISSING` — file at manifest.taxonomyPath not found
- `TAXONOMY_INVALID` — taxonomy JSON doesn't parse

### 7. REGISTRY STATE PERSISTS CORRECTLY

When a vertical is activated via VerticalRegistry.activate(), it must:
- Load the config from disk via VerticalLoader
- Store it in the activeVerticals map
- Be retrievable via getVertical(id)
- Return the same reference on second call to getVertical(id)

When deactivated, it must be completely removed.

### 8. PROMPT INJECTION ORDER MATTERS

System prompts are injected in order:
1. Base system prompt (from kernel)
2. For each active vertical (in activation order):
   - Vertical's context prompts from prompts/ directory

This order determines LLM behavior. Tests must verify order.

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

Phase 26E (NodeConfig, node self-object) must be complete.

```bash
# NodeConfig must exist
ls packages/protocol-types/src/node-config.ts

# Node bootstrap service must exist
ls packages/protocol-types/src/node-bootstrap.ts

# VerticalConfig must exist
ls packages/loom/src/config/verticalConfig.ts

# Storage adapters must exist
ls packages/protocol-types/src/storage.ts
ls packages/protocol-types/src/adapters/

# Shell chat must exist
ls packages/shell/src/chat.ts
```

All files must exist. If anything is missing, STOP and report what's missing.

### 0.4 Create Phase 26F branch

```bash
git checkout -b phase-26f-vertical-loading
```

---

## Step 1: VerticalManifest Interface + Validation (D26F.1)

Create `packages/protocol-types/src/vertical-manifest.ts`.

This defines the structure of `config.json` in each vertical package.

Deliverable:
- `VerticalManifest` interface with fields: id, name, version, taxonomyPath, flowsDir, promptsDir, objectsDir (optional), requiredCapabilities (optional), facetRoles (optional), metadata (optional)
- `validateVerticalManifest()` function that validates an object against the schema and throws `Error` with a descriptive message if invalid
- All JSDoc comments (follow the pattern in ConfigStore.ts and verticalConfig.ts)

Also update `packages/loom/src/config/verticalConfig.ts`:
- Add optional field `manifestPath?: string;` to VerticalConfig interface

Verify: `manifestPath` is optional and doesn't break existing code.

Commit: `phase-26f/D26F.1: VerticalManifest interface and validation`

---

## Step 2: VerticalLoader Service (D26F.2)

Create `packages/protocol-types/src/vertical-loader.ts`.

Implements the VerticalLoader class with these methods:

- `constructor(storage: StorageAdapter)` — stores the adapter
- `async loadVertical(verticalPath: string): Promise<VerticalConfig>` — reads config.json, validates, loads taxonomy, flows, prompts, returns merged VerticalConfig
- `async loadAllVerticals(verticalPaths: string[]): Promise<VerticalConfig[]>` — calls loadVertical for each path
- `mergeVerticals(configs: VerticalConfig[]): VerticalConfig` — merges multiple configs (union of objectTypes by typeHash, union of capabilities by id, concatenate flows, merge taxonomy dimensions)

Also implement:
- `VerticalLoadError` class extending Error with fields: code (string), verticalPath (string)
- `mergeTaxonomyNodes()` helper function

Implementation requirements:
- Read manifest from `${verticalPath}/config.json`
- Validate manifest, throw VerticalLoadError if invalid
- Read taxonomy from `${verticalPath}/${manifest.taxonomyPath}`
- List `${verticalPath}/${manifest.flowsDir}` and load all .json files
- List `${verticalPath}/${manifest.promptsDir}` and load all .md files (warn on failures, continue)
- Return a VerticalConfig with merged taxonomy and flows
- Use TextDecoder to convert Uint8Array to string

Verify: Every function does real work. No hardcoded data. No "not implemented" errors.

Commit: `phase-26f/D26F.2: VerticalLoader service with manifest validation and merging`

---

## Step 3: Prompt Script Injection (D26F.3)

Modify `packages/shell/src/chat.ts`.

Add two functions:

- `buildSystemPromptFromVerticals(baseSystemPrompt: string, verticalConfigs: VerticalConfig[]): string` — concatenates base prompt with flow instructions from each vertical
- `async loadVerticalPrompts(verticalPath: string, storage: StorageAdapter): Promise<string>` — lists prompts/ directory, reads all .md files, returns concatenated markdown

Implementation:
- buildSystemPromptFromVerticals: Append each flow's name and id to the system prompt, separated by double newlines
- loadVerticalPrompts: Read all .md files from prompts/, concatenate with `\n\n---\n\n` separator

Verify: Prompt injection order matches the activation order of verticals. No breaking changes to existing prompts.

Commit: `phase-26f/D26F.3: Prompt script injection from vertical prompts/ directories`

---

## Step 4: Node Vertical Registry (D26F.4)

Create `packages/protocol-types/src/vertical-registry.ts`.

Implements the VerticalRegistry class with these methods:

- `constructor(nodeConfig: NodeConfig)` — reads verticalCapabilities from config
- `async activate(verticalId: string, verticalPath: string, loader: VerticalLoader): Promise<VerticalConfig>` — loads vertical, validates id matches, stores in map, returns config
- `deactivate(verticalId: string): boolean` — removes from map, returns true if was active
- `getAllActive(): VerticalConfig[]` — returns all active verticals
- `getVertical(verticalId: string): VerticalConfig | undefined` — returns a single vertical
- `isActive(verticalId: string): boolean` — checks if active
- `setCapability(verticalId: string, token: Uint8Array): void` — stores capability token
- `getCapability(verticalId: string): Uint8Array | undefined` — retrieves capability token

Verify: Registry state is mutable and persistent during the lifetime of a node instance.

Also update `packages/protocol-types/src/node-config.ts` to add:
- `verticalPaths: string[]` — array of installed vertical paths
- `verticalCapabilities: Record<string, Uint8Array>` — capability tokens per vertical
- `activeVerticals?: Array<{ id, name, version, activatedAt }>` — metadata about active verticals

Commit: `phase-26f/D26F.4: VerticalRegistry with activation/deactivation and NodeConfig updates`

---

## Step 5: Gate Tests (TDD)

Create `packages/__tests__/phase26f-vertical-loading.test.ts`.

Implement 20 tests organized as follows:

**Unit Tests (T1–T8)**
- T1: Valid manifest passes validation
- T2: Missing id throws error
- T3: Missing taxonomyPath throws error
- T4: Invalid version string throws error
- T5: loadVertical() reads manifest, taxonomy, flows, prompts
- T6: loadVertical() throws VerticalLoadError if manifest missing (MANIFEST_MISSING)
- T7: loadVertical() throws VerticalLoadError if taxonomy invalid JSON (TAXONOMY_INVALID)
- T8: loadVertical() skips missing flow/prompt files, logs warning, continues

**Integration Tests (T9–T16)**
- T9: VerticalRegistry.activate() loads vertical and adds to registry
- T10: VerticalRegistry.deactivate() removes vertical
- T11: activate() "trades" + activate() "sovereignty" → both active
- T12: getAllActive() returns all in order
- T13: mergeVerticals([trades, sovereignty]) → union of objectTypes by typeHash
- T14: mergeVerticals() resolves duplicate typeHash (keeps first)
- T15: mergeVerticals() merges taxonomy dimensions correctly
- T16: Node startup loads all verticals from NodeConfig.verticalPaths

**Anti-Regression Tests (T17–T20)**
- T17: Compiled verticals in bundle still work (fallback path)
- T18: No existing VerticalConfig tests broken
- T19: Chat.ts system prompt injection doesn't break existing flows
- T20: Node self-object creation succeeds with multi-vertical setup

Test setup:
- Use `configs/extensions/trades-services.json` and `configs/extensions/core.json` as real test data
- Create a test MemoryAdapter or NodeFsAdapter to simulate filesystem reads
- Each test should verify the exact behavior (not just `toBeDefined()`)

Commit: `phase-26f/T1-T20: full gate test suite — unit, integration, anti-regression`

---

## Step 6: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new and modified file
2. Check that VerticalLoadError codes are exact matches
3. Check that mergeVerticals() doesn't mutate input arrays
4. Check that prompt injection concatenates in the correct order
5. Check that deactivate() returns false for non-existent verticals
6. Check that merging taxonomy dimensions doesn't lose any nodes
7. Write errata doc as `docs/prd/PHASE-26F-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/protocol-types/src/vertical-manifest.ts` exists with validation
- [ ] `packages/protocol-types/src/vertical-loader.ts` exists with full VerticalLoader implementation
- [ ] `packages/protocol-types/src/vertical-registry.ts` exists with activation/deactivation
- [ ] `packages/shell/src/chat.ts` updated with prompt injection functions
- [ ] `packages/protocol-types/src/node-config.ts` updated with verticalPaths and verticalCapabilities
- [ ] `packages/loom/src/config/verticalConfig.ts` has manifestPath field
- [ ] Tests T1–T20 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-26f/D26F.N:` naming convention
- [ ] Branch is `phase-26f-vertical-loading`
- [ ] Errata sprint complete with `docs/prd/PHASE-26F-ERRATA.md`

---

## Next Phase

Phase 26G packages the kernel for deployment: Docker image, install script, admin CLI. Verticals ship as separate packages from the Semantos registry.
