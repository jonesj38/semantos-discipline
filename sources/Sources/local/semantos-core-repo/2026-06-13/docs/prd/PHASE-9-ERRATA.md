---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-9-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.718981+00:00
---

# Phase 9 Errata — Service Layer, Intent Classification, Flow Routing

Audit of the Phase 9 implementation: 10 renderer-agnostic services, modified providers, ConversationPanel, CommandBar, executor/parser, extension config flows.

**Audited files**: `services/TypedEventEmitter.ts`, `services/LoomStore.ts`, `services/IdentityStore.ts`, `services/ConfigStore.ts`, `services/SettingsStore.ts`, `services/IntentClassifier.ts`, `services/FlowRegistry.ts`, `services/FlowRunner.ts`, `services/intent-types.ts`, `services/index.ts`, `state/WorkbenchProvider.tsx`, `canvas/ConversationPanel.tsx`, `commands/parser.ts`, `commands/executor.ts`, `config/extensionConfig.ts`, `types/workbench.ts`, `configs/extensions/trades-services.json`, `configs/extensions/blockchain-risk.json`

---

## BUG-1: Empty typeHash on internal ObjectTypeDefinitions

**Severity**: BUG
**File**: `services/IdentityStore.ts`, lines 44–84
**Details**: `IDENTITY_TYPE`, `FACET_TYPE`, and `POLICY_TYPE` all have `typeHash: ''`. These are used to create LoomObjects via `createObject()`. Every Identity, Facet, and Policy object will have an empty type hash in its cell header, which means:
- They cannot be validated against the WASM kernel's type registry
- `cell_validate_magic` and any future type-based routing will fail silently
- If two different type definitions both have `typeHash: ''`, there's no way to distinguish them at the cell level

**Fix**: Compute stable SHA256 hashes for these three type definitions, matching the pattern used in the extension config JSON files. These are system types so they should use well-known constant hashes.

---

## BUG-2: Module-level `idCounter` resets on reload; collides with persisted IDs

**Severity**: BUG
**File**: `services/IdentityStore.ts`, line 88
**Details**: `let idCounter = 0` is module-scoped. On page reload, it resets to 0, but `localStorage` still holds identity data with previously generated IDs like `facet-1711234567890-3`. If the user creates a new facet after reload, `generateId('facet')` could produce `facet-1711234568000-1`, which is unique due to the timestamp component. However, the counter portion starts from 1 again, and if two calls happen within the same millisecond (e.g., during deserialization or rapid creation), the IDs will collide.

**Impact**: Low probability collision, but the fix is trivial.
**Fix**: Seed `idCounter` from a random offset or from the count of existing items during `loadFromStorage()`.

---

## BUG-3: `flow start` command is a no-op — doesn't actually start the flow

**Severity**: BUG
**File**: `commands/executor.ts`, lines 118–122
**Details**: The `flow start <id>` command finds the flow in config, then returns a message saying "use conversation panel to interact." It never creates a FlowRunner, never dispatches any state change, and never transitions the flow to running. The command is effectively decorative.

**Contrast**: ConversationPanel _does_ start flows correctly via `flowRunner.startFlow(flow, object.id)`. But the command-line path is dead.

**Fix**: Either wire the executor to a shared FlowRunner instance (which requires refactoring executor to receive a FlowRunner in context), or document it as intentionally unsupported from CommandBar and remove the misleading success message. The latter is more honest for now.

---

## BUG-4: `unknown` command handler hardcodes ALL_CAPABILITIES `[1..10]`

**Severity**: BUG
**File**: `commands/executor.ts`, line 188
**Details**: When an unknown command is classified by the LLM, `findFlow()` is called with `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]` as the capability array instead of the active facet's actual capabilities. This bypasses capability gating entirely — a facet with only `[4, 5]` capabilities would still match flows requiring `[2, 9]`.

**Fix**: Pass the active facet's capabilities through `CommandContext`. Add `facetCapabilities?: number[]` to the `CommandContext` interface and thread it from the calling component.

---

## INCONSISTENCY-1: Lazy `await import('./index')` creates a circular dependency path

**Severity**: INCONSISTENCY
**File**: `services/IntentClassifier.ts`, line 98
**Details**: `classifyIntent()` does `const { settingsStore: store } = await import('./index')` when no `settings` parameter is provided. `index.ts` imports from `IntentClassifier.ts` (re-exports `classifyIntent`). This creates a module-level circular dependency. It works today because the lazy import is dynamic and deferred, but it's fragile — any refactor that makes the import eager (or any bundler that hoists it) will break.

