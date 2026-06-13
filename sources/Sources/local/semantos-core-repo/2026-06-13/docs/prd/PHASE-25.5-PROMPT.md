---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-25.5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.693243+00:00
---

# Phase 25.5 Execution Prompt — Host Function Dispatch (OP_CALLHOST)

> Paste this prompt into a fresh session to execute Phase 25.5.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phases 0–21 built a 28KB Zig/WASM cell engine with linearity enforcement, 2-PDA, SPV verification, Lisp policy compilation, and transfer protocols. The cell engine has fixed opcodes: 0x00–0xAF (standard Bitcoin Script), 0xB0–0xBF (Craig macros), 0xC0–0xCF (Plexus domain checks).

Phase 25.5 adds **OP_CALLHOST** (0xD0) — a generic host function dispatch opcode. It allows **domain phases (26–29) to register named predicates** without modifying the cell engine binary. A domain phase (Games, CDM, SCADA) can register zero-arity predicates like `diagonal-path?`, `payment-overdue?`, `zone-locked?` via a `HostFunctionRegistry`. At script evaluation time, `(diagonal-path?)` (a zero-arity form) compiles to `push "diagonal-path?" OP_CALLHOST`. The Zig executor pops the function name, calls the host extern `host_call_by_name()`, and the TypeScript host dispatches to the registered function.

**Design decision: zero-arity with frozen context.** Host functions do NOT consume stack items. They read a pre-set, immutable evaluation context. This keeps domain logic out of the cell engine and leverages TypeScript's type system for policy expression.

The key insight: domain packages can extend the capability system without shipping new WASM binaries. A Lisp form like `(payment-overdue?)` can check a frozen context field — say, `ctx._currentValue: number` (the expected payment date) — and a registered function checks whether it has passed. No new opcodes. No cell engine changes. Just registration + frozen context.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the Phase 25.5 PRD — your requirements):
- `docs/prd/PHASE-25.5-HOST-FUNCTION-DISPATCH.md` — Full spec with D25.5.1–D25.5.5, anti-bullshit rules, gate tests, completion criteria

**Read second** (Zig opcode dispatch patterns):
- `packages/cell-engine/src/executor.zig` — how opcodes are dispatched in the main loop (see standard/macro/plexus dispatch)
- `packages/cell-engine/src/opcodes/standard.zig` — standard opcode implementation pattern
- `packages/cell-engine/src/opcodes/plexus.zig` — domain-specific opcode (Phase 4) — shows OP_CHECKDOMAINFLAG as a reference

**Read third** (host function system):
- `packages/cell-engine/src/host.zig` — host extern declarations and unified wrappers (callByName wrapper is here)
- `packages/cell-engine/bindings/host-functions.ts` — `HostFunctionRegistry` class and `createHostFunctions` integration point

**Read fourth** (WASM loaders and type system):
- `packages/cell-engine/bindings/wasm-loader-bun.ts` — how `host_call_by_name` is wired into Bun WASM instantiation
- `packages/cell-engine/bindings/wasm-loader-node.ts` — Node loader pattern
- `packages/cell-engine/bindings/wasm-loader-browser.ts` — Browser loader pattern
- `packages/shell/src/lisp/types.ts` — `ConstraintExpr` union (where `HostCallExpr` is added)
- `packages/shell/src/lisp/compiler.ts` — `compileConstraint` function (where host call compilation is added)

**Read fifth** (constants and protocol types):
- `packages/constants/constants.json` — where opcode ranges are defined
- `packages/cell-ops/src/opcodes.ts` — Opcode enum (OP_CALLHOST is added here)
- `packages/protocol-types/src/index.ts` — Cell header types, domain flags, linearity modes

**Read sixth** (stack operations):
- `packages/cell-engine/src/pda.zig` — PDA operations (stack push/pop)

**Read seventh** (system architecture):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch strategy and gate test requirements

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. ONE OPCODE ONLY
OP_CALLHOST is 0xD0. The range 0xD1–0xDF is **reserved for future host function variants** (not implemented in Phase 25.5). Do not add other opcodes. Do not add 0xD1.

