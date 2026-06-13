---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-9-FULL-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.673846+00:00
---

# Phase 9 — Full Execution Prompt (Git Hygiene + Build + Errata)

> Paste this prompt into a fresh session. It handles everything: git setup, Phase 9 execution, and errata audit — in order, end to end. Do NOT cherry-pick sections. Execute sequentially.

---

## PART 0: GIT HYGIENE & PRE-FLIGHT

Before writing any code, get the repository into a clean, known state.

### 0.1 Verify and Prepare

1. `cd` to the `semantos-core` repo root.
2. Run `git status`. If there are uncommitted changes:
   - Read what changed. Group them logically (cleanup vs. feature work vs. stale files).
   - Commit each group separately with a descriptive message.
   - Do NOT use `git add -A`. Stage files explicitly by name.
3. Run `git log --oneline -10` to understand where you are.
4. Confirm you are on `main` or a clean branch point. If you are on a stale phase branch:
   - `git checkout main && git pull` (if remote exists).

### 0.2 Create the Phase Branch

```bash
git checkout main
git checkout -b phase-9-intent-classification
```

If `phase-9-intent-classification` already exists and contains partial work:
- Check what's in it: `git log main..phase-9-intent-classification --oneline`
- If the work is salvageable, continue from it.
- If it's garbage, delete it and recreate: `git branch -D phase-9-intent-classification && git checkout -b phase-9-intent-classification`

### 0.3 Set Git Identity (if needed)

```bash
git config user.email "$(git config user.email || echo 'dev@semantos.dev')"
git config user.name "$(git config user.name || echo 'Semantos Dev')"
```

### 0.4 Validate Existing State

Before building anything new, verify the codebase you're inheriting:

1. Check that extension configs parse: load each JSON in `configs/extensions/` and call `validateExtensionConfig()`.
2. Check that the WASM binary exists at `packages/cell-engine/zig-out/bin/cell-engine-embedded.wasm`.
3. Check that `packages/protocol-types/src/constants.ts` exports `Linearity`, `CommercePhase`.
4. Run `npx tsc --noEmit` (or `bun run check` if available). Note pre-existing errors but don't fix them unless they block Phase 9 work.

**GATE**: You have a clean branch, a clean working tree, and you know the state of the codebase. Only then proceed to Part 1.

---

## PART 1: READ BEFORE YOU WRITE

**Do not skip this.** Read every file listed below before writing a single line of code. If you produce stubs, mocks, or code that doesn't integrate with the existing codebase, it's because you skipped this step.

**Read first** (your requirements):
- `docs/prd/SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md` — Full audit + Phase 9 spec (deliverables D9.1–D9.4)

**Read second** (architectural constraint):
- The "Renderer Agnosticism" section in the above PRD. ALL new services go in `packages/loom/src/services/`. Services never import from React.

**Read third** (code you are extending):
- `packages/loom/src/types/workbench.ts`
- `packages/loom/src/config/extensionConfig.ts`
- `packages/loom/src/state/workbenchReducer.ts`
- `packages/loom/src/state/objectFactory.ts`
- `packages/loom/src/canvas/ConversationPanel.tsx`
- `packages/loom/src/canvas/CommandBar.tsx`
- `packages/loom/src/commands/parser.ts`
- `packages/loom/src/commands/executor.ts`
- `packages/loom/src/identity/IdentityProvider.tsx`
- `packages/loom/src/config/ExtensionProvider.tsx`

**Read fourth** (GIP identity model):
- `docs/TAXONOMY-SEED-DESIGN.md` § "GIP Integration"
- `src/types/gip.ts`

**Read fifth** (extension configs — your test data):
- `configs/extensions/trades-services.json`
- `configs/extensions/blockchain-risk.json`
- `configs/extensions/core.json`
- `configs/extensions/development.json`

**Read sixth** (kernel types and constants):
- `src/cell-engine/typeHashRegistry.ts`
- `packages/protocol-types/src/constants.ts`

**Read seventh** (branching and quality policy):
- `docs/BRANCHING-AND-CI-POLICY.md`

---

## PART 2: EXECUTE PHASE 9

Follow the deliverables below in order. Commit after each deliverable completes its gate test. Use the commit format: `phase-9/D9.X: <what changed>`.

### D9.0: Pre-flight — Fix typeHash + Extract Service Layer

1. Compute stable SHA256 typeHash values for every ObjectTypeDefinition in all 4 extension configs. Stamp them into the JSON files. For system types (Identity, Facet, Policy), use `SHA256("semantos.system.<TypeName>")`.

