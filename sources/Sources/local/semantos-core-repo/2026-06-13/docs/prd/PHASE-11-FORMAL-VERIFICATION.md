---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-11-FORMAL-VERIFICATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.676558+00:00
---

# Phase 11 — Formal Verification: Lean 4 Kernel Proofs

**Depends on**: Phases 0–6 (cell-engine Zig/WASM is the proof target)
**Branch**: `phase-11-formal-verification`
**Tag**: `v11.0`

---

## Objective

Mechanically prove that the Semantos Plane kernel satisfies invariants K1–K5 and K7 using Lean 4. These invariants are the foundation of the compliance claim in the Compliance Demonstration Test Specification. Without machine-checked proofs, the claim "compliance by architecture" is marketing. With them, it's mathematics.

---

## Deliverables

### D11.0: Lean 4 Project Scaffold + Crypto Axioms

**What**: Initialize a Lean 4 project at `proofs/lean/` with lakefile, Mathlib4 dependency, and the cryptographic axiom module.

**Files**:
- `proofs/lean/lakefile.lean` — project config, Mathlib dependency
- `proofs/lean/lean-toolchain` — pin Lean version
- `proofs/lean/Semantos.lean` — root import
- `proofs/lean/Semantos/CryptoAxioms.lean` — SHA-256 collision resistance, ECDSA unforgeability, HMAC PRF axioms

**Crypto axioms** (stated precisely, not proved — standard practice):

```lean
-- Idealized oracle assumptions. These are deliberately stronger than
-- computational security definitions (which involve PPT bounds).
-- This is standard in mechanized verification — Lean has no notion
-- of computational complexity. The real-world justification rests on
-- decades of cryptanalysis of the underlying primitives.
-- See Appendix B of FORMAL-VERIFICATION-STRATEGY.md for the
-- two-level assumption structure.

axiom sha256_collision_free :
  ∀ (m1 m2 : ByteArray), m1 ≠ m2 → sha256 m1 ≠ sha256 m2
  -- Idealization of: no PPT adversary finds collisions with
  -- non-negligible probability

axiom ecdsa_existential_unforgeability :
  ∀ (pk : PubKey) (msg sig : ByteArray),
    ecdsaVerify pk msg sig = true →
    ∃ (sk : SecKey), derives pk sk
  -- Idealization of: EUF-CMA security for secp256k1
  -- Does NOT claim unique signatures

axiom hmac_collision_free :
  ∀ (k : ByteArray) (m1 m2 : ByteArray),
    m1 ≠ m2 → hmacSha256 k m1 ≠ hmacSha256 k m2
  -- Idealization of: HMAC-SHA-256 PRF security
```

**Gate**: `lake build` succeeds. Axiom module type-checks. No sorry in the codebase. Each axiom has a comment explaining what it idealizes.

**Commit**: `phase-11/D11.0: Lean 4 scaffold + cryptographic axioms`

---

### D11.1: Cell and Linearity Model

**What**: Model the 1KB cell format, the three linearity classes, and the linearity permission table — corresponding exactly to `cell.zig`, `linearity.zig`, and the 256-byte header layout.

**Files**:
- `proofs/lean/Semantos/Cell.lean`
- `proofs/lean/Semantos/Linearity.lean`

**Cell model** must capture:
- 256-byte header: magic (16), linearity (4), version (4), flags (4), refCount (2), typeHash (32), ownerId (16), timestamp (8), cellCount (4), totalSize (4), phase (1), dimension (1), parentHash (32), prevStateHash (32)
- Linearity enum: `linear | affine | relevant | debug`
- The permission table from `linearity.zig`:

| | duplicate | discard | consume | swap | inspect |
|---------|-----------|---------|---------|------|---------|
| LINEAR | ✗ | ✗ | ✓ | ✓ | ✓ |
| AFFINE | ✗ | ✓ | ✓ | ✓ | ✓ |
| RELEVANT | ✓ | ✗ | ✓ | ✓ | ✓ |
| DEBUG | ✓ | ✓ | ✓ | ✓ | ✓ |

**Model fidelity constraint**: The Lean `linearityPermits` function must be a direct transliteration of the Zig `checkLinearity` function. Every row in the table must match. If they diverge, the proof is about a different program.

**Gate**: `lake build` succeeds. The permission table is exhaustively encoded. DecidableEq instances for all enums.

**Commit**: `phase-11/D11.1: Cell structure + linearity model`

---

### D11.2: 2-PDA Model

**What**: Model the dual-stack pushdown automaton from `pda.zig` — bounded stacks, push/pop/peek operations, stack depth queries.

**Files**:
- `proofs/lean/Semantos/PDA.lean`
- `proofs/lean/Semantos/BoundedStack.lean`

**PDA model** must capture:
- Main stack: max 1024 cells
- Aux stack: max 256 cells
- Operations: `spush`, `spop`, `speek`, `speekAt`, `apush`, `apop`, `sdepth`, `adepth`
- Error returns: `stack_overflow`, `stack_underflow`, `invalid_depth`
- LIFO ordering for both stacks

**BoundedStack** — a generic bounded LIFO:

```lean
structure BoundedStack (α : Type) (maxDepth : Nat) where
  items : List α
  depth_invariant : items.length ≤ maxDepth
```

Push/pop return `Option` or `Except` to model overflow/underflow.

**Gate**: `lake build` succeeds. Push to full stack returns error. Pop from empty stack returns error. Push then pop returns original item.

**Commit**: `phase-11/D11.2: 2-PDA model with bounded stacks`

---

### D11.3: Opcode Semantics Model

**What**: Model the standard Bitcoin Script opcodes and Plexus custom opcodes (0xC0–0xCF) from `opcodes/standard.zig`, `opcodes/macro.zig`, and `opcodes/plexus.zig`.

**Files**:
- `proofs/lean/Semantos/Opcodes/Standard.lean` — DUP, DROP, SWAP, OVER, ROT, NIP, PICK, etc.
- `proofs/lean/Semantos/Opcodes/Plexus.lean` — OP_CHECKLINEARTYPE through OP_DEREF_POINTER
- `proofs/lean/Semantos/Opcodes/Classify.lean` — maps each opcode to its `StackOp` (duplicate/discard/consume/swap/inspect)

**Critical modeling requirement**: Each opcode's effect on the PDA state must be modeled as a function `PDA → Except Error PDA`. The Plexus opcodes must use the **peek-then-mutate** pattern:

```lean
def opCheckDomainFlag (pda : PDA) : Except Error PDA :=
  -- Step 1: peek (no mutation)
  let expectedFlag ← pda.speek 0    -- top of stack
  let cell ← pda.speek 1            -- cell below
  let actualFlag := cell.header.domainFlag
  -- Step 2: check
  if actualFlag ≠ expectedFlag then
    Except.error .domain_flag_mismatch  -- stack UNCHANGED
  else
    -- Step 3: mutate only on success
    let pda' ← pda.spop              -- remove expected flag
    pda'.spush trueCell              -- push TRUE
```

**Gate**: `lake build` succeeds. Each Plexus opcode modeled. Opcode classification covers all opcodes in the instruction set.

**Commit**: `phase-11/D11.3: opcode semantics model (standard + Plexus)`

---

### D11.4: Executor Model

**What**: Model the execution loop from `executor.zig` — script loading, sequential opcode dispatch, opcount enforcement, termination.

**Files**:
- `proofs/lean/Semantos/Executor.lean`

**Executor model**:

```lean
structure ExecutorState where
  pda : PDA
  script : List Opcode
  pc : Nat
  opcount : Nat
  opcountLimit : Nat
  linearityEnforced : Bool

def step (state : ExecutorState) : Except Error ExecutorState :=
  if state.opcount ≥ state.opcountLimit then
    Except.error .opcount_exceeded
  else if state.pc ≥ state.script.length then
    Except.ok state  -- script complete
  else
    let op := state.script[state.pc]
    -- Linearity gate: check before executing
    if state.linearityEnforced then
      let stackOp := classifyOp op
      let topCell ← state.pda.speek 0
      if ¬(linearityPermits topCell.linearity stackOp) then
        Except.error (linearityError topCell.linearity stackOp)
      else
        executeOp op { state with pc := state.pc + 1, opcount := state.opcount + 1 }
    else
      executeOp op { state with pc := state.pc + 1, opcount := state.opcount + 1 }
```

**Key property**: No backward jumps. `pc` increments monotonically. The instruction set has no JMP, CALL, GOTO, or any control flow that decreases `pc`.

**Gate**: `lake build` succeeds. `step` is total (always returns). `pc` monotonically increases.

**Commit**: `phase-11/D11.4: executor model with opcount + linearity gate`

---

### D11.5: Kernel Invariant Theorems (K1–K5, K7)

**What**: Prove the 6 kernel invariants as Lean theorems. This is the deliverable that matters.

**Files**:
- `proofs/lean/Semantos/Theorems/LinearityK1.lean`
- `proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean`
- `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean`
- `proofs/lean/Semantos/Theorems/FailureAtomicK4.lean`
- `proofs/lean/Semantos/Theorems/TerminationK5.lean`
- `proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean`

**Theorem K1 (Linearity)** — three sub-theorems:

*K1a (No duplication while live)*:

```lean
theorem linear_cell_no_duplicate :
  ∀ (state : ExecutorState) (op : Opcode),
    state.linearityEnforced = true →
    classifyOp op = .duplicate →
    (state.pda.speek 0).linearity = .linear →
    step state = Except.error (.cannot_duplicate_linear) := by
  ...
```

*K1b (No unauthorized discard)*:

```lean
theorem linear_cell_no_discard :
  ∀ (state : ExecutorState) (op : Opcode),
    state.linearityEnforced = true →
    classifyOp op = .discard →
    (state.pda.speek 0).linearity = .linear →
    step state = Except.error (.cannot_discard_linear) := by
  ...
```

*K1c (No reintroduction — the strong version)*:

```lean
theorem linear_cell_unique_on_stacks :
  ∀ (trace : List ExecutorState) (cell : Cell),
    cell.linearity = .linear →
    validTrace trace →
    countOccurrences cell (allStackItems trace.last) ≤ 1 := by
  -- Key insight: cell identity includes prevStateHash + timestamp.
  -- A new cell with same payload has different header fields,
  -- so it is a distinct Cell value in the model.
  ...
```

**Theorem K2 (Authorization Soundness)**: Any transition that changes authenticated semantic state (identity verification, capability check, domain flag check) requires successful verification of an authorized identity proof. Purely local stack transformations (arithmetic, hashing, data manipulation) are excluded.

**Theorem K3 (Domain Isolation)**: OP_CHECKDOMAINFLAG pushes TRUE iff the domain flags match. No other code path produces a TRUE result for domain checking.

**Theorem K4 (Failure Atomicity)**: For all Plexus opcodes, if the opcode returns an error, the PDA state is identical to the state before the opcode was called.

```lean
theorem plexus_failure_atomic :
  ∀ (pda : PDA) (op : PlexusOpcode),
    isError (executePlexus op pda) →
    pda = (executePlexus op pda).getState := by
  ...
```

**Theorem K5 (Termination)**: Every execution terminates in at most `opcountLimit` steps.

```lean
theorem execution_terminates :
  ∀ (state : ExecutorState),
    ∃ (n : Nat), n ≤ state.opcountLimit ∧
      (iterate step state n).isTerminal := by
  ...
```

**Theorem K7 (Cell Immutability)**: After cell packing, the header linearity field cannot be changed by any operation in the instruction set.

**Gate**: `lake build` succeeds. **Zero `sorry` in any theorem file.** Every theorem is fully proved.

**Commit**: `phase-11/D11.5: kernel invariant theorems K1–K5, K7 — all proved`

---

### D11.6: Gate Test + CI Integration

**What**: A Bun gate test that verifies the Lean proofs compile, and CI workflow that runs `lake build` on every push to the phase branch.

**Files**:
- `packages/__tests__/phase11-gate.test.ts` — cumulative gate (Phase 0 + Phase 11)
- `.github/workflows/gate.yml` — updated with Lean 4 build step

**Gate test**:

```typescript
describe("Phase 11: Formal verification", () => {
  test("Lean 4 project builds without sorry", async () => {
    // Run: lake build
    // Grep output for "sorry" — must be zero
  });

  test("All theorem files present", () => {
    // Check: LinearityK1.lean, AuthSoundnessK2.lean, DomainIsolationK3.lean,
    //        FailureAtomicK4.lean, TerminationK5.lean, CellImmutabilityK7.lean
  });

  test("Lean model matches Zig source constants", () => {
    // Cross-check: linearity enum values, stack bounds, header offsets
    // Read from Lean source, compare to Zig constants
  });
});
```

**CI addition**:

```yaml
lean:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: leanprover/lean4-action@v1
    - run: cd proofs/lean && lake build
    - name: No sorry in proofs
      run: |
        if grep -rn "sorry" proofs/lean/Semantos/Theorems/ --include="*.lean"; then
          echo "FAIL: Unfinished proofs (sorry found)"
          exit 1
        fi
```

**Gate**: Gate test passes. CI runs Lean build. No sorry.

**Commit**: `phase-11/D11.6: gate test + CI for Lean proofs`

---

## Errata Scan Checklist

After all deliverables, audit for:

1. Any `sorry` in theorem files (zero tolerance)
2. Any Lean model that diverges from the Zig source:
   - Linearity table mismatch (compare `Linearity.lean` row-by-row against `linearity.zig`)
   - Stack bounds mismatch (1024 main, 256 aux)
   - Header offset mismatch (check byte offsets in `Cell.lean` vs `cell.zig`)
   - Opcode classification mismatch (check every opcode's StackOp)
3. Theorems that prove a weaker property than claimed (e.g., proving "LINEAR can't be DUPed" but not proving "LINEAR appears at most once on all stacks")
4. Missing edge cases in K4 (failure atomicity) — did we cover ALL Plexus opcodes, not just a subset?
5. K5 (termination) — did we actually prove termination for ALL opcodes, or only for the ones without host imports?
6. Axioms not documented as idealizations — each axiom MUST have a comment explaining (a) what real-world assumption it idealizes, and (b) why the idealization is acceptable in a mechanized proof context
7. Gate test that checks file existence but not proof completeness

---

## Anti-Bullshit Rules

1. **No sorry.** A theorem with sorry is not a theorem. It's a wish.
2. **No axiom inflation.** We axiomatize crypto primitives. Everything else must be proved from the model. If you need a new axiom, document why in the file header.
3. **Model fidelity.** If the Lean model says the main stack has 2048 slots but the Zig code says 1024, the proof is about a fantasy program. Every constant must match.
4. **No structural proofs of behavioral properties.** "The function exists and type-checks" is not a proof that it does the right thing. Prove the behavior.
5. **Commit after each deliverable gate, not at the end.**
6. **Read the Zig source first.** Before modeling any module in Lean, read the corresponding .zig file cover to cover. If you model from memory or from the PRD, you'll model the spec, not the implementation.
