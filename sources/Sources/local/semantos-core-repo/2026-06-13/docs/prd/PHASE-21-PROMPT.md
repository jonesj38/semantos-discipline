---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-21-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.676281+00:00
---

# Phase 21 Execution Prompt — Lisp Axiom Compiler

> Paste this prompt into a fresh session to execute Phase 21.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Lisp is the **formal policy language**. Natural language is for discovery. CLI is for commitment. Lisp is for composition. Forth is for execution.

When conversations compress to repeatable patterns, those patterns become Lisp axioms. The Lisp layer compiles s-expressions to Forth words and capability token cells. This closes the compression gradient:

```
"only homeowners can approve repairs over $500"
    ↓ (classify intent + compile)
(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)
    ↓ (macro expand)
500 AMOUNT-GT HOMEOWNER-FLAG CHECK-DOMAIN BOOLAND
    ↓ (pack cell)
CAPABILITY cell with script bytes
```

Same intent. Four representations. Each one is inspectable, composable, deterministic.

This is a **SEPARATE PRODUCT** that **CONSUMES** the cell engine and the loom's type system. It does NOT change either.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real requirements and architecture you are building on top of.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-21-LISP-AXIOM-COMPILER.md` — Phase 21 spec with deliverables D21.1–D21.6, TDD gate T1–T18, completion criteria

**Read second** (the architecture — understand the compression gradient):
- `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` — Layer 3 Axiom Layer section. Especially the compression gradient diagram and the Lisp-to-Forth pipeline.
- `docs/prd/COMMERCIAL-CONTEXT.md` (if available) — the practical application of policy compilation

**Read third** (the services and types you are integrating with):
- `packages/loom/src/services/LoomStore.ts` — Object state for policy evaluation
- `packages/loom/src/services/FlowRegistry.ts` and `FlowRunner.ts` — Flow guards are what compiled policies become
- `packages/loom/src/types/workbench.ts` — Object schema for constraint field resolution
- `packages/loom/src/config/extensionConfig.ts` — Where policies bind to object types

**Read fourth** (the flow guard system — this is what Lisp policies integrate with):
- `packages/loom/src/services/FlowRunner.ts` — Look for guard evaluation (from Graft 1: FSM Constraint Guards)
- The FlowStepGuard type definition — compiled policies produce these

**Read fifth** (the cell engine format — for compatibility):
- `docs/PHASE-12-CELL-ENGINE-WASM.md` (if available) or Phase 12 PRD
- Cell header structure, linearity constants, payload format
- If Phase 12 WASM bindings are available in the repo, study them

**Read sixth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-21-lisp-compiler`. Commits as `phase-21/D21.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–20. Plus:

### 1. NOT A GENERAL LISP

This is a POLICY DSL with s-expression syntax. NOT a Scheme/Common Lisp interpreter.

- No closures, no lambdas
- No continuations, no call/cc
- No mutable state, no set!
- No dynamic scope
- No macros that take code as data

Just s-expressions that compile to Forth words. That's it.

### 2. PURE COMPILATION

Compilation is a pure transformation. No side effects. No I/O.

```typescript
const compiled = compiler.compile(expr);  // same input = same output, always
```

Not:
```typescript
const compiled = compiler.compile(expr, db, network);  // NO
```

### 3. NO RUNTIME EVALUATION

The Lisp compiler does NOT run Lisp code. It does NOT interpret s-expressions. It transforms them to Forth.

The **Forth words** are executed by the **cell engine**, not by the compiler.

### 4. CELL COMPATIBILITY

Compiled policies must produce cells that the Zig cell engine can evaluate. Format compliance is non-negotiable.

### 5. CONSTRAINTS FROM REAL SCHEMAS

Policies reference fields from object payloads. Constraints must resolve against real extension config schemas, not made-up fields.

Test with real objects from real extensions (trades-services, core, etc).

### 6. NO EXTERNAL PARSING LIBRARIES

Pure TypeScript s-expression parser. No `scheme`, `lisp`, `clojure`, or any external runtime.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites are complete

```bash
# Phase 19 shell exists (eval verb reserved)
ls packages/shell/src/commands/

# Services exist (unchanged from Phase 19)
ls packages/loom/src/services/LoomStore.ts
ls packages/loom/src/services/FlowRunner.ts
ls packages/loom/src/services/FlowRegistry.ts

# Extension configs exist
ls configs/extensions/trades-services.json
ls configs/extensions/core.json

# Type definitions exist
ls packages/loom/src/types/workbench.ts
```

All files must exist. If anything is missing, STOP.

### 0.3 Create Phase 21 branch

```bash
git checkout -b phase-21-lisp-compiler
```

---

## Step 1: S-Expression Parser (D21.1)

Create `packages/shell/src/lisp/parser.ts`.

**Requirements**:

- `parseExpression(input: string): SExpression` — parse a single s-expression
- `parseProgram(input: string): SExpression[]` — parse multiple s-expressions

- **Atom types**:
  - Symbols: `homeowner`, `approve-repair`, `amount`
  - Numbers: `500`, `3.14`, `-42`
  - Strings: `"quoted string"`
  - Keywords: `:subject`, `:action`, `:constraint`, `:linearity`

- **List types**:
  - Simple lists: `(policy :subject homeowner ...)`
  - Nested lists: `(and (> amount 500) (has-capability 6))`

- **Syntax**:
  - Comments: `;` to end of line
  - Flexible whitespace
  - Nested parentheses to any depth

- **Error handling**:
  - Unmatched parens → `SyntaxError` with line/column
  - Clear error messages

- **Output**: `SExpression` type
  ```typescript
  type SExpression = Atom | List;

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

- **NO external dependencies**. Pure TypeScript.

**Commit**: `phase-21/D21.1: s-expression parser with pure TypeScript`

---

## Step 2: Policy Type System (D21.2)

Create `packages/shell/src/lisp/types.ts`.

**Requirements**:

- **PolicyForm interface**:
  ```typescript
  interface PolicyForm {
    subject: IdentityRef;
    action: string;
    constraint: ConstraintExpr;
    linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
    description?: string;
  }
  ```

- **Identity reference**:
  ```typescript
  type IdentityRef =
    | { type: 'role'; name: string }
    | { type: 'domainFlag'; flag: number }
    | { type: 'certPattern'; pattern: string }
  ```

- **Constraint expressions**:
  - ComparisonExpr: `(> field value)`, `(<= field value)`, etc.
  - LogicalExpr: `(and ...)`, `(or ...)`, `(not ...)`
  - CapabilityExpr: `(has-capability n)`
  - DomainCheckExpr: `(check-domain flag)`
  - TimeConstraintExpr: `(time-after iso)`, `(time-before iso)`

- **Type validation**:
  - Policies are validated at parse time
  - Identity refs must resolve to known roles or domain flags
  - Constraints must reference real fields from object schemas
  - Linearity modes map to cell engine constants

**Commit**: `phase-21/D21.2: policy type system with constraint definitions`

---

## Step 3: Macro Expander (D21.3)

Create `packages/shell/src/lisp/compiler.ts`.

**Requirements**:

- `LispCompiler` class:
  ```typescript
  class LispCompiler {
    compile(expr: SExpression): ForthOutput;
    compilePolicy(policyForm: SExpression): ForthOutput;
  }
  ```

- **Expansion rules** (implement exactly as specified in PRD):
  ```
  (> amount 500)          → "500 AMOUNT-GT"
  (and (> a 5) (< b 10))  → "5 A-GT 10 B-LT BOOLAND"
  (has-capability 6)      → "6 CHECK-CAP"
  (policy ...)            → combines all checks
  ```

- **Forth output**:
  ```typescript
  interface ForthOutput {
    forthWords: string;         // "500 AMOUNT-GT ..."
    forthBytes: Uint8Array;     // packed bytes
    metadata: {
      subject?: string;
      action?: string;
      linearity?: string;
      inputExpr: string;
      compiledAt: string;
    };
  }
  ```

- **Determinism**: same input always produces exact same output
- **No I/O or external calls** during compilation

**Commit**: `phase-21/D21.3: macro expander (Lisp → Forth) with pure transformation`

---

## Step 4: Capability Token Packing (D21.4)

Create `packages/shell/src/lisp/packer.ts`.

**Requirements**:

- `packCapabilityCell(forthBytes: Uint8Array, options: PackOptions): Uint8Array`

- **Cell format**:
  - Magic + version
  - Type: `CAPABILITY`
  - Linearity: LINEAR | AFFINE | RELEVANT | FUNGIBLE
  - Payload: compiled script bytes
  - Timestamp

- **Compatibility**:
  - Output matches Zig cell engine spec
  - If Phase 12 bindings available, use them
  - Otherwise implement 256-byte header + payload

- **Example**:
  ```typescript
  const forth = "500 AMOUNT-GT HOMEOWNER-FLAG CHECK-DOMAIN BOOLAND";
  const bytes = compileForth(forth);
  const cell = packCapabilityCell(bytes, { linearity: 'LINEAR' });
  // cell is ready for cell engine
  ```

**Commit**: `phase-21/D21.4: capability cell packing (Forth → cell bytes)`

---

## Step 5: Shell Integration (D21.5)

Create `packages/shell/src/commands/eval.ts` (and extend shell routing if needed).

**Requirements**:

- **Commands**:
  ```bash
  semantos eval '(> amount 500)' --object job-1774
    → true/false

  semantos compile '(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)'
    → ~/.semantos/policies/homeowner-approval.cell

  semantos bind homeowner-approval.cell --type trades.job.plumbing
    → confirmation + type hash update

  semantos verify job-1774 --policy homeowner-approval
    → true/false
  ```

- **Implementation**:
  - `eval`: parse expr, resolve against object, return boolean
  - `compile`: parse, run through compiler + packer, write to file
  - `bind`: load cell, update extension config, register in FlowRegistry
  - `verify`: load policy, evaluate against object

**Commit**: `phase-21/D21.5: shell commands (eval, compile, bind, verify)`

---

## Step 6: Extension Config Integration (D21.6)

Modify `packages/loom/src/config/extensionConfig.ts`.

**Requirements**:

- Extend `ObjectTypeDefinition`:
  ```typescript
  interface ObjectTypeDefinition {
    // ... existing ...
    policies?: PolicyBinding[];
  }

  interface PolicyBinding {
    name: string;
    path: string;  // or inlinePayload
    inlinePayload?: string;
    description?: string;
    appliedAt?: string;
  }
  ```

- **Policy loading**:
  - At config load time, read all policy paths
  - Load each policy cell
  - Register in FlowRegistry as guards

- **Policy evaluation**:
  - FlowRunner evaluates policies as guards during flow execution
  - If policy returns false, step is blocked

**Commit**: `phase-21/D21.6: extension config policies field with loading + registry integration`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase21-gate.test.ts`.

