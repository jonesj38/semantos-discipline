---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-25.6-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.696008+00:00
---

# Phase 25.6 Execution Prompt — Surface Opcodes + Metering Host Functions

> Paste this prompt into a fresh session to execute Phase 25.6.

---

## Context

You are working in the `semantos-core` repo — the TypeScript application layer for Bitcoin-native semantic objects. The Zig/WASM kernel (cell engine) in the sibling `semantos` repo has already compiled three opcodes (OP_CHECKDOMAINFLAG 0xC6, OP_CHECKTYPEHASH 0xC7, OP_DEREF_POINTER 0xC8) into the binary. Phase 18 implemented metering channels (channel-fsm.ts, settlement.ts) in pure TypeScript.

Your task is Phase 25.6: Surface those 3 missing opcodes into the TypeScript enum, constants, and Lisp compiler. Then implement a metering host function registry — 9 zero-arity functions that expose channel FSM state and settlement validation to the cell engine via OP_CALLHOST.

**Key constraint**: ZERO WASM recompilation. The opcodes already exist in the binary. You are only exposing them in TypeScript.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. If you skip this, you will produce stubs or code that doesn't integrate.

**Read the PRD (your requirements)**:
- `docs/prd/PHASE-25.6-OPCODE-SURFACE-METERING-HOSTFNS.md` — Full spec with deliverables D25.6.1-D25.6.5, all 25 TDD tests, verification criteria

**Read the opcode reference (the Zig source — you are NOT modifying it, only reading)**:
- `packages/cell-engine/src/opcodes/plexus.zig` — Handlers for 0xC6, 0xC7, 0xC8. Extract stack protocols and failure semantics. Read-only.

**Read the metering core (you are NOT modifying these, only querying)**:
- `packages/metering/src/channel-fsm.ts` — ChannelState enum, FSM methods. Read-only.
- `packages/metering/src/settlement.ts` — `verifyTickProof()` function signature. Read-only.

**Read the host function pattern (how to register)**:
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry class and registration API

**Read what you will modify**:
- `packages/cell-ops/src/opcodes.ts` — TypeScript enum you will extend
- `packages/constants/constants.json` — Add entries for 0xC6, 0xC7, 0xC8
- `packages/shell/src/lisp/compiler.ts` — Add compilation rules for new constraints
- `packages/shell/src/lisp/types.ts` — Extend ConstraintExpr union

**Read the existing structure (understand the system)**:
- `packages/metering/src/index.ts` — Current exports
- `packages/metering/package.json` — Package structure

**Read branching policy**:
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-25.6-opcode-surface-metering-hostfns`. Commits as `phase-25.6/D25.6.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. ZERO WASM RECOMPILATION

- Do NOT modify plexus.zig
- Do NOT run `zig build`
- Do NOT invoke any Zig compilation
- You are only exposing opcodes that already exist in the binary
- WASM binary size must be unchanged (±1KB tolerance)

### 2. NO FICTIONAL OPCODES

- Surface ONLY 0xC6, 0xC7, 0xC8 from the existing Zig binary
- Stack protocols and failure semantics come from plexus.zig handlers
- Do NOT invent or modify opcode behavior
- Extract the exact protocol from the Zig source

### 3. STACK PROTOCOLS FROM ZIG

- OP_CHECKDOMAINFLAG: [cell, expected_flag] → [cell, TRUE]
- OP_CHECKTYPEHASH: [cell, expected_hash_32B] → [cell, TRUE]
- OP_DEREF_POINTER: [pointer_cell] → [fetched_cell]
- All are failure-atomic
- These protocols come from plexus.zig handlers, not from imagination

### 4. METERING HOST FUNCTIONS ARE ZERO-ARITY

- All 9 functions take zero arguments
- They read from frozen context passed at registration time
- They never call setState() or mutate channel FSM state
- Context is a snapshot; mutations don't escape

### 5. DO NOT MODIFY METERING CORE

- channel-fsm.ts is read-only
- settlement.ts is read-only
- Do NOT add methods or export new functions from these modules
- Only read ChannelState enum and verifyTickProof() signature
- Host functions query these modules; they do NOT change them

