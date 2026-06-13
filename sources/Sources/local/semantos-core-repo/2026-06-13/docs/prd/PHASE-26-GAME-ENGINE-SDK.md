---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26-GAME-ENGINE-SDK.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.701723+00:00
---

# Phase 26 — Game Engine SemanticObject SDK

**Version**: 1.0
**Date**: March 2026
**Status**: Exploratory — not sequenced after Phase 25
**Duration**: 6 weeks (with 40% buffer: 8.4 weeks)
**Prerequisites**: Phase 25.5 complete (OP_CALLHOST + HostFunctionRegistry). Phase 7 complete (Bun/Node/browser WASM bindings). Phase 12 recommended (implementation bridge for cross-language fuzz testing). Phase 21 complete (Lisp policy compiler for game rule authoring).
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + `COMMERCIAL-CONTEXT.md`
**Branch**: `phase-26-game-engine-sdk`

---

## Context

The cell engine is a general-purpose runtime for linearity-enforced semantic objects. Everything it knows about — ownership transfer, capability gating, type enforcement, SPV verification — applies directly to game state. A LINEAR sword cannot be duplicated. An AFFINE health potion can be used once then destroyed. A RELEVANT quest flag must be checked but can't be discarded. These aren't metaphors. They are the same opcodes.

This phase builds a **SemanticObject SDK** that game engines consume. The SDK wraps the Zig/WASM cell engine (28KB binary) in an API surface that game developers understand: inventories, entities, ownership graphs, state machines. Underneath, every game object is a cell. Every inventory operation is an opcode sequence. Every trade is a capability-gated transfer.

