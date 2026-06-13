---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-9-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.661532+00:00
---

# Phase 9 Execution Prompt — LLM Intent Classification + Flow Routing

> Paste this prompt into a fresh session to execute Phase 9.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in `packages/cell-engine/`; this repo also holds the type system, compiler, WASM bindings, and loom UI. The system uses 256-byte cell headers, linearity enforcement (LINEAR/AFFINE/RELEVANT), and extension configs that drive all rendering and behavior. Phase 7.5 scaffolded the loom. Phase 8 built the three-panel canvas (Sidebar, Canvas, Inspector) with conversation-as-patches. Phase 8.5 added identity as an AFFINE object with facets and provenance. All of these are complete and merged to main.

Your task is Phase 9: extract React-coupled state into plain TypeScript services (renderer agnosticism), add LLM intent classification via OpenRouter, and build a flow registry/runner so conversations can drive object creation, transitions, and navigation.

The six-axis coordinate system (WHAT/HOW/WHY required, WHERE/WHEN/WHO optional) is documented in `docs/TAXONOMY-SEED-DESIGN.md`. Identity uses GIP (Genealogical Identity Protocol) trait structure — see the GIP Integration section of that document.

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real
implementations you are building on top of. If you haven't read them, you will produce
stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRD — your requirements):
- `docs/prd/SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md` — Full audit + Phase 9 spec with deliverables D9.1-D9.4

**Read second** (the architectural constraint you MUST follow):
- The "Renderer Agnosticism" section in the above PRD. ALL new services are plain TypeScript in `src/services/`. React components import from services. Services never import from React.

**Read third** (the loom you are extending — actual code, not specs):
- `packages/loom/src/types/workbench.ts` — LoomObject, ObjectPatch, LoomCard, Identity, Facet, ConversationMessage
- `packages/loom/src/config/extensionConfig.ts` — ExtensionConfig, ObjectTypeDefinition, TaxonomyNode, PolicyDefinition, ScriptTemplate
- `packages/loom/src/state/workbenchReducer.ts` — LoomState, 16 action types (ADD_OBJECT, ADD_PATCH, TRANSITION_LINEARITY, etc.)
- `packages/loom/src/state/objectFactory.ts` — createObject(), uses @semantos/protocol-types constants
- `packages/loom/src/canvas/ConversationPanel.tsx` — Current conversation implementation: messages as patches with facet provenance
- `packages/loom/src/canvas/CommandBar.tsx` — Current command system with parser + executor
- `packages/loom/src/commands/parser.ts` — Typed command parser (11 command types)
- `packages/loom/src/commands/executor.ts` — Command executor with loom context
- `packages/loom/src/identity/IdentityProvider.tsx` — Identity context, facet management, localStorage persistence
- `packages/loom/src/config/ExtensionProvider.tsx` — Extension config loading + switching

**Read fourth** (GIP identity model — you will use this in IdentityStore extraction):
- `docs/TAXONOMY-SEED-DESIGN.md` § "GIP Integration" — how GIP maps to the six-axis coordinate system
- `src/types/gip.ts` — GIPUser, GIPCertificate, GIPTraits (disclosed/hashed/merkle_root), selective disclosure model

**Read fifth** (the extension configs — your test data):
- `configs/extensions/trades-services.json` — OddJobTodd: 7 object types, 3-dimension taxonomy, scoring policy
- `configs/extensions/blockchain-risk.json` — BREM: different types, different phases
- `configs/extensions/core.json` — Base types (Thing, Action, Instrument)
- `configs/extensions/development.json` — Full debug config

**Read sixth** (the kernel — what types and constants exist):
- `src/cell-engine/typeHashRegistry.ts` — computeTypeHash(), buildCellHeader(), packCell(), CellHeader interface
- `src/types/semantic-objects.ts` — Semantic object type definitions
- `src/types/capability.ts` — Capability types and domain flags
- `packages/protocol-types/src/constants.ts` — Linearity, CommercePhase, DomainFlags enums

