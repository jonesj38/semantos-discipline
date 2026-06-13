---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-25.5-SWEEP-2PDA-CALLHOST.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.718199+00:00
---

# Phase 25.5 Sweep — OP_CALLHOST Documentation Consistency

**Version**: 1.0
**Date**: March 2026
**Status**: Documentation sweep — not yet executed
**Duration**: 2 days (revision pass only, no code changes)
**Prerequisites**: Phase 26, Phase 27, Phase 28, Phase 29 PRDs + Prompts all exist
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + `COMMERCIAL-CONTEXT.md`
**Branch**: `phase-25.5-sweep-callhost-consistency`

---

## Context

Phase 25.5 introduced `OP_CALLHOST` (0xD0) — the opcode for dispatching domain-specific predicates to host functions during cell engine execution. The infrastructure is:

- **Zig side**: `packages/cell-engine/src/opcodes/hostcall.zig` — the 0xD0 opcode handler
- **TypeScript side**: `packages/cell-engine/bindings/host-functions.ts` — contains `HostFunctionRegistry` class that maps predicate names to callable functions
- **Built-in patterns**: `packages/cell-engine/bindings/builtin-host-functions.ts` — example implementations for registering domain predicates

Phase 25.5 is architecturally complete. However, subsequent domain-specific phases (26, 27, 28, 29) that build on top of Phase 25.5 contain four categories of defects in their PRDs and Prompts:

1. **Missing source file references** to `builtin-host-functions.ts` in source tables
2. **Wrong file paths** for `host-function-registry.ts` (pointing to `src/` instead of `bindings/`)
3. **Missing explicit instructions** to create domain-specific host-functions files and call `registry.register()`
4. **Malformed predicate forms** in Lisp policies (multi-arity forms that violate the `_currentArg` convention)

This sweep fixes all documentation defects without modifying code. It ensures downstream phases (26–29) have correct file paths, complete source tables, and clear guidance on host function registration.

### Why This Matters

Downstream phase documentation is the "contract" developers execute. Wrong file paths cause:
- Developers searching for non-existent files and wasting time
- Unclear patterns for how to register domain predicates
- Confusion about whether builtin patterns exist to learn from
- Incorrectly structured Lisp policies that won't evaluate

This sweep closes those gaps cleanly before Phase 26 and beyond are executed.

---

## Defects Found

### Defect 1: Missing `builtin-host-functions.ts` in Source Tables

**Affected phases**: 27, 28, 29 (PRDs only; Prompts do not have source tables)

**Location**: Phase 27 PRD: source files table (lines 48–61)
              Phase 28 PRD: source files table (lines 57–74)
              Phase 29 PRD: source files table (lines 75–91)

**Issue**: These phases reference `HOST:REGISTRY` but do not reference `HOST:BUILTIN` (the builtin-host-functions.ts pattern file). Phase 26 PRD correctly includes it; subsequent phases should too.

**Impact**: Developers implementing domain-specific predicates have no clear pattern for registration structure.

---

### Defect 2: Wrong File Path for host-function-registry.ts

**Affected phases**: 28 Prompt (2 occurrences), 29 Prompt (2 occurrences)

**Location**: PHASE-28-PROMPT.md
  - Line 45: `packages/cell-engine/src/host-function-registry.ts`
  - Line 125: `ls packages/cell-engine/src/host-function-registry.ts`

             PHASE-29-PROMPT.md
  - Line 44: `packages/cell-engine/src/host-function-registry.ts`
  - Line 143: `ls packages/cell-engine/src/host-function-registry.ts`

**Actual file**: `packages/cell-engine/bindings/host-functions.ts`
                (The HostFunctionRegistry class is in bindings/, not src/)

**Issue**: The registry lives in the bindings layer (TypeScript-to-WASM bridge), not in the opcodes/src/ layer. Pointing to a wrong path causes `ls` checks to fail.