### 2. CONTEXT IS FROZEN
When a host function is invoked, `Object.freeze()` is called on the context object. Host functions receive an immutable object. The evaluation context is set **once per script execution** via `registry.setContext()`, cleared after via `registry.clearContext()`. No per-call mutations. This is critical for determinism and prevents side-channel injection.

### 3. HOST FUNCTIONS ARE ZERO-ARITY ON THE STACK
OP_CALLHOST pops **one item** from the stack: the function name (a string). It does NOT pop arguments. All inputs come from the pre-set evaluation context. If a domain phase needs to pass a value to a predicate, it sets `ctx._currentValue` before evaluation. The compiler sugar `(predicate?)` (a symbol ending in `?` with no arguments) compiles to `push "predicate?" OP_CALLHOST`. Exception: for compound forms like `(call-host "custom-fn")`, push the name and dispatch — same pattern.

### 4. BACKWARD COMPATIBILITY NON-NEGOTIABLE
Existing scripts that do not use OP_CALLHOST must behave identically before and after Phase 25.5. No changes to standard opcode dispatch, PDA behavior, or WASM binary size. The WASM binary must remain under 32KB.

### 5. NO DOMAIN-SPECIFIC FUNCTIONS IN PHASE 25.5
Phase 25.5 provides only **built-in generics**: `field-eq?`, `field-gt?`, `field-lt?`, `has-capability?`. Domain-specific predicates (diagonal-path?, payment-overdue?) are registered by Phases 26–29, not by Phase 25.5. The Registry is extensible; the phase is not.

### 6. WASM SIZE BUDGET
The WASM binary must stay under 32KB. OP_CALLHOST is 5–10 lines of Zig (hostcall.zig). The TypeScript registry adds ~50 lines. Built-in host functions add ~60 lines. The compiler change adds ~20 lines. Total new code: <150 lines. This must not push the binary size past the 32KB gate.

### 7. COMPILATION STAYS PURE
The Lisp compiler does NOT validate that a host function is registered. `(diagonal-path?)` compiles successfully to bytecode even if `diagonal-path?` has never been registered. The **runtime** (when executing the script) fails if the function is unknown. This separation keeps compilation pure and deterministic.

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
# Phase 21 compiler exists
ls packages/shell/src/lisp/compiler.ts
ls packages/shell/src/lisp/types.ts

# Executor and dispatch patterns exist
ls packages/cell-engine/src/executor.zig
ls packages/cell-engine/src/opcodes/standard.zig
ls packages/cell-engine/src/opcodes/plexus.zig

# Host extern system exists
ls packages/cell-engine/src/host.zig

# WASM loaders exist
ls packages/cell-engine/bindings/wasm-loader-bun.ts
ls packages/cell-engine/bindings/wasm-loader-node.ts
ls packages/cell-engine/bindings/wasm-loader-browser.ts

# WASM binary exists
ls packages/cell-engine/zig-out/semantos.wasm

# Constants and opcodes exist
ls packages/constants/constants.json
ls packages/cell-ops/src/opcodes.ts

# Protocol types exist
ls packages/protocol-types/src/index.ts

# PDA exists
ls packages/cell-engine/src/pda.zig

# Existing tests pass
bun run check
bun run build
```

All must exist and pass. If anything fails, STOP.

### 0.3 Create Phase 25.5 branch

```bash
git checkout -b phase-25.5-host-function-dispatch
```

---

## Step 1: OP_CALLHOST Opcode in Zig (D25.5.1)

### 1.1 Create `packages/cell-engine/src/opcodes/hostcall.zig`

Implement the OP_CALLHOST opcode handler. Pop the function name from the stack, call `host.callByName()`, push the result (0 or 1) back.

**Pattern**: Follow `opcodes/plexus.zig` structure. Use error handling from executor.zig.

```zig
pub fn executeCallHost(p: *pda_mod.PDA) HostCallError!void {
    // Pop function name string
    // Call host extern
    // Handle 0xFFFFFFFF (unknown function) as error
    // Push result (0 or 1) as script number
}
```

### 1.2 Update `packages/cell-engine/src/executor.zig`

Add the 0xD0 dispatch case in `executeOneOpcode()`:

```zig
// Host function dispatch (0xD0) — Phase 25.5
if (opcode == 0xD0) {
    if (!ctx.executing) return;
    try hostcall.executeCallHost(ctx.pda);
    return;
}
```

**After Plexus (0xC0–0xCF), before returning invalid opcode error.**

### 1.3 Update `packages/cell-engine/src/host.zig`

Add the host extern and wrapper function:

```zig
pub extern "host" fn host_call_by_name(name_ptr: [*]const u8, name_len: u32) u32;

