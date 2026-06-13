---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-21-LISP-AXIOM-COMPILER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.696555+00:00
---

# Phase 21 — Lisp Axiom Compiler

**Version**: 1.0
**Date**: March 2026
**Status**: Pending Phase 20 gate (or can start after Phase 19)
**Duration**: 4 weeks (5-day buffer)
**Prerequisites**: Phase 19 merged (shell with `eval` verb reserved). Phase 12 recommended (cell engine bridge for compatibility).
**Master document**: SEMANTIC-SHELL-ARCHITECTURE.md + COMMERCIAL-CONTEXT.md
**Branch**: `phase-21-lisp-compiler`

---

## Context

Lisp is the **formal policy language**. Natural language is for discovery. CLI is for commitment. Lisp is for composition. Forth is for execution.

When conversations compress to repeatable patterns, those patterns become Lisp axioms. When CLI commands need conditional logic that exceeds simple flags, Lisp expresses constraints. The Lisp layer compiles s-expressions to Forth words / capability token scripts. This closes the **compression gradient**:

```
"only homeowners can approve repairs over $500"
    ↓ (classify intent)
(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)
    ↓ (compile to Forth)
500 AMOUNT-GT HOMEOWNER-FLAG CHECK-DOMAIN BOOLAND
    ↓ (pack as capability cell)
CAPABILITY cell with payload = compiled script bytes
```

Same intent. Four representations. Each one is inspectable, composable, and deterministic from the previous one.

This is a **SEPARATE PRODUCT** that **CONSUMES** the cell engine and the loom's type system. It does NOT change either.

### The Thesis

Lisp is intentionally minimal. It is NOT a general-purpose Lisp. It is a **policy DSL** with s-expression syntax.

- No closures, no lambdas, no continuations
- No mutable state, no side effects
- No dynamic scope
- Just macros that expand to Forth words

Compilation is a **pure transformation**. No runtime, no interpreter. Input s-expression → output Forth word sequence → output capability cell bytes. All deterministic.

---

## Deliverables

### D21.1 — S-Expression Parser

**File**: `packages/shell/src/lisp/parser.ts` (or `packages/lisp/src/parser.ts` if separate package)

Pure TypeScript parser for Lisp-like s-expressions:

- `parseExpression(input: string): SExpression` — parses a single s-expression
- `parseProgram(input: string): SExpression[]` — parses multiple s-expressions
- **Atom types**:
  - Symbols: `homeowner`, `approve-repair`, `amount`
  - Numbers: integers and floats (no scientific notation for now)
  - Strings: `"quoted string"`
  - Keywords: `:subject`, `:action`, `:constraint`, `:linearity`

- **List types**:
  - Simple lists: `(policy :subject homeowner :action approve-repair ...)`
  - Nested lists: `(and (> amount 500) (has-capability 6))`
  - Quoted forms: `'symbol` → returns `(quote symbol)`

- **Syntax support**:
  - Comments: `;` to end of line
  - Whitespace: flexible
  - Nested parentheses to any depth

- **Error handling**:
  - Unmatched parentheses → `SyntaxError` with line/column
  - Unknown syntax → `SyntaxError` with context
  - Clear error messages for troubleshooting

- **Output**: `SExpression` AST type
  ```typescript
  type SExpression =
    | Atom
    | List;

  interface Atom {
    type: 'atom';
    kind: 'symbol' | 'number' | 'string' | 'keyword';
    value: string | number;
    line: number;
    column: number;
  }

  interface List {
    type: 'list';
    elements: SExpression[];
    line: number;
    column: number;
  }
  ```

- **NO external dependencies**. Pure TypeScript, no Scheme/CL runtime.

---

### D21.2 — Policy Type System

**File**: `packages/shell/src/lisp/types.ts`

Type definitions for the Lisp policy DSL:

- **Policy form**:
  ```typescript
  interface PolicyForm {
    subject: IdentityRef;              // who can act
    action: string;                    // what verb (approve-repair, publish, etc.)
    constraint: ConstraintExpr;        // what conditions must hold
    linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
    description?: string;              // human-readable docs
  }
  ```

- **Identity reference**:
  ```typescript
  type IdentityRef =
    | { type: 'role'; name: string }           // homeowner, admin, etc.
    | { type: 'domainFlag'; flag: number }     // 0x00010006
    | { type: 'certPattern'; pattern: string } // "m/0x01/[0-2]" (BRC-42 derivation path)
  ```

