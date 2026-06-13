---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-25.6-OPCODE-SURFACE-METERING-HOSTFNS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.700042+00:00
---

# Phase 25.6 — Surface Missing Opcodes + Metering Host Functions

**Version**: 1.0
**Date**: 2026-03-31
**Status**: Not yet implemented
**Duration**: 1.5 weeks (with 40% buffer: ~10 days)
**Prerequisites**: Phase 25.0-25.5 complete — plexus.zig compiled, metering FSM + settlement modules operational
**Branch**: `phase-25.6-opcode-surface-metering-hostfns`

---

## Objective

Three opcodes (OP_CHECKDOMAINFLAG 0xC6, OP_CHECKTYPEHASH 0xC7, OP_DEREF_POINTER 0xC8) are already compiled in the Zig WASM binary but missing from the TypeScript host layer. This phase surfaces them into the enum, constants, and Lisp compiler. Additionally, implement the metering host function registry — 9 zero-arity host functions that expose channel FSM state queries and settlement validation to the cell engine via OP_CALLHOST, without modifying the metering core modules.

**Scope**: TypeScript bindings only. Zero WASM recompilation. No changes to plexus.zig, channel-fsm.ts, or settlement.ts.

---

## Context

The cell engine (packages/cell-engine) exports a WASM binary from Zig. Phase 17-25 implemented linearity enforcement, cryptographic opcodes, and metering channels. The Zig code has compiled:

- **plexus.zig** — Plexus opcodes (0xC0-0xCF range for bilateral consensus and domain-specific checks)
- **channel-fsm.ts** — Metering channel state machine (Pure TypeScript, no WASM)
- **settlement.ts** — HMAC tick proof settlement (Pure TypeScript, no WASM)

The HostFunctionRegistry pattern (packages/cell-engine/bindings/host-functions.ts) allows registering zero-arity functions that query frozen context (engine state, metering state, config) and return scalar values or booleans to the cell stack via OP_CALLHOST (0xD0).

**Trust boundary**: Engine opcodes (0xC0-0xCF) for bilateral consensus and cell-level constraints. Host functions (via OP_CALLHOST) for application-layer state queries.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `PLEXUS:OPCODES` | `packages/cell-engine/src/opcodes/plexus.zig` | **Canonical opcode reference.** Handlers for 0xC6, 0xC7, 0xC8. Extract stack protocol, failure-atomic semantics, and return codes. |
| `METERING:FSM` | `packages/metering/src/channel-fsm.ts` | **Channel state machine.** State enum, transition methods, invariants. Read-only in this phase. |
| `METERING:SETTLEMENT` | `packages/metering/src/settlement.ts` | **Tick proof verification.** `verifyTickProof()` function signature and failure modes. Read-only in this phase. |
| `HOSTFN:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | **Host function registration pattern.** How OP_CALLHOST resolves function names, how context is passed, return value encoding. |
| `OPCODES:TS-ENUM` | `packages/cell-ops/src/opcodes.ts` | **TypeScript enum.** Current range stops at OP_ASSERTLINEAR (0xC5). Must extend to 0xC8. |
| `CONSTANTS:JSON` | `packages/constants/constants.json` | **Constants source.** Where 0xC6, 0xC7, 0xC8 and metering host function names are registered. |
| `COMPILER:LISP` | `packages/shell/src/lisp/compiler.ts` | **Lisp → bytecode compilation.** Where new opcode constant references are resolved. Must add compilation rules for `(check-type-hash)` and `(deref)`. |
| `COMPILER:TYPES` | `packages/shell/src/lisp/types.ts` | **Lisp AST types.** ConstraintExpr union must be extended for TypeHashCheckExpr and DerefExpr. |

---

## Deliverables

### D25.6.1 — Surface 3 Missing Opcodes in TypeScript Enum

**File**: `packages/cell-ops/src/opcodes.ts`

Add to the Plexus opcode range (0xC0-0xCF):

```typescript
export enum Opcode {
  // ... existing opcodes ...

  // Plexus opcodes (0xC0-0xCF)
  OP_ASSERTLINEAR = 0xC5,
  OP_CHECKDOMAINFLAG = 0xC6,  // NEW: Stack [cell, expected_flag] → [cell, TRUE]
  OP_CHECKTYPEHASH = 0xC7,    // NEW: Stack [cell, expected_hash] → [cell, TRUE]
  OP_DEREF_POINTER = 0xC8,    // NEW: Stack [pointer_cell] → [fetched_cell]

