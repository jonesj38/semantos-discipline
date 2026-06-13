---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-11-FULL-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.686243+00:00
---

# Phase 11 — Full Execution Prompt (Git Hygiene + Build + Errata)

> Paste this into a fresh Claude Code session. It handles git cleanup, Phase 11 execution, and errata — end to end.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
git stash list
```

Read the output. Know what branch you're on, what's uncommitted, what's stale.

### 0.2 Commit or discard uncommitted work

If uncommitted changes exist:
- Read each changed file. Is this previous phase work that should be committed, or stale junk?
- Commit real work in logical groups (stage files explicitly, never `git add -A`).
- Discard stale files: `git checkout -- <file>`.
- Ignore untracked `.claude/worktrees/` artifacts — do NOT commit them.

### 0.3 Find the right branch point

Previous phases (through Phase 10) should be committed. Verify:

```bash
git log --oneline --all | grep -i "phase.10\|phase.9.5\|errata"
```

Branch from wherever the latest completed phase lives.

### 0.4 Create the Phase 11 branch

```bash
git checkout -b phase-11-formal-verification
```

### 0.5 Verify prerequisites

The cell-engine Zig source is the proof target. These files MUST exist:

```bash
ls packages/cell-engine/src/linearity.zig \
   packages/cell-engine/src/pda.zig \
   packages/cell-engine/src/cell.zig \
   packages/cell-engine/src/executor.zig \
   packages/cell-engine/src/opcodes/plexus.zig \
   packages/cell-engine/src/opcodes/standard.zig \
   packages/cell-engine/src/constants.zig
