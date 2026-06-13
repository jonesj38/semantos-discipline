---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-25.5-SWEEP-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.660350+00:00
---

# Phase 25.5 Sweep Prompt — 2PDA + CALLHOST Consistency

> Paste this prompt into a fresh session to execute the Phase 25.5 sweep — a documentation-only fix of Phases 26–29 PRDs and execution prompts to properly reference the OP_CALLHOST infrastructure that Phase 25.5 added.

---

## Context

Phase 25.5 added two critical components:
1. **OP_CALLHOST (0xD0) opcode** in the Zig cell engine — a generic dispatch mechanism for host functions
2. **HostFunctionRegistry class** in TypeScript — manages named predicates that the cell engine invokes without modifying bytecode

Phase 25.5 was completed and merged. However, Phases 26–29 PRDs and execution prompts were written before Phase 25.5 was fully specified. These documents contain:

- **Wrong file paths** — referencing `src/host-function-registry.ts` instead of `packages/cell-engine/bindings/host-functions.ts`
- **Missing source file references** — failure to document `builtin-host-functions.ts` where domain-specific predicates are registered
- **Fictional opcodes in compression gradients** — e.g., `RARITY-EQ` instead of actual opcode sequences ending in `OP_CALLHOST`
- **Multi-arity predicates** — e.g., `(diagonal-path? from to)` instead of zero-arity `(diagonal-path?)` with args passed via _currentArg convention
- **Unclear host function registration patterns** — missing instructions on where/how to register domain-specific predicates

This sweep is **DOCUMENTATION ONLY**. No code changes. No new implementations. Only corrections to existing PRDs and prompts to reflect the actual Phase 25.5 architecture.

---

## ANTI-BULLSHIT RULES

### Rule 1: HOST FUNCTIONS FILE PATH
**Correct path**: `packages/cell-engine/bindings/host-functions.ts`

Contains the `HostFunctionRegistry` class with methods:
- `register(name: string, fn: (context: EvaluationContext) => boolean): void`
- `setContext(ctx: EvaluationContext): void`
- `clearContext(): void`
- `call(name: string): boolean`
- `has(name: string): boolean`
- `list(): string[]`

**Wrong paths** (find and replace):
- `src/host-function-registry.ts` → `packages/cell-engine/bindings/host-functions.ts`
- `packages/cell-engine/src/host-function-registry.ts` → `packages/cell-engine/bindings/host-functions.ts`
- `host-function-registry.ts` without full path → always expand to `packages/cell-engine/bindings/host-functions.ts`

### Rule 2: BUILTIN HOST FUNCTIONS
**Correct path**: `packages/cell-engine/bindings/builtin-host-functions.ts`

Contains built-in predicates registered at initialization:
- `field-eq?(context) → checks field equality`
- `field-gt?(context) → checks field greater-than`
- `field-lt?(context) → checks field less-than`
- `has-capability?(context) → checks capability presence`

This file is the **pattern** for registering domain-specific predicates in domain packages (e.g., `packages/games/src/host-functions.ts`, `packages/cdm/src/host-functions.ts`).

### Rule 3: ZERO-ARITY PREDICATES ONLY
Host function predicates in Lisp MUST be zero-arity. Arguments flow through the _currentArg convention or via the evaluation context (frozen before script execution).

**CORRECT**:
```lisp
(diagonal-path?)              ; zero-arity, compiles to push "diagonal-path?" OP_CALLHOST
(sensor-reading)              ; zero-arity, reads from context
(= (sensor-reading) 100)      ; sensor-reading is zero-arity
```

**INCORRECT** (find and fix):
```lisp
(diagonal-path? from to)      ; multi-arity — WRONG
(sensor-reading "PT-101")     ; looks like multi-arity — needs to be (sensor-reading) with PT-101 in context
(path-clear? from to board)   ; multi-arity — WRONG
```

**Exception** — Compound forms that pass literals through _currentArg:
```lisp
(sensor-reading "PT-101")     ; OK if the host function reads _currentArg for the string argument
```

The distinction: bare predicates ending in `?` are zero-arity. Compound forms like `(constraint-check "some-id")` still compile to `push "some-id" push "constraint-check" OP_CALLHOST` and the host function reads the stack or context.

### Rule 4: NO FICTIONAL OPCODES
Compression gradients and opcode sequences must use REAL opcodes from `packages/cell-ops/src/opcodes.ts`:
```typescript
OP_CALLHOST = 0xd0
OP_PUSH = 0x4c
OP_EQUAL = 0x87
OP_AND = 0x9a
// etc.
```