The target engines are **Godot** (GDScript/C# via GDExtension) and **Unity** (C# via native plugin). Both can load WASM modules. The SDK provides:

1. A **platform-agnostic TypeScript core** that wraps the cell engine
2. **Engine-specific bindings** that expose the core through each engine's plugin API
3. A **Lisp policy surface** for game designers to author rules without touching code

### Why This Matters

Game engines are the world's most sophisticated state machines. But their object models are ad hoc — an inventory is a list, ownership is a foreign key, duplication is a bug you patch with if-statements. The cell engine makes these constraints **structural**. LINEAR isn't a rule you remember to check. It's a property the runtime enforces at the opcode level before your game code runs.

This is also the most intuitive demonstration of the Semantos thesis: that semantic objects with formal ownership properties are useful outside finance and governance. If a 12-year-old can understand that a LINEAR sword can't be copied, the concept is accessible.

### The Compression Gradient (Game Domain)

```
Game designer: "legendary items can't be duplicated and only drop from bosses"
    ↓ (policy authoring)
(policy :subject boss-entity
        :action drop-item
        :constraint (and (= rarity "legendary") (has-capability 9))
        :linearity LINEAR)
    ↓ (Lisp compiler, Phase 21)
"legendary" "rarity-eq?" OP_CALLHOST 9 OP_CHECKCAPABILITY BOOLAND VERIFY
    ↓ (cell packing)
CAPABILITY cell → LINEAR item cell with boss-only drop script
    ↓ (runtime)
Cell engine enforces: item cannot be DUP'd, DROP requires consume opcode
```

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `WASM:BINARY` | `packages/cell-engine/zig-out/semantos.wasm` | 28KB WASM binary — the runtime you're wrapping |
| `BIND:BUN` | `packages/cell-engine/src/wasm-loader-bun.ts` | Bun WASM loader — pattern for host function injection |
| `BIND:NODE` | `packages/cell-engine/src/wasm-loader-node.ts` | Node WASM loader — pattern for fs-backed loading |
| `BIND:BROWSER` | `packages/cell-engine/src/wasm-loader-browser.ts` | Browser WASM loader — pattern for fetch-based loading |
| `TYPES:PROTO` | `packages/protocol-types/src/index.ts` | Cell header types, linearity modes, opcodes |
| `CONST:ALL` | `packages/constants/constants.json` | Magic bytes, offsets, version constants |
| `LISP:COMPILER` | `packages/shell/src/lisp/compiler.ts` | LispCompiler — how policies compile to Forth/bytes |
| `LISP:PACKER` | `packages/shell/src/lisp/packer.ts` | Capability cell packing — output format for game rules |
| `TRANSFER:CORE` | `src/kernel/transfer.ts` | Ownership transfer protocol — the pattern game trades follow |
| `CAPABILITY:TYPES` | `src/types/capability.ts` | Capability token structure — gating model for game actions |
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | HostFunctionRegistry class — how game predicates are registered for OP_CALLHOST dispatch |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation — the opcode handler game predicates dispatch through |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering domain predicates |

---

## Deliverables

### D26.1 — Game Object Types

**File**: `packages/game-sdk/src/types.ts`

Type definitions mapping game concepts to cell engine primitives:

```typescript
/** A game entity backed by a semantic cell */
interface GameEntity {
  cellId: string;                          // cell address (BCA-derived)
  entityType: string;                      // "weapon", "potion", "quest-flag", etc.
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
  ownerId: string;                         // identity facet of owning player
  metadata: Record<string, unknown>;       // game-specific payload
  scriptBytes?: Uint8Array;                // compiled behavior (from Lisp policies)
}

/** Inventory is a typed collection of cells with linearity enforcement */
interface Inventory {
  ownerId: string;
  slots: Map<string, GameEntity>;          // slotId → entity
  capacity: number;                        // max slots (octave-dependent)

  /** Add entity — fails if slot occupied (no implicit overwrite) */
  add(entity: GameEntity): Result<void, InventoryError>;

  /** Remove entity — enforces linearity:
   *  LINEAR: must transfer to another inventory (consume + create)
   *  AFFINE: can destroy (consume without create)
   *  RELEVANT: cannot remove (must keep)
   *  FUNGIBLE: free removal */
  remove(slotId: string, destination?: Inventory): Result<GameEntity, InventoryError>;

  /** Transfer between inventories — atomic via cell engine */
  transfer(slotId: string, target: Inventory): Result<void, TransferError>;
}

/** Trade is a two-party atomic swap of cells */
interface TradeProposal {
  offerer: string;                         // identity
  receiver: string;                        // identity
  offered: GameEntity[];                   // cells being offered
  requested: GameEntity[];                 // cells being requested
  expiresAt?: string;                      // ISO timestamp
  capabilityRequired?: number;             // capability gate (e.g., merchant license)
}

/** State machine for entity lifecycle */
type EntityState = 'UNOWNED' | 'OWNED' | 'EQUIPPED' | 'TRADING' | 'CONSUMED' | 'DESTROYED';

interface EntityTransition {
  from: EntityState;
  to: EntityState;
  requires?: ConstraintExpr;               // Lisp constraint (reuses Phase 21 types)
  consumesLinearity: boolean;              // true if this transition uses the entity's linear use
}
```

**Critical constraints**:
- GameEntity is a **view** over a cell, not a separate data structure. The cell IS the entity.
- Inventory operations compile to opcode sequences, not method calls with side effects.
- Trade is atomic: both sides succeed or neither does. No partial trades.
- EntityState transitions are validated against linearity before execution.

---

### D26.2 — Game Cell Engine Wrapper

**File**: `packages/game-sdk/src/engine.ts`

Thin wrapper over the WASM cell engine with game-domain vocabulary:

```typescript
class GameCellEngine {
  private wasm: WebAssembly.Instance;

  /** Load the 28KB WASM binary (platform-detected loader) */
  static async create(options?: { wasmPath?: string }): Promise<GameCellEngine>;

  /** Create a new game entity as a cell */
  createEntity(params: {
    entityType: string;
    linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
    owner: string;
    metadata: Record<string, unknown>;
    script?: Uint8Array;
  }): GameEntity;

  /** Execute a state transition on an entity */
  transition(entity: GameEntity, to: EntityState, context?: TransitionContext): Result<GameEntity, TransitionError>;

  /** Execute an atomic trade between two players */
  executeTrade(proposal: TradeProposal): Result<TradeReceipt, TradeError>;

  /** Evaluate a Lisp policy against an entity */
  evaluatePolicy(entity: GameEntity, policy: Uint8Array): boolean;

  /** Pack entity to wire format (for networking / persistence) */
  serialize(entity: GameEntity): Uint8Array;

  /** Unpack entity from wire format */
  deserialize(bytes: Uint8Array): GameEntity;
}
```

- `createEntity()` calls through to cell packing (Phase 1 format: magic + header + payload)
- `transition()` executes opcodes on the 2-PDA (Phase 3 engine)
- `executeTrade()` uses the transfer protocol (Phase 17 chain-of-custody)
- `evaluatePolicy()` loads compiled script bytes onto the 2-PDA and runs them
- Serialization is byte-identical to the cell engine's native format

**Context protocol**: `evaluatePolicy()` MUST call `registry.setContext(gameState)` before executing compiled scripts on the 2-PDA, and `registry.clearContext()` after evaluation completes. The context carries all state that host function predicates need: board layout, piece data, move parameters, active player. Without this, OP_CALLHOST predicates will fail to read game state.

---

### D26.3 — Godot GDExtension Bindings

**File**: `packages/game-sdk/src/bindings/godot/`

GDExtension bindings that expose the SDK as Godot nodes:

- `SemanticInventory` — Node that manages a player's inventory cells
- `SemanticEntity` — Resource that wraps a GameEntity
- `SemanticTradeUI` — Control node for trade interfaces
- `SemanticPolicyEditor` — In-editor Lisp policy authoring

**Implementation strategy**:
- Godot 4.x loads WASM via GDExtension's C API
- The TypeScript core compiles to a single WASM module (via wasm-pack or similar)
- GDScript wrapper classes call into the WASM module via `call_native()`
- Signals (`entity_created`, `trade_completed`, `policy_violated`) bridge to Godot's signal system

---

### D26.4 — Unity Native Plugin Bindings

**File**: `packages/game-sdk/src/bindings/unity/`

Unity plugin that exposes the SDK as MonoBehaviour components:

- `SemanticInventory` — MonoBehaviour for inventory management
- `SemanticEntity` — ScriptableObject wrapping a GameEntity
- `SemanticTradeManager` — Singleton for trade coordination
- `SemanticPolicyAsset` — Custom asset type for Lisp policies

**Implementation strategy**:
- Unity loads the WASM binary via its native plugin interface
- C# wrapper classes use P/Invoke to call into the WASM module
- UnityEvents (`OnEntityCreated`, `OnTradeCompleted`, `OnPolicyViolated`) bridge to Unity's event system
- Editor integration: custom inspectors for entity properties and policy editing

---

### D26.5 — Policy Authoring for Game Designers

**File**: `packages/game-sdk/src/policies/`

Game-specific policy primitives built on Phase 21's Lisp compiler:

```lisp
;; Item rarity gate — legendary items require boss capability
(define-policy legendary-drop
  :subject boss-entity
  :action drop-item
  :constraint (and
    (= rarity "legendary")
    (has-capability 9))        ;; capability 9 = "boss loot table"
  :linearity LINEAR)

;; Trade restriction — no trading quest items
(define-policy quest-no-trade
  :subject any
  :action trade
  :constraint (not (= category "quest"))
  :linearity RELEVANT)         ;; RELEVANT = must keep, can inspect

;; Level gate — equipment requires minimum level
(define-policy level-gate
  :subject player
  :action equip
  :constraint (>= player-level required-level)
  :linearity AFFINE)           ;; AFFINE = can use once then destroy
```

- Pre-built policy templates for common game patterns
- Each template compiles to a capability cell via the existing Lisp compiler
- Game designers edit `.policy` files; the SDK compiles them at build time or runtime

**Host function registration**: Each game-domain primitive (`square-empty?`, `path-clear?`, `adjacent?`, etc.) MUST be registered with `HostFunctionRegistry.register()` during SDK initialization. The evaluation context (frozen via `setContext()`) carries the current game state — board layout, active piece, source/target squares. Predicates read from this context and return 0 (false) or 1 (true). They do NOT take arguments from the stack. See Phase 25.5 (`PHASE-25.5-HOST-FUNCTION-DISPATCH.md`) for the registration pattern.

---

## TDD Gate — Tests That Must Pass

### Test 1: Entity Creation (TypeScript)

```typescript
describe("D26.1 — GameEntity creation", () => {
  test("LINEAR entity has correct cell header", () => {});
  test("entity metadata round-trips through serialize/deserialize", () => {});
  test("entity type maps to taxonomy coordinate", () => {});
  test("cellId is deterministic from entity params", () => {});
});
```

### Test 2: Linearity Enforcement (TypeScript)

```typescript
describe("D26.2 — Linearity enforcement", () => {
  test("LINEAR entity cannot be added to two inventories", () => {});
  test("AFFINE entity can be destroyed but not duplicated", () => {});
  test("RELEVANT entity cannot be removed from inventory", () => {});
  test("FUNGIBLE entity can be freely copied and removed", () => {});
  test("inventory.remove() on LINEAR without destination throws", () => {});
  test("inventory.transfer() is atomic — both sides or neither", () => {});
});
```

### Test 3: Trade Protocol (TypeScript)

```typescript
describe("D26.2 — Trade execution", () => {
  test("atomic swap transfers cells between two inventories", () => {});
  test("trade fails if offerer doesn't own offered items", () => {});
  test("trade fails if capability requirement not met", () => {});
  test("expired trade proposal is rejected", () => {});
  test("LINEAR items appear in receiver inventory after trade", () => {});
  test("LINEAR items absent from offerer inventory after trade", () => {});
});
```

### Test 4: Policy Evaluation (TypeScript)

```typescript
describe("D26.5 — Game policies", () => {
  test("legendary-drop policy allows boss to drop legendary item", () => {});
  test("legendary-drop policy blocks non-boss from dropping legendary", () => {});
  test("quest-no-trade policy blocks trade of quest items", () => {});
  test("level-gate policy blocks equip below required level", () => {});
  test("policy compilation is deterministic", () => {});
});
```

### Test 5: Serialization Compatibility (Cross-language)

```typescript
describe("D26.2 — Cell compatibility", () => {
  test("GameEntity serializes to valid cell engine format", () => {});
  test("serialized entity loadable by Zig WASM cell engine", () => {});
  test("cell engine output deserializes to valid GameEntity", () => {});
  test("byte-identical output across Node/Bun/browser loaders", () => {});
});
```

---

## Phase Completion Criteria

You are **done with Phase 26** when ALL of the following are true:

1. `packages/game-sdk/` exists with `types.ts`, `engine.ts`, `policies/`
2. `GameCellEngine.create()` loads the 28KB WASM binary on Node, Bun, and browser
3. LINEAR/AFFINE/RELEVANT/FUNGIBLE enforcement works at the inventory level
4. Atomic trade produces correct cell transfers (verified by cell engine)
5. Game policies compile via Phase 21 Lisp compiler and evaluate correctly
6. Godot binding scaffold exists with `SemanticInventory` node
7. Unity binding scaffold exists with `SemanticInventory` MonoBehaviour
8. Serialized entities are byte-compatible with the cell engine's native format
9. All gate tests pass: `bun test packages/__tests__/phase26-gate.test.ts`
10. `bun run check` passes
11. `bun run build` succeeds
12. No React imports in game-sdk package
13. Errata sprint complete with `docs/prd/PHASE-26-ERRATA.md`
14. All commits follow `phase-26/D26.N:` naming convention
15. Branch is `phase-26-game-engine-sdk`

---

## What NOT to Do

1. **Do NOT build a game engine.** This is an SDK that existing engines consume.
2. **Do NOT implement networking.** Multiplayer sync is a future phase. This phase handles local state.
3. **Do NOT implement rendering.** The SDK manages semantic state, not pixels.
4. **Do NOT bypass the cell engine.** Every operation goes through the WASM binary. No shadow state.
5. **Do NOT hardcode game-specific logic.** The SDK is domain-agnostic. Chess, RPGs, card games all use the same primitives.
6. **Do NOT implement a marketplace or payment system.** Phase 18 metering exists but integration is a separate concern.
7. **Do NOT modify the cell engine or Lisp compiler.** The SDK registers game-domain host functions via Phase 25.5's `HostFunctionRegistry`. It does NOT add opcodes, modify the executor, or change the compiler.
8. **Do NOT implement AI/NPCs.** Behavior scripting is out of scope.

---

## Next Phase

Phase 26 output feeds into **Phase 27: Simple Games**, which builds chess and other proof-of-concept games that exercise every SDK primitive — entity creation, linearity enforcement, state transitions, policy evaluation, and (eventually) multiplayer state sync.
