---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-12-FULL-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.697396+00:00
---

# Phase 12 — Full Execution Prompt (Git Hygiene + Build + Errata)

> Paste this into a fresh Claude Code session. It handles git cleanup, Phase 12 execution, and errata — end to end.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify Phase 11 + 11.5 are complete

```bash
# Lean proofs exist (note: K2 is AuthSoundnessK2, NOT AuthTotalityK2) and have no sorry
ls proofs/lean/Semantos/Theorems/*.lean
grep -rn "sorry" proofs/lean/Semantos/Theorems/ --include="*.lean" && echo "FAIL" || echo "PASS"

# TLA+ specs exist
ls proofs/tla/*.tla

# Both phases committed
git log --oneline --all | grep -i "phase.11"
```

All Lean theorem files must exist with zero sorry. All TLA+ specs must exist. Both phases committed. If anything is missing, STOP.

### 0.4 Create Phase 12 branch

```bash
git checkout -b phase-12-implementation-bridge
```

### 0.5 Verify Zig builds and tests pass

```bash
cd packages/cell-engine
zig build test 2>&1 | tail -10
```

If Zig tests fail, STOP. The implementation we're bridging to must be correct.

### 0.6 Set git identity

```bash
git config user.email 2>/dev/null || git config user.email "dev@semantos.dev"
git config user.name 2>/dev/null || git config user.name "Semantos Dev"
```

**GATE**: Clean branch, Lean proofs verified, TLA+ specs present, Zig tests passing. Proceed.

---

## PART 1: READ BEFORE YOU WRITE

**Read first** (requirements):
- `docs/prd/PHASE-12-IMPLEMENTATION-BRIDGE.md` — deliverables D12.0–D12.6
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — the P4.1 capstone structure (Section 7)

**Read second** (the code you are fuzzing/testing):
- `packages/cell-engine/src/linearity.zig` — the linearity permission table
- `packages/cell-engine/src/pda.zig` — stack operations
- `packages/cell-engine/src/opcodes/plexus.zig` — Plexus opcodes, peek-then-mutate
- `packages/cell-engine/src/executor.zig` — execution loop
- `packages/cell-engine/src/constants.zig` — all bounds and magic values

**Read third** (what the Lean model says):
- `proofs/lean/Semantos/Linearity.lean` — the permission table as modeled
- `proofs/lean/Semantos/PDA.lean` — stack bounds as modeled
- `proofs/lean/Semantos/Opcodes/Classify.lean` — opcode classification
- `proofs/lean/Semantos/CryptoAxioms.lean` — idealized oracle assumptions (deliberately stronger than computational definitions)

Compare Lean model constants against Zig constants. Note any discrepancies — those are bugs in Phase 11 that need fixing. Also verify the Lean theorems use `AuthSoundnessK2` (NOT `AuthTotalityK2`), and that K1 has all three sub-theorems (K1a, K1b, K1c).