2. Create `packages/loom/src/services/` with these files:
   - `TypedEventEmitter.ts` — minimal browser-safe event emitter (no Node deps)
   - `LoomStore.ts` — extracted from WorkbenchProvider. EventEmitter-based, holds LoomState, dispatches through workbenchReducer. `subscribe()`/`getSnapshot()` for useSyncExternalStore.
   - `IdentityStore.ts` — extracted from IdentityProvider. GIP trait structure (`IdentityTraits: { disclosed, hashed, schema }`). localStorage persistence. Supports `createIdentity`, `addFacet`, `switchFacet`, `addPolicy`, `togglePolicy`, `updateTraits`.
   - `ConfigStore.ts` — loads extension configs, validates, emits on change. `mergeExtensions()` for core+domain.
   - `SettingsStore.ts` — OpenRouter API key, model ID, temperature. localStorage persistence.
   - `intent-types.ts` — `IntentClassification`, `ClassificationContext`, `UNKNOWN_INTENT`.
   - `index.ts` — barrel re-exports + singleton instances.

3. Rewrite React providers as thin `useSyncExternalStore` wrappers over the stores.

**GATE**: Import stores directly in a non-React test. Create an identity, add a facet, switch facets, create an object — all without React.

**Commit**: `phase-9/D9.0: service layer extraction + typeHash stamping`

### D9.1: OpenRouter LLM Bridge — IntentClassifier

1. `packages/loom/src/services/IntentClassifier.ts`:
   - `classifyIntent(message, context, settings?)` → `Promise<IntentClassification>`
   - Builds system prompt from extension config (object types, taxonomy paths, flow IDs)
   - Calls OpenRouter API (`https://openrouter.ai/api/v1/chat/completions`)
   - Parses structured JSON response
   - Returns `UNKNOWN_INTENT` when no API key (real degradation, not a stub)
   - Never throws on network errors

2. `buildContextFromConfig(config, extras?)` — utility to build ClassificationContext from ExtensionConfig.

3. **No canned responses. No hardcoded classifications. No lazy imports through barrel files (avoid circular deps).**

**GATE**: Verify correct prompt construction from trades-services.json. Verify degraded mode. Verify IntentClassification shape.

**Commit**: `phase-9/D9.1: OpenRouter LLM bridge for intent classification`

### D9.2: Flow Registry + Flow Runner

1. Add to `extensionConfig.ts`: `ConversationFlow`, `FlowStep`, `FlowAction` interfaces. Add `flows?: ConversationFlow[]` to `ExtensionConfig`. Add validation in `validateExtensionConfig`.

2. Add flows to `trades-services.json` (create-job, generate-estimate, schedule-visit) and `blockchain-risk.json` (new-assessment, extract-evidence).

3. `FlowRegistry.ts`:
   - `findFlow(intent, facetCapabilities, config)` — matches intent against triggerIntents, checks requiredCapabilities.
   - Pure lookup, no side effects.

4. `FlowRunner.ts` (extends TypedEventEmitter):
   - `startFlow(flow, objectId?)`, `advanceFlow(response, extractedFields?)`, `cancelFlow()`, `reset()`
   - Immutable state updates (do NOT mutate `this.state` in place)
   - Emits 'step', 'complete', 'cancel' events

**GATE**: Load trades-services.json. Find flow for "create.job". Run through all steps. Verify object creation on completion. Verify capability gating rejects unauthorized facets.

**Commit**: `phase-9/D9.2: flow registry and runner with conversation flows`

### D9.3: ConversationPanel Integration

1. Modify `ConversationPanel.tsx`:
   - On every user message: classify intent asynchronously
   - If classification matches a flow and facet has capabilities: start FlowRunner
   - During active flow: show step prompts, collect responses, show progress
   - On flow completion: execute FlowAction (create object, patch, transition, navigate)
   - Handle ALL FlowAction types: create, patch, transition, navigate

2. Graceful degradation: no API key → works exactly like before (plain text patches).

**GATE**: Full flow from "I need a plumber" → 3-step intake → Job object created.

**Commit**: `phase-9/D9.3: ConversationPanel intent classification + flow integration`

### D9.4: CommandBar Intent Bridge

1. Modify `executor.ts`:
   - Add `facetCapabilities?: number[]` to CommandContext
   - New commands: `settings`, `flow list`, `flow start <id>` (honest about limitations), `intent <text>`
   - LLM fallback for unknown commands: classify via IntentClassifier, use REAL facet capabilities (not hardcoded `[1..10]`)

2. Modify `parser.ts`: add command types for settings, flow, intent.

**GATE**: "show plumbing jobs" classifies as navigate. Unknown commands fall through to classifier. Existing commands still work.

**Commit**: `phase-9/D9.4: CommandBar intent bridge + new commands`

### Final Commit

After all deliverables pass their gates:

```bash
git log main..HEAD --oneline  # Verify 4-5 clean commits
```

---

## PART 3: ERRATA SPRINT

**Do this in the same session, immediately after Part 2.** The errata sprint catches bugs introduced during implementation while context is fresh.

### 3.1 Re-read All Delivered Code Adversarially