pub fn callByName(name: []const u8) u32 {
    if (comptime is_wasm) {
        return host_call_by_name(name.ptr, @intCast(name.len));
    }
    // Native: no host function registry — always return unknown
    _ = .{name};
    return 0xFFFFFFFF;
}
```

### 1.4 Commit

```bash
git add packages/cell-engine/src/opcodes/hostcall.zig
git add packages/cell-engine/src/executor.zig
git add packages/cell-engine/src/host.zig
git commit -m "phase-25.5/D25.5.1: add OP_CALLHOST (0xD0) opcode dispatch in Zig"
```

---

## Step 2: HostFunctionRegistry in TypeScript (D25.5.2)

### 2.1 Create `packages/cell-engine/bindings/host-functions.ts`

Implement the `HostFunctionRegistry` class:

```typescript
export interface HostFunctionContext {
  [key: string]: unknown;
}

export type HostFunction = (ctx: HostFunctionContext) => number;

export class HostFunctionRegistry {
  private functions: Map<string, HostFunction> = new Map();
  private context: HostFunctionContext = {};

  register(name: string, fn: HostFunction): void {
    this.functions.set(name, fn);
  }

  setContext(ctx: HostFunctionContext): void {
    this.context = Object.freeze({ ...ctx });
  }

  clearContext(): void {
    this.context = {};
  }

  call(name: string): number {
    const fn = this.functions.get(name);
    if (!fn) return 0xFFFFFFFF;
    return fn(this.context);
  }

  has(name: string): boolean {
    return this.functions.has(name);
  }

  list(): string[] {
    return [...this.functions.keys()];
  }
}
```

### 2.2 Wire into WASM loaders

Update `packages/cell-engine/bindings/wasm-loader-bun.ts`, `wasm-loader-node.ts`, and `wasm-loader-browser.ts` to accept and wire a `hostRegistry` parameter:

```typescript
export function createHostFunctions(
  memory: WebAssembly.Memory,
  context: ScriptContext = defaultContext,
  cellStore?: OctaveCellStore,
  hostRegistry?: HostFunctionRegistry,  // ← NEW
): Record<string, Function> {
  const store = cellStore ?? defaultOctaveCellStore;
  return {
    // ... existing crypto host functions ...

    host_call_by_name: (namePtr: number, nameLen: number): number => {
      if (!hostRegistry) return 0xFFFFFFFF;
      const name = new TextDecoder().decode(
        new Uint8Array(memory.buffer, namePtr, nameLen),
      );
      return hostRegistry.call(name);
    },
  };
}
```

### 2.3 Commit

```bash
git add packages/cell-engine/bindings/host-functions.ts
git add packages/cell-engine/bindings/wasm-loader-bun.ts
git add packages/cell-engine/bindings/wasm-loader-node.ts
git add packages/cell-engine/bindings/wasm-loader-browser.ts
git commit -m "phase-25.5/D25.5.2: add HostFunctionRegistry and host_call_by_name dispatch"
```

---

## Step 3: Lisp Compiler Extension (D25.5.3)

### 3.1 Update `packages/shell/src/lisp/types.ts`

Add `HostCallExpr` to the `ConstraintExpr` union:

```typescript
export interface HostCallExpr {
  kind: 'hostCall';
  functionName: string;
}

export type ConstraintExpr =
  | ComparisonExpr
  | LogicalExpr
  | CapabilityExpr
  | DomainCheckExpr
  | TimeConstraintExpr
  | HostCallExpr;
```

### 3.2 Update `packages/shell/src/lisp/compiler.ts`

Add host call compilation in `compileConstraint()`:

```typescript
const OP_CALLHOST = 0xD0;