  // OP_CALLHOST = 0xD0 (existing)
}
```

**Stack protocols** (from plexus.zig):

- **OP_CHECKDOMAINFLAG** (0xC6): [cell, flag] → [cell, 0x01]. Checks if domain-specific flag bit is set on cell. Failure-atomic.
- **OP_CHECKTYPEHASH** (0xC7): [cell, hash] → [cell, 0x01]. Compares SHA-256 type hash (32 bytes from stack). Failure-atomic.
- **OP_DEREF_POINTER** (0xC8): [pointer_cell] → [fetched_cell]. Dereferences pointer via host_fetch_cell. Returns fetched cell or fails atomically.

**Gate**: Enum compiles without errors. OP_CHECKDOMAINFLAG, OP_CHECKTYPEHASH, OP_DEREF_POINTER are defined at 0xC6, 0xC7, 0xC8 respectively.

**Commit**: `phase-25.6/D25.6.1: surface opcodes 0xC6-0xC8 in TypeScript enum`

---

### D25.6.2 — Constants Update

**File**: `packages/constants/constants.json`

Add opcode entries for 0xC6, 0xC7, 0xC8:

```json
{
  "opcodes": {
    "OP_CHECKDOMAINFLAG": {
      "value": 198,
      "hex": "0xC6",
      "range": "plexus",
      "description": "Domain flag check — failure-atomic"
    },
    "OP_CHECKTYPEHASH": {
      "value": 199,
      "hex": "0xC7",
      "range": "plexus",
      "description": "SHA-256 type hash comparison — failure-atomic"
    },
    "OP_DEREF_POINTER": {
      "value": 200,
      "hex": "0xC8",
      "range": "plexus",
      "description": "Dereference pointer cell — failure-atomic"
    }
  },
  "metering": {
    "hostFunctions": [
      "channel-in-state?",
      "channel-active?",
      "channel-funded?",
      "balance-sufficient?",
      "tick-proof-valid?",
      "dispute-window-open?",
      "funding-sufficient?",
      "tick-count",
      "cumulative-satoshis"
    ]
  }
}
```

**Opcode allocation map** (full 0x00-0xFF post-Phase 25.6):

```
0x00-0x3F: Standard stack + crypto (OP_PUSH, OP_DUP, OP_SHA256, OP_CHECKSIG, etc.)
0x40-0xBF: Macro opcodes (OP_UNPACK, OP_PACK, OP_ASSERT_LINEAR, etc.)
0xC0-0xCF: Plexus (bilateral consensus + domain checks)
  0xC0: OP_CHECKPROVENANCE
  0xC1: OP_VERIFYCERT
  0xC2: OP_GETFACET
  0xC3: OP_SETFACET
  0xC4: OP_ASSERTLINEAR
  0xC5: (reserved)
  0xC6: OP_CHECKDOMAINFLAG (NEW)
  0xC7: OP_CHECKTYPEHASH (NEW)
  0xC8: OP_DEREF_POINTER (NEW)
  0xC9-0xCF: (reserved for future plexus)
0xD0: OP_CALLHOST (host function dispatch)
0xD1-0xDF: (reserved for future host)
0xE0-0xFF: (reserved for future expansion)
```

**Gate**: constants.json is valid JSON. Build script generates constants.zig and constants.ts without errors. Enum values match hex constants.

**Commit**: `phase-25.6/D25.6.2: add opcode constants 0xC6-0xC8 + metering host function registry`

---

### D25.6.3 — Lisp Compiler Extensions

**File**: `packages/shell/src/lisp/compiler.ts`

Add constants for the new opcodes:

```typescript
const OPCODE_CONSTANTS = {
  // ... existing ...
  CHECK_DOMAIN_FLAG: 0xC6,
  CHECK_TYPE_HASH: 0xC7,
  DEREF_POINTER: 0xC8,
};
```

Add compilation rules:

```typescript
// Compile (check-type-hash <32-byte-hash>) → OP_PUSH <hash> + OP_CHECKTYPEHASH
compileCheckTypeHash(expr: CheckTypeHashExpr): Bytecode {
  const hash = expr.hash; // 32-byte buffer
  return [
    ...compilePush(hash),
    OPCODE_CONSTANTS.CHECK_TYPE_HASH,
  ];
}

