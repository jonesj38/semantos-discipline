---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-14-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.663444+00:00
---

# Phase 14 Execution Prompt — PlexusAdapter + Stub (The Non-Locking Boundary)

> Paste this prompt into a fresh session to execute Phase 14.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, compiler, WASM bindings, and loom UI. Phase 9 extracted services from React, added LLM intent classification via OpenRouter, and built a flow registry/runner. Phase 9.5 added publication/visibility/governance. Phase 10 implemented the three-axis taxonomy (WHAT/HOW/WHY), reputation, and taxonomy governance. Phase 13 replaced the flat intent classifier with a hierarchical intent taxonomy.

Your task is Phase 14: define the `PlexusAdapter` interface, implement the `StubPlexusAdapter` (in-memory, deterministic, no wallet), create a `PlexusService` (renderer-agnostic), and wire it into `IdentityStore` and `LoomStore`. After this phase, every identity operation and object creation flows through the adapter. The stub means we can develop the entire loom without a running Plexus instance.

### The Boundary Rule

The loom NEVER imports `@plexus/*` packages directly. It imports a `PlexusAdapter` interface. In production (Phase 15), this is backed by the real Plexus SDK. In dev/test, it is backed by the stub. No Plexus-internal types cross the adapter boundary. Everything is expressed in loom-native types (string keys, hex hashes, capability numbers). The adapter translates.

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRDs — your requirements):
- `docs/prd/PHASE-14-PLEXUS-ADAPTER.md` — Phase 14 spec with deliverables D14.1–D14.5, TDD gate T1–T20, completion criteria
- `docs/prd/PLEXUS-INTEGRATION-MAP.md` — Architecture reference: adapter interface, component mappings, domain flags, anti-lock checklist, grafting plan

**Read second** (the services you are integrating with — understand them completely):
- `packages/loom/src/services/IdentityStore.ts` — Identity and facet state. You are wiring this to PlexusService.
- `packages/loom/src/services/LoomStore.ts` — Object creation. You are stamping certId onto ownerId.
- `packages/loom/src/services/ConfigStore.ts` — Config loading pattern. Your PlexusService follows this pattern.
- `packages/loom/src/services/SettingsStore.ts` — Settings pattern reference.

**Read third** (the types your adapter must be compatible with):
- `packages/loom/src/types/workbench.ts` — `LoomObject`, cell header, `ownerId` field
- `packages/loom/src/config/extensionConfig.ts` — `ExtensionConfig`, `ObjectTypeDefinition`

**Read fourth** (the extension configs — your test data):
- `configs/extensions/trades-services.json` — OddJobTodd: 7 object types, taxonomy, flows
- `configs/extensions/core.json` — Base types + governance flows (Dispute, Ballot, Stake, Resolution)

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-14-plexus-adapter`. Commits as `phase-14/D14.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–13. Plus:

### 1. NO STUBS

Every function must do real work. The StubPlexusAdapter is an in-memory implementation — it is NOT a mock. Every method must compute deterministic results. If a function body is `throw new Error("not implemented")` or `return undefined`, you have failed.

### 2. NO PLEXUS IMPORTS OUTSIDE THE ADAPTER DIRECTORY

`@plexus/*` imports may ONLY appear in files under `packages/loom/src/plexus/`. If any other workbench file imports from `@plexus/*`, you have broken the containment boundary. Gate test T16 enforces this.

### 3. NO PLEXUS TYPES IN THE ADAPTER INTERFACE

The `PlexusAdapter` interface uses ONLY primitive types: `string`, `number`, `boolean`, `Record<string, string>`. No `PlexusNode`, `PlexusCert`, `BRC52Certificate`, or any type from `@plexus/contracts` in the interface signature. Gate test T17 enforces this.

### 4. NO MOCKS IN PRODUCTION PATHS

Test files may use fixtures. Source files may not contain mock data or hardcoded responses. The stub adapter computes results deterministically from inputs (sha256-based), not from canned data.