```

All 7 must exist. These are what we're proving properties about.

Also verify the Zig tests pass (they're the behavioral baseline):

```bash
cd packages/cell-engine && zig build test 2>&1 | tail -5
```

If Zig tests fail, STOP. Fix them before attempting formal proofs of a broken implementation.

### 0.6 Install Lean 4

```bash
# Check if elan/lean is available
lean --version 2>/dev/null || echo "NEED LEAN INSTALL"
```

If Lean is not installed:
```bash
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y
source ~/.profile
```

Verify: `lean --version` should show 4.x.

### 0.7 Set git identity if needed

```bash
git config user.email 2>/dev/null || git config user.email "dev@semantos.dev"
git config user.name 2>/dev/null || git config user.name "Semantos Dev"
```

**GATE**: Clean branch, clean working tree, Zig source verified, Lean installed. Proceed.

---

## PART 1: READ BEFORE YOU WRITE

**Do not skip this.** The formal model must exactly match the implementation. If you model from imagination, the proofs are about a fantasy program.

**Read first** (your requirements):
- `docs/prd/PHASE-11-FORMAL-VERIFICATION.md` — deliverables D11.0–D11.6
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — the overall proof architecture and compliance mapping

**Read second** (the Zig code you are modeling — read ALL of these cover to cover):
- `packages/cell-engine/src/linearity.zig` — the permission table, LinearityType enum, checkLinearity function
- `packages/cell-engine/src/pda.zig` — dual-stack machine, push/pop/peek, bounds
- `packages/cell-engine/src/cell.zig` — cell structure, header layout, magic bytes
- `packages/cell-engine/src/constants.zig` — all numeric constants (stack sizes, header offsets, magic values)
- `packages/cell-engine/src/executor.zig` — execution loop, opcount, linearity gate
- `packages/cell-engine/src/opcodes/plexus.zig` — all Plexus opcodes (0xC0–0xCF), peek-then-mutate pattern
- `packages/cell-engine/src/opcodes/standard.zig` — Bitcoin Script opcodes, which ones are DUP/DROP/SWAP

**Read third** (Zig conformance tests — these are the behavioral specification):
- `packages/cell-engine/tests/linearity_conformance.zig`
- `packages/cell-engine/tests/pda_conformance.zig`
- `packages/cell-engine/tests/plexus_conformance.zig`
- `packages/cell-engine/tests/executor_conformance.zig`
- `packages/cell-engine/tests/cell_conformance.zig`

**Read fourth** (branching and CI policy):
- `docs/BRANCHING-AND-CI-POLICY.md`

**After reading**: Make a mental (or written) cross-reference:
- What are the exact stack bounds? (main: ?, aux: ?)
- What are the exact header byte offsets for linearity, domainFlag, typeHash, ownerId?
- What opcodes are classified as duplicate? discard? consume? swap? inspect?
- What is the exact error returned for each linearity violation?
- What is the opcount limit?

These numbers go directly into the Lean model. If they're wrong, the proofs prove nothing.

---

## PART 2: EXECUTE PHASE 11

Follow the deliverables in `docs/prd/PHASE-11-FORMAL-VERIFICATION.md` in order. Commit after each deliverable passes its gate.

### D11.0: Lean scaffold + crypto axioms

1. Create `proofs/lean/` directory structure.
2. Initialize with `lake init Semantos` or manually write lakefile.lean.
3. Add Mathlib4 dependency (for `Fin`, `Vector`, `ByteArray` utilities).
4. Write `Semantos/CryptoAxioms.lean` with the three standard cryptographic axioms.
5. Run `lake build`. Must succeed.

**Commit**: `phase-11/D11.0: Lean 4 scaffold + cryptographic axioms`

### D11.1: Cell + linearity model

1. Read `cell.zig` and `constants.zig` again. Extract every header offset and size.
2. Write `Semantos/Cell.lean` — model the cell header as a structure with typed fields.
3. Read `linearity.zig` again. Copy the permission table exactly.
4. Write `Semantos/Linearity.lean` — linearity enum, StackOp enum, `linearityPermits` function.
5. Write exhaustive unit lemmas: `linearityPermits .linear .duplicate = false`, etc.
6. `lake build`. Must succeed.

**Commit**: `phase-11/D11.1: Cell structure + linearity model`

### D11.2: 2-PDA model

1. Read `pda.zig` again. Note the exact stack bounds and operation signatures.
2. Write `Semantos/BoundedStack.lean` — generic bounded LIFO with push/pop/peek returning Except.
3. Write `Semantos/PDA.lean` — dual-stack machine instantiated at (1024, 256) or whatever the Zig constants say.
4. Prove basic stack properties: push-then-pop identity, overflow detection, underflow detection.
5. `lake build`. Must succeed.

**Commit**: `phase-11/D11.2: 2-PDA model with bounded stacks`

### D11.3: Opcode semantics

1. Read `opcodes/standard.zig`, `opcodes/macro.zig`, `opcodes/plexus.zig` cover to cover.
2. For each opcode, determine: does it duplicate, discard, consume, swap, or inspect the top of stack?
3. Write `Semantos/Opcodes/Classify.lean` — the classification function.
4. Write `Semantos/Opcodes/Standard.lean` — each standard opcode as a PDA → Except Error PDA function.
5. Write `Semantos/Opcodes/Plexus.lean` — each Plexus opcode using the peek-then-mutate pattern.
6. `lake build`. Must succeed.

**Commit**: `phase-11/D11.3: opcode semantics model (standard + Plexus)`

### D11.4: Executor model

1. Read `executor.zig` cover to cover.
2. Write `Semantos/Executor.lean` — the step function, script representation, opcount enforcement.
3. Prove: `pc` monotonically increases. `opcount` monotonically increases. No backward control flow.
4. `lake build`. Must succeed.

**Commit**: `phase-11/D11.4: executor model with opcount + linearity gate`

### D11.5: PROVE THE THEOREMS

This is the hard part. Take your time.

1. Write `Semantos/Theorems/LinearityK1.lean` — three sub-theorems:
   - K1a (No duplication while live): DUP on LINEAR cell → error (direct from permission table).
   - K1b (No unauthorized discard): DROP on LINEAR cell → error (direct from permission table).
   - K1c (No reintroduction — the strong version): across any valid execution trace, a LINEAR cell appears at most once on all stacks combined.

2. Write `Semantos/Theorems/AuthSoundnessK2.lean` (Authorization Soundness — NOT "Authentication Totality"):
   - Prove: any transition that changes authenticated semantic state (identity verification, capability check, domain flag check) requires successful verification of an authorized identity proof.
   - Prove: purely local stack transformations (arithmetic, hashing, data manipulation) are excluded from this requirement.
   - Prove: executing OP_CHECKIDENTITY with invalid signature → error, stack unchanged.
   - Prove: no opcode other than OP_CHECKIDENTITY can produce an identity-verified state.

3. Write `Semantos/Theorems/DomainIsolationK3.lean`:
   - Prove: OP_CHECKDOMAINFLAG pushes TRUE iff flags match.
   - Prove: failure case leaves stack unchanged.

4. Write `Semantos/Theorems/FailureAtomicK4.lean`:
   - For EVERY Plexus opcode (0xC0–0xCF), prove: if the opcode returns error, the PDA state equals the input state.

5. Write `Semantos/Theorems/TerminationK5.lean`:
   - Prove: for any script and initial state, execution terminates in ≤ opcountLimit steps.
   - Key insight: no backward jumps + opcount increments monotonically + bounded limit.

6. Write `Semantos/Theorems/CellImmutabilityK7.lean`:
   - Prove: no opcode in the instruction set modifies the linearity field of a cell on the stack.
   - Prove: no opcode modifies the header of a cell after it has been packed.

7. `lake build`. Must succeed. **ZERO sorry anywhere in the Theorems/ directory.**

**Commit**: `phase-11/D11.5: kernel invariant theorems K1–K5, K7 — all proved`

### D11.6: Gate test + CI

1. Write `packages/__tests__/phase11-gate.test.ts`:
   - Verify Lean project builds (`lake build`)
   - Verify all theorem files exist
   - Verify no `sorry` in theorem files
   - Cross-check constants between Lean model and Zig source

2. Update `.github/workflows/gate.yml` with Lean build step.

3. Run the gate: `bun test packages/__tests__/phase11-gate.test.ts`

**Commit**: `phase-11/D11.6: gate test + CI for Lean proofs`

---

## PART 3: ERRATA SPRINT

### 3.1 Files to audit

Every file under `proofs/lean/Semantos/`. Plus the gate test.

### 3.2 Scan checklist

1. **Any `sorry`?** Zero tolerance. A sorry is not a proof.
2. **Linearity table match?** Compare `Linearity.lean` exhaustively against `linearity.zig`. Every cell in the table must match.
3. **Stack bounds match?** Compare `PDA.lean` bounds against `constants.zig`. Are they exactly 1024 and 256?
4. **Header offsets match?** Compare `Cell.lean` field offsets against the header layout in `cell.zig` comments. Byte for byte.
5. **Opcode classification match?** For every opcode in `standard.zig` that calls DUP/DROP/SWAP etc., verify `Classify.lean` assigns the correct StackOp.
6. **Plexus opcode coverage?** Are ALL opcodes 0xC0–0xCF modeled, or only a subset? Missing opcodes are holes in the K4 proof.
7. **Axiom audit**: Are the crypto axioms stated as idealized oracle assumptions? SHA-256 collision resistance is `m1 ≠ m2 → H(m1) ≠ H(m2)`, which is deliberately stronger than computational security definitions (no PPT bound). Each axiom MUST have a comment explaining (a) what real-world assumption it idealizes, and (b) why the idealization is standard practice in mechanized verification.
8. **Theorem strength**: Does K1 actually prove "at most once on all stacks" or just "DUP returns error"? The latter is necessary but not sufficient.
9. **K5 completeness**: Does the termination proof cover host import opcodes? Host imports are external calls — if the host doesn't return, the executor doesn't terminate. Is this scoped out explicitly?
10. **No hardcoded test expectations matching default values.** The gate test must verify real properties.

### 3.3 Write errata doc

Create `docs/prd/PHASE-11-ERRATA.md` in the established format.

### 3.4 Fix MUST FIX items and commit

```bash
git add <fixed files> docs/prd/PHASE-11-ERRATA.md
git commit -m "Phase 11 errata: audit doc + fix N issues

