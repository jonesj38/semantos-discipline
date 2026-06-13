---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-12-IMPLEMENTATION-BRIDGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.706719+00:00
---

# Phase 12 — Implementation Bridge: Fuzzing, Differential Testing, P4.1 Capstone

**Depends on**: Phase 11 (Lean proofs) + Phase 11.5 (TLA+ model checking)
**Branch**: `phase-12-implementation-bridge`
**Tag**: `v12.0`

---

## Objective

Bridge the gap between abstract proofs and concrete implementation. Phase 11 proved properties of a Lean model. Phase 11.5 checked protocol properties of a TLA+ model. Phase 12 establishes that the actual Zig/WASM binary conforms to these models, and assembles the P4.1 capstone argument.

Three pillars:
1. **Property-based fuzzing** — bombard the Zig implementation with random inputs, assert the proved invariants hold
2. **Differential testing** — feed the same inputs to the Lean model and Zig implementation, verify identical outputs
3. **WASM binary integrity** — reproducible builds + hash anchoring on BSV

---

## Deliverables

### D12.0: Zig Property-Based Fuzz Harnesses

**What**: Write fuzz harnesses for the critical Zig modules. Each harness generates random inputs and asserts the corresponding Lean-proved invariant.

**Files**:
- `packages/cell-engine/fuzz/linearity_fuzz.zig`
- `packages/cell-engine/fuzz/opcode_fuzz.zig`
- `packages/cell-engine/fuzz/stack_bounds_fuzz.zig`
- `packages/cell-engine/fuzz/plexus_atomic_fuzz.zig`

**Linearity fuzzer** (`linearity_fuzz.zig`):

```
Input: random sequence of (opcode, cell_linearity) pairs, length 1..100
Setup: push a LINEAR cell onto a fresh PDA
Action: execute the opcode sequence with linearity enforcement ON
Assert:
  - After every step, the LINEAR cell appears at most once across both stacks (K1)
  - If any operation was rejected, the stack state matches the pre-operation state (K4)
  - Execution terminates within opcountLimit steps (K5)
```

**Opcode fuzzer** (`opcode_fuzz.zig`):

```
Input: random valid script (opcodes from the instruction set), length 1..50
Setup: push 2-5 cells with random linearity classes
Action: execute the script
Assert:
  - No LINEAR cell is duplicated (K1)
  - No RELEVANT cell is discarded (K1 variant)
  - All Plexus opcodes that fail leave stack unchanged (K4)
```

**Stack bounds fuzzer** (`stack_bounds_fuzz.zig`):

```
Input: random push/pop sequence, length 1..2048
Action: execute on a fresh PDA
Assert:
  - Main stack never exceeds 1024 (or whatever constants.zig says)
  - Aux stack never exceeds 256
  - Overflow returns a clean error, not a crash
  - Underflow returns a clean error, not a crash
```

**Plexus atomicity fuzzer** (`plexus_atomic_fuzz.zig`):

```
Input: for each Plexus opcode (0xC0-0xCF), generate random stack configurations
Action: execute the opcode
Assert:
  - If the opcode succeeds: stack changed correctly
  - If the opcode fails: stack is byte-for-byte identical to pre-execution (K4)
```

**Running**:
```bash
cd packages/cell-engine
zig build fuzz-linearity    # runs for 60 seconds by default
zig build fuzz-opcodes
zig build fuzz-stack
zig build fuzz-plexus
```

**Gate**: Each fuzzer runs for ≥ 60 seconds without finding a counterexample. Total: ≥ 4 minutes of fuzzing.

**Commit**: `phase-12/D12.0: property-based fuzz harnesses for linearity, opcodes, stack bounds, plexus atomicity`

---

### D12.1: Differential Test Vectors

**What**: Generate a shared set of test vectors that can be evaluated by both the Lean model and the Zig implementation. Compare outputs.