- **Constraint expressions**:
  ```typescript
  type ConstraintExpr =
    | ComparisonExpr
    | LogicalExpr
    | CapabilityExpr
    | DomainCheckExpr
    | TimeConstraintExpr;

  interface ComparisonExpr {
    op: '>' | '<' | '>=' | '<=' | '=' | '!=';
    field: string;      // e.g., "amount", "urgency", "estimatedTime"
    value: number | string;
  }

  interface LogicalExpr {
    op: 'and' | 'or' | 'not';
    operands: ConstraintExpr[];
  }

  interface CapabilityExpr {
    type: 'hasCapability';
    capabilityNumber: number;   // 1-10 (loom capabilities)
  }

  interface DomainCheckExpr {
    type: 'checkDomain';
    domainFlag: number | string;  // 0x00010006 or symbolic name
  }

  interface TimeConstraintExpr {
    type: 'timeAfter' | 'timeBefore';
    isoTimestamp: string;
  }
  ```

- **Type validation**:
  - All policy forms are validated at parse time (not runtime)
  - Identity refs must resolve to known roles or domain flags
  - Constraints must reference fields that exist in the target object type
  - Linearity modes map to cell engine constants

- **Constraint evaluation semantics** (documented, not implemented here):
  - Fields are resolved from the object's typed payload
  - Comparisons are type-aware (string vs number)
  - Logical operators short-circuit (and/or)
  - Capability checks use the loom's capability system

---

### D21.3 — Macro Expander (Lisp → Forth)

**File**: `packages/shell/src/lisp/compiler.ts`

Pure transformation from policy s-expressions to Forth word sequences:

- **Expansion rules**:
  ```
  (> field value)
    → <value> <FIELD>-GT
    e.g., (> amount 500) → 500 AMOUNT-GT

  (< field value)
    → <value> <FIELD>-LT

  (>= field value)
    → <value> <FIELD>-GTE

  (<= field value)
    → <value> <FIELD>-LTE

  (= field value)
    → <value> <FIELD>-EQ

  (!= field value)
    → <value> <FIELD>-NE

  (and constraint1 constraint2 ...)
    → <compiled constraint1> <compiled constraint2> ... BOOLAND (n-1 times)
    e.g., (and (> a 5) (< b 10)) → 5 A-GT 10 B-LT BOOLAND

  (or constraint1 constraint2 ...)
    → <compiled constraint1> <compiled constraint2> ... BOOLOR (n-1 times)

  (not constraint)
    → <compiled constraint> BOOLNOT

  (has-capability n)
    → <n> CHECK-CAP

  (check-domain flag)
    → <flag> CHECK-DOMAIN

  (time-after iso-timestamp)
    → <unix-timestamp> TIME-AFTER

  (time-before iso-timestamp)
    → <unix-timestamp> TIME-BEFORE

  (policy :subject <identity-ref>
          :action <verb>
          :constraint <constraint-expr>
          :linearity <mode>)
    → <subject-check> <action-check> <constraint-compiled> <linearity-check>
  ```

- **Compiler class**:
  ```typescript
  class LispCompiler {
    compile(expr: SExpression): ForthOutput;
    compilePolicy(policyForm: SExpression): ForthOutput;
  }

  interface ForthOutput {
    forthWords: string;              // human-readable "500 AMOUNT-GT HOMEOWNER CHECK-DOMAIN BOOLAND"
    forthBytes: Uint8Array;          // packed bytes for cell engine
    metadata: {
      subject?: string;
      action?: string;
      linearity?: string;
      inputExpr: string;              // original s-expression
      compiledAt: string;             // ISO timestamp
    };
  }
  ```

- **Compilation is pure**:
  - Same input always produces same output
  - No mutable state during compilation
  - No I/O or external lookups
  - Deterministic

- **No runtime evaluation**:
  - Compilation is a transformation, not execution
  - The Forth words are executed by the cell engine, not by the compiler

---

### D21.4 — Capability Token Packing

**File**: `packages/shell/src/lisp/packer.ts`

Takes compiled Forth output and packs it into a capability token cell:

- `packCapabilityCell(forthBytes: Uint8Array, options: PackOptions): Uint8Array`

- **Cell format** (256-byte header + payload):
  - Magic: version + type identifier
  - Type: `CAPABILITY`
  - Linearity: LINEAR | AFFINE | RELEVANT | FUNGIBLE
  - Payload: compiled script bytes
  - Timestamp: cell creation time