**INCORRECT** (find and fix):
```
RARITY-EQ
DIAGONAL-PATH
SENSOR-QUALITY-CHECK
```

These are NOT opcodes. They are pseudo-names. Replace with actual opcode sequences. Example:

**BEFORE**:
```
Compression gradient: DIAGONAL-PATH (opcode 0xE0 reserved for domain games)
```

**AFTER**:
```
Compression gradient: diagonal-path host function dispatch
  - Lisp: (diagonal-path?)
  - Compiles to: push "diagonal-path?" OP_CALLHOST (0xd0)
  - Runtime: HostFunctionRegistry.call("diagonal-path?")
  - Returns: 0 (false) or 1 (true) to main stack
```

### Rule 5: HOST FUNCTION REGISTRATION INSTRUCTIONS
Every phase PRD that uses host functions MUST include explicit registration pattern. Example:

**Pattern A — In phase PRD D.N section**:
```markdown
### Host Function Registration Pattern

Register chess-domain predicates with `HostFunctionRegistry`:

**File**: `packages/games/src/host-functions.ts` (new)

```typescript
import { HostFunctionRegistry } from 'packages/cell-engine/bindings/host-functions';
import { EvaluationContext } from 'packages/protocol-types';

export function registerChessHostFunctions(registry: HostFunctionRegistry): void {
  registry.register('diagonal-path?', (context: EvaluationContext) => {
    // fromSquare, toSquare, board state in context
    const from = context.state?.from;
    const to = context.state?.to;
    const dx = Math.abs(from.x - to.x);
    const dy = Math.abs(from.y - to.y);
    return dx === dy; // diagonal movement
  });

  registry.register('path-clear?', (context: EvaluationContext) => {
    // Check if path from square to square has no pieces in between
    const from = context.state?.from;
    const to = context.state?.to;
    const board = context.state?.board;
    // ... path-clear logic ...
    return true; // or false
  });
}
```

Call this during SDK initialization:
```typescript
import { registerChessHostFunctions } from 'packages/games/src/host-functions';

const gameEngine = new GameCellEngine();
registerChessHostFunctions(gameEngine.hostRegistry);
```
```

### Rule 6: SOURCE FILE TABLES MUST BE COMPLETE
Every phase PRD source file table must include:
- `HOST:REGISTRY` → `packages/cell-engine/bindings/host-functions.ts`
- `HOST:BUILTIN` → `packages/cell-engine/bindings/builtin-host-functions.ts`
- Domain-specific registration file → e.g., `packages/games/src/host-functions.ts` (for Phase 27)

---

## Execution Steps

Each step targets one defect category. For each step, provide BEFORE and AFTER excerpts with exact file paths.

### Step 1: Fix source file tables in Phase 27, 28, 29 PRDs

**Files to fix**:
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-27-SIMPLE-GAMES.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-28-ISDA-CDM.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-29-SCADA.md`

**Action**: Add `HOST:BUILTIN` row to each source file table. These tables already reference `HOST:REGISTRY` (which is correct). Verify the path is `bindings/host-functions.ts` (not `src/`). Add the `HOST:BUILTIN` row referencing `packages/cell-engine/bindings/builtin-host-functions.ts`.

**Example BEFORE** (Phase 27 source file table, truncated):
```markdown
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-function-registry.ts` | HostFunctionRegistry — register chess/Go predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |
```

**Example AFTER**:
```markdown
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | HostFunctionRegistry — register chess/Go predicates |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in predicates — pattern for domain predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |
```

### Step 2: Fix wrong paths in Phase 28 and Phase 29 PROMPT files