**Files**:
- `proofs/vectors/linearity-vectors.json` — input/expected-output pairs for linearity checks
- `proofs/vectors/opcode-vectors.json` — input/expected-output for opcode execution
- `proofs/vectors/plexus-vectors.json` — input/expected-output for each Plexus opcode
- `proofs/vectors/generate-vectors.ts` — Bun script that generates vectors from the Lean model
- `proofs/vectors/verify-vectors.zig` — Zig test that runs the same vectors against the implementation
- `packages/cell-engine/tests/differential_conformance.zig` — the Zig-side runner

**Vector format**:

```json
{
  "test_id": "K1-linear-dup-reject",
  "description": "DUP on LINEAR cell must fail",
  "setup": {
    "main_stack": [{"linearity": 1, "domain_flag": 1, "type_hash": "..."}],
    "aux_stack": [],
    "linearity_enforced": true
  },
  "script": [118],  // OP_DUP = 0x76
  "expected": {
    "result": "error",
    "error_code": "cannot_duplicate_linear",
    "main_stack_after": [{"linearity": 1, "domain_flag": 1, "type_hash": "..."}],
    "aux_stack_after": []
  }
}
```

**Workflow**:
1. `generate-vectors.ts` calls the Lean model (via `lake env lean --run`) to produce expected outputs
2. `differential_conformance.zig` loads the JSON vectors and runs each through the Zig PDA
3. Outputs must match exactly

**Gate**: All vectors pass in both Lean and Zig. Zero mismatches.

**Commit**: `phase-12/D12.1: differential test vectors (Lean model ↔ Zig implementation)`

---

### D12.2: Mutation Testing

**What**: Deliberately break the Zig linearity and plexus implementations. Verify that the existing conformance tests + fuzz harnesses catch every mutation.

**Files**:
- `packages/cell-engine/mutations/linearity_mutations.md` — catalog of mutations and results
- `packages/cell-engine/mutations/plexus_mutations.md`
- `packages/cell-engine/mutations/run-mutations.sh` — script to apply each mutation, run tests, verify failure

**Mutations to test**:

| ID | File | Mutation | Must Be Caught By |
|----|------|----------|-------------------|
| M1 | linearity.zig | Change `linear, .duplicate => false` to `true` | linearity_conformance.zig, linearity_fuzz.zig |
| M2 | linearity.zig | Change `linear, .discard => false` to `true` | linearity_conformance.zig, linearity_fuzz.zig |
| M3 | linearity.zig | Change `affine, .duplicate => false` to `true` | linearity_conformance.zig |
| M4 | linearity.zig | Change `relevant, .discard => false` to `true` | linearity_conformance.zig |
| M5 | plexus.zig | Remove the failure-return in OP_CHECKDOMAINFLAG (always push TRUE) | plexus_conformance.zig, plexus_atomic_fuzz.zig |
| M6 | plexus.zig | In OP_CHECKIDENTITY, skip signature verification | plexus_conformance.zig |
| M7 | plexus.zig | In OP_CHECKLINEARTYPE, read wrong header offset | plexus_conformance.zig, cell_conformance.zig |
| M8 | pda.zig | Change main stack max from 1024 to 2048 | stack_bounds_fuzz.zig (if vector-based), pda_conformance.zig |
| M9 | executor.zig | Remove opcount check (allow unlimited execution) | executor_conformance.zig |
| M10 | plexus.zig | In OP_CHECKCAPABILITY, mutate stack on failure (break atomicity) | plexus_atomic_fuzz.zig |

**Process per mutation**:
```bash
# Apply mutation (sed or manual edit)
# Run: zig build test
# Verify: at least one test fails
# Record: which test(s) caught it
# Revert mutation
```

**Kill rate target**: 100% of mutations caught. Any surviving mutant means the test suite has a gap that must be filled.

**Gate**: All 10 mutations caught. Kill rate = 100%. Results documented in markdown.

**Commit**: `phase-12/D12.2: mutation testing — 10/10 mutations caught`

---

### D12.3: WASM Reproducible Build + Binary Hash

**What**: Establish that the same Zig source + same compiler version produces the same WASM binary byte-for-byte. Record the hash.

**Files**:
- `packages/cell-engine/scripts/reproducible-build.sh`
- `packages/cell-engine/WASM-MANIFEST.json`