- **Compatibility**:
  - Output format matches the Zig cell engine spec (from Phase 7/12)
  - If Phase 12 cell engine bindings are available, use them
  - Otherwise, implement the cell header format directly (28-byte header + 256-byte payload)

- **Example**:
  ```typescript
  const forth = "500 AMOUNT-GT HOMEOWNER-FLAG CHECK-DOMAIN BOOLAND";
  const bytes = compileForth(forth);  // Uint8Array
  const cell = packCapabilityCell(bytes, { linearity: 'LINEAR' });
  // cell is now 256+ bytes, ready for the cell engine
  ```

---

### D21.5 — Shell Integration

**File**: `packages/shell/src/commands/eval.ts` (and related files)

Wire the `eval` verb (reserved in Phase 19) to the Lisp compiler:

- **Commands**:
  ```bash
  semantos eval '(> amount 500)' --object job-1774
    Evaluates a constraint expression against an object
    Returns: true/false

  semantos compile '(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)'
    Compiles a policy to a capability cell
    Returns: cell file path

  semantos bind homeowner-approval.cell --type trades.job.plumbing
    Binds a compiled policy to an object type
    Adds policy to the type definition in the extension config
    Returns: confirmation + type hash update

  semantos verify job-1774 --policy homeowner-approval
    Checks if a policy holds for an object
    Returns: true/false + explanation
  ```

- **Implementation**:
  - `eval` verb:
    - Parse the s-expression
    - Resolve it against the object's state
    - Return true/false
  - `compile` verb:
    - Parse the s-expression
    - Run through LispCompiler
    - Run through packer
    - Write cell to file (in `~/.semantos/policies/` by default)
    - Return file path
  - `bind` verb:
    - Read the cell file
    - Extract policy metadata
    - Update the extension config
    - Register the policy in FlowRegistry (as a guard)
    - Return confirmation
  - `verify` verb:
    - Load the policy cell
    - Evaluate it against the object
    - Return result

---

### D21.6 — Policy Objects in Extension Config

**File**: `packages/loom/src/config/extensionConfig.ts` (extend)

Extend `ObjectTypeDefinition` with optional `policies` field:

```typescript
interface ObjectTypeDefinition {
  // ... existing fields ...
  policies?: PolicyBinding[];
}

interface PolicyBinding {
  name: string;                    // "homeowner-approval"
  path: string;                    // "~/.semantos/policies/homeowner-approval.cell" or inline
  inlinePayload?: string;          // base64-encoded cell bytes (alternative to path)
  description?: string;
  appliedAt?: string;              // ISO timestamp of binding
}
```

- **Loading policies**:
  - At config load time, `loadExtensionConfig()` reads all policy paths
  - Each policy cell is loaded and registered in `FlowRegistry`
  - Policies become guards that `FlowRunner` evaluates during flow execution

- **Policy evaluation in flows**:
  - When a flow step has a policy bound, `FlowRunner.advanceFlow()` evaluates it
  - Policy evaluation is the same as guard evaluation (from Phase 10 grafts)
  - If policy returns false, step is blocked

- **Example** (in a extension config):
  ```json
  {
    "objectTypes": {
      "trades.job.plumbing": {
        "linearity": "AFFINE",
        "policies": [
          {
            "name": "homeowner-approval",
            "path": "~/.semantos/policies/homeowner-approval.cell"
          },
          {
            "name": "safety-inspection",
            "inlinePayload": "AgE..."
          }
        ]
      }
    }
  }
  ```

- **Connection to Graft 1** (FSM Constraint Guards → FlowRunner):
  - Compiled policies produce the same guard types that FlowRunner evaluates
  - This connects the Lisp layer to the flow execution layer seamlessly

---

## Gate Tests

### Unit Tests (T1–T7)

- **T1**: Parser correctly parses `(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)` with no errors
- **T2**: Parser correctly handles nested constraints: `(and (> amount 500) (has-capability 6))`
- **T3**: Parser rejects invalid forms (unmatched parens, unknown keywords) with clear error messages
- **T4**: Compiler produces correct Forth for `(> amount 500)` → `"500 AMOUNT-GT"` (exact string)
- **T5**: Compiler produces correct Forth for `(and (> amount 500) (has-capability 6))` → `"500 AMOUNT-GT 6 CHECK-CAP BOOLAND"` (exact string)
- **T6**: Compiler produces correct Forth for full policy form (subject + action + constraint + linearity combines correctly)
- **T7**: Compilation is pure: same input always produces exact same output (deterministic)