BUG-1: ...
INC-1: ...

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## ANTI-BULLSHIT RULES

1. **No sorry.** Not one. Not in a helper lemma. Not in a "we'll come back to this." No sorry.
2. **Model matches implementation.** Every constant, every enum value, every table row. If the Lean says 2048 and the Zig says 1024, the proof is worthless.
3. **Read the Zig first.** Before writing each Lean file, read the corresponding Zig file. Not the PRD. Not the strategy doc. The Zig.
4. **Prove the strong version.** "DUP on LINEAR returns error" is K1a, not all of K1. You need K1a + K1b + K1c. Prove "LINEAR cells appear at most once across all stacks in any valid execution trace" (K1c).
5. **Commit after each gate.** Not at the end. Not in one big commit.
6. **No axiom creep.** Three crypto axioms. If you need more axioms, justify each one in the file header.

---

## Completion Check

`git log main..HEAD --oneline` should show approximately:

```
<hash> Phase 11 errata: audit doc + fix N issues
<hash> phase-11/D11.6: gate test + CI for Lean proofs
<hash> phase-11/D11.5: kernel invariant theorems K1–K5, K7 — all proved
<hash> phase-11/D11.4: executor model with opcount + linearity gate
<hash> phase-11/D11.3: opcode semantics model (standard + Plexus)
<hash> phase-11/D11.2: 2-PDA model with bounded stacks
<hash> phase-11/D11.1: Cell structure + linearity model
<hash> phase-11/D11.0: Lean 4 scaffold + cryptographic axioms
```

Each commit builds. Zero sorry. Constants match. Proofs are real.