**Read seventh** (the branching and CI policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Follow this. Branch from main as `phase-9-intent-classification`. After merge, run the errata scan protocol before starting Phase 9.5.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

These rules override any instinct to "get something working" by cutting corners.

### 1. NO STUBS

Every function you write must do real work. If a function's body is `throw new Error("not implemented")` or `return undefined` or `return {}`, you have failed. If you can't implement something fully, stop and explain what's blocking you. Do not leave stubs.

### 2. NO MOCKS IN PRODUCTION PATHS

Test files may use fixtures. Source files may not contain mock data, hardcoded responses, or fake classifications. The IntentClassifier must call a real LLM endpoint (or gracefully degrade with a clear "no API key configured" state). It must never return a canned response.

### 3. NO EASY TESTS

Tests must verify real behavior with real extension configs. If you write a test that passes because it checks a default value, it's worthless. Every test must:
- Use at least one real extension config (trades-services.json or blockchain-risk.json)
- Create real objects via `createObject()` with real ObjectTypeDefinitions
- Verify non-trivial outcomes (correct intent classification, correct flow activation, correct patch creation)

If a test is one line that checks `expect(result).toBeDefined()`, delete it and write a real test.

### 4. NO TESTS THAT MATCH BROKEN CODE

If your code produces the wrong output, FIX THE CODE. Do not change the test expectation to match the broken output. Tests encode requirements. Code conforms to tests. If a test expectation seems wrong, re-read the source files listed above.

### 5. RENDERER AGNOSTICISM IS NOT OPTIONAL

If you put business logic in a React component, you have violated the architectural constraint. All services go in `packages/loom/src/services/`. React components in `src/canvas/`, `src/sidebar/`, `src/identity/` may only call service methods and render results.

---

## PRE-FLIGHT: Fix typeHash Values

Before starting Phase 9 deliverables, fix the empty typeHash problem discovered in the audit.

1. In `packages/loom/src/state/objectFactory.ts` or a new `src/services/typeHashService.ts`:
   - Import `computeTypeHash` from `src/cell-engine/typeHashRegistry.ts`
   - When creating an object, compute the typeHash from the ObjectTypeDefinition's category field
   - If category is a dotted path like `services.trades`, derive WHAT/HOW/INSTRUMENT from the extension config taxonomy
   - Fallback: SHA256 of the type name if no category is set

2. Update all 4 extension config JSON files: pre-compute typeHash values for every ObjectTypeDefinition.

3. Gate test: `packages/__tests__/phase9-gate.test.ts` must verify that no object created from any extension config has an all-zero typeHash.

---

## Step 1: Service Layer Extraction (D9.0 — prerequisite)

Before adding new features, extract existing business logic from React into plain TypeScript services.

1. Create `packages/loom/src/services/` directory.

2. Extract `LoomStore` from `WorkbenchProvider.tsx`:
   ```typescript
   // src/services/LoomStore.ts
   // EventEmitter-based store. Holds LoomState, dispatches WorkbenchActions.
   // React's WorkbenchProvider becomes a thin wrapper: useEffect subscribes to store events.
   // Game engine / CLI / WebSocket client subscribes directly.
   ```

3. Extract `IdentityStore` from `IdentityProvider.tsx`:
   ```typescript
   // src/services/IdentityStore.ts
   // Holds Identity, manages facets, persists to storage (localStorage now, wallet later).
   // React's IdentityProvider wraps this.
   //
   // IMPORTANT: Build with GIP trait structure from day one.
   // Do NOT extract the flat SerializedIdentity as-is and refactor later.
   // The IdentityStore must support:
   //
   interface IdentityTraits {
     disclosed: Record<string, any>;   // public traits (name, etc.)
     hashed: Record<string, string>;   // SHA256 hashed, verifiable with preimage
     schema: string;                   // "gip.heraldic.v0.0.1" or version
   }
   //
   // Add traits field to Identity. Add optional genealogicalLinks (object IDs
   // of parent/child typed connections). Disclosure rules are keyed by
   // jurisdiction (WHERE coordinate) — but for now just store the
   // disclosed/hashed split. ZK proofs and jurisdiction-scoped disclosure
   // come in Phase 10+.
   //
   // See: docs/TAXONOMY-SEED-DESIGN.md § GIP Integration
   // See: src/types/gip.ts for full GIP type definitions
   ```

4. Extract `ConfigStore` from `ExtensionProvider.tsx`:
   ```typescript
   // src/services/ConfigStore.ts
   // Loads extension configs from server, validates, emits on change.
   ```

5. React providers become thin wrappers that subscribe to the stores via `useSyncExternalStore` or `useEffect` + `useState`. No business logic in providers.

**Gate test**: Import services directly (not via React) and verify they work in a pure Node/Bun context. Create an object, add a patch, switch facets — all without React.

---

## Step 2: OpenRouter LLM Bridge (D9.1)

```
packages/loom/src/services/IntentClassifier.ts
```

1. Define the `IntentClassification` interface:
   ```typescript
   interface IntentClassification {
     intent: string;              // "create.job", "publish", "stake", "challenge", "navigate"
     confidence: number;          // 0-1
     objectType?: string;         // name of the target object type (from extension config)
     typePath?: string;           // taxonomy path for auto-classification
     flowId?: string;             // script/flow to activate
     extractedFields?: Record<string, unknown>;  // fields parsed from natural language
   }
   ```

2. Implement `classifyIntent(message, context)`:
   - `context` includes: active extension config, active facet + capabilities, current object (if on a card), recent conversation history
   - Builds a system prompt from the extension config: "You are classifying user intent for the {config.name} extension. Available object types: {names}. Available flows: {flow ids}. Taxonomy paths: {paths}."
   - Calls OpenRouter API (fetch POST to `https://openrouter.ai/api/v1/chat/completions`)
   - Parses the structured JSON response into IntentClassification
   - Returns `{ intent: "unknown", confidence: 0 }` if no API key is configured (NOT a stub — a real degraded state)

3. API key storage:
   - `src/services/SettingsStore.ts` — holds user settings including OpenRouter API key
   - Persists to localStorage (BYOK model from commercial context)
   - React: `SettingsPanel.tsx` component for entering the key

4. **No canned responses.** If the LLM returns garbage, return `{ intent: "unknown", confidence: 0 }`. Do not hardcode fallback classifications.

**Gate test**:
- With a mock HTTP server (not a mock classifier), verify that the correct prompt is constructed from trades-services.json
- Verify that "I need a plumber in Northcote" produces a request body containing the taxonomy paths
- Verify degraded mode when no API key is set
- Verify IntentClassification shape on a successful response

---

## Step 3: Flow Registry + Flow Runner (D9.2)

```
packages/loom/src/services/FlowRegistry.ts
packages/loom/src/services/FlowRunner.ts
```

1. Add `flows` to the ExtensionConfig schema in `extensionConfig.ts`:
   ```typescript
   interface ConversationFlow {
     id: string;
     triggerIntents: string[];
     requiredCapabilities: number[];
     steps: FlowStep[];
     onComplete: FlowAction;
   }

   interface FlowStep {
     prompt: string;
     extractionSchema: Record<string, FieldType>;
     validation?: string;
     optional?: boolean;
   }

   interface FlowAction {
     type: 'create' | 'transition' | 'patch' | 'navigate';
     objectType?: string;
     linearityTransition?: string;
     patchFields?: string[];
     targetPath?: string;
   }
   ```

2. Add flows to trades-services.json and blockchain-risk.json:
   ```json
   "flows": [
     {
       "id": "create-job",
       "triggerIntents": ["create.job", "need.service", "request.quote"],
       "requiredCapabilities": [4, 5],
       "steps": [
         {"prompt": "What type of work do you need?", "extractionSchema": {"categoryPath": "string"}},
         {"prompt": "What's the urgency?", "extractionSchema": {"urgency": "enum"}},
         {"prompt": "Any specific details?", "extractionSchema": {"description": "string"}, "optional": true}
       ],
       "onComplete": {"type": "create", "objectType": "Job"}
     }
   ]
   ```

3. `FlowRegistry.ts`:
   - `findFlow(intent: string, capabilities: number[]): ConversationFlow | null`
   - Matches intent against triggerIntents, checks capability requirements
   - Pure lookup, no side effects

4. `FlowRunner.ts`:
   - `startFlow(flow, objectId?)`: begins a flow, returns FlowState
   - `advanceFlow(flowState, userMessage, classifiedFields)`: processes one step
   - `isFlowComplete(flowState)`: check if all required steps are done
   - `completeFlow(flowState)`: executes the FlowAction (creates object, transitions linearity, etc.)
   - Emits patches and actions through the LoomStore
   - FlowState is a LINEAR-like concept: started once, consumed on completion

**Gate test**:
- Load trades-services.json, find flow for intent "create.job"
- Run flow through all steps with simulated user messages
- Verify object is created on flow completion with correct type, category, and field values
- Verify flow requires correct capabilities (reject if facet lacks them)

---

## Step 4: ConversationPanel Intent Integration (D9.3)

```
packages/loom/src/canvas/ConversationPanel.tsx (modify existing)
```

1. On every user message:
   - Call `IntentClassifier.classifyIntent()` asynchronously
   - Store classification result on the patch: `patch.delta.intent = classification`
   - If classification matches a flow trigger, check FlowRegistry
   - If flow found and facet has required capabilities, start FlowRunner

2. When a flow is active:
   - Show the current step's prompt as a system message
   - Extract fields from user responses (via LLM if available, regex fallback)
   - Show flow progress indicator (step 2 of 3, etc.)
   - On flow completion, execute the FlowAction and show result

3. When no flow is active:
   - Messages are plain text patches (existing behavior)
   - Intent classification still runs (shows badge) but doesn't trigger actions

4. **Graceful degradation**: If no API key is configured, ConversationPanel works exactly as it does today — plain text patches. Intent badges show "no classifier" instead of classified intent.

**Gate test**:
- Integration test: create a Job object through conversation flow on trades-services extension
- Verify patches have intent classification attached
- Verify flow step prompts appear in conversation
- Verify object is created with correct fields on flow completion

---

## Step 5: CommandBar Intent Bridge (D9.4)

```
packages/loom/src/canvas/CommandBar.tsx (modify existing)
packages/loom/src/commands/parser.ts (modify existing)
packages/loom/src/commands/executor.ts (modify existing)
```

1. Add an LLM fallback to the command parser:
   - If `parseCommand()` returns `{ type: 'unknown' }`, send the raw input to IntentClassifier
   - If the classifier returns a navigation intent, execute it
   - If it returns a create intent, start the appropriate flow

2. New command types:
   - `settings` — open settings panel (API key configuration)
   - `flow <flow-id>` — manually start a flow
   - `intent <text>` — show what the classifier would return for this input

**Gate test**:
- "show plumbing jobs" classifies as navigate intent to services.trades.plumbing
- "I need a carpenter" triggers create-job flow via intent classification
- Commands that match existing parser patterns still work (no regressions)

---

## Phase 9 Gate Test File

Create `packages/__tests__/phase9-gate.test.ts`:

```typescript
describe("Phase 9 Gate: Intent Classification + Flow Routing", () => {
  // Gate 1: Service layer extraction
  test("LoomStore works without React", () => { /* ... */ });
  test("IdentityStore works without React", () => { /* ... */ });
  test("ConfigStore loads extension configs without React", () => { /* ... */ });

  // Gate 2: typeHash pre-computation
  test("all extension config objects have non-zero typeHash", () => { /* ... */ });
  test("typeHash is deterministic (same inputs = same hash)", () => { /* ... */ });

  // Gate 3: Intent classification
  test("IntentClassifier constructs correct prompt from extension config", () => { /* ... */ });
  test("IntentClassifier returns unknown when no API key", () => { /* ... */ });
  test("IntentClassification shape is valid", () => { /* ... */ });

  // Gate 4: Flow registry + runner
  test("FlowRegistry finds correct flow for intent on trades-services", () => { /* ... */ });
  test("FlowRegistry rejects flow when capabilities insufficient", () => { /* ... */ });
  test("FlowRunner creates object on flow completion", () => { /* ... */ });
  test("FlowRunner applies correct fields from conversation", () => { /* ... */ });

  // Gate 5: Anti-regression
  test("no NOT_IMPLEMENTED in loom source", () => { /* ... */ });
  test("no hardcoded classifications in IntentClassifier", () => { /* ... */ });
  test("ConversationPanel still works without API key (graceful degradation)", () => { /* ... */ });
});
```

Every test must be fleshed out with real assertions against real data. The skeleton above is your checklist, not your implementation.

---

## Completion Criteria

1. User types "I need a plumber in Northcote" in ConversationPanel → intent classified as create.job with typePath services.trades.plumbing
2. Flow activates, asks for details across 2-3 turns, creates AFFINE Job object on completion
3. CommandBar accepts "show plumbing jobs" → navigates to taxonomy filter
4. Intent classification works with both trades-services and blockchain-risk extensions
5. BYOK: OpenRouter API key configurable in settings, not hardcoded
6. All services work in pure TypeScript without React (imported and tested directly)
7. `bun test packages/__tests__/phase9-gate.test.ts` passes
8. `bun run check` passes (zero TypeScript errors)
9. No stubs, no mocks, no hardcoded classifications in source files

---

## Post-Phase: Errata Sprint

After merging to main, follow the errata scan protocol in `docs/BRANCHING-AND-CI-POLICY.md`.
Open a FRESH session, paste the errata scan prompt, and review all delivered code adversarially.
Fix any issues on an `errata/phase-9` branch before starting Phase 9.5.