**Files to fix**:
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-28-PROMPT.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-29-PROMPT.md`

**Action**: Find all references to `packages/cell-engine/src/host-function-registry.ts` and replace with `packages/cell-engine/bindings/host-functions.ts`. Find references to `host-function-registry.ts` (without path) and replace.

**Example BEFORE** (Phase 29 PROMPT, line 44):
```markdown
- `packages/cell-engine/src/host-function-registry.ts` — HostFunctionRegistry (register SCADA-domain predicates here: `sensor-reading`, `sensor-quality`, `has-dual-authorization`)
```

**Example AFTER**:
```markdown
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry (register SCADA-domain predicates here: `sensor-reading`, `sensor-quality`, `has-dual-authorization`)
```

### Step 3: Add explicit host function registration instructions to Phase 27 and Phase 29 PRDs

**Files to fix**:
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-27-SIMPLE-GAMES.md` — D27.3 or D27.4
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-29-SCADA.md` — D29.5 or D29.6

**Action**: Add a new subsection (or extend existing D.N section) with the host function registration pattern. Use the template from Rule 5 above. For Phase 27, show chess predicates (`diagonal-path?`, `path-clear?`, `piece-type?`). For Phase 29, show SCADA predicates (`sensor-reading`, `sensor-quality`, `has-dual-authorization`).

**Insert location** (Phase 27): After D27.2 (entity creation), add "### Host Function Registration Pattern" subsection showing chess-domain predicates.

**Insert location** (Phase 29): After D29.4 (Lisp policy compilation), add "### Host Function Registration Pattern" subsection showing SCADA-domain predicates.

### Step 4: Fix Phase 29 multi-arity predicates

**File to fix**:
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-29-SCADA.md`

**Action**: Scan D29.5 (Lisp policy system) for multi-arity predicate examples. Find patterns like `(sensor-reading "PT-101")` or `(has-dual-authorization role)` and explain the _currentArg convention. Clarify that these compile to stack-based opcode sequences, not to multi-arity function calls.

**Example BEFORE**:
```markdown
Sensor predicates like `(sensor-reading "PT-101")` read the current telemetry value.
```

**Example AFTER**:
```markdown
Sensor predicates like `(sensor-reading "PT-101")` use the _currentArg convention:
- Lisp form: `(sensor-reading "PT-101")`
- Compiles to: `push "PT-101" push "sensor-reading" OP_CALLHOST`
- Runtime: Host function reads "PT-101" from main stack (via _currentArg), looks up sensor, returns 0/1

Zero-arity form `(sensor-reading)` expects sensor ID in the evaluation context:
- Lisp form: `(sensor-reading)`
- Compiles to: `push "sensor-reading" OP_CALLHOST`
- Runtime: Host function reads context.sensorId, looks up sensor, returns 0/1

Both patterns are correct depending on whether the sensor ID is a literal or dynamic.
```

### Step 5: Fix compression gradients in Phase 26, 27, 28, 29 PRDs

**Files to fix**:
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-26-GAME-ENGINE-SDK.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-27-SIMPLE-GAMES.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-28-ISDA-CDM.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-29-SCADA.md`

**Action**: Scan each PRD for "compression gradient" sections or opcode sequence examples. Find fictional opcode names (RARITY-EQ, DIAGONAL-PATH, SENSOR-QUALITY-CHECK, etc.) and replace with actual OP_CALLHOST patterns.

**Example BEFORE**:
```markdown
### Compression Gradient — Game Move Legality

| Constraint | Opcode Sequence |
|---|---|
| Bishop diagonal | DIAGONAL-PATH (reserved 0xE0) |
| Path clear | PATH-CLEAR (reserved 0xE1) |
| Piece type match | PIECE-TYPE-CHECK (reserved 0xE2) |
```

**Example AFTER**:
```markdown
### Host Function Dispatch Patterns — Game Move Legality

| Constraint | Lisp | Opcode Sequence | Host Function |
|---|---|---|---|
| Bishop diagonal | `(diagonal-path?)` | `push "diagonal-path?" OP_CALLHOST` | registry.call("diagonal-path?") |
| Path clear | `(path-clear?)` | `push "path-clear?" OP_CALLHOST` | registry.call("path-clear?") |
| Piece type match | `(= piece-type "bishop")` | `OP_LOADFIELD + OP_EQUAL` (built-in) | N/A (compiled field comparison) |
```

### Step 6: Verify anti-bullshit rules in all phase prompts

**Files to check**:
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-26-PROMPT.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-27-PROMPT.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-28-PROMPT.md`
- `/sessions/nice-exciting-hopper/mnt/semantos-core/docs/prd/PHASE-29-PROMPT.md`

**Action**: Verify that the "ANTI-BULLSHIT RULES" section in each prompt mentions OP_CALLHOST and host function registration correctly. Update any rules that reference fictional opcodes or incorrect paths.

**Example BEFORE** (Phase 27 PROMPT, if it had):
```markdown
### 1. RULES ARE POLICIES, NOT IF-STATEMENTS

...domain-specific opcodes like DIAGONAL-PATH (0xE0) are reserved...
```