**Fix**: Accept `SettingsStore` as a parameter in all call sites, or import `SettingsStore` directly instead of going through the barrel file:
```typescript
import { SettingsStore } from './SettingsStore';
```

---

## INCONSISTENCY-2: FlowRunner mutates `this.state` in place, then emits

**Severity**: INCONSISTENCY
**File**: `services/FlowRunner.ts`, lines 84–110
**Details**: `advanceFlow()` mutates `this.state.collectedData[field]` and `this.state.currentStepIndex++` directly, then emits events with the mutated state. This is inconsistent with the immutable-update pattern used elsewhere (LoomStore uses `workbenchReducer` which returns new state objects; IdentityStore uses spread copies).

The direct mutation means:
- Any listener that captured the state object before the event sees the mutation retroactively
- `completeFlow()` returns `{ ...this.state }` — a shallow copy, but `collectedData` is the same reference

**Fix**: Build a new state object per advance:
```typescript
this.state = {
  ...this.state,
  currentStepIndex: this.state.currentStepIndex + 1,
  collectedData: { ...this.state.collectedData, [field]: value },
};
```

---

## INCONSISTENCY-3: ConversationPanel creates FlowRunner per-component; event listeners leak

**Severity**: INCONSISTENCY
**File**: `canvas/ConversationPanel.tsx`, line 31
**Details**: `const [flowRunner] = useState(() => new FlowRunner())` creates a FlowRunner instance per ConversationPanel mount. FlowRunner extends TypedEventEmitter, but no `useEffect` cleanup ever calls `off()` or disposes the listener set. If the component unmounts and remounts (e.g., selecting different objects), the old FlowRunner and its listener closures persist in memory.

More critically, the component doesn't subscribe to FlowRunner events at all — it drives the flow imperatively via `advanceFlow()` and reads state inline. The event emitter machinery is dead weight in this usage pattern.

**Fix**: Either (a) add cleanup via `useEffect(() => () => flowRunner.reset(), [])`, or (b) since events aren't used by the component, consider making FlowRunner a plain class without event emission for the React integration path.

---

## INCONSISTENCY-4: `validateExtensionConfig` doesn't validate `typeHash` presence

**Severity**: INCONSISTENCY
**File**: `config/extensionConfig.ts`, lines 119–143
**Details**: The validator checks for `name`, `linearity`, and `fields` on each object type, but doesn't check `typeHash`. A config with empty or missing typeHash values passes validation, even though the cell-engine kernel needs non-empty hashes to enforce type-based semantics.

**Fix**: Add to the objectType validation loop:
```typescript
if (!ot.typeHash || typeof ot.typeHash !== 'string' || ot.typeHash.length !== 64) {
  throw new Error(`Invalid typeHash on objectType: ${ot.name}`);
}
```

---

## INCONSISTENCY-5: `LoomStore.openAsCard` uses mutable counter for positioning

**Severity**: INCONSISTENCY (minor)
**File**: `services/LoomStore.ts`, lines 81–99
**Details**: `private cardCounter = 0` is used for both card IDs and cascade positioning. It resets on store construction (page reload) but existing cards from state won't reset the counter. New card IDs could collide with old ones if state were ever persisted (it isn't today, but the LoomStore is designed for future persistence).

**Fix**: Initialize `cardCounter` from `this.state.cards.size` in the constructor, or use a UUID/timestamp-based ID.

---

## INCONSISTENCY-6: `buildContextFromConfig` only traverses 2 taxonomy levels

**Severity**: INCONSISTENCY
**File**: `services/IntentClassifier.ts`, lines 160–172
**Details**: The taxonomy path extractor does `dim.nodes → node.children` but doesn't recurse deeper. If a extension config has 3+ levels of taxonomy nesting, the deeper paths are invisible to the intent classifier. The trades-services config currently only has 2 levels so this doesn't bite yet, but it's a latent issue.

**Fix**: Use a recursive traversal:
```typescript
function collectPaths(nodes: { path: string; children?: { path: string; children?: any[] }[] }[]): string[] {
  const paths: string[] = [];
  for (const node of nodes) {
    paths.push(node.path);
    if (node.children) paths.push(...collectPaths(node.children));
  }
  return paths;
}
```

---

## INCONSISTENCY-7: ConversationPanel `executeFlowCompletion` doesn't match all FlowAction types

**Severity**: INCONSISTENCY
**File**: `canvas/ConversationPanel.tsx`, lines 73–138
**Details**: `FlowAction.type` is a union of `'create' | 'transition' | 'patch' | 'navigate'`. The completion handler covers `create`, `patch`, and `navigate`, but not `transition`. A flow with `onComplete: { type: 'transition' }` would silently do nothing.