### 5. NO EASY TESTS

Tests must use real extension configs and verify real behavior. Tests that check `expect(result).toBeDefined()` are worthless. Delete them and write real tests.

### 6. NO TESTS THAT MATCH BROKEN CODE

If your code produces the wrong output, FIX THE CODE. Do not change the test expectation.

### 7. RENDERER AGNOSTICISM IS NOT OPTIONAL

`PlexusService.ts`, `types.ts`, `stub.ts` are plain TypeScript in `src/plexus/`. They never import from React.

### 8. THE STUB IS NEVER REMOVED

The stub is the test harness forever. Do not build it as a temporary thing. Build it as permanent infrastructure.

### 9. MONOTONIC CHILD INDEX

Plexus enforces that `child_index` only ever increments, even if a child is deleted. The stub must enforce this. If a facet is revoked, its index slot is permanently consumed.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

```bash
# Services exist
ls packages/loom/src/services/IdentityStore.ts
ls packages/loom/src/services/LoomStore.ts
ls packages/loom/src/services/ConfigStore.ts
ls packages/loom/src/services/SettingsStore.ts
ls packages/loom/src/services/FlowRunner.ts
ls packages/loom/src/services/FlowRegistry.ts
ls packages/loom/src/services/IntentClassifier.ts

# Types exist
ls packages/loom/src/types/workbench.ts
ls packages/loom/src/config/extensionConfig.ts

# Extension configs exist
ls configs/extensions/trades-services.json
ls configs/extensions/core.json
```

All files must exist and not be stubbed. If anything is missing, STOP.

### 0.4 Create Phase 14 branch

```bash
git checkout -b phase-14-plexus-adapter
```

---

## Step 1: PlexusAdapter Interface (D14.1)

Create `packages/loom/src/plexus/types.ts`.

This defines the non-locking boundary. Every method. Every JSDoc comment. Only primitive types in the signature.

Include:

- `PlexusAdapter` interface — full interface as specified in the PRD (Identity, Graph, Capabilities, Key Derivation, Recovery, Transport sections)
- `PlexusMode` type: `'stub' | 'local' | 'cloud'`
- `PlexusConfig` interface: `{ mode: PlexusMode; endpoint?: string; debugLogging?: boolean }`
- `PlexusError` interface: `{ code: string; message: string; recoverable: boolean }`

Also create `packages/loom/src/plexus/index.ts` — barrel export for the adapter directory.

Verify: no `@plexus/*` imports in this file. The interface is pure loom types.

Commit: `phase-14/D14.1: PlexusAdapter interface — non-locking boundary with primitive-only types`

---

## Step 2: StubPlexusAdapter (D14.2)

Create `packages/loom/src/plexus/stub.ts`.

This is the in-memory implementation. It is NOT a mock. Every method computes deterministic results.

Implementation requirements:

- **Identity**: `registerIdentity(email)` → deterministic `certId = sha256("stub:" + email + ":" + seed)`, `publicKey = sha256("pubkey:" + certId)`
- **Derivation**: `deriveChild(parentCertId, resourceId, domainFlag)` → enforces monotonic childIndex (never reuses), `derivationPath = "m/" + domainFlag + "'/" + childIndex + "'"`, `certId = sha256(parentCertId + ":" + resourceId + ":" + domainFlag + ":" + childIndex)`
- **Resolution**: `resolveIdentity(certId)` → returns node state from in-memory map, throws `PlexusError` if not found
- **Edges**: `createEdge(params)` → deterministic `edgeId = sha256(source + ":" + target + ":" + edgeType)`, `sharedSecret = sha256("secret:" + edgeId)`
- **Subtree**: `querySubtree(certId, depth)` → walks in-memory tree, returns flat array of descendants up to depth
- **Capabilities**: `presentCapability(certId, flag)` → always returns `{ valid: true }` in stub mode (capabilities not enforced until Phase 16)
- **Minting**: `mintCapability(targetCertId, flag, ttl)` → returns deterministic `utxoRef`
- **Recovery**: `initiateRecovery(email)` → returns `{ sessionId, challengeCount: 3 }` from in-memory state
- **Challenge**: `submitChallengeAnswers(sessionId, answers)` → verifies against stored hashes, returns `{ verified: true/false, exportPayload }`
- **Transport**: `sendAuthenticated(endpoint, payload)` → logs if `debugLogging`, returns `payload` echo
- **Shared secrets**: `deriveSharedSecret(local, remote, context)` → `sha256(local + ":" + remote + ":" + context)`
- **Domain keys**: `deriveDomainKey(certId, domainFlag, rotationIndex)` → deterministic derivation