**reproducible-build.sh**:

```bash
#!/bin/bash
set -euo pipefail

ZIG_VERSION=$(zig version)
PROFILE=${1:-embedded}  # embedded or full

echo "Building cell-engine WASM ($PROFILE profile)"
echo "Zig version: $ZIG_VERSION"

# Clean build
rm -rf zig-out zig-cache
zig build -Dembedded=$([[ "$PROFILE" == "embedded" ]] && echo true || echo false)

WASM_PATH="zig-out/bin/cell-engine-${PROFILE}.wasm"
if [ ! -f "$WASM_PATH" ]; then
  WASM_PATH="zig-out/bin/cell-engine.wasm"
fi

HASH=$(sha256sum "$WASM_PATH" | awk '{print $1}')
SIZE=$(stat -c%s "$WASM_PATH" 2>/dev/null || stat -f%z "$WASM_PATH")

echo "Binary: $WASM_PATH"
echo "SHA-256: $HASH"
echo "Size: $SIZE bytes"

# Write manifest
cat > WASM-MANIFEST.json << EOF
{
  "profile": "$PROFILE",
  "zigVersion": "$ZIG_VERSION",
  "sha256": "$HASH",
  "sizeBytes": $SIZE,
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sourceCommit": "$(git rev-parse HEAD)"
}
EOF

echo "Manifest written to WASM-MANIFEST.json"
```

**Verification**: Build twice from the same commit. Hashes must match.

**WASM-MANIFEST.json** is committed to the repo and checked by CI. If a future build produces a different hash from the same source, something changed (compiler version, flags, source modification).

**Gate**: Two consecutive builds from the same commit produce identical SHA-256. Manifest committed.

**Commit**: `phase-12/D12.3: reproducible WASM build + binary manifest`

---

### D12.4: P4.1 Capstone Proof Document

**What**: The paper proof that assembles everything. This is the document a regulator reads.

**File**: `proofs/paper/P4.1-CAPSTONE.md`

**Structure**:

```markdown
# P4.1 — Compliance Properties Cannot Be Disabled

## Thesis
The only way to disable the verified enforcement properties is to replace
the measured binary, and that replacement is externally detectable.

## Evidence Chain (ordered by dependency)

### 0. Trusted Boot / Measurement Root (PREREQUISITE)
P4.1 is only meaningful if there is a trusted verifier OUTSIDE the WASM
binary that checks integrity before loading.
- Devices verify SHA-256(loaded_wasm) == anchored_hash at boot.
- This check is in the boot/loader sequence, not in the WASM binary (no circularity).
- Hash mismatch → refuse to load → alert operators (Test 6.2).
- The anchored hash is on BSV, verifiable by any SPV client.
- WITHOUT THIS STEP, THE REST OF THE ARGUMENT IS VACUOUS.

### 1. Kernel Invariants Are Proved (Phase 11) — Machine-Checked
K1 (Linearity): Theorem LinearityK1, proved in Lean 4. [hash of proof file]
  - K1a: no duplication while live
  - K1b: no unauthorized discard
  - K1c: no reintroduction after consumption
K2 (Auth soundness): Theorem AuthSoundnessK2, proved in Lean 4. [hash]
K3 (Domain isolation): Theorem DomainIsolationK3, proved in Lean 4. [hash]
K4 (Failure atomicity): Theorem FailureAtomicK4, proved in Lean 4. [hash]
K5 (Termination): Theorem TerminationK5, proved in Lean 4. [hash]
K7 (Cell immutability): Theorem CellImmutabilityK7, proved in Lean 4. [hash]

### 2. Protocol Properties Are Model-Checked (Phase 11.5) — Exhaustive within bounds
K6 (Hash-chain integrity): EvidenceChain.tla, verified by TLC. [log hash]
Replay impossibility: ReplayPrevention.tla, verified by TLC. [log hash]
Revocation immediacy: CertRevocation.tla, verified by TLC. [log hash]
FSM correctness: MeteringFSM.tla, verified by TLC. [log hash]
Zone enforcement: ZoneBoundary.tla, verified by TLC. [log hash]
Partition resilience: PartitionResilience.tla, verified by TLC. [log hash]

### 3. Implementation Conforms to Model (Phase 12) — Strong Empirical Evidence
NOTE: This is evidence, not proof in the Layer 1/2 sense. A verified compiler
for Zig→WASM does not exist. This is the weakest link in the chain.
- Property-based fuzzing: 4 harnesses × 60s = 240s of randomized testing. Zero failures.
- Differential testing: N vectors evaluated by both Lean model and Zig. Zero mismatches.
- Mutation testing: 10/10 mutations caught. Kill rate 100%.
- Conformance tests: 240+ Zig tests passing (Phases 0–6).
- Structured code review of linearity.zig, plexus.zig, executor.zig against Lean model.

### 4. Binary Is Deterministic and Anchored
- Reproducible build: SHA-256 of WASM binary is deterministic from source + compiler.
- WASM-MANIFEST.json records: hash, Zig version, source commit, build timestamp.
- [Future: BSV anchor transaction ID for the manifest hash]

### 5. No Configuration Pathway Disables Enforcement
- `kernel_set_enforcement(enabled)` is compile-time gated to debug builds.
- Production WASM is built with `embedded = true`.
- The `build_options` module strips the debug path at compile time.
- Code reference: `build.zig` line ~51: `options.addOption(bool, "embedded", embedded)`
- In embedded mode, `linearity.zig` enforcement is unconditional.

### 6. Database Modifications Are Irrelevant
- The WASM engine reads cell headers from the stack (in-memory).
- It does not query any external database for linearity class.
- An administrator who modifies the database changes nothing about how the engine evaluates cells.
- The engine's only inputs are: script bytes, cells on the stack, host imports.

## Compliance Test Coverage

[Table mapping each of the 25+ compliance tests to the specific proof artifact
providing kernel contribution to requirement satisfaction — theorem name,
TLA+ property, fuzz harness, or paper argument, PLUS the stated assumptions
each mapping depends on]

## Cryptographic Assumptions
[Two-level structure: idealized oracle axioms (used in Lean) and the
computational assumptions that justify them. See Appendix B of strategy doc.]

## Limitations (Honest)
[1. Host import correctness — not formally verified
 2. Implementation conformance gap — evidence, not proof
 3. Trusted boot integrity — standard root-of-trust problem
 4. Hardware correctness — outside scope of all software verification
 5. Side channels — not modeled
 6. BSV chain availability — assumed
 7. Social engineering — system prevents technical bypasses, not social ones
 8. Application-layer bypass — kernel enforces, but app must route through kernel]
```

**Gate**: Document is complete. Every compliance test maps to a specific proof artifact. No handwaving. No "we believe" — only "we proved" or "we assume" with explicit justification.

**Commit**: `phase-12/D12.4: P4.1 capstone proof document`

---

### D12.5: Compliance Coverage Matrix

**What**: A machine-readable mapping from every compliance test to its proof artifacts. This is the index a regulator or auditor uses.

**File**: `proofs/compliance-matrix.json`

**Format**:

```json
{
  "version": "1.0",
  "generatedAt": "...",
  "frameworks": {
    "IEC-62443": {
      "SR-1.1": {
        "tests": [
          {
            "id": "1.1.1",
            "title": "Command requires valid identity",
            "kernelContribution": "K2 (Authorization soundness) ensures no semantic state transition without verified identity proof",
            "additionalAssumptions": ["host_checksig correct", "crypto axioms"],
            "proofArtifacts": [
              {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean", "theorem": "auth_soundness"},
              {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig", "test": "test_check_identity_rejects_invalid"},
              {"type": "fuzz", "file": "packages/cell-engine/fuzz/plexus_atomic_fuzz.zig"}
            ],
            "kernelInvariants": ["K2"],
            "status": "supported"
          },
          {
            "id": "1.1.2",
            "title": "Stolen credential cannot be replayed",
            "kernelContribution": "K1 (Linearity) ensures consumed LINEAR objects cannot be re-consumed",
            "additionalAssumptions": ["crypto axioms"],
            "proofArtifacts": [
              {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean", "theorem": "linear_cell_unique_on_stacks"},
              {"type": "tla-property", "file": "proofs/tla/ReplayPrevention.tla", "property": "SingleConsumption"},
              {"type": "tla-property", "file": "proofs/tla/ReplayPrevention.tla", "property": "ReplayAlwaysFails"}
            ],
            "kernelInvariants": ["K1"],
            "status": "supported"
          }
        ]
      }
    }
  }
}
```