### Unit Tests (T1–T7)

```typescript
describe("Phase 21 — Lisp parser", () => {
  // T1: parse (policy :subject homeowner ...)
  // T2: parse (and (> amount 500) (has-capability 6))
  // T3: reject invalid forms with clear errors
});

describe("Phase 21 — Lisp compiler", () => {
  // T4: (> amount 500) → "500 AMOUNT-GT"
  // T5: (and ...) → correct BOOLAND output
  // T6: (policy ...) → full output
  // T7: determinism: same input = same output
});
```

### Integration Tests (T8–T13)

```typescript
describe("Phase 21 — integration", () => {
  // T8: packer produces valid cell bytes
  // T9: semantos eval works
  // T10: semantos compile writes valid cell
  // T11: semantos verify works
  // T12: extension config policies load + register
  // T13: compiled policy = manual guard equivalence
});
```

### Round-Trip Tests (T14–T15)

```typescript
describe("Phase 21 — round-trip", () => {
  // T14: parse → compile → pack → evaluate
  // T15: parser handles comments, whitespace, multiline
});
```

### Anti-Lock Tests (T16–T18)

```typescript
describe("Phase 21 — anti-lock", () => {
  // T16: no React imports in Lisp package
  // T17: compiler has no external runtime deps
  // T18: cell packing compatible with engine (if bindings available)
});
```

**Commit**: `phase-21/T1-T18: full gate test suite`

---

## Step 8: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Adversarial review of every new file
2. Check that parser handles edge cases (deeply nested, long symbols)
3. Check that compiler output is actually valid Forth
4. Check that cell packing produces correct byte format
5. Check that policies integrate cleanly with FlowRunner guards
6. Check that extension config validates with policies
7. Write errata doc as `docs/prd/PHASE-21-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/shell/src/lisp/parser.ts` exists with pure TypeScript parser
- [ ] `packages/shell/src/lisp/types.ts` exists with policy type defs
- [ ] `packages/shell/src/lisp/compiler.ts` exists with LispCompiler
- [ ] `packages/shell/src/lisp/packer.ts` exists with cell packing
- [ ] `packages/shell/src/commands/eval.ts` exists with all verbs
- [ ] `packages/loom/src/config/extensionConfig.ts` extended with policies
- [ ] `semantos eval` works
- [ ] `semantos compile` works
- [ ] `semantos bind` works
- [ ] `semantos verify` works
- [ ] Tests T1–T18 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in Lisp package
- [ ] Errata sprint complete with `docs/prd/PHASE-21-ERRATA.md`
- [ ] All commits follow `phase-21/D21.N:`
- [ ] Branch is `phase-21-lisp-compiler`

---

## What NOT to Do

1. Do NOT build a general Lisp interpreter
2. Do NOT add closures or lambdas
3. Do NOT depend on external Lisp runtimes
4. Do NOT bypass the cell engine
5. Do NOT implement runtime evaluation
6. Do NOT change the cell engine format
7. Do NOT implement natural language → Lisp (that is Phase 22+)

---

## After Phase 21: The Full Gradient

After Phase 21, users can enter at any level:

```
Natural language
    ↓ (LLM classification)
CLI command
    ↓ (shell verb)
Lisp axiom
    ↓ (compilation)
Forth word
    ↓ (cell packing)
Cell execution
```

All five forms resolve to the same semantic operation. Same intent. Four representations.

**Post-Phase note**: "The compression gradient is now operational. Users can author policies in natural language, CLI, or Lisp. The system compiles all three to the same Forth execution form. This is the unified semantic shell."