// Compile (deref) → OP_DEREF_POINTER
compileDeref(expr: DerefExpr): Bytecode {
  return [OPCODE_CONSTANTS.DEREF_POINTER];
}
```

**File**: `packages/shell/src/lisp/types.ts`

Extend ConstraintExpr union:

```typescript
export type ConstraintExpr =
  | CheckProvenanceExpr
  | VerifyCertExpr
  | GetFacetExpr
  | SetFacetExpr
  | AssertLinearExpr
  | CheckDomainFlagExpr
  | CheckTypeHashExpr  // NEW
  | DerefExpr;         // NEW

export interface CheckTypeHashExpr {
  type: "check-type-hash";
  hash: Buffer; // 32 bytes
}

export interface DerefExpr {
  type: "deref";
}
```

**Gate**: Compiler parses and emits bytecode for `(check-type-hash #"...")` and `(deref)` without errors. Emitted bytecode contains correct opcode bytes (0xC7 and 0xC8).

**Commit**: `phase-25.6/D25.6.3: add Lisp compilation rules for check-type-hash and deref`

---

### D25.6.4 — Metering Host Functions Registry

**File**: `packages/metering/src/host-functions.ts` (new file)

Implement the 9 zero-arity host functions:

```typescript
import { HostFunctionRegistry } from '@semantos/cell-engine/bindings/host-functions';
import { ChannelState, ChannelFSM } from './channel-fsm';
import { verifyTickProof } from './settlement';

export function registerMeteringHostFunctions(
  registry: HostFunctionRegistry,
  context: {
    channelState?: ChannelState;
    currentArg?: number;
    cumulativeSatoshis?: number;
    fundingAmount?: number;
    latestTickProof?: Buffer;
    sharedSecret?: Buffer;
    channelId?: string;
    disputeOpenedAtBlock?: number;
    disputeWindowBlocks?: number;
    currentBlockHeight?: number;
    currentTick?: number;
  }
): void {
  // 1. channel-in-state? — returns 1 if state matches expected, 0 otherwise
  registry.register('channel-in-state?', () => {
    if (!context.channelState || context.currentArg === undefined) return 0;
    return context.channelState === context.currentArg ? 1 : 0;
  });

  // 2. channel-active? — returns 1 if channel is ACTIVE, 0 otherwise
  registry.register('channel-active?', () => {
    if (!context.channelState) return 0;
    return context.channelState === ChannelState.ACTIVE ? 1 : 0;
  });

  // 3. channel-funded? — returns 1 if funding > 0, 0 otherwise
  registry.register('channel-funded?', () => {
    if (context.fundingAmount === undefined || context.fundingAmount <= 0) return 0;
    return 1;
  });

  // 4. balance-sufficient? — returns 1 if cumulativeSatoshis >= fundingAmount
  registry.register('balance-sufficient?', () => {
    if (context.cumulativeSatoshis === undefined || context.fundingAmount === undefined) return 0;
    return context.cumulativeSatoshis >= context.fundingAmount ? 1 : 0;
  });

  // 5. tick-proof-valid? — delegates to verifyTickProof()
  registry.register('tick-proof-valid?', () => {
    if (!context.latestTickProof || !context.sharedSecret || !context.channelId) return 0;
    try {
      const valid = verifyTickProof(
        context.latestTickProof,
        context.sharedSecret,
        context.channelId
      );
      return valid ? 1 : 0;
    } catch {
      return 0;
    }
  });

  // 6. dispute-window-open? — returns 1 if currentBlockHeight < openedAt + windowBlocks
  registry.register('dispute-window-open?', () => {
    if (
      context.disputeOpenedAtBlock === undefined ||
      context.disputeWindowBlocks === undefined ||
      context.currentBlockHeight === undefined
    ) return 0;
    return context.currentBlockHeight < (context.disputeOpenedAtBlock + context.disputeWindowBlocks) ? 1 : 0;
  });

  // 7. funding-sufficient? — returns 1 if fundingAmount >= _currentArg (threshold)
  registry.register('funding-sufficient?', () => {
    if (context.fundingAmount === undefined || context.currentArg === undefined) return 0;
    return context.fundingAmount >= context.currentArg ? 1 : 0;
  });

  // 8. tick-count — returns current tick as u32
  registry.register('tick-count', () => {
    if (context.currentTick === undefined) return 0;
    return context.currentTick;
  });

  // 9. cumulative-satoshis — returns cumulative satoshis as u32
  registry.register('cumulative-satoshis', () => {
    if (context.cumulativeSatoshis === undefined) return 0;
    return context.cumulativeSatoshis;
  });
}
```

**Context freeze requirement**: All 9 functions accept a frozen context object passed at registration time. They never call into channel-fsm.ts or settlement.ts methods directly; they only read context fields and invoke pure functions (like verifyTickProof). This prevents state mutations during cell execution.

**Failure mode**: All functions return 0 or false on missing/invalid context. No exceptions bubble to the engine.

**Gate**: Functions register without errors. Registry can be queried via `registry.lookup('channel-active?')`. Each function is callable and returns the correct scalar type (0/1 for predicates, u32 for counts).

**Commit**: `phase-25.6/D25.6.4: add 9 metering host functions with frozen context`

---

### D25.6.5 — Metering Package Exports

**File**: `packages/metering/src/index.ts`

Export the new host function registry:

```typescript
export { registerMeteringHostFunctions } from './host-functions';
export { ChannelState, ChannelFSM } from './channel-fsm';
export { verifyTickProof, verifyTickProofSignature } from './settlement';
```

**File**: `packages/metering/package.json`

Verify exports are included in `"exports"` field:

```json
{
  "exports": {
    ".": "./src/index.ts",
    "./channel-fsm": "./src/channel-fsm.ts",
    "./settlement": "./src/settlement.ts",
    "./host-functions": "./src/host-functions.ts"
  }
}
```

**Gate**: `npm list @semantos/metering` shows the package. `import { registerMeteringHostFunctions } from '@semantos/metering'` resolves without errors.

**Commit**: `phase-25.6/D25.6.5: export metering host functions + update package.json`

---

## TDD Gate — Tests That Must Pass

### T1: Opcode enum values
```
OP_CHECKDOMAINFLAG === 0xC6 (198)
OP_CHECKTYPEHASH === 0xC7 (199)
OP_DEREF_POINTER === 0xC8 (200)
```

### T2: Constants JSON valid
```
constants.json parses without errors
opcodes.OP_CHECKDOMAINFLAG.value === 198
metering.hostFunctions includes all 9 function names
```

### T3: Lisp compiler constants defined
```
OPCODE_CONSTANTS.CHECK_TYPE_HASH === 0xC7
OPCODE_CONSTANTS.DEREF_POINTER === 0xC8
```

### T4: Lisp compiler emits check-type-hash bytecode
```
compile('(check-type-hash #"abc...xyz")') produces [0xC7, ...]
```

### T5: Lisp compiler emits deref bytecode
```
compile('(deref)') produces [0xC8]
```

### T6: ConstraintExpr types defined
```
CheckTypeHashExpr and DerefExpr are in ConstraintExpr union
```

### T7: Host function registry accepts new functions
```
registry.register('channel-active?', fn)
registry.lookup('channel-active?') returns fn
```

### T8: channel-active? returns correct value
```
With channelState=ACTIVE, returns 1
With channelState=INACTIVE, returns 0
With no context, returns 0
```

### T9: channel-funded? threshold check
```
With fundingAmount=1000, returns 1
With fundingAmount=0, returns 0
With fundingAmount=undefined, returns 0
```

### T10: balance-sufficient? comparison
```
With cumulativeSatoshis=1000, fundingAmount=500, returns 1
With cumulativeSatoshis=400, fundingAmount=500, returns 0
```

### T11: tick-proof-valid? delegates to verifyTickProof()
```
Calls verifyTickProof() with correct args
Returns 1 on success, 0 on exception
```

### T12: dispute-window-open? block height check
```
With openedAt=100, window=10, current=105, returns 1
With openedAt=100, window=10, current=110, returns 0
```

### T13: funding-sufficient? threshold
```
With fundingAmount=1000, threshold=500, returns 1
With fundingAmount=400, threshold=500, returns 0
```

### T14: tick-count returns u32
```
With currentTick=42, returns 42
With currentTick=undefined, returns 0
Returned value fits in u32
```

### T15: cumulative-satoshis returns u32
```
With cumulativeSatoshis=1000000, returns 1000000
With cumulativeSatoshis=undefined, returns 0
Returned value fits in u32
```

### T16: All 9 host functions register
```
Registry contains all 9 function names
Each can be looked up and invoked
```

### T17: Context is frozen during execution
```
Function receives snapshot of context
Mutations to context object do not affect subsequent calls
```

### T18: Backward compatibility — existing opcodes
```
OP_ASSERTLINEAR (0xC5) still defined
OP_CALLHOST (0xD0) still defined
All previous Plexus opcodes unchanged
```

### T19: Lisp compilation — existing constraints unchanged
```
(check-provenance ...) still compiles correctly
(verify-cert ...) still compiles correctly
No regressions in existing constraint compilation
```

### T20: Opcode allocation map is accurate
```
0xC0-0xC8 allocated to Plexus
0xD0 allocated to OP_CALLHOST
No gaps or overlaps
```

### T21: Host function names match constants.json
```
registry.lookup('channel-in-state?') === 'channel-in-state?' from metering.hostFunctions
All 9 function names in registry match constants
```

### T22: verifyTickProof integration
```
tick-proof-valid? calls verifyTickProof() without reimplementing it
```

### T23: Error handling — all functions graceful on null context
```
All 9 functions handle missing/null context fields
None throw exceptions; all return safe defaults
```

### T24: Package exports resolve
```
import { registerMeteringHostFunctions } from '@semantos/metering' succeeds
```

### T25: WASM binary unchanged size
```
wasm binary size unchanged (±1KB tolerance)
No Zig files modified
No zig build invoked
```

---

## Verification Criteria

### V1: Opcodes surfaced
Three opcodes (0xC6, 0xC7, 0xC8) are defined in TypeScript enum and constants.json with correct values.

### V2: Lisp compiler supports new constraints
`(check-type-hash ...)` and `(deref)` parse and compile without errors. Emitted bytecode contains correct opcode bytes.

### V3: Metering host functions registered
All 9 functions are registered via HostFunctionRegistry. Each accepts frozen context and returns scalar or boolean.

### V4: No metering core modifications
channel-fsm.ts and settlement.ts are unchanged. Only read, never written.

### V5: Backward compatibility maintained
All existing opcodes, constants, and Lisp compilation rules continue to work. No regressions in test suite.

### V6: Context freeze enforced
Host functions receive context snapshot. No mutations escape to channel FSM state.

---

## Phase Completion Criteria

You are **done with Phase 25.6** when ALL of the following are true:

1. OP_CHECKDOMAINFLAG (0xC6), OP_CHECKTYPEHASH (0xC7), OP_DEREF_POINTER (0xC8) are defined in `packages/cell-ops/src/opcodes.ts`
2. Constants for all three opcodes exist in `packages/constants/constants.json`
3. Lisp compiler (`packages/shell/src/lisp/compiler.ts`) compiles `(check-type-hash)` and `(deref)` to correct bytecode
4. `packages/shell/src/lisp/types.ts` includes CheckTypeHashExpr and DerefExpr in ConstraintExpr union
5. `packages/metering/src/host-functions.ts` exports `registerMeteringHostFunctions()` with all 9 functions
6. All metering host functions are registered with frozen context semantics
7. All TDD gate tests T1-T25 pass
8. All verification criteria V1-V6 are satisfied
9. WASM binary size is unchanged (±1KB tolerance)
10. `packages/metering/package.json` exports host-functions module
11. No Zig files modified; no `zig build` invoked
12. All existing tests pass; no regressions

---

## What NOT to Do

1. **DO NOT recompile WASM.** The opcodes already exist in the binary. You are surfacing them in TypeScript only.
2. **DO NOT modify plexus.zig.** Stack protocols and failure semantics are already correct.
3. **DO NOT modify channel-fsm.ts or settlement.ts.** These are read-only. Host functions query them via frozen context, never mutate them.
4. **DO NOT create new opcodes.** Surface only 0xC6, 0xC7, 0xC8 from the existing binary.
5. **DO NOT add metering state mutations inside host functions.** All context is frozen at registration time.
6. **DO NOT create a separate host-function-registry.ts file.** Use the existing HostFunctionRegistry in `packages/cell-engine/bindings/host-functions.ts`.
7. **DO NOT break backward compatibility.** All existing opcodes, constants, and Lisp rules remain unchanged.