**Fix**: Add a `transition` handler that dispatches a state transition patch on the current object, or throw an explicit "not implemented" error so it's visible during development.

---

## TECH_DEBT-1: Singletons instantiated at module import time

**Severity**: TECH_DEBT
**File**: `services/index.ts`, lines 26–29
**Details**: All four store singletons (`loomStore`, `identityStore`, `configStore`, `settingsStore`) are created at module evaluation time. `IdentityStore` and `SettingsStore` both hit `localStorage` in their constructors. This means:
- Any test that imports from `services/index.ts` triggers localStorage access
- SSR environments will throw unless localStorage is polyfilled
- Import order between stores could matter if one store ever depends on another during construction

**Fix**: Lazy initialization pattern:
```typescript
let _loomStore: LoomStore | null = null;
export function getLoomStore(): LoomStore {
  if (!_loomStore) _loomStore = new LoomStore();
  return _loomStore;
}
```
Or use a DI container. Not urgent for browser-only usage.

---

## TECH_DEBT-2: No rate limiting or debounce on intent classification

**Severity**: TECH_DEBT
**File**: `canvas/ConversationPanel.tsx`, line 190; `commands/executor.ts`, line 180
**Details**: Every message in ConversationPanel and every unknown command in executor triggers an async LLM classification call with no debounce, no deduplication, and no cancellation of in-flight requests. Rapid typing + Enter could fire multiple concurrent API calls, and stale responses could arrive after newer ones.

**Fix**: Add an AbortController pattern:
```typescript
const abortRef = useRef<AbortController | null>(null);
// In handleSend:
abortRef.current?.abort();
abortRef.current = new AbortController();
const classification = await classifyIntent(text, context, undefined, abortRef.current.signal);
```
This requires threading the signal through `classifyIntent` to `fetch()`.

---

## TECH_DEBT-3: FlowRunner not shared between ConversationPanel and CommandBar

**Severity**: TECH_DEBT
**File**: `canvas/ConversationPanel.tsx`, line 31; `commands/executor.ts`, lines 110–127
**Details**: ConversationPanel creates its own FlowRunner. The executor doesn't create one at all (BUG-3). If both paths are ever meant to drive the same flow, they need a shared instance — either lifted into a store or passed through context. Currently there's no way for the command bar to know a flow is already running in ConversationPanel, or vice versa.

**Fix**: Create a `FlowStore` service (extends TypedEventEmitter) that holds a single FlowRunner and exposes it through the service layer. Both ConversationPanel and executor would use the same instance.

---

## TECH_DEBT-4: Extension config flow `extractionSchema` is unused

**Severity**: TECH_DEBT
**File**: `config/extensionConfig.ts`, line 106; `configs/extensions/trades-services.json` (multiple steps)
**Details**: `FlowStep.extractionSchema` is defined in the type and populated in every flow step in both extension configs (e.g., `"extractionSchema": { "categoryPath": "string" }`), but no code reads it. `FlowRunner.advanceFlow()` accepts `extractedFields` as a parameter but the caller (ConversationPanel) never extracts fields from responses using the schema. The schema data is dead config.

**Fix**: Either implement extraction (e.g., pass the schema to the LLM as a structured output request alongside the step prompt), or remove `extractionSchema` from the config and type definition to avoid confusion.

---

## Summary

| ID | Category | Severity | Effort | Status |
|----|----------|----------|--------|--------|
| BUG-1 | Empty typeHash on system types | High | Low | FIXED |
| BUG-2 | idCounter collision on reload | Low | Low | FIXED |
| BUG-3 | `flow start` command is no-op | Medium | Medium | FIXED |
| BUG-4 | Hardcoded ALL_CAPABILITIES in executor | Medium | Low | FIXED |
| INC-1 | Circular import in IntentClassifier | Medium | Low | FIXED |
| INC-2 | Mutable state in FlowRunner | Medium | Low | FIXED |
| INC-3 | FlowRunner event listener leak | Low | Low | NOTED (events unused by component) |
| INC-4 | No typeHash validation in config | Medium | Low | FIXED |
| INC-5 | Mutable card counter | Low | Low | COULD FIX |
| INC-6 | Shallow taxonomy traversal | Low | Low | COULD FIX |
| INC-7 | Missing `transition` handler | Medium | Low | FIXED |
| TD-1 | Eager singleton construction | Low | Medium | COULD FIX |
| TD-2 | No rate limiting on LLM calls | Medium | Medium | SHOULD FIX |
| TD-3 | No shared FlowStore | Medium | Medium | SHOULD FIX |
| TD-4 | Dead extractionSchema config | Low | Low | COULD FIX |