**Example AFTER**:
```markdown
### 1. RULES ARE POLICIES, NOT IF-STATEMENTS

...domain-specific predicates compile to `push "name" OP_CALLHOST` via Phase 25.5's host function dispatch...
```

### Step 7: Run verification grep commands

Execute the following grep searches to find any remaining defects:

```bash
cd /sessions/nice-exciting-hopper/mnt/semantos-core

# Find fictional opcode names
grep -r "RARITY-EQ\|DIAGONAL-PATH\|SENSOR-QUALITY-CHECK\|PATH-CLEAR\|PIECE-TYPE-CHECK\|counterparty-in-default\|PAYMENT-OVERDUE" docs/prd/ || echo "No fictional opcodes found"

# Find wrong paths (src/host-function-registry)
grep -r "src/host-function-registry\|src/host-function-dispatch" docs/prd/ || echo "No wrong paths found"

# Find multi-arity predicate definitions (should have only zero-arity)
grep -r "diagonal-path? from to\|sensor-reading .* to\|path-clear? from" docs/prd/ || echo "No multi-arity predicates found"

# Verify all phases reference bindings/ for host functions
grep -c "bindings/host-functions.ts" docs/prd/PHASE-26-PROMPT.md docs/prd/PHASE-27-PROMPT.md docs/prd/PHASE-28-PROMPT.md docs/prd/PHASE-29-PROMPT.md || echo "Check path references"

# Verify builtin-host-functions is documented in PRD tables
grep -c "builtin-host-functions.ts" docs/prd/PHASE-27-SIMPLE-GAMES.md docs/prd/PHASE-28-ISDA-CDM.md docs/prd/PHASE-29-SCADA.md || echo "Check builtin documentation"
```

### Step 8: Commit with phase-25.5-sweep naming

After all edits are complete:

```bash
git add -A
git commit -m "phase-25.5-sweep/D-SWEEP.ALL: Fix Phase 26-29 PRDs/prompts for OP_CALLHOST consistency

- Fix source file paths: src/host-function-registry.ts → bindings/host-functions.ts
- Add HOST:BUILTIN rows to Phase 27, 28, 29 source file tables
- Replace fictional opcodes with OP_CALLHOST patterns in compression gradients
- Add host function registration instructions to Phase 27 and 29 PRDs
- Clarify _currentArg convention for domain predicates
- Update anti-bullshit rules to reference OP_CALLHOST correctly
- Verify no multi-arity predicates remain (all zero-arity)

This is documentation-only. No code changes to the cell engine or SDK."
```

---

## Verification Checklist

Before committing, verify:

- [ ] No references to `src/host-function-registry.ts` remain (all → `bindings/host-functions.ts`)
- [ ] All phase PRDs (26, 27, 28, 29) source file tables include `HOST:REGISTRY` and `HOST:BUILTIN` rows
- [ ] All phase PRDs source file tables reference `bindings/` paths (not `src/`)
- [ ] No fictional opcode names (RARITY-EQ, DIAGONAL-PATH, etc.) in any PRD
- [ ] All compression gradient sections reference OP_CALLHOST dispatch patterns
- [ ] Phase 27 and 29 PRDs include explicit host function registration patterns
- [ ] All phase prompts reference correct paths for `host-functions.ts`
- [ ] Phase 29 PROMPT lists `packages/cell-engine/src/host-function-registry.ts` correction
- [ ] No multi-arity predicate syntax remains (e.g., `(diagonal-path? from to)`)
- [ ] _currentArg convention is explained where applicable
- [ ] Anti-bullshit rules in all prompts reference OP_CALLHOST, not fictional opcodes

---

## Related Files (Read-Only Reference)

Phase 25.5 implementation files (DO NOT EDIT):
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry class
- `packages/cell-engine/bindings/builtin-host-functions.ts` — Built-in predicates
- `packages/cell-engine/src/opcodes/hostcall.zig` — OP_CALLHOST handler
- `packages/shell/src/lisp/compiler.ts` — Lisp compilation to `push "name" OP_CALLHOST`
- `packages/cell-ops/src/opcodes.ts` — Opcode enum with OP_CALLHOST = 0xd0

---

## Status

**Not yet executed** — ready for a fresh session with 7 sequential steps covering all defects.

Each step is independent within its category (e.g., all Phase 26/27/28/29 source tables in Step 1 can be edited in parallel).