**Impact**: During phase execution, the prerequisite check `ls packages/cell-engine/src/host-function-registry.ts` fails, blocking progress.

---

### Defect 3: Missing Explicit Instructions to Create Domain-Specific Host Functions Files and Register

**Affected phases**: 27 PRD, 29 PRD

**Location**: Phase 27 PRD — no deliverable explicitly instructs creation of `packages/games/src/*/host-functions.ts` files with `registry.register()` calls
             Phase 29 PRD — no deliverable explicitly instructs creation of `packages/scada/src/policies/host-functions.ts` with `registry.register()` calls

(Phase 28 and Phase 26 do have these instructions; Phase 27 and 29 do not.)

**Issue**: Deliverables in Phase 27 (D27.3 Chess Host Functions) and Phase 29 (D29.5 SCADA Host Functions) describe WHAT should be registered but not HOW — no explicit `registry.register("predicate-name", fn)` pseudo-code or TypeScript template.

**Impact**: Without clear templates, developers must infer the registration pattern from Phase 26 (which they may not have read) or from builtin-host-functions.ts (which Phase 27 and 29 don't reference).

---

### Defect 4: Malformed Multi-Arity Predicate Forms in Phase 29

**Affected phase**: 29 SCADA PRD

**Location**: PHASE-29-SCADA.md, lines 297–352 (policy examples in D29.4)

**Examples**:
```lisp
(< (sensor-reading "PT-101") 150.0)    ;; Line 297
(> (sensor-reading "LT-101") 20.0)     ;; Line 307
(< (abs (- (sensor-reading "TT-201A") (sensor-reading "TT-201B"))) 5.0)  ;; Line 347
```

**Issue**: Per Phase 25.5 design, `sensor-reading` and `sensor-quality` are **zero-arity predicates** that read from frozen context (the evaluation context passed to the host function). They are dispatched via `OP_CALLHOST` and return a value that is then used in the containing expression.

The forms above use `(sensor-reading "PT-101")` as if sensor-reading takes an argument, then nest that inside another operation like `(<  ...)`. This is **syntactically valid** for the Lisp compiler (it compiles to the bytecode shown on line 66: `"PT-101" "sensor-reading" OP_CALLHOST 150.0 OP_LESSTHAN`) but **conceptually wrong** — it suggests sensor-reading is a **arity-1** predicate, not arity-0.

The correct conceptual model: sensor-reading is a **host function that takes no arguments but reads from the evaluation context**. The "PT-101" is passed **to the WASM engine in the context object**, not as a parameter to the predicate.

**Correct conceptual form** (per Phase 25.5):
```lisp
(< (sensor-reading-pt-101) 150.0)  ;; arity-0 predicate, _currentArg context provides the sensor ID
```

Or, if parameterized:
```lisp
(sensor-reading-PT-101? 150.0)      ;; host function takes 1 arg (threshold), compares against frozen context value
```

Not:
```lisp
(< (sensor-reading "PT-101") 150.0)  ;; misleading — suggests arity-1, but it's arity-0 with context lookup
```

**Impact**: While the compiled bytecode is correct, the documentation misleads future developers about the arity contract of host functions. New predicates may be implemented with the wrong signature.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `PHASE-26-PRD` | `docs/prd/PHASE-26-GAME-ENGINE-SDK.md` | Correct source file table (reference for D26.1–D26.N) |
| `PHASE-26-PROMPT` | `docs/prd/PHASE-26-PROMPT.md` | Correct references and patterns (if it exists) |
| `PHASE-27-PRD` | `docs/prd/PHASE-27-SIMPLE-GAMES.md` | To be fixed: add HOST:BUILTIN reference |
| `PHASE-27-PROMPT` | `docs/prd/PHASE-27-PROMPT.md` | To be fixed: add D27.3 registration template |
| `PHASE-28-PRD` | `docs/prd/PHASE-28-ISDA-CDM.md` | Correct (no changes needed) |
| `PHASE-28-PROMPT` | `docs/prd/PHASE-28-PROMPT.md` | To be fixed: line 45, 125 path corrections |
| `PHASE-29-PRD` | `docs/prd/PHASE-29-SCADA.md` | To be fixed: D29.4 policy example corrections + HOST:BUILTIN reference |
| `PHASE-29-PROMPT` | `docs/prd/PHASE-29-PROMPT.md` | To be fixed: line 44, 143 path corrections + D29.5 template |
| `HOST:FUNCTIONS` | `packages/cell-engine/bindings/host-functions.ts` | Actual file containing HostFunctionRegistry |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Pattern file for domain predicates |

---

## Deliverables

### D-SWEEP.1 — Fix PHASE-27-SIMPLE-GAMES.md Source Table

**File**: `docs/prd/PHASE-27-SIMPLE-GAMES.md`

Add missing `HOST:BUILTIN` reference to the source files table (after line 60, before the closing `---`):

**Before** (lines 48–61):
```markdown
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-function-registry.ts` | HostFunctionRegistry — register chess/Go predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |
```

**After**:
```markdown
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-function-registry.ts` | HostFunctionRegistry — register chess/Go predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering domain predicates |
```

---

### D-SWEEP.2 — Fix PHASE-28-PROMPT.md File Path (2 occurrences)

**File**: `docs/prd/PHASE-28-PROMPT.md`

**Fix 1 - Line 45** (in the "Read fourth" section):

**Before**:
```markdown
- `packages/cell-engine/src/host-function-registry.ts` — HostFunctionRegistry (register CDM-domain predicates here)
```

**After**:
```markdown
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry (register CDM-domain predicates here)
```

**Fix 2 - Line 125** (in the prerequisite check section):

**Before**:
```bash
ls packages/cell-engine/src/host-function-registry.ts
```

**After**:
```bash
ls packages/cell-engine/bindings/host-functions.ts
```

---

### D-SWEEP.3 — Add HOST:BUILTIN Reference to PHASE-28-ISDA-CDM.md

**File**: `docs/prd/PHASE-28-ISDA-CDM.md`

Add missing `HOST:BUILTIN` reference to the source files table. Find the line with `HOST:CALLZIG` and add the following after it:

**Location**: Source files table (lines ~57–74, exact line TBD by inspection)

**Add after the `HOST:CALLZIG` row**:
```markdown
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering CDM-domain predicates |
```

---

### D-SWEEP.4 — Fix PHASE-29-PROMPT.md File Path (2 occurrences)

**File**: `docs/prd/PHASE-29-PROMPT.md`

**Fix 1 - Line 44** (in the "Read fourth" section):

**Before**:
```markdown
- `packages/cell-engine/src/host-function-registry.ts` — HostFunctionRegistry (register SCADA-domain predicates here: `sensor-reading`, `sensor-quality`, `has-dual-authorization`)
```

**After**:
```markdown
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry (register SCADA-domain predicates here: `sensor-reading`, `sensor-quality`, `has-dual-authorization`)
```

**Fix 2 - Line 143** (in the prerequisite check section):

**Before**:
```bash
ls packages/cell-engine/src/host-function-registry.ts
```

**After**:
```bash
ls packages/cell-engine/bindings/host-functions.ts
```

---

### D-SWEEP.5 — Fix PHASE-29-SCADA.md Host Function Reference

**File**: `docs/prd/PHASE-29-SCADA.md`

Add missing `HOST:BUILTIN` reference to the source files table. Find the line with `HOST:CALLZIG` (line ~90) and add the following after it:

**Add after the `HOST:CALLZIG` row**:
```markdown
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering SCADA-domain predicates |
```

---

### D-SWEEP.6 — Correct Multi-Arity Predicate Forms in PHASE-29-SCADA.md

**File**: `docs/prd/PHASE-29-SCADA.md`

**Location**: D29.4 "Safety Interlocks via Lisp Policies" section (lines 297–352)

**Issue**: Policy examples show multi-arity predicate forms like `(sensor-reading "PT-101")` that mislead about the arity contract. The compiled bytecode is correct, but the Lisp source is semantically confusing.

**Correction strategy**:
1. Add a clarifying note at the start of the policy examples explaining that `sensor-reading` and `sensor-quality` are host functions that read from the evaluation context, not function arguments.
2. Rewrite policy examples to use arity-0 helper predicates (recommended approach) or add comments clarifying the context-passing model.

**Specific rewrite** (lines 297–308, first interlock policy):

**Before**:
```lisp
(define-policy bypass-valve-safety
  :subject operator
  :action open-valve
  :constraint (and
    (= target "bypass-valve-BV-101")
    (< (sensor-reading "PT-101") 150.0)    ;; pressure transmitter PT-101, max 150 PSI
    (> (sensor-reading "LT-101") 20.0)     ;; level transmitter LT-101, minimum 20%
    (= (sensor-quality "LT-101") "GOOD")   ;; sensor must be healthy
    (has-capability 1))
  :linearity LINEAR)
```

**After**:
```lisp
(define-policy bypass-valve-safety
  :subject operator
  :action open-valve
  :constraint (and
    (= target "bypass-valve-BV-101")
    (pressure-below-threshold? 150.0)      ;; host function reads PT-101 from context, compares against 150 PSI
    (level-above-minimum? 20.0)            ;; host function reads LT-101 from context, compares against 20%
    (sensor-quality-good? "LT-101")        ;; host function checks quality flag in context
    (has-capability 1))
  :linearity LINEAR)
```

**Add explanatory note before D29.4 examples**:

```markdown
**Host Function Context Model**

SCADA predicates like `pressure-below-threshold?`, `level-above-minimum?`, `sensor-quality-good?` are host functions registered via Phase 25.5's `HostFunctionRegistry`. Each host function:
- Takes zero or more VALUE arguments (e.g., threshold, sensor ID)
- Reads sensor state from the evaluation context (passed to `registry.setContext(scadaState)` before policy evaluation)
- Returns a boolean via `OP_CALLHOST` (0xD0)

When the Lisp compiler encounters `(pressure-below-threshold? 150.0)`, it generates:
```
150.0 "pressure-below-threshold?" OP_CALLHOST
```

The WASM engine pushes 150.0, dispatches to the host function via OP_CALLHOST, the host function reads the current sensor value from context, compares against 150.0, and pushes the result back. The context object (set before evaluation) contains the current PT-101 reading; the host function doesn't need it passed as an argument.

This is different from regular Forth functions. Host functions are the bridge between the cell engine (which has no knowledge of SCADA specifics) and the SCADA domain layer (which knows how to read sensors and evaluate thresholds).
```

**Additional rewrites** (lines 316–322, second interlock):

**Before**:
```lisp
(or
  (> (sensor-reading "TT-201") 500.0)    ;; reactor temperature > 500°C
  (= (sensor-quality "TT-201") "GOOD"))  ;; only on valid reading
```

**After**:
```lisp
(or
  (reactor-temp-exceeds-limit?)          ;; host function reads TT-201, checks > 500°C
  (reactor-sensor-valid?))               ;; host function reads TT-201 quality flag
```

**For complex example** (lines 347–352, dual-sensor voting):

**Before**:
```lisp
(and
  (< (abs (- (sensor-reading "TT-201A") (sensor-reading "TT-201B"))) 5.0)
  (or
    (and (= (sensor-quality "TT-201A") "BAD")
         (= (sensor-quality "TT-201B") "GOOD"))
    (and (= (sensor-quality "TT-201B") "BAD")
         (= (sensor-quality "TT-201A") "GOOD"))))
```

**After**:
```lisp
(and
  (dual-reactor-sensors-agree? 5.0)      ;; host function reads both sensors, checks delta < 5°C
  (or
    (sensor-a-bad-sensor-b-good?)        ;; host function checks quality flags
    (sensor-b-bad-sensor-a-good?)))      ;; host function checks quality flags
```

**Rationale**:
- The multi-arity forms like `(sensor-reading "PT-101")` suggest `sensor-reading` is a arity-1 function taking a sensor ID.
- In reality, per Phase 25.5, the sensor ID is context-dependent — the evaluation context is set BEFORE policy execution.
- Using named predicates like `pressure-below-threshold?` makes the arity contract explicit: the predicate takes a threshold VALUE (not a sensor ID), reads the sensor from context, and returns a boolean.
- This pattern is more maintainable and correctly reflects how host functions work.

---

### D-SWEEP.7 — Add HOST:BUILTIN to PHASE-29-PROMPT.md

**File**: `docs/prd/PHASE-29-PROMPT.md`

Find the source files section (after the "CRITICAL: READ THESE FILES FIRST" section) and verify the source files table references `HOST:BUILTIN`. If missing, add it.

(Note: PHASE-29-PROMPT.md may not have a full source table like the PRD — verify first. If it has references to host-function-registry, it should also reference builtin-host-functions for pattern guidance.)

---

### D-SWEEP.8 — Verify All PHASE-*-PROMPT.md Files Have Correct Paths

**Files**:
- `docs/prd/PHASE-26-PROMPT.md` (if it exists — verify)
- `docs/prd/PHASE-27-PROMPT.md` (if it exists — verify)
- `docs/prd/PHASE-28-PROMPT.md` (already fixed in D-SWEEP.2)
- `docs/prd/PHASE-29-PROMPT.md` (already fixed in D-SWEEP.4)

**Action**: Search each prompt file for occurrences of `packages/cell-engine/src/host-function-registry.ts` or `packages/cell-engine/src/host-functions.ts`. If found, replace with `packages/cell-engine/bindings/host-functions.ts`.

---

## Verification Criteria

**V1**: All source file tables in Phase 26, 27, 28, 29 PRDs contain both `HOST:REGISTRY` and `HOST:BUILTIN` entries pointing to the correct files.

**V2**: All file path references to `host-function-registry.ts` or `host-functions.ts` in Prompts point to `packages/cell-engine/bindings/host-functions.ts`, not `packages/cell-engine/src/`.

**V3**: All prerequisite check commands in Phase 28 and 29 Prompts (`ls` commands) use the correct path and will succeed.

**V4**: Phase 28 PRD contains a reference to `HOST:BUILTIN` in its source table.

**V5**: Phase 29 PRD contains a reference to `HOST:BUILTIN` in its source table.

**V6**: Phase 29 SCADA PRD policy examples (D29.4) use semantically correct arity-0 predicate forms with clarifying comments, or include an explanatory note about the context-passing model.

---

## Completion Criteria

1. All defects listed in the "Defects Found" section are fixed.
2. All eight deliverables (D-SWEEP.1 through D-SWEEP.8) are complete.
3. All six verification criteria (V1–V6) pass.
4. A final review confirms:
   - No file paths are broken or point to wrong locations
   - No source tables are missing required references
   - No Lisp policy examples in Phase 29 are misleading about arity contracts
   - The sweep is documentation-only (no code changes)
5. Branch `phase-25.5-sweep-callhost-consistency` is ready to merge after review.

---

## Notes

- **No code changes**: This sweep is documentation only. The Phase 25.5 infrastructure (OP_CALLHOST, HostFunctionRegistry) is complete and correct. Only the downstream PRDs/Prompts are fixed.
- **Backwards compatible**: Fixes do not change requirements or deliverables of Phases 26–29. They only clarify references and correct misleading examples.
- **Phase 25.5 is not modified**: The PRD for Phase 25.5 itself is not changed. This sweep only fixes references TO Phase 25.5 infrastructure in later phases.