case 'hostCall': {
  // (call-host "name") or (predicate?) → push "name" OP_CALLHOST
  const nameBytes = [...encodePushString(expr.functionName)];
  return {
    words: [`"${expr.functionName}" OP_CALLHOST`],
    bytes: [...nameBytes, OP_CALLHOST],
  };
}
```

### 3.3 Update `packages/shell/src/lisp/compiler.ts` interpretation

In `interpretConstraint()`, add two cases:

```typescript
// (call-host "function-name")
if (op === 'call-host') {
  if (expr.elements.length !== 2) {
    throw new Error(`'call-host' requires exactly 1 argument`);
  }
  const nameAtom = expr.elements[1];
  if (nameAtom.type !== 'atom' || nameAtom.kind !== 'string') {
    throw new Error(`Expected string argument to call-host`);
  }
  return { kind: 'hostCall', functionName: nameAtom.value as string };
}

// Zero-arity sugar: (predicate?) → host call
// Symbols ending in '?' that are not known built-in operators
if (op.endsWith('?') && expr.elements.length === 1) {
  return { kind: 'hostCall', functionName: op };
}
```

### 3.4 Commit

```bash
git add packages/shell/src/lisp/types.ts
git add packages/shell/src/lisp/compiler.ts
git commit -m "phase-25.5/D25.5.3: add HostCallExpr type and compiler support for OP_CALLHOST"
```

---

## Step 4: Constants Update (D25.5.4)

### 4.1 Update `packages/constants/constants.json`

Add opcode ranges and the OP_CALLHOST opcode:

```json
{
  "opcodeRanges": {
    "hostCallMin": 208,
    "hostCallMax": 223
  },
  "opcodes": {
    "OP_CALLHOST": 208
  }
}
```

### 4.2 Regenerate Zig constants

Run the generate-constants script:

```bash
cd packages/cell-engine/src
node scripts/generate-constants.js
```

This updates `packages/cell-engine/src/constants.zig` with:

```zig
pub const OPCODE_HOST_CALL_MIN: u8 = 208;
pub const OPCODE_HOST_CALL_MAX: u8 = 223;
```

### 4.3 Update `packages/cell-ops/src/opcodes.ts`

Add to the Opcode enum:

```typescript
OP_CALLHOST = 0xd0,  // Pop function name, dispatch to registered host function
```

### 4.4 Commit

```bash
git add packages/constants/constants.json
git add packages/cell-engine/src/constants.zig
git add packages/cell-ops/src/opcodes.ts
git commit -m "phase-25.5/D25.5.4: add OP_CALLHOST (0xD0) to constants and opcodes"
```

---

## Step 5: Built-in Host Functions (D25.5.5)

### 5.1 Create `packages/cell-engine/bindings/builtin-host-functions.ts`

Implement generic field-accessor and capability-check functions:

```typescript
export function registerBuiltinHostFunctions(registry: HostFunctionRegistry): void {
  // field-eq?: compare context.fields[fieldName] === context.expectedValue
  registry.register('field-eq?', (ctx: HostFunctionContext): number => {
    const field = ctx._currentField as string;
    const expected = ctx._currentValue;
    const fields = ctx.fields as Record<string, unknown> | undefined;
    if (!fields || !(field in fields)) return 0;
    return fields[field] === expected ? 1 : 0;
  });

  // field-gt?, field-lt?, has-capability? follow similar pattern
  // See implementation for full details
}
```

**Built-in functions:**
- `field-eq?(ctx._currentField, ctx._currentValue)` — equality check on a named field
- `field-gt?(ctx._currentField, ctx._currentValue)` — greater-than on a numeric field
- `field-lt?(ctx._currentField, ctx._currentValue)` — less-than on a numeric field
- `has-capability?(ctx._currentValue)` — check if identity holds a capability number

### 5.2 Update `packages/cell-engine/bindings/index.ts`

Export the registration function:

```typescript
export { registerBuiltinHostFunctions } from './builtin-host-functions';
```

### 5.3 Commit

```bash
git add packages/cell-engine/bindings/builtin-host-functions.ts
git add packages/cell-engine/bindings/index.ts
git commit -m "phase-25.5/D25.5.5: add built-in host functions (field-eq?, field-gt?, field-lt?, has-capability?)"
```

---

## Step 6: Gate Tests (T1–T5)

Create `packages/__tests__/phase25.5-gate.test.ts` with comprehensive tests:

### T1: OP_CALLHOST opcode dispatch
- Test that `push "test-fn" OP_CALLHOST` pops the name, dispatches, and pushes result

### T2: HostFunctionRegistry
- `register()`, `call()`, `has()`, `list()` all work correctly
- `setContext()` freezes the object (attempting mutation throws)
- `clearContext()` empties the context
- Unknown function returns 0xFFFFFFFF sentinel

### T3: Lisp compiler
- `(call-host "field-eq?")` compiles to `push "field-eq?" 0xD0`
- `(diagonal-path?)` (zero-arity sugar) compiles to `push "diagonal-path?" 0xD0`
- Existing compiler behavior unchanged (backward compat)

### T4: WASM integration
- OP_CALLHOST dispatches through `host_call_by_name` host extern
- Context is passed correctly from TypeScript to Zig
- Registry integration with Bun/Node/browser loaders

### T5: Built-in host functions
- `field-eq?` checks field equality
- `field-gt?` and `field-lt?` perform numeric comparisons
- `has-capability?` checks capability membership
- All functions return 0 or 1 (falsy/truthy)

**Gate test must pass before proceeding.**

```bash
bun test packages/__tests__/phase25.5-gate.test.ts
```

### Commit

```bash
git add packages/__tests__/phase25.5-gate.test.ts
git commit -m "phase-25.5/gate: T1–T5 gate tests — opcode dispatch, registry, compiler, integration, built-ins"
```

---

## Step 7: Errata Sprint

Review implementation for:
- WASM binary size under 32KB
- No regressions in existing tests
- Backward compatibility (Phase 0–24 scripts unchanged)
- No stubs, no "NOT_IMPLEMENTED"

```bash
bun run build
bun run check
bun test  # all tests, all phases
```

If issues found, fix and create new commits with `phase-25.5/errata: description`.

---

## Completion Criteria

- [ ] OP_CALLHOST (0xD0) opcode implemented in Zig
- [ ] `host_call_by_name` extern added to host.zig
- [ ] Executor dispatches 0xD0 to hostcall module
- [ ] HostFunctionRegistry class with register/call/setContext/clearContext/has/list
- [ ] Context frozen via Object.freeze()
- [ ] WASM loaders wire hostRegistry into createHostFunctions
- [ ] HostCallExpr added to Lisp ConstraintExpr union
- [ ] Compiler interprets (call-host "name") and (predicate?) sugar
- [ ] Compiler compiles host calls to push name + 0xD0
- [ ] Constants.json updated with opcode ranges
- [ ] Zig constants regenerated (OPCODE_HOST_CALL_MIN/MAX)
- [ ] Opcode enum includes OP_CALLHOST
- [ ] Built-in host functions: field-eq?, field-gt?, field-lt?, has-capability?
- [ ] All gate tests (T1–T5) pass
- [ ] WASM binary under 32KB
- [ ] Backward compatibility verified
- [ ] All existing phase tests still pass

---

## What NOT to Do

1. **Do not add new opcodes beyond 0xD0.** 0xD1–0xDF are reserved.
2. **Do not make the host function registry global/mutable during execution.** Freeze the context at setContext time.
3. **Do not add domain-specific predicates in Phase 25.5.** That's Phases 26–29.
4. **Do not modify the cell engine's stack behavior.** OP_CALLHOST pops ONE item (the name). Inputs come from frozen context, not stack.
5. **Do not implement runtime validation in the compiler.** The compiler doesn't check whether a function is registered. The runtime does.
6. **Do not change the WASM binary size budget.** Stay under 32KB.
7. **Do not break backward compatibility.** Existing scripts must work unchanged.
8. **Do not add stubs or "TODO" placeholders.** Every function must be complete and tested.

---

## Status: COMPLETE

This phase has been implemented and merged into main. This documentation is retroactive and covers the completed work.

**Related phases:**
- Phase 25.0–25.4: Prerequisite work (compiler, constants, etc.)
- Phase 26–29: Domain packages that use OP_CALLHOST to register domain-specific predicates

**Important note on file naming:** The HostFunctionRegistry lives in `packages/cell-engine/bindings/host-functions.ts`, NOT in a separate `host-function-registry.ts` file. Later phase PRDs may reference `host-function-registry.ts` — use `host-functions.ts` instead.