Go back and read every file you created or modified. This time you are the auditor, not the author. You are looking for bugs.

**Files to audit**:
- `packages/loom/src/services/TypedEventEmitter.ts`
- `packages/loom/src/services/LoomStore.ts`
- `packages/loom/src/services/IdentityStore.ts`
- `packages/loom/src/services/ConfigStore.ts`
- `packages/loom/src/services/SettingsStore.ts`
- `packages/loom/src/services/IntentClassifier.ts`
- `packages/loom/src/services/FlowRegistry.ts`
- `packages/loom/src/services/FlowRunner.ts`
- `packages/loom/src/services/intent-types.ts`
- `packages/loom/src/services/index.ts`
- `packages/loom/src/state/WorkbenchProvider.tsx`
- `packages/loom/src/canvas/ConversationPanel.tsx`
- `packages/loom/src/commands/parser.ts`
- `packages/loom/src/commands/executor.ts`
- `packages/loom/src/config/extensionConfig.ts`
- `configs/extensions/trades-services.json`
- `configs/extensions/blockchain-risk.json`

### 3.2 Scan Checklist

For each file, check:

1. **Empty typeHash** — any ObjectTypeDefinition with `typeHash: ''`?
2. **Circular imports** — any dynamic `await import('./index')` or barrel-file cycles?
3. **Mutable state** — any `this.state.field = value` instead of immutable update?
4. **Leaked listeners** — any event subscriptions without cleanup in useEffect returns?
5. **Hardcoded capabilities** — any `[1, 2, 3, ... 10]` where real facet caps should be used?
6. **Missing FlowAction handlers** — does the completion handler cover ALL of `create | transition | patch | navigate`?
7. **Dead code** — config fields defined but never read? Functions exported but never called?
8. **Module-level side effects** — constructors that hit localStorage at import time?
9. **No rate limiting** — LLM calls with no debounce/cancellation?
10. **Swallowed errors** — catch blocks that return undefined instead of propagating?
11. **Stubs** — any function that returns hardcoded values or throws "not implemented"?
12. **`as any` casts** — type safety holes?
13. **React in services** — any `import ... from 'react'` in `src/services/`?

### 3.3 Write the Errata Document

Create `docs/prd/PHASE-9-ERRATA.md` with this structure:

```markdown
# Phase 9 Errata — Service Layer, Intent Classification, Flow Routing

Audit of the Phase 9 implementation...

**Audited files**: [list]

---

## BUG-N: <Title>

**Severity**: BUG | INCONSISTENCY | TECH_DEBT
**File**: <path>, line <N>
**Details**: <What's wrong>
**Fix**: <What it should be>

---

## Summary

| ID | Category | Severity | Effort | Status |
|----|----------|----------|--------|--------|
| ... | ... | ... | ... | MUST FIX / SHOULD FIX / COULD FIX |
```

### 3.4 Fix All MUST FIX Items

Apply fixes. Do NOT amend previous commits — create a new commit:

```bash
git add <fixed files> docs/prd/PHASE-9-ERRATA.md
git commit -m "Phase 9 errata: audit doc + fix N issues across service layer

BUG-1: ...
BUG-2: ...
INC-1: ...

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### 3.5 Verify

Run `npx tsc --noEmit` (or `bun run check`). Confirm no new errors in the files you touched. Pre-existing errors in other files are acceptable.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

These apply across all three parts. Violating any one of these means the phase is incomplete.

1. **No stubs.** Every function does real work or doesn't exist.
2. **No mocks in production paths.** Real LLM endpoint or real degradation.
3. **No easy tests.** Real extension configs, real objects, real assertions.
4. **No tests that match broken code.** Fix the code, not the test.
5. **Renderer agnosticism.** All business logic in `src/services/`. React imports from services, never the reverse.
6. **No circular imports through barrel files.** Import the specific module, not `./index`.
7. **Immutable state updates.** Never mutate `this.state.field` directly — spread and replace.
8. **Thread real facet capabilities.** Never hardcode `[1, 2, 3, ..., 10]`.
9. **Handle all FlowAction types.** If the union is `create | transition | patch | navigate`, handle all four.
10. **Commit after each gate, not at the end.** Atomic commits with gate-passing state.

---

## Completion Criteria

When you are done, `git log main..HEAD --oneline` should show approximately:

```
<hash> Phase 9 errata: audit doc + fix N issues across service layer
<hash> phase-9/D9.4: CommandBar intent bridge + new commands
<hash> phase-9/D9.3: ConversationPanel intent classification + flow integration
<hash> phase-9/D9.2: flow registry and runner with conversation flows
<hash> phase-9/D9.1: OpenRouter LLM bridge for intent classification
<hash> phase-9/D9.0: service layer extraction + typeHash stamping
```

Each commit should leave the codebase in a compiling, gate-passing state. The errata doc should be honest and thorough. The fixes should be real.