### Integration Tests (T8–T13)

- **T8**: Packer produces valid cell bytes (correct magic, type = CAPABILITY, linearity, payload length)
- **T9**: `semantos eval '(> amount 500)' --object job-1774` evaluates against object state (returns boolean)
- **T10**: `semantos compile '(policy ...)' --output test.cell` writes valid cell file to disk
- **T11**: `semantos verify job-1774 --policy test.cell` returns true/false correctly
- **T12**: Policy field in extension config loads and registers in FlowRegistry (FlowRegistry.getGuards() includes the policy)
- **T13**: Compiled policy produces same evaluation result as manually constructed FlowStepGuard (from Phase 10 guards)

### Round-Trip Tests (T14–T15)

- **T14**: Round-trip: parse → compile → pack → evaluate produces correct result (policy cell evaluates to expected boolean)
- **T15**: Parser handles comments, whitespace, and multiline input correctly

### Anti-Lock Tests (T16–T18)

- **T16**: Lisp package has ZERO React imports (grep confirms)
- **T17**: Compiler has no runtime dependencies (pure transformation, no I/O, no external calls)
- **T18**: Cell packing is compatible with Zig cell engine format (if bindings available from Phase 12, test interop)

---

## Completion Criteria

- [ ] `packages/shell/src/lisp/parser.ts` exists with pure TypeScript s-expression parser
- [ ] `packages/shell/src/lisp/types.ts` exists with policy type definitions
- [ ] `packages/shell/src/lisp/compiler.ts` exists with LispCompiler class (pure transformation)
- [ ] `packages/shell/src/lisp/packer.ts` exists with capability cell packing
- [ ] `packages/shell/src/commands/eval.ts` exists with eval/compile/bind/verify verbs
- [ ] `packages/loom/src/config/extensionConfig.ts` extended with policies field
- [ ] `semantos eval` command evaluates s-expressions
- [ ] `semantos compile` command produces cell files
- [ ] `semantos bind` command registers policies
- [ ] `semantos verify` command checks policies
- [ ] Tests T1–T18 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in Lisp package
- [ ] Errata sprint complete with `docs/prd/PHASE-21-ERRATA.md`
- [ ] All commits follow `phase-21/D21.N:`
- [ ] Branch is `phase-21-lisp-compiler`

---

## What NOT to Do

1. **Do NOT implement a general-purpose Lisp.** This is a POLICY DSL only.
2. **Do NOT add closures, lambdas, dynamic scoping, or mutable state.** Not needed for policies.
3. **Do NOT depend on an external Scheme/Common Lisp runtime.** Pure TypeScript only.
4. **Do NOT bypass the cell engine.** Compiled policies must produce cells the engine can evaluate.
5. **Do NOT implement runtime evaluation in the compiler.** Compilation is a pure transformation.
6. **Do NOT change the cell engine format.** The compiler conforms to the existing spec.
7. **Do NOT implement natural language → Lisp compilation.** That is a future LLM integration, not this phase.
8. **Do NOT hardcode policy examples in the compiler.** Tests use real extension configs.

---

## What Comes After

After Phase 21, the full compression gradient is operational:

```
Natural language        "only homeowners can approve repairs over $500"
    ↓ (LLM intent classification)
CLI command             semantos bind policy.cell --type job
    ↓ (shell verb resolution)
Lisp axiom              (policy :subject homeowner :action approve-repair :constraint (> amount 500))
    ↓ (compiler)
Forth word              500 AMOUNT-GT HOMEOWNER CHECK-DOMAIN BOOLAND
    ↓ (cell packing)
Cell execution          cell engine evaluates, returns boolean
```

Users enter at whatever level matches their expertise. The system compiles down to the same executable form regardless.

---

## Future: Natural Language Integration

Phase 22+ (future) can add an LLM bridge that compiles natural language directly to Lisp axioms:

```bash
semantos learn "only homeowners can approve repairs over $500"
  → Creates a Lisp axiom
  → Compiles to capability cell
  → Binds to trades.job type
```

But that is a SEPARATE concern. The Lisp layer is complete without it.

The compiler is the bridge between formal policy (Lisp) and execution (cell engine). The NLP is a convenience layer above that bridge, not required for it to work.
