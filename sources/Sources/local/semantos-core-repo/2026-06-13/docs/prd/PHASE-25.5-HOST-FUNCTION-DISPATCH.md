---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-25.5-HOST-FUNCTION-DISPATCH.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.709464+00:00
---

# Phase 25.5 — Host Function Dispatch

**Version**: 1.0
**Date**: March 2026
**Status**: COMPLETE — implemented and merged via phase-25-combined
**Duration**: 1 week
**Prerequisites**: Phase 25 core (OP_LOADFIELD, OP_PICKFIELD, OP_ARRAY_* opcodes). Phase 21 (Lisp compiler) for HostCallExpr AST node.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + commercial context.
**Branch**: `phase-25.5-host-function-dispatch`

---

## Context

Host function dispatch is the bridge between script-world (Forth-like cell engine) and host-world (TypeScript runtime functions). A script can evaluate a predicate like `(has-capability?)` or `(field-eq?)` without hardcoding those checks in the Forth bytecode. Instead, it invokes a host function by name.

This phase adds:

1. **OP_CALLHOST (0xD0) opcode** — pops a function name string from the main stack, calls the host registry, pushes a boolean result
2. **HostFunctionRegistry class** — TypeScript runtime manages named host functions, provides context (Object.freeze'd), allows domain phases to register custom predicates
3. **Built-in host functions** — field-eq?, field-gt?, field-lt?, has-capability?
4. **Lisp compiler support** — `(diagonal-path?)` and similar forms compile to `push "diagonal-path?" OP_CALLHOST`
5. **Opcode allocation** — 0xD0 reserved, 0xD1-0xDF reserved for future, keeps WASM under 32KB

This is NOT a general RPC layer. Host functions are deterministic, evaluation-context-aware, and cannot modify state. They read from a frozen context object set before script execution.

---

## Source Files Table

| Alias | Path | What to extract |
|-------|------|----------------|
| EXEC:MAIN | packages/cell-engine/src/executor.zig | Main opcode dispatch loop — 0xD0 case calls `hostcall.executeCallHost(ctx.pda)` |
| EXEC:HOSTCALL | packages/cell-engine/src/opcodes/hostcall.zig | OP_CALLHOST handler — pops string from main stack, calls `host.callByName(name)`, pushes result (0 or 1) |
| EXEC:PLEXUS | packages/cell-engine/src/opcodes/plexus.zig | Reference pattern for custom opcode handlers |
| HOST:ZIG | packages/cell-engine/src/host.zig | extern host_call_by_name, WASM bridge declaration |
| HOST:TS | packages/cell-engine/bindings/host-functions.ts | HostFunctionRegistry class (register, setContext, clearContext, call, has, list methods) |
| HOST:BUILTIN | packages/cell-engine/bindings/builtin-host-functions.ts | Built-in predicates: field-eq?, field-gt?, field-lt?, has-capability? |
| LISP:COMPILER | packages/shell/src/lisp/compiler.ts | OP_CALLHOST = 0xD0 constant, HostCallExpr compilation (push name, OP_CALLHOST) |
| LISP:TYPES | packages/shell/src/lisp/types.ts | HostCallExpr type in ConstraintExpr union, compound form support (sensor-reading, etc.) |
| CONST:ALL | packages/constants/constants.json | "OP_CALLHOST": 208 |
| OPS:ENUM | packages/cell-ops/src/opcodes.ts | Opcode enum OP_CALLHOST = 0xd0 |

---

## Deliverables

### D25.5.1 — OP_CALLHOST Opcode (0xD0) in Zig

**File**: `packages/cell-engine/src/opcodes/hostcall.zig`

The OP_CALLHOST opcode handler:

- **Opcode number**: 0xD0 (208 decimal)
- **Stack operation**:
  - Pops a string (function name) from the main stack
  - Calls `host.callByName(name)` with the current evaluation context
  - Pushes the result (0 for false/unknown, 1 for true) back to main stack
- **Error handling**:
  - If stack is empty → return error (invalid script)
  - If host returns 0xFFFFFFFF → means function not found, still pushes 0 to stack
  - If evaluation context is not set → return error
- **Zig signature**:
  ```zig
  pub fn executeCallHost(pda: *PDA) PDAError!void {
      const name = try pda.pop_string();
      const result = try host.callByName(name, pda.context);
      try pda.push_u32(if (result == 0xFFFFFFFF) 0 else result);
  }
  ```
- **Performance**: Single opcode dispatch, no memory allocation, deterministic
- **Compatibility**: Works with both linear and affine stacks, respects linearity constraints

---

### D25.5.2 — Executor Integration (0xD0 Dispatch)

**File**: `packages/cell-engine/src/executor.zig` — Main opcode dispatch loop

The executor's main loop must dispatch 0xD0:

```zig
switch (opcode) {
    // ... existing opcodes (0x00-0xCF) ...
    0xD0 => {
        // OP_CALLHOST
        try hostcall.executeCallHost(ctx.pda);
    },
    // 0xD1-0xDF reserved
    else => return error.UnknownOpcode,
}
```

- **Guard**: Confirm 0xD0 reaches hostcall handler, not standard Bitcoin Script fallback
- **Context passing**: Executor's context struct (with evaluation context) is accessible to hostcall
- **No side effects**: Host functions cannot modify PDA state except stack push/pop
- **WASM boundary**: Calls into TypeScript via `host_call_by_name` WASM import

---

### D25.5.3 — Host Call WASM Bridge

**File**: `packages/cell-engine/src/host.zig`

Zig extern declaration for the host call:

```zig
extern "env" fn host_call_by_name(name_ptr: u32, name_len: u32, context_ptr: u32, context_len: u32) u32;

pub fn callByName(name: []const u8, context: ?*const EvaluationContext) HostError!u32 {
    if (context == null) return error.NoEvaluationContext;

    const name_ptr = @ptrToInt(name.ptr);
    const name_len = name.len;
    const context_ptr = @ptrToInt(context);
    const context_len = @sizeOf(EvaluationContext);

    const result = host_call_by_name(name_ptr, name_len, context_ptr, context_len);
    return result;
}
```

- **Calling convention**: Pass name as (pointer, length) and context pointer separately
- **Return value**: 0 = false, 1 = true, 0xFFFFFFFF = function not found
- **Deterministic**: Same name + context always produces same result
- **No state modification**: Host function cannot reach back into Zig to mutate PDA or heap

---

### D25.5.4 — HostFunctionRegistry (TypeScript)

**File**: `packages/cell-engine/bindings/host-functions.ts`

The TypeScript registry that backs host function dispatch:

```typescript
export class HostFunctionRegistry {
  private functions: Map<string, (context: EvaluationContext) => boolean>;
  private context: EvaluationContext | null = null;

  register(name: string, fn: (context: EvaluationContext) => boolean): void {
    this.functions.set(name, fn);
  }

  setContext(ctx: EvaluationContext): void {
    this.context = Object.freeze({ ...ctx });
  }

  clearContext(): void {
    this.context = null;
  }

  call(name: string): boolean {
    if (!this.context) throw new Error('Evaluation context not set');
    const fn = this.functions.get(name);
    if (!fn) return false; // Unknown function → 0xFFFFFFFF → pushed as 0
    return fn(this.context);
  }

  has(name: string): boolean {
    return this.functions.has(name);
  }

  list(): string[] {
    return Array.from(this.functions.keys());
  }
}

// WASM export bridge
export function host_call_by_name(namePtr: number, nameLen: number, contextPtr: number, contextLen: number): number {
  const memory = new Uint8Array(wasmExports.memory.buffer);
  const name = new TextDecoder().decode(memory.slice(namePtr, namePtr + nameLen));
  // context is read from WASM memory if needed
  return globalRegistry.call(name) ? 1 : 0;
}
```

**Methods**:
- `register(name, fn)` — Add a host function to the registry
- `setContext(ctx)` — Freeze and set evaluation context before script execution
- `clearContext()` — Clear context after script execution
- `call(name)` — Look up and invoke a host function
- `has(name)` — Check if a function is registered
- `list()` — Get all registered function names

**Key property**:
- Context is `Object.freeze()`'d immediately after `setContext()` — immutable during evaluation
- Functions are pure: given the same name and context, always return the same boolean
- No async functions, no I/O, no external lookups

---

### D25.5.5 — Built-in Host Functions

**File**: `packages/cell-engine/bindings/builtin-host-functions.ts`

Bootstrap the registry with domain-agnostic predicates:

```typescript
export function registerBuiltinHostFunctions(registry: HostFunctionRegistry): void {
  // field-eq?: compare a typed field to a literal value
  registry.register('field-eq?', (ctx: EvaluationContext) => {
    const field = ctx.field;
    const expectedValue = ctx._currentArg;
    if (!field || expectedValue === undefined) return false;
    return field === expectedValue;
  });

  // field-gt?: compare a numeric field to a threshold
  registry.register('field-gt?', (ctx: EvaluationContext) => {
    const field = parseFloat(ctx.field as any);
    const threshold = parseFloat(ctx._currentArg as any);
    if (isNaN(field) || isNaN(threshold)) return false;
    return field > threshold;
  });

  // field-lt?: compare a numeric field to a threshold
  registry.register('field-lt?', (ctx: EvaluationContext) => {
    const field = parseFloat(ctx.field as any);
    const threshold = parseFloat(ctx._currentArg as any);
    if (isNaN(field) || isNaN(threshold)) return false;
    return field < threshold;
  });

  // has-capability?: check if evaluation context has a specific capability number
  registry.register('has-capability?', (ctx: EvaluationContext) => {
    const capNum = ctx._currentArg;
    if (typeof capNum !== 'number') return false;
    return ctx.capabilities?.includes(capNum) ?? false;
  });
}
```

**Design principles**:
- Functions are **stateless** — they read from context only
- Functions are **domain-agnostic** — they don't know about specific business logic
- Functions are **composable** — Lisp compiler chains them with AND/OR
- Functions are **registerable** — domain phases (26-29) call `registry.register()` to add custom predicates
- Exception: Compound forms like `(sensor-reading "PT-101")` push the sensor ID to context key `_currentArg` before calling the host function

---

### D25.5.6 — Lisp Compiler Extension

**File**: `packages/shell/src/lisp/compiler.ts`

Extend the Lisp compiler to handle HostCallExpr:

**Constant**:
```typescript
export const OP_CALLHOST = 0xD0;
```

**Compilation**:
```typescript
case 'hostCall': {
  const expr = expression as HostCallExpr;
  // For simple predicates: push the name, call OP_CALLHOST
  // e.g., (diagonal-path?) → push "diagonal-path?" OP_CALLHOST

  // For compound forms: set _currentArg context, then call
  // e.g., (sensor-reading "PT-101") → push "PT-101" to context, push "sensor-reading?" OP_CALLHOST

  let forthWords: string[] = [];

  if (expr.args && expr.args.length > 0) {
    // Compound form: (sensor-reading "PT-101")
    const arg = compileExpression(expr.args[0]);
    forthWords.push(`${arg} _CONTEXT_ARG SET`); // Set _currentArg
  }

  forthWords.push(`"${expr.name}" OP_CALLHOST`);
  return forthWords;
}
```

**AST Node** (from `packages/shell/src/lisp/types.ts`):
```typescript
interface HostCallExpr {
  type: 'hostCall';
  name: string;               // "diagonal-path?"
  args?: SExpression[];       // optional arguments for context
}
```

This becomes a case in the `ConstraintExpr` union:
```typescript
type ConstraintExpr =
  | ComparisonExpr
  | LogicalExpr
  | CapabilityExpr
  | DomainCheckExpr
  | TimeConstraintExpr
  | HostCallExpr;             // NEW
```

---

### D25.5.7 — Opcode Allocation Table

**File**: `packages/constants/constants.json` + `packages/cell-ops/src/opcodes.ts`

Update opcode constants:

```json
{
  "OP_CALLHOST": 208,
  "OP_CALLHOST_HEX": "0xd0"
}
```

```typescript
export enum Opcode {
  // ... 0x00-0xAF: Bitcoin Script standard ...
  // ... 0xB0-0xBF: Craig macros + LOADFIELD ...
  // ... 0xC0-0xCF: Plexus type enforcement ...

  OP_CALLHOST = 0xd0,  // 208 — Host function dispatch
  // 0xD1-0xDF RESERVED for future host-related opcodes

  // ... 0xE0-0xFF: Unallocated ...
}
```

**Allocation map**:
```
0x00-0xAF (0-175):    Bitcoin Script standard
0xB0-0xBF (176-191):  Craig macros + LOADFIELD
0xC0-0xCF (192-207):  Plexus type enforcement + custom opcodes
0xD0 (208):           OP_CALLHOST — Host function dispatch
0xD1-0xDF (209-223):  RESERVED
0xE0-0xFF (224-255):  Unallocated for future phases
```

**WASM footprint**: All opcodes fit in 32KB without compression.

---

## TDD Gate Tests

### Unit Tests (T1–T8)

- **T1**: `hostcall.executeCallHost()` pops a string from main stack without error
- **T2**: `hostcall.executeCallHost()` calls `host.callByName()` with the popped string
- **T3**: `hostcall.executeCallHost()` pushes the result (0 or 1) to the main stack
- **T4**: If stack is empty before pop, `executeCallHost()` returns error
- **T5**: If host function not found (result = 0xFFFFFFFF), stack receives 0
- **T6**: `HostFunctionRegistry.register()` adds a function to the registry
- **T7**: `HostFunctionRegistry.call()` retrieves and invokes the registered function
- **T8**: `HostFunctionRegistry.setContext()` freezes the context (Object.freeze() applied)

### Integration Tests (T9–T15)

- **T9**: Executor 0xD0 case dispatches to `hostcall.executeCallHost()` (not to standard script handler)
- **T10**: `field-eq?` built-in function returns true when field matches _currentArg
- **T11**: `field-gt?` built-in function returns true when field > _currentArg (numeric)
- **T12**: `field-lt?` built-in function returns true when field < _currentArg (numeric)
- **T13**: `has-capability?` built-in function returns true when capability is in context.capabilities
- **T14**: Lisp compiler emits correct Forth for `(diagonal-path?)` → `"diagonal-path?" OP_CALLHOST`
- **T15**: Lisp compiler emits correct Forth for compound form `(sensor-reading "PT-101")` (context setup + host call)

### Round-Trip Tests (T16–T18)

- **T16**: Parse → Compile → Execute: `(diagonal-path?)` evaluates correctly with host function
- **T17**: Registry context freezing prevents modification during script execution
- **T18**: Opcode 0xD0 is reserved in enum, 0xD1-0xDF are reserved (not assigned to other opcodes)

### Anti-Lock Tests (T19–T21)

- **T19**: WASM binary size remains < 32KB after adding OP_CALLHOST
- **T20**: Host functions have NO async, NO I/O, NO mutable state (pure functions only)
- **T21**: Registry can be extended by domain phases without modifying cell engine (open/closed principle)

---

## Completion Criteria

- [ ] `packages/cell-engine/src/opcodes/hostcall.zig` exists with `executeCallHost()` handler
- [ ] `packages/cell-engine/src/executor.zig` dispatches 0xD0 to hostcall
- [ ] `packages/cell-engine/src/host.zig` declares `host_call_by_name` extern
- [ ] `packages/cell-engine/bindings/host-functions.ts` exists with `HostFunctionRegistry` class
- [ ] `packages/cell-engine/bindings/builtin-host-functions.ts` exists with field-eq?, field-gt?, field-lt?, has-capability?
- [ ] `packages/shell/src/lisp/compiler.ts` has OP_CALLHOST constant and HostCallExpr compilation
- [ ] `packages/shell/src/lisp/types.ts` has HostCallExpr in ConstraintExpr union
- [ ] `packages/constants/constants.json` has "OP_CALLHOST": 208
- [ ] `packages/cell-ops/src/opcodes.ts` has OP_CALLHOST = 0xd0
- [ ] Built-in host functions are registered at runtime
- [ ] Tests T1–T21 all pass
- [ ] WASM binary stays under 32KB
- [ ] `bun run check` passes (no type errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-25.5/D25.5.N:` prefix
- [ ] Branch is `phase-25.5-host-function-dispatch`
- [ ] Errata sprint complete with `docs/prd/PHASE-25.5-ERRATA.md` if needed

---

## What NOT to Do

1. **Do NOT implement a general RPC layer.** Host functions are deterministic predicates only, not a remote execution framework.
2. **Do NOT allow host functions to modify state.** No PDA mutations, no global state changes, no side effects.
3. **Do NOT implement async host functions.** Evaluation must be deterministic and immediate.
4. **Do NOT bypass opcode allocation.** 0xD0 is the ONLY opcode for host calls; 0xD1-0xDF are reserved.
5. **Do NOT hardcode domain-specific predicates in the cell engine.** The cell engine only knows about field-eq?, field-gt?, field-lt?, has-capability?. Domain phases (26-29) register their own.
6. **Do NOT allow context to be mutable after setContext().** Object.freeze() is non-negotiable.
7. **Do NOT reuse opcode numbers.** 0xD0 is committed and cannot be reused by future phases.
8. **Do NOT implement natural language parsing for host function names.** That is a future LLM concern, not this phase.
9. **Do NOT increase the WASM binary size beyond 32KB.** Monitor binary size during development.

---

## Design Decisions

**Zero-arity core, context-based arguments**:
- Host functions are called with zero stack arguments
- All "parameters" come from the frozen evaluation context
- Compound forms like `(sensor-reading "PT-101")` set `_currentArg` context key before calling the host function
- This keeps the stack machine simple and matches Forth idioms (words read from context, not stack)

**One opcode only (0xD0)**:
- Future host-related operations (if any) will use different opcodes or be implemented as macros
- Keeps the design simple and the opcode space organized

**Determinism requirement**:
- Host functions cannot call external APIs, spawn threads, or read non-deterministic state
- Same input (name + frozen context) always produces same boolean output
- This enables script caching and deterministic execution guarantees

**Open/closed principle**:
- Cell engine does NOT know about domain-specific predicates (sensor-reading?, approval-required?, etc.)
- Domain phases (26-29) call `registry.register()` to add their own
- No modification to cell engine needed when adding new domain predicates

---

## What Comes After

After Phase 25.5:

1. **Phase 26** (Game Engine SDK) registers game-specific predicates: `(tile-occupied?)`, `(is-player?)`, etc.
2. **Phase 27** (Simple Games) builds playable games using the predicate dispatch layer
3. **Phase 28** (ISDA CDM) registers financial predicates: `(contract-active?)`, `(settlement-due?)`, etc.
4. **Phase 29** (SCADA) registers industrial predicates: `(sensor-reading?)`, `(threshold-exceeded?)`, etc.

Each domain phase independently extends the host function registry. The cell engine never changes.

---

## References

- **SEMANTOS_ZIG_WASM_PRD.md** — Core architecture and opcode space
- **PHASE-25-PROMPT.md** — Original phase 25 requirements (OP_LOADFIELD, OP_PICKFIELD, OP_ARRAY_*)
- **PHASE-21-LISP-AXIOM-COMPILER.md** — Lisp compiler design (ConstraintExpr types, compilation flow)
- **COMMERCIAL-CONTEXT.md** — Product vision and use cases