**Read fourth** (existing Zig tests — know what's already covered):
- `packages/cell-engine/tests/linearity_conformance.zig`
- `packages/cell-engine/tests/plexus_conformance.zig`
- `packages/cell-engine/tests/pda_conformance.zig`
- `packages/cell-engine/tests/executor_conformance.zig`

**Read fifth**:
- `docs/BRANCHING-AND-CI-POLICY.md`

---

## PART 2: EXECUTE PHASE 12

### D12.0: Fuzz harnesses

1. Create `packages/cell-engine/fuzz/` directory.
2. Write `linearity_fuzz.zig`:
   - Generate random (opcode, cell_linearity) sequences
   - Push a LINEAR cell, execute sequence with enforcement ON
   - Assert K1: cell appears at most once across both stacks after every step
   - Assert K4: rejected operations leave stack unchanged
3. Write `opcode_fuzz.zig`:
   - Generate random valid scripts
   - Push cells with random linearity classes
   - Assert no LINEAR duplicated, no RELEVANT discarded
4. Write `stack_bounds_fuzz.zig`:
   - Random push/pop sequences
   - Assert bounds respected, errors clean (no crash)
5. Write `plexus_atomic_fuzz.zig`:
   - For each Plexus opcode, random stack configs
   - Assert: failure ⟹ stack unchanged
6. Add fuzz targets to `build.zig`.
7. Run each for ≥ 60 seconds.

**Commit**: `phase-12/D12.0: property-based fuzz harnesses`

### D12.1: Differential test vectors

1. Design vector format (JSON).
2. Write `generate-vectors.ts` — produces vectors from the Lean model (or hand-craft vectors that match the Lean theorems).
3. Write `differential_conformance.zig` — loads vectors, runs through Zig PDA, compares.
4. Generate ≥ 50 vectors covering:
   - All linearity types × all operation types (K1 matrix)
   - All Plexus opcodes in success + failure modes (K2, K3, K4)
   - Stack at max depth (K5 bounds)
   - Empty stack operations (edge cases)
5. Run. Zero mismatches.

**Commit**: `phase-12/D12.1: differential test vectors (Lean ↔ Zig)`

### D12.2: Mutation testing

1. For each of the 10 mutations listed in the PRD:
   - Apply the mutation to the Zig source
   - Run `zig build test`
   - Record which tests catch it
   - Revert the mutation
2. Document results in `mutations/linearity_mutations.md` and `mutations/plexus_mutations.md`.
3. If any mutation survives (no test catches it), write a new test that DOES catch it, then re-run.
4. Kill rate must be 100%.

**Commit**: `phase-12/D12.2: mutation testing — 10/10 mutations caught`

### D12.3: Reproducible WASM build

1. Write `scripts/reproducible-build.sh`.
2. Run it twice from the same commit.
3. Compare SHA-256 hashes — must be identical.
4. Write `WASM-MANIFEST.json` with hash, Zig version, source commit.
5. Commit the manifest.

**Commit**: `phase-12/D12.3: reproducible WASM build + binary manifest`

### D12.4: P4.1 capstone

1. Write `proofs/paper/P4.1-CAPSTONE.md`.
2. Structure per the PRD: sections 0–7 (Section 0 = Trusted Boot prerequisite — WITHOUT THIS, THE REST IS VACUOUS).
3. Section 3 (Implementation Conformance) MUST be labeled "Strong Empirical Evidence" with explicit note: "This is evidence, not proof in the Layer 1/2 sense."
4. Include the compliance test coverage table with `kernelContribution` and `additionalAssumptions` columns. Status = "supported", NOT "proved".
5. State cryptographic assumptions using the two-level structure: idealized oracle axioms (Lean) + computational assumptions that justify them.
6. State limitations honestly — all 8+ items from the PRD.
7. For each claim, cite the specific file and theorem/property/test.

**Commit**: `phase-12/D12.4: P4.1 capstone proof document`

### D12.5: Compliance matrix

1. Write `proofs/compliance-matrix.json`.
2. Cover EVERY test from the Compliance Demonstration Test Specification:
   - Part 1: IEC 62443 — Tests 1.1.1, 1.1.2, 1.2.1, 1.3.1, 2.1.1, 2.1.2, 3.3.1, 3.4.1
   - Part 2: EU AI Act — Tests 2.1, 2.2, 2.3, 2.4
   - Part 3: GDPR — Tests 3.1, 3.2, 3.3
   - Part 4: Basel III/IV — Tests 4.1, 4.2
   - Part 5: HIPAA — Tests 5.1, 5.2, 5.3
   - Part 6: NIS2 — Tests 6.1, 6.2
   - Part 7: Cross-Framework — Tests P1.1, P2.1, P3.1, P4.1
3. Every test must have status "supported" (NOT "proved") and ≥ 1 proof artifact. Use `kernelContribution` and `additionalAssumptions` fields per the PRD format.

**Commit**: `phase-12/D12.5: compliance coverage matrix`

### D12.6: Gate test + CI

1. Write `packages/__tests__/phase12-gate.test.ts`.
2. Update `.github/workflows/gate.yml`.
3. Run gate.

**Commit**: `phase-12/D12.6: gate test + CI for implementation bridge`

---

## PART 3: ERRATA SPRINT

### 3.1 Files to audit

All files under `packages/cell-engine/fuzz/`, `proofs/vectors/`, `packages/cell-engine/mutations/`, `proofs/paper/`, `proofs/compliance-matrix.json`, and the gate test.

### 3.2 Scan checklist

1. **Fuzz harnesses actually fuzz?** Do they generate random inputs, or use fixed inputs disguised as fuzz?
2. **Linearity fuzzer checks BOTH stacks?** Not just main stack — check main + aux combined.
3. **Differential vectors cover all Plexus opcodes?** Not just a subset?
4. **Mutation testing reverted cleanly?** Is the source identical to pre-mutation after each test?
5. **Reproducible build actually tested twice?** Two builds, same hash, verified?
6. **P4.1 capstone references real files?** Every file path in the document actually exists?
7. **P4.1 capstone Section 0 (Trusted Boot) present?** Without this, the rest is vacuous. Is it explicit?
8. **P4.1 Section 3 labeled as "Strong Empirical Evidence"?** Does it say "NOT proof"?
9. **Compliance matrix covers all 25+ tests?** No gaps?
10. **Compliance matrix uses "supported" not "proved"?** Every test has `kernelContribution` and `additionalAssumptions`?
11. **Compliance matrix proof artifacts exist?** Every referenced file actually exists?
9. **Gate test runs fuzzers in CI?** With a short timeout (10s) so CI doesn't hang?
10. **No mock fuzz results?** The fuzzer output must be from an actual run, not fabricated.

### 3.3 Write errata doc

Create `docs/prd/PHASE-12-ERRATA.md`.

### 3.4 Fix and commit

```bash
git add <fixed files> docs/prd/PHASE-12-ERRATA.md
git commit -m "Phase 12 errata: audit doc + fix N issues

<list fixes>

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## ANTI-BULLSHIT RULES

1. **Fuzzers must actually fuzz.** Random inputs. Not 3 hardcoded test cases with "fuzz" in the filename.
2. **Differential tests compare exact state.** Not just "both returned OK."
3. **100% mutation kill rate.** No exceptions. No "this mutation is unlikely in practice."
4. **Reproducible means two builds, same hash.** Not "we expect it to be reproducible."
5. **The capstone is honest about what we can't prove.** Hardware, side channels, host imports, BSV availability, implementation conformance gap (no verified compiler), application-layer bypass. Section 3 says "evidence, not proof."
6. **The compliance matrix has zero gaps.** Every test. Every framework. No "TBD."
7. **Commit after each gate.**

---

## Completion Check

```
<hash> Phase 12 errata: audit doc + fix N issues
<hash> phase-12/D12.6: gate test + CI for implementation bridge
<hash> phase-12/D12.5: compliance coverage matrix
<hash> phase-12/D12.4: P4.1 capstone proof document
<hash> phase-12/D12.3: reproducible WASM build + binary manifest
<hash> phase-12/D12.2: mutation testing — 10/10 mutations caught
<hash> phase-12/D12.1: differential test vectors (Lean ↔ Zig)
<hash> phase-12/D12.0: property-based fuzz harnesses
```

Each commit passes its gate. Fuzzers actually ran. Vectors actually matched. Mutations actually killed. Build actually reproducible. Capstone actually complete. Matrix actually covers everything.

---

## What You Have When This Is Done

At the end of Phase 12, you have:

- **7 machine-checked proofs** (Lean 4) of kernel invariants K1–K5, K7
- **6 model-checked protocol properties** (TLA+) covering K6 + all distributed properties
- **4 fuzz harnesses** that have pounded the implementation with random inputs
- **50+ differential test vectors** proving the implementation matches the model
- **100% mutation kill rate** proving the test suite catches all critical regressions
- **A reproducible WASM binary** with a committed SHA-256 manifest
- **A capstone proof document** that a regulator can read
- **A compliance coverage matrix** mapping every regulatory test to its proof artifact

This is the strongest evidence package that can be assembled for the claim "compliance by architecture, not by control." P4.1 is not a marketing claim. It's a mathematical claim, backed by machine-checked proofs, with an honest statement of assumptions and limitations.