**Coverage**: Every test from the Compliance Demonstration Test Specification must appear. No gaps.

**Gate**: JSON parses. Every test has ≥ 1 proof artifact. Every test has `status: "supported"`, `kernelContribution`, and `additionalAssumptions`.

**Commit**: `phase-12/D12.5: compliance coverage matrix`

---

### D12.6: Gate Test + CI Integration

**What**: Cumulative gate test. CI runs fuzzers (short duration), differential tests, and verifies the compliance matrix.

**Files**:
- `packages/__tests__/phase12-gate.test.ts`
- `.github/workflows/gate.yml` updated

**Gate test**:

```typescript
describe("Phase 12: Implementation bridge", () => {
  test("Fuzz harnesses exist and compile", async () => {
    // zig build fuzz-linearity --check (compile only, don't run)
  });

  test("Differential test vectors all pass", async () => {
    // zig build test-differential
  });

  test("Mutation testing results document exists and reports 100% kill rate", () => {
    // Read linearity_mutations.md, parse summary table
  });

  test("WASM manifest exists with valid hash", () => {
    // Read WASM-MANIFEST.json, verify sha256 is 64 hex chars
  });

  test("Reproducible build check", async () => {
    // Build WASM, compare hash to WASM-MANIFEST.json
  });

  test("P4.1 capstone document complete", () => {
    // Verify sections 1–7 all present
  });

  test("Compliance matrix covers all tests", () => {
    // Load compliance-matrix.json
    // Verify every test ID from the spec is present
    // Verify every test has status "supported" (NOT "proved")
  });
});
```

**Commit**: `phase-12/D12.6: gate test + CI for implementation bridge`

---

## Errata Scan Checklist

1. **Fuzz harnesses actually test the invariants?** Does the linearity fuzzer check "at most once on both stacks" or just "DUP returns error"?
2. **Differential vectors cover edge cases?** Empty stack, full stack, all linearity types, all Plexus opcodes?
3. **Mutation testing thorough?** Did we mutate ALL linearity rules, not just LINEAR?
4. **Reproducible build actually reproducible?** Two builds, same hash?
5. **P4.1 capstone honest about limitations?** Does it list host import correctness, hardware, side channels?
6. **Compliance matrix complete?** Does it cover ALL 25+ tests, or just the easy ones?
7. **WASM manifest commit hash matches?** Does `sourceCommit` in the manifest match the actual git commit?
8. **No dead fuzz harnesses?** Does each harness actually run when invoked, or does it compile but skip the fuzz loop?
9. **Differential test runner handles errors correctly?** If Lean says "error" and Zig says "error", do we compare the error types too?
10. **Mutation revert clean?** After each mutation test, is the source reverted to the exact pre-mutation state?

---

## Anti-Bullshit Rules

1. **Fuzzers must run.** A fuzz harness that compiles but doesn't execute random inputs is a stub.
2. **Differential tests compare outputs, not just "both succeed."** Check the exact stack state after execution.
3. **100% mutation kill rate.** Any surviving mutant is a test gap. Fill it.
4. **Reproducible means reproducible.** Two builds, same hash, or the gate fails.
5. **The capstone document is honest.** State limitations explicitly. "We assume SHA-256 is collision resistant" is honest. "Our system is unhackable" is not.
6. **Commit after each gate.**

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

Each commit passes its gate. Fuzzers run. Differential tests match. Mutations killed. Build reproducible. Capstone complete. Matrix covers all tests.