### 6. BACKWARD COMPATIBILITY NON-NEGOTIABLE

- All existing opcodes (0xC0-0xC5, 0xD0) remain unchanged
- All existing Lisp compilation rules remain unchanged
- All existing tests must pass
- New code adds functionality, it does not break existing systems

### 7. CONTEXT IS FROZEN

- Host functions receive context object at registration time
- This context is immutable during cell execution
- Functions read context fields, they never assign to them
- No side effects on global state or metering channels

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /sessions/nice-exciting-hopper/mnt/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify plexus.zig exists and contains 0xC6, 0xC7, 0xC8

```bash
grep -n "0xC6\|0xC7\|0xC8" packages/cell-engine/src/opcodes/plexus.zig
```

All three must be present. If not, STOP.

### 0.4 Verify metering modules exist

```bash
ls packages/metering/src/channel-fsm.ts
ls packages/metering/src/settlement.ts
ls packages/metering/src/index.ts
```

All three must exist and not be stubbed. If anything is missing, STOP.

### 0.5 Create Phase 25.6 branch

```bash
git checkout -b phase-25.6-opcode-surface-metering-hostfns
```

---

## Step 1: Surface Opcodes in TypeScript Enum (D25.6.1)

**File to modify**: `packages/cell-ops/src/opcodes.ts`

Add to the Plexus opcode range (after OP_ASSERTLINEAR at 0xC5):

```typescript
OP_CHECKDOMAINFLAG = 0xC6,
OP_CHECKTYPEHASH = 0xC7,
OP_DEREF_POINTER = 0xC8,
```

Verify:
- Enum values are correct (0xC6 = 198, 0xC7 = 199, 0xC8 = 200)
- These are added to the Plexus range (0xC0-0xCF), not somewhere else
- OP_CALLHOST (0xD0) remains unchanged below these

Run type check:
```bash
npx tsc --noEmit packages/cell-ops/src/opcodes.ts
```

Commit:
```bash
git add packages/cell-ops/src/opcodes.ts
git commit -m "phase-25.6/D25.6.1: surface opcodes 0xC6-0xC8 in TypeScript enum"
```

---

## Step 2: Update Constants (D25.6.2)

**File to modify**: `packages/constants/constants.json`

Add three opcode entries and a metering host function list:

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

Verify:
- JSON is valid (no syntax errors)
- Hex values match decimal values
- All 9 host function names are present

Validate JSON:
```bash
node -e "const fs = require('fs'); JSON.parse(fs.readFileSync('packages/constants/constants.json', 'utf-8')); console.log('OK')"
```

Commit:
```bash
git add packages/constants/constants.json
git commit -m "phase-25.6/D25.6.2: add opcode constants 0xC6-0xC8 + metering host function registry"
```

---

## Step 3: Lisp Compiler Extensions (D25.6.3)

**File to modify**: `packages/shell/src/lisp/compiler.ts`

Add to the OPCODE_CONSTANTS object:

```typescript
CHECK_TYPE_HASH: 0xC7,
DEREF_POINTER: 0xC8,
```

Add compilation functions (follow existing pattern from check-provenance, verify-cert, etc.):

```typescript
function compileCheckTypeHash(expr: CheckTypeHashExpr): Bytecode {
  const hash = expr.hash; // 32-byte buffer
  return [
    ...compilePush(hash),
    OPCODE_CONSTANTS.CHECK_TYPE_HASH,
  ];
}

function compileDeref(expr: DerefExpr): Bytecode {
  return [OPCODE_CONSTANTS.DEREF_POINTER];
}
```

Add to the main compile dispatch (wherever constraint expressions are handled):

```typescript
case 'check-type-hash':
  return compileCheckTypeHash(expr);
case 'deref':
  return compileDeref(expr);
```

**File to modify**: `packages/shell/src/lisp/types.ts`

Extend the ConstraintExpr union:

```typescript
export type ConstraintExpr =
  | CheckProvenanceExpr
  | VerifyCertExpr
  | GetFacetExpr
  | SetFacetExpr
  | AssertLinearExpr
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

Verify:
- Compiler parses `(check-type-hash #"abc...xyz")` without error
- Compiler parses `(deref)` without error
- Emitted bytecode for `check-type-hash` includes 0xC7
- Emitted bytecode for `deref` is just [0xC8]

Test:
```bash
cd packages/shell
npm test -- compiler.test.ts
```

Commit:
```bash
git add packages/shell/src/lisp/compiler.ts packages/shell/src/lisp/types.ts
git commit -m "phase-25.6/D25.6.3: add Lisp compilation rules for check-type-hash and deref"
```

---

## Step 4: Metering Host Functions Registry (D25.6.4)

**File to create**: `packages/metering/src/host-functions.ts`

Implement the 9 zero-arity host functions:

```typescript
import { HostFunctionRegistry } from '@semantos/cell-engine/bindings/host-functions';
import { ChannelState } from './channel-fsm';
import { verifyTickProof } from './settlement';

export interface MeteringContext {
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

export function registerMeteringHostFunctions(
  registry: HostFunctionRegistry,
  context: MeteringContext
): void {
  // 1. channel-in-state?
  registry.register('channel-in-state?', () => {
    if (context.channelState === undefined || context.currentArg === undefined) return 0;
    return context.channelState === context.currentArg ? 1 : 0;
  });

  // 2. channel-active?
  registry.register('channel-active?', () => {
    if (context.channelState === undefined) return 0;
    return context.channelState === ChannelState.ACTIVE ? 1 : 0;
  });

  // 3. channel-funded?
  registry.register('channel-funded?', () => {
    if (context.fundingAmount === undefined || context.fundingAmount <= 0) return 0;
    return 1;
  });

  // 4. balance-sufficient?
  registry.register('balance-sufficient?', () => {
    if (context.cumulativeSatoshis === undefined || context.fundingAmount === undefined) return 0;
    return context.cumulativeSatoshis >= context.fundingAmount ? 1 : 0;
  });

  // 5. tick-proof-valid?
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

  // 6. dispute-window-open?
  registry.register('dispute-window-open?', () => {
    if (
      context.disputeOpenedAtBlock === undefined ||
      context.disputeWindowBlocks === undefined ||
      context.currentBlockHeight === undefined
    ) return 0;
    return context.currentBlockHeight < (context.disputeOpenedAtBlock + context.disputeWindowBlocks) ? 1 : 0;
  });

  // 7. funding-sufficient?
  registry.register('funding-sufficient?', () => {
    if (context.fundingAmount === undefined || context.currentArg === undefined) return 0;
    return context.fundingAmount >= context.currentArg ? 1 : 0;
  });

  // 8. tick-count
  registry.register('tick-count', () => {
    if (context.currentTick === undefined) return 0;
    return context.currentTick;
  });

  // 9. cumulative-satoshis
  registry.register('cumulative-satoshis', () => {
    if (context.cumulativeSatoshis === undefined) return 0;
    return context.cumulativeSatoshis;
  });
}
```

**Key requirements**:
- All functions are zero-arity (take no arguments, read context)
- All return scalar values (0/1 for booleans, u32 for counts)
- Context is frozen (read-only snapshot at registration time)
- No modifications to channel-fsm.ts or settlement.ts
- tick-proof-valid? delegates to verifyTickProof(), does not reimplement it

Verify:
- Functions register without errors
- Each function is callable via registry.lookup()
- Return values match expected types
- No mutations to metering core modules

Test:
```bash
cd packages/metering
npm test -- host-functions.test.ts
```

Commit:
```bash
git add packages/metering/src/host-functions.ts
git commit -m "phase-25.6/D25.6.4: add 9 metering host functions with frozen context"
```

---

## Step 5: Metering Package Exports (D25.6.5)

**File to modify**: `packages/metering/src/index.ts`

Add export:

```typescript
export { registerMeteringHostFunctions, MeteringContext } from './host-functions';
```

Verify existing exports remain unchanged:

```typescript
export { ChannelState, ChannelFSM } from './channel-fsm';
export { verifyTickProof, verifyTickProofSignature } from './settlement';
```

**File to verify/modify**: `packages/metering/package.json`

Ensure `"exports"` field includes:

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

Verify import resolution:
```bash
node -e "const m = require('@semantos/metering'); console.log(typeof m.registerMeteringHostFunctions)"
```

Output should be `function`.

Commit:
```bash
git add packages/metering/src/index.ts packages/metering/package.json
git commit -m "phase-25.6/D25.6.5: export metering host functions + update package.json"
```

---

## Step 6: TDD Gate Tests (All 25 Tests)

Run all tests for Phase 25.6:

```bash
# Test constants
npm test -- constants.test.ts

# Test opcodes enum
npm test -- opcodes.test.ts

# Test Lisp compiler
npm test -- lisp/compiler.test.ts

# Test metering host functions
npm test -- metering/host-functions.test.ts

# Test backward compatibility
npm test -- backward-compat.test.ts
```

All tests must pass. If any test fails:
1. Do NOT change the test
2. Fix the code
3. Re-run the test
4. Verify it passes

Tests T1-T25 from the PRD must all pass:
- T1-T3: Opcode enum and constants
- T4-T6: Lisp compiler extensions
- T7-T16: Metering host functions
- T17-T19: Context freeze and backward compatibility
- T20-T25: Opcode allocation, integration, and WASM unchanged

---

## Step 7: Verify and Clean (Final Checks)

### 7.1 WASM binary size unchanged

```bash
cd packages/cell-engine
ls -lh build/cell-engine.wasm
```

Size should be unchanged (±1KB tolerance). If it changed, you compiled Zig — do NOT do that.

### 7.2 No Zig files modified

```bash
git diff --name-only | grep -i \.zig
```

Output should be empty. If any .zig files are modified, revert them.

### 7.3 All tests pass

```bash
npm test
```

No regressions. All existing tests pass.

### 7.4 Type check passes

```bash
npx tsc --noEmit
```

No TypeScript errors.

### 7.5 Clean git status

```bash
git status -u
```

All changes staged and committed. No uncommitted files (except untracked non-code files).

---

## Completion Criteria

You are **DONE** when ALL of the following are true:

1. ✓ OP_CHECKDOMAINFLAG (0xC6), OP_CHECKTYPEHASH (0xC7), OP_DEREF_POINTER (0xC8) defined in `packages/cell-ops/src/opcodes.ts`
2. ✓ Constants for all three opcodes in `packages/constants/constants.json`
3. ✓ Lisp compiler compiles `(check-type-hash)` and `(deref)` to correct bytecode
4. ✓ `packages/shell/src/lisp/types.ts` includes CheckTypeHashExpr and DerefExpr in ConstraintExpr union
5. ✓ `packages/metering/src/host-functions.ts` exports `registerMeteringHostFunctions()` with all 9 functions
6. ✓ All metering host functions registered with frozen context semantics
7. ✓ All 25 TDD gate tests pass (T1-T25)
8. ✓ All verification criteria satisfied (V1-V6 from PRD)
9. ✓ WASM binary size unchanged (±1KB tolerance)
10. ✓ `packages/metering/package.json` exports host-functions module
11. ✓ No Zig files modified; no `zig build` invoked
12. ✓ All existing tests pass; no regressions
13. ✓ Branch: `phase-25.6-opcode-surface-metering-hostfns`
14. ✓ Commits in format `phase-25.6/D25.6.N: description`

---

## What NOT to Do

1. **DO NOT recompile WASM.** Opcodes already exist.
2. **DO NOT modify plexus.zig.** It is read-only.
3. **DO NOT modify channel-fsm.ts or settlement.ts.** They are read-only.
4. **DO NOT create fictional opcodes.** Surface only 0xC6, 0xC7, 0xC8.
5. **DO NOT add metering state mutations.** Context is frozen.
6. **DO NOT create separate registry file.** Use existing HostFunctionRegistry.
7. **DO NOT break backward compatibility.** All existing code remains unchanged.
8. **DO NOT skip reading the files.** You will produce stubs without reading them.
9. **DO NOT change test expectations.** Fix the code, not the tests.
10. **DO NOT run `zig build`.** You are not writing Zig code.

