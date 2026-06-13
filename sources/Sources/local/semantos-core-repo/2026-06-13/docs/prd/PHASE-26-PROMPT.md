---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.680219+00:00
---

# Phase 26 Execution Prompt — Game Engine SemanticObject SDK

> Paste this prompt into a fresh session to execute Phase 26.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phases 0–7 built a 28KB Zig/WASM cell engine with linearity enforcement, dual-stack 2-PDA, and SPV verification. Phase 7 delivered Bun/Node/browser WASM loaders. Phase 12 bridged the implementation with fuzzing and differential testing. Phase 17 built the transfer protocol for LINEAR objects. Phase 21 built the Lisp policy compiler that transforms s-expressions into capability cell scripts. Phase 25.5 added `OP_CALLHOST` (0xD0) — a generic host function dispatch opcode — and the `HostFunctionRegistry` that lets domain packages register named predicates without modifying the cell engine.

This phase wraps the cell engine in a **Game Engine SDK** — a platform-agnostic TypeScript core that maps game concepts (entities, inventories, trades, state machines) onto cell engine primitives. The SDK is consumed by game engines (Godot, Unity) through engine-specific bindings. Underneath, every game object is a cell. Every inventory operation is an opcode sequence. Every trade is a capability-gated transfer.

The key insight: the four linearity modes map directly to game object semantics:

- **LINEAR**: unique items (legendary sword — one instance, no duplication, must transfer or destroy)
- **AFFINE**: consumables (health potion — use once, then it's gone)
- **RELEVANT**: quest markers (must keep, can inspect, cannot discard)
- **FUNGIBLE**: currency/ammo (freely copy, split, merge)

This is the most accessible demonstration of the Semantos thesis. If a 12-year-old understands that a LINEAR sword can't be copied, the concept is accessible.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-26-GAME-ENGINE-SDK.md` — Full spec with D26.1–D26.5, gate tests, completion criteria

**Read second** (the cell engine you are wrapping):
- `packages/cell-engine/src/wasm-loader-bun.ts` — Bun WASM loader pattern
- `packages/cell-engine/src/wasm-loader-node.ts` — Node WASM loader pattern
- `packages/cell-engine/src/wasm-loader-browser.ts` — Browser WASM loader pattern
- `packages/protocol-types/src/index.ts` — Cell header types, linearity modes, opcodes
- `packages/constants/constants.json` — Magic bytes, offsets, version constants

**Read third** (the host function dispatch system — Phase 25.5):
- `packages/cell-engine/bindings/host-function-registry.ts` — `HostFunctionRegistry` class (register, setContext, call)
- `packages/cell-engine/bindings/builtin-host-functions.ts` — Built-in generics (field-eq?, field-gt?, etc.)
- The `(predicate?)` sugar in the Lisp compiler — how zero-arity predicates compile to `push "name" OP_CALLHOST`

**Read fourth** (the transfer and capability systems you consume):
- `src/kernel/transfer.ts` — Ownership transfer protocol (the pattern game trades follow)
- `src/types/capability.ts` — Capability token structure
- `packages/shell/src/lisp/compiler.ts` — LispCompiler class
- `packages/shell/src/lisp/packer.ts` — Capability cell packing

**Read fourth** (existing patterns for wrapping the cell engine):
- `packages/cell-ops/` — Cell packing/unpacking operations (study how it wraps the engine)
- `packages/loom/src/services/LoomStore.ts` — How the loom creates objects (same pattern)

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26-game-engine-sdk`. Commits as `phase-26/D26.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. THE CELL ENGINE IS THE RUNTIME

Every game operation goes through the WASM binary. No shadow state in TypeScript. If an entity exists, it exists as a cell. If it's in an inventory, it's a cell reference. There is no parallel data structure that "represents" a game object separate from its cell.

### 2. LINEARITY IS ENFORCED BY THE ENGINE, NOT BY YOUR CODE

You do NOT write `if (entity.linearity === 'LINEAR') throw new Error('cannot duplicate')`. The cell engine's 2-PDA rejects DUP on LINEAR cells at the opcode level. Your SDK surfaces the error. It does not implement the check.

### 3. NO GAME ENGINE DEPENDENCIES

The TypeScript core has ZERO dependencies on Godot, Unity, or any game engine. It is a pure wrapper over the WASM cell engine. The engine-specific bindings (D26.3, D26.4) are thin adapter layers on top of the core.

### 4. TRADES ARE ATOMIC

A trade is not "remove from inventory A, add to inventory B." A trade is an atomic transfer at the cell level (Phase 17 protocol). Both sides succeed or neither does. No intermediate state where an item is in neither inventory.

### 5. POLICIES ARE COMPILED, NOT INTERPRETED

Game rules authored in Lisp (D26.5) compile to capability cells via the Phase 21 compiler. Game-domain predicates (`diagonal-path?`, `path-clear?`, etc.) use the `(predicate?)` sugar from Phase 25.5, which compiles to `push "name" OP_CALLHOST`. At runtime, the cell engine dispatches to the registered host function. The SDK does NOT interpret Lisp at runtime.

### 5.5. HOST FUNCTIONS ARE REGISTERED, NOT HARDCODED

Game-domain predicates (board queries, piece queries) are registered via `HostFunctionRegistry.register()` from Phase 25.5. The SDK does NOT add opcodes to the cell engine. It does NOT modify the Lisp compiler. It registers named functions that OP_CALLHOST dispatches at evaluation time.

### 6. SERIALIZATION IS BYTE-IDENTICAL TO THE CELL ENGINE

`GameEntity.serialize()` produces the same bytes the Zig cell engine produces. Not "compatible." Identical. Test this with cross-language round-trip assertions.

### 7. ENGINE BINDINGS ARE SCAFFOLDS

D26.3 (Godot) and D26.4 (Unity) are interface definitions and thin wrappers. They are NOT complete engine integrations. They demonstrate the pattern. Full integration requires engine-specific testing that is out of scope.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites

```bash
# Phase 7 bindings exist
ls packages/cell-engine/src/wasm-loader-bun.ts
ls packages/cell-engine/src/wasm-loader-node.ts
ls packages/cell-engine/src/wasm-loader-browser.ts

# WASM binary exists
ls packages/cell-engine/zig-out/semantos.wasm

# Protocol types exist
ls packages/protocol-types/src/index.ts

# Constants exist
ls packages/constants/constants.json

# Phase 25.5 host function dispatch exists
ls packages/cell-engine/bindings/host-function-registry.ts
ls packages/cell-engine/bindings/builtin-host-functions.ts
bun test packages/__tests__/phase25.5-gate.test.ts

# Phase 21 Lisp compiler exists (with OP_CALLHOST from Phase 25.5)
ls packages/shell/src/lisp/compiler.ts
ls packages/shell/src/lisp/packer.ts

# Transfer protocol exists
ls src/kernel/transfer.ts

# Existing tests pass
bun run check
bun run build
```

All must exist and pass. If anything fails, STOP.

### 0.3 Create Phase 26 branch

```bash
git checkout -b phase-26-game-engine-sdk
```

---

## Step 1: Game Object Types (D26.1)

Create `packages/game-sdk/src/types.ts`.

**Requirements**:

Define the core type mappings between game concepts and cell engine primitives:

- `GameEntity` — wraps a cell with game-domain metadata (entityType, ownerId, metadata, scriptBytes). The cell IS the entity.
- `Inventory` — typed collection of cell references with linearity-enforced add/remove/transfer operations.
- `TradeProposal` — two-party atomic swap specification with capability gating and expiry.
- `EntityState` — lifecycle states: UNOWNED, OWNED, EQUIPPED, TRADING, CONSUMED, DESTROYED.
- `EntityTransition` — state transition rules with optional Lisp constraint guards.

Reuse types from `packages/protocol-types/src/index.ts` for linearity modes and cell header fields. Do NOT duplicate type definitions.

Create `packages/game-sdk/package.json` with:
- name: `@semantos/game-sdk`
- dependencies: `@semantos/protocol-types`, `@semantos/constants`, `@semantos/cell-engine`
- NO React dependencies. NO game engine dependencies.

**Commit**: `phase-26/D26.1: game entity, inventory, trade, and state types`

---

## Step 2: Game Cell Engine Wrapper (D26.2)

Create `packages/game-sdk/src/engine.ts`.

**Requirements**:

- `GameCellEngine` class wrapping the WASM cell engine with game-domain methods:
  - `static async create(options?)` — loads the 28KB WASM binary, auto-detects platform (Node/Bun/browser)
  - `createEntity(params)` — creates a cell with game metadata in the payload
  - `transition(entity, to, context?)` — executes a state transition via opcode sequence
  - `executeTrade(proposal)` — atomic two-party swap using Phase 17 transfer protocol
  - `evaluatePolicy(entity, policy)` — loads compiled script bytes onto the 2-PDA and runs them
  - `serialize(entity)` — packs entity to wire format (byte-identical to cell engine format)
  - `deserialize(bytes)` — unpacks entity from wire format

- `Inventory` class implementing the add/remove/transfer operations:
  - `add()` — fails if slot occupied, no implicit overwrite
  - `remove()` — enforces linearity: LINEAR must transfer, AFFINE can destroy, RELEVANT cannot remove, FUNGIBLE free
  - `transfer()` — atomic via cell engine, both sides succeed or neither

Platform detection pattern: copy from `packages/cell-engine/src/wasm-loader-*.ts`. Use the same auto-detection logic.

**Context protocol**: When implementing `evaluatePolicy()`, wrap the execution in context management:
1. `registry.setContext({ board, from, to, piece, color, ... })` — freeze game state
2. Execute compiled script bytes on the 2-PDA
3. `registry.clearContext()` — release context

This ensures all `OP_CALLHOST` predicates (registered game host functions) can read the current game state during evaluation.

**Commit**: `phase-26/D26.2: GameCellEngine wrapper with entity CRUD, trade, policy evaluation, and inventory`

---

## Step 3: Godot GDExtension Bindings (D26.3)

Create `packages/game-sdk/src/bindings/godot/`.

**Requirements**:

Define TypeScript interfaces and scaffold classes for Godot GDExtension integration:

- `SemanticInventory` — maps to a Godot Node; manages inventory cells
- `SemanticEntity` — maps to a Godot Resource; wraps GameEntity
- `SemanticTradeUI` — maps to a Godot Control; trade interface scaffold
- `SemanticPolicyEditor` — maps to an in-editor tool; Lisp policy authoring

This is a SCAFFOLD. It defines the interface contract and demonstrates the binding pattern. It does NOT compile to a working GDExtension (that requires Godot toolchain).

Include a README in the directory explaining:
- How to build with `scons` for Godot 4.x
- How signals (`entity_created`, `trade_completed`, `policy_violated`) bridge to Godot's signal system
- How the WASM binary is loaded via GDExtension's C API

**Commit**: `phase-26/D26.3: Godot GDExtension binding scaffold with interface definitions`

---

## Step 4: Unity Native Plugin Bindings (D26.4)

Create `packages/game-sdk/src/bindings/unity/`.

**Requirements**:

Define TypeScript interfaces and scaffold classes for Unity native plugin integration:

- `SemanticInventory` — maps to a MonoBehaviour
- `SemanticEntity` — maps to a ScriptableObject
- `SemanticTradeManager` — maps to a singleton MonoBehaviour
- `SemanticPolicyAsset` — maps to a custom asset type

Same rules as D26.3: SCAFFOLD only. Define interface contract and binding pattern.

Include a README explaining:
- How to build as a Unity native plugin (P/Invoke to WASM)
- How UnityEvents bridge to the SDK's callback system
- How custom inspectors expose entity properties and policy editing

**Commit**: `phase-26/D26.4: Unity native plugin binding scaffold with interface definitions`

---

## Step 5: Policy Authoring for Game Designers (D26.5)

Create `packages/game-sdk/src/policies/`.

**Requirements**:

Build game-specific policy primitives on top of Phase 21's Lisp compiler:

- `templates/` — pre-built `.policy` files for common game patterns:
  - `legendary-drop.policy` — LINEAR items requiring boss capability to drop
  - `quest-no-trade.policy` — RELEVANT quest items cannot be traded
  - `level-gate.policy` — equipment requires minimum player level to equip
  - `durability.policy` — AFFINE items with use-count tracking
  - `trade-restriction.policy` — capability-gated trading (merchant license)

- `compiler.ts` — thin wrapper that:
  - Loads `.policy` files
  - Passes them through `LispCompiler.compilePolicy()`
  - Packs the output via `packCapabilityCell()`
  - Returns the capability cell bytes ready for the cell engine

- `primitives.ts` — game-domain constraint primitives:
  - Board/spatial queries: `square-empty?`, `path-clear?`, `adjacent?`
  - Entity queries: `has-tag?`, `rarity-eq?`, `level-gte?`
  - Inventory queries: `inventory-full?`, `inventory-contains?`
  - These compile to host function calls that the cell engine dispatches

**CRITICAL**: Each board-query primitive (`square-empty?`, `path-clear?`, `adjacent?`, etc.) is a host function registered with `HostFunctionRegistry.register('square-empty?', (ctx) => ...)`. The context object (set via `registry.setContext()` before evaluation) carries the current board state. Predicates are zero-arity — they read from the frozen context and return 0/1. Do NOT implement these as TypeScript functions that take board/position arguments. Follow the pattern in `packages/cell-engine/bindings/builtin-host-functions.ts`.

**Commit**: `phase-26/D26.5: game policy templates, compiler wrapper, and domain primitives`

---

## Step 6: Gate Tests

Create `packages/__tests__/phase26-gate.test.ts`.

### Entity Creation Tests (T1–T4)

```typescript
describe("D26.1/D26.2 — GameEntity creation", () => {
  // T1: LINEAR entity has correct cell header (magic, linearity byte, version)
  // T2: entity metadata round-trips through serialize/deserialize (byte-identical)
  // T3: entity type maps to correct taxonomy coordinate string
  // T4: cellId is deterministic from entity params (same input = same cellId)
});
```

### Linearity Enforcement Tests (T5–T10)

```typescript
describe("D26.2 — Linearity enforcement", () => {
  // T5: LINEAR entity cannot be added to two inventories simultaneously
  // T6: AFFINE entity can be destroyed but not duplicated
  // T7: RELEVANT entity cannot be removed from inventory
  // T8: FUNGIBLE entity can be freely copied and removed
  // T9: inventory.remove() on LINEAR without destination throws TransferError
  // T10: inventory.transfer() is atomic — source empties and target fills in one operation
});
```

### Trade Protocol Tests (T11–T14)

```typescript
describe("D26.2 — Trade execution", () => {
  // T11: atomic swap transfers cells between two inventories
  // T12: trade fails if offerer doesn't own offered items
  // T13: trade fails if capability requirement not met
  // T14: expired trade proposal is rejected
});
```

### Policy Compilation Tests (T15–T18)

```typescript
describe("D26.5 — Game policies", () => {
  // T15: legendary-drop.policy compiles to valid capability cell
  // T16: compiled policy evaluates correctly (boss can drop, non-boss can't)
  // T17: level-gate.policy blocks equip below required level
  // T18: policy compilation is deterministic (same input = same bytes)
});
```

### Serialization Compatibility Tests (T19–T22)

```typescript
describe("D26.2 — Cell compatibility", () => {
  // T19: GameEntity serializes to valid cell engine format (magic bytes correct)
  // T20: serialized entity loadable by Zig WASM cell engine
  // T21: cell engine output deserializes to valid GameEntity
  // T22: byte-identical output across Node/Bun/browser loaders
});
```

### Anti-Lock Tests (T23–T25)

```typescript
describe("D26 — Anti-lock", () => {
  // T23: no React imports in game-sdk package (grep confirms)
  // T24: no game engine imports in core package (grep confirms)
  // T25: package.json has no Godot or Unity dependencies
});
```

**Commit**: `phase-26/T1-T25: full gate test suite — entities, linearity, trades, policies, compatibility, anti-lock`

---

## Step 7: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Adversarial review: does `GameEntity` always resolve to a real cell, or can orphaned entities exist?
2. Adversarial review: is `executeTrade()` truly atomic? Can a crash leave items in neither inventory?
3. Check that `serialize()` output is byte-identical to `packages/cell-ops/` output for the same cell
4. Check that `evaluatePolicy()` handles malformed script bytes gracefully (doesn't crash the WASM)
5. Check that WASM loader auto-detection works in all three environments
6. Check that Godot/Unity scaffolds don't import the core incorrectly
7. Check that policy templates all compile without errors
8. Check that `inventory.add()` rejects cells with mismatched entityType
9. Measure entity creation throughput — 1000 entities should create in <1 second
10. Write errata doc as `docs/prd/PHASE-26-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/game-sdk/` exists with `types.ts`, `engine.ts`, `policies/`
- [ ] `packages/game-sdk/package.json` has correct dependencies and NO React/engine deps
- [ ] `GameCellEngine.create()` loads the 28KB WASM binary on Node, Bun, and browser
- [ ] `createEntity()` produces cells with correct magic, linearity, and metadata
- [ ] LINEAR/AFFINE/RELEVANT/FUNGIBLE enforcement works at the inventory level
- [ ] `executeTrade()` is atomic — verified by concurrent access test
- [ ] `evaluatePolicy()` runs compiled Lisp policies through the cell engine
- [ ] `serialize()/deserialize()` produces byte-identical output to cell engine native format
- [ ] Godot binding scaffold exists in `packages/game-sdk/src/bindings/godot/`
- [ ] Unity binding scaffold exists in `packages/game-sdk/src/bindings/unity/`
- [ ] Policy templates compile and evaluate correctly
- [ ] Tests T1–T25 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in game-sdk package
- [ ] Errata sprint complete with `docs/prd/PHASE-26-ERRATA.md`
- [ ] All commits follow `phase-26/D26.N:` naming convention
- [ ] Branch is `phase-26-game-engine-sdk`

---

## What NOT to Do

1. Do NOT build a game engine — this is an SDK that existing engines consume
2. Do NOT implement networking or multiplayer — local state only
3. Do NOT implement rendering — the SDK manages semantic state, not pixels
4. Do NOT bypass the cell engine — every operation goes through WASM
5. Do NOT hardcode game-specific logic — the SDK is domain-agnostic
6. Do NOT implement a marketplace — Phase 18 metering exists but integration is separate
7. Do NOT modify the cell engine or Lisp compiler — register host functions via Phase 25.5 HostFunctionRegistry
8. Do NOT implement AI/NPC behavior — out of scope

---

## After Phase 26: The SDK Is the Bridge

After Phase 26, game developers have a TypeScript SDK that turns any game engine into a linearity-enforced semantic runtime. The same cell engine that enforces financial trade ownership, governance ballot voting, and SCADA command authorization now enforces game item uniqueness.

Phase 27 proves it works by building chess, Go, and a card game on top of this SDK. Every piece, every stone, every card is a cell. Every rule is a compiled policy. Every game is a demonstration that semantic objects are universal — not domain-specific.