Use a simple `sha256` utility (Node's `crypto.createHash('sha256')` or a pure-TS implementation). Do NOT import `@plexus/*` for hashing.

Commit: `phase-14/D14.2: StubPlexusAdapter — in-memory DAG, deterministic keys, full interface compliance`

---

## Step 3: PlexusService (D14.3)

Create `packages/loom/src/plexus/PlexusService.ts`.

Renderer-agnostic service following the Phase 9 pattern (same as LoomStore, ConfigStore, etc.):

- Constructor takes `PlexusConfig`, instantiates the appropriate adapter (stub for now)
- Public API mirrors the adapter methods but adds state management
- Maintains `PlexusState`: `{ initialized: boolean; rootCertId: string | null; mode: PlexusMode }`
- `subscribe(listener)` / `getSnapshot()` for `useSyncExternalStore` compatibility
- State-changing operations (register, derive, createEdge) notify all subscribers after completion
- Error handling: catches adapter errors, wraps in `PlexusError`, emits to subscribers

Commit: `phase-14/D14.3: PlexusService — renderer-agnostic wrapper with useSyncExternalStore state`

---

## Step 4: IdentityStore Integration (D14.4)

Modify `packages/loom/src/services/IdentityStore.ts`.

Wire identity operations to delegate to PlexusService:

- `IdentityStore` receives `PlexusService` (injected or imported singleton)
- `createIdentity()` → calls `plexusService.registerIdentity()`, stores returned `certId` as root identity
- Facet creation → calls `plexusService.deriveChild()` with the appropriate domain flag, stores returned `certId` on the facet
- Identity resolution → calls `plexusService.resolveIdentity()` for cert state queries

The existing `IdentityStore` public API does NOT change. Callers are unaffected. Only internal implementation delegates to PlexusService.

Do NOT break any existing IdentityStore tests or behavior.

Commit: `phase-14/D14.4: IdentityStore delegates cert operations to PlexusService`

---

## Step 5: Object Creation Integration (D14.5)

Modify `packages/loom/src/services/LoomStore.ts`.

Wire `createObject()`:

- Before creating the object, call `plexusService.deriveChild()` to get a certId for this object
- Stamp `certId` as the `ownerId` field on the cell header
- The `resourceId` passed to `deriveChild()` should be the object's type path (e.g., `"trades.job"`)
- The `domainFlag` should be the client-defined CREATE flag (0x00010002)

Do NOT break any existing LoomStore tests or behavior.

Commit: `phase-14/D14.5: LoomStore.createObject() stamps Plexus-derived certId as ownerId`

---

## Step 6: Gate Tests

Create `packages/__tests__/phase14-gate.test.ts`.

### Unit Tests (T1–T10)

```typescript
describe("StubPlexusAdapter", () => {
  // T1: registerIdentity returns deterministic certId + publicKey
  // T2: deriveChild produces correct derivation path at 3 levels deep
  // T3: deriveChild enforces monotonic childIndex (delete child, derive new → index increments)
  // T4: createEdge returns edgeId + sharedSecret hash
  // T5: querySubtree returns correct tree at depth 1, 2, 3
  // T6: presentCapability returns { valid: true } for all capabilities
  // T7: initiateRecovery returns sessionId + challengeCount
  // T8: submitChallengeAnswers with correct answers returns { verified: true }
  // T9: PlexusService constructor with mode 'stub' creates working service
  // T10: PlexusService.subscribe notifies after state changes
});
```

### Integration Tests (T11–T15)

```typescript
describe("PlexusService integration", () => {
  // T11: IdentityStore.createIdentity delegates to PlexusService, stamps certId
  // T12: IdentityStore.createFacet calls deriveChild with correct domain flag
  // T13: LoomStore.createObject stamps certId as ownerId
  // T14: 3 facets under one identity → 3 distinct certIds with sequential childIndex
  // T15: querySubtree on root returns all derived facets
});
```

### Anti-Lock Tests (T16–T20)

```typescript
describe("Anti-lock boundary", () => {
  // T16: No @plexus imports outside packages/loom/src/plexus/
  //   → Use fs.readFileSync + regex scan of all .ts files
  // T17: PlexusAdapter interface contains only primitive types
  //   → Parse types.ts, verify no @plexus type references
  // T18: Adapter swap test — create service with stub, perform operations, create new service with fresh stub, same operations produce same results
  // T19: Unknown parentCertId throws PlexusError with recoverable: true
  // T20: No Plexus error types outside packages/loom/src/plexus/
  //   → Scan all .ts files for PlexusCert, PlexusNode, BRC52Certificate
});
```

Commit: `phase-14/T1-T20: full gate test suite — unit, integration, anti-lock`

---

## Step 7: CI Gate Extension

Verify the existing `.github/workflows/gate.yml` will pick up `packages/__tests__/phase14-gate.test.ts` automatically (it runs `bun test packages/__tests__/`).

Add a lint check specific to Phase 14:

```bash
# No @plexus imports outside adapter directory
if grep -rn "@plexus" packages/loom/src/ --include="*.ts" --include="*.tsx" | grep -v "/plexus/" | grep -v "node_modules"; then
  echo "FAIL: @plexus imports found outside adapter directory"
  exit 1
fi
```

This can be added to the lint job or as a separate step.

Commit: `phase-14/CI: anti-lock lint check for @plexus containment`

---

## Step 8: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new and modified file
2. Check for mutations not caught by tests
3. Check that `resolveIdentity()` on a revoked node returns `isRevoked: true`
4. Check that monotonic childIndex survives service restart (re-instantiation)
5. Check that `PlexusService.subscribe()` properly cleans up listeners on unsubscribe
6. Check that no `any` casts mask type errors at the adapter boundary
7. Check that `sendAuthenticated()` logging doesn't leak sensitive data
8. Write errata doc as `docs/prd/PHASE-14-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/loom/src/plexus/types.ts` exists with full `PlexusAdapter` interface (no stubs)
- [ ] `packages/loom/src/plexus/stub.ts` exists with full `StubPlexusAdapter` (every method implemented)
- [ ] `packages/loom/src/plexus/PlexusService.ts` exists with `useSyncExternalStore`-compatible state
- [ ] `packages/loom/src/plexus/index.ts` barrel export exists
- [ ] `IdentityStore` delegates cert operations to `PlexusService` (no hardcoded IDs)
- [ ] `LoomStore.createObject()` stamps `certId` as `ownerId`
- [ ] Tests T1–T20 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@plexus/*` imports outside `packages/loom/src/plexus/`
- [ ] Errata sprint complete with `docs/prd/PHASE-14-ERRATA.md`
- [ ] All commits follow `phase-14/D14.N:` naming convention
- [ ] Branch is `phase-14-plexus-adapter`

---

## Next Phase

Phase 15 replaces the stub with the real Plexus Vendor SDK. The adapter interface does not change. The loom does not change. Only the implementation behind the interface changes. That is the point.
