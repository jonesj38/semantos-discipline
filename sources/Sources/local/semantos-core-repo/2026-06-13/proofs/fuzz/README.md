---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/fuzz/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.352122+00:00
---

# Formal Verification Harness — Design Document

This document is the canonical reference for how Semantos closes the gap between
what is formally proved and what is deployed. It governs the three-tier testing
structure, the oracle pattern used for differential fuzzing, and the process for
adding new oracles and TLA+ specs to CI.

---

## Purpose

TLA+ and Lean4 models are necessarily simplified. They axiomatize cryptographic
primitives, fix finite constant sets, and abstract over implementation details
that are irrelevant to the property being proved. The harness exists to check
that the real implementation agrees with those models on every case the models
specify, and to make that check mandatory in CI.

A divergence between oracle and implementation is not a test flake — it is either
a bug in the implementation or a gap in the model. Both outcomes are useful.

---

## Three-Tier Structure

### L1 — Implementation unit tests

Zig conformance tests (`zig build test`) and Bun end-to-end tests
(`bun test` per package). These test the implementation against its own spec
in isolation. They do not reference any formal model.

Toolchain:
- Zig 0.15.2 (`core/cell-engine`, `runtime/node`)
- Bun latest (`apps/wallet-browser`, etc.)

### L2 — Property-based fuzzing

Random-input fuzzing that checks invariants hold in the implementation without
reference to a formal model. Harnesses are compiled as Zig fuzz targets:

```
zig build fuzz-linearity fuzz-opcodes fuzz-stack fuzz-plexus
```

These harnesses live in `core/cell-engine/src/fuzz/` and are verified to compile
in CI (gate.yml `cell-engine` job). Local corpus runs use `zig build fuzz-<name>
-Dfuzz` against a persistent corpus directory.

### L3 — Differential testing: implementation vs formal model oracle

A Lean4 model is compiled to a native binary (the "oracle"). A Bun fuzzer
generates random inputs, queries both the oracle and the Zig/WASM implementation,
and asserts agreement. Any divergence is a genuine semantic difference requiring
investigation.

This is the highest-value tier: it catches cases where the implementation and
the model disagree on a real input that the model specifies, including edge cases
that pure unit testing would not discover.

---

## The Oracle Pattern

The oracle pattern is established and working in `core/cell-engine/lean4/`.
All future L3 oracles follow the same shape.

### Structure of a Lean4 oracle project

```
core/<component>/lean4/
  lakefile.toml          # declares [[lean_lib]] and [[lean_exe]] targets
  lean-toolchain         # pins the Lean version (currently leanprover/lean4:v4.29.1)
  BranchOnOutput.lean    # library — the formal model
  Main.lean              # executable — reads stdin, runs model, prints result
```

### lakefile.toml shape

```toml
name = "MyOracle"
defaultTargets = ["MyOracle", "MyOracleOracle"]

[[lean_lib]]
name = "MyOracle"

[[lean_exe]]
name = "MyOracleOracle"
root = "Main"
```

### Main.lean interface contract

- Reads a single newline-terminated JSON line from stdin
- Runs the relevant model function
- Prints a single newline-terminated JSON line to stdout
- Exits 0 on success, non-zero on parse error

### Building

```bash
cd core/<component>/lean4
~/.elan/bin/lake build
# Produces: .lake/build/bin/<oracle-name>
```

Incremental builds are fast (< 1 s on warm cache). The lean-toolchain file is
honoured automatically by lake.

### Calling from a Bun fuzzer

```typescript
import { spawnSync } from "bun";

function queryOracle(oraclePath: string, input: object): object {
  const result = spawnSync([oraclePath], {
    stdin: Buffer.from(JSON.stringify(input) + "\n"),
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`Oracle exited ${result.exitCode}: ${result.stderr.toString()}`);
  }
  return JSON.parse(result.stdout.toString().trim());
}
```

Compare the oracle result to the Zig/WASM result. Any divergence throws,
causing the Bun test to fail.

### Running the Zig/WASM engine in-process

For L3 tests, load the cell-engine WASM via Bun's WebAssembly API:

```typescript
const wasm = await WebAssembly.instantiate(
  readFileSync("core/cell-engine/zig-out/bin/cell-engine.wasm"),
  { /* host imports */ }
);
```

Call the relevant exported function and compare to the oracle output.

---

## Known Model Simplifications (Gaps to Track)

These are known differences between what the formal models prove and what the
full implementation does. They are not bugs — they are intentional scope
boundaries. Track them here so they are never silently widened.

### BranchOnOutput.lean (`core/cell-engine/lean4/`)

| Simplification | Status |
|---|---|
| `TxContext` models only `currentOutputIndex`; all other tx fields absent | Intentional scope |
| `checksig` is a ghost `Bool` (no real EC verification) | Intentional — K11 covers sign soundness separately |
| Truthy was simplified (the `[0x80]` negative-zero edge case) | Fixed in `feat/op-branchonoutput`, closes the gap |

### K1–K18 (`proofs/lean/Semantos/Theorems/`)

| Simplification | Affected theorems |
|---|---|
| All cryptographic primitives are axioms: `sha256`, `ecdsa_verify` treated as perfect oracles | K2, K6, K11, K12 |
| `concat` injectivity is axiomatic (`CryptoAxioms.lean`) | K2, K6 |
| No modelling of nonce reuse or timing side-channels | K11, K12 |

### TLA+ specs (`proofs/tla/`)

| Simplification | Affected specs |
|---|---|
| Hash functions modelled as injective over a finite model-value set | EvidenceChain, ReplayPrevention, CertRevocation, TreeOfChainsMerge |
| Time modelled as a monotone counter (no wall-clock, no drift) | TierEscalation, VaultCooldownNsequence, MeteringFSM |
| Network partition is an abstract failure counter, not a real topology | PartitionResilience, FederationPropagation |
| Constant sets are small (N ≤ 3) for tractable TLC runtime | All 20 specs |

---

## Targets for Future L3 Oracles

Priority order reflects proximity to the live execution engine and risk of
implementation drift.

| Priority | Oracle target | Source theorem/spec | Notes |
|---|---|---|---|
| 0 | `BranchOnOutputOracle` | `BranchOnOutput.lean`, T1-T4 | **DONE** — 30/30 pass; oracle in `core/cell-engine/lean4/`; fuzzer in `proofs/fuzz/branch-on-output/` |
| 1 | K1 Linearity oracle | `LinearityK1.lean` | **DONE** — 29/29 pass, exhaustive 4×5 table, oracle in `proofs/lean/` |
| 2 | K4 FailureAtomicity oracle | `FailureAtomicK4.lean` | **DONE** — 50/50 pass; depth-underflow gate for all 16 Plexus ops; oracle in `proofs/lean/` |
| 3 | K7 CellImmutability oracle | `CellImmutabilityK7.lean` | **DONE** — 16/16 pass; K7d/K7e/K7f inspect classification + linearity enforcement; oracle in `proofs/lean/` |
| 4 | K8 Demotion oracle | `DemotionK8.lean` | **DONE** — 25/25 pass, exhaustive 4×4 table, oracle in `proofs/lean/` |

K2 (AuthSoundness), K11 (SignSoundness), K12 (KeyCustody) are deferred because
their cryptographic axioms cannot be discharged by a Lean binary oracle alone —
they require either a real EC library or a separate property-based test against
the cryptographic implementation directly.

---

## How to Add a New Oracle

1. **Write the Lean model function** in the relevant lean4 project. It should be
   a pure function from an input record to an output record.

2. **Write `Main.lean`** that reads a JSON line from stdin, deserializes it,
   calls the model function, and serializes the result to stdout.

3. **Add a `lean_exe` target to the project's lakefile**:

   For `proofs/lean/` (uses `lakefile.lean` DSL):
   ```lean
   lean_exe «MyOracleOracle» where
     root := `Semantos.Oracles.MyOracleOracle
   ```

   For `core/<component>/lean4/` (uses `lakefile.toml`):
   ```toml
   [[lean_exe]]
   name = "MyOracleOracle"
   root = "Main"
   ```

4. **Build and smoke-test** locally:
   ```bash
   cd core/<component>/lean4
   ~/.elan/bin/lake build
   echo '{"input": 42}' | .lake/build/bin/MyOracleOracle
   ```

5. **Write a Bun fuzzer** in `proofs/fuzz/<oracle-name>/fuzz.test.ts`:
   - Generate random inputs covering the model's domain
   - Query the oracle binary (see oracle pattern above)
   - Query the Zig/WASM implementation
   - Assert agreement; log divergences with full input/oracle/impl triple

6. **Register the oracle** in the Active differential oracles table below.

7. **Add a CI job** to `gate.yml` under the `lean` job or as a sibling job
   that: installs elan, runs `lake build`, then runs `bun test` in the fuzzer
   directory. Do not add the oracle build to `tla-verify.yml` — keep that
   workflow TLA+-only.

---

## Active Differential Oracles

| Oracle | Lean project | Fuzzer | Status | Theorems covered |
|---|---|---|---|---|
| `BranchOnOutputOracle` | `core/cell-engine/lean4/` | `proofs/fuzz/branch-on-output/fuzz.test.ts` | **LIVE** — 30/30 pass; T2 u32ToLE exact match × 9 indices; T4 outputIndex independence | T2 (stack delta +1, correct LE bytes), T4 (sole observer: non-branch scripts are outputIndex-independent) |
| `K1LinearityOracle` | `proofs/lean/` | `proofs/fuzz/k1-linearity/fuzz.test.ts` | **LIVE** — 29/29 pass; exhaustive 4×5 table | K1a (no dup linear), K1b (no drop linear), affine/relevant variants, 16 always-true cells |
| `K4FailureAtomicOracle` | `proofs/lean/` | `proofs/fuzz/k4-failure-atomic/fuzz.test.ts` | **LIVE** — 50/50 pass; all 16 Plexus ops × 3 depth tiers | K4 depth-underflow gate: 16 ops at depth=0, multi-arg ops at minDepth−1, 16 ops at minDepth |
| `K7ClassifyOpOracle` | `proofs/lean/` | `proofs/fuzz/k7-cell-immutability/fuzz.test.ts` | **LIVE** — 16/16 pass; K7d/e/f inspect + contrast duplicate/discard enforcement | K7d (0xC9=inspect), K7e (0xCC=inspect), K7f (0xAB=inspect); full classify differential |
| `K8DemotionOracle` | `proofs/lean/` | `proofs/fuzz/k8-demotion/fuzz.test.ts` | **LIVE** — 25/25 pass; exhaustive 4×4 table | K8a (linear→affine), K8b (linear→relevant), K8c–K8i (all invalid transitions) |

---

## TLA+ CI

The `tla-verify.yml` workflow (`.github/workflows/tla-verify.yml`) runs TLC on
all 20 specs whenever `proofs/tla/**` changes. It is additive alongside the
existing `gate.yml` `tla` job — both run the same `make check` target; the
difference is that `tla-verify.yml` has a path filter so proof-only PRs get a
dedicated, focused CI result without waiting for the full gate suite.

### Toolchain

| Tool | Version | Source |
|---|---|---|
| TLC (tla2tools.jar) | 1.8.0 | Makefile `TLA2TOOLS_VERSION`, cached by `actions/cache@v4` keyed on `Makefile` hash |
| Java | Temurin 17 | `actions/setup-java@v4`, matches gate.yml |

### Runtime budget

All 20 specs use constant sets of N ≤ 3 elements. On a standard GitHub Actions
`ubuntu-latest` runner, the full `make check` run targets < 2 minutes. If a new
spec causes the job to exceed 5 minutes, either reduce the model size in the
`.cfg` or add a separate `small` Makefile target and invoke that instead.

### Adding a new TLA+ spec

1. Create `proofs/tla/<SpecName>.tla` and `proofs/tla/<SpecName>.cfg`.
2. Keep constant sets at N ≤ 3. Add a comment in the `.cfg` noting what N
   represents if it is not obvious from context.
3. Add `<SpecName>` to the `SPECS` list in `proofs/tla/Makefile`.
4. Verify locally: `cd proofs/tla && make setup && make <SpecName>`.
5. Check that the log contains "Model checking completed. No error" and that
   distinct states > 0.
6. Update the spec table in `proofs/tla/README.md`.
7. Update this document if the spec covers a new proof layer or introduces a
   new known simplification.

### Interpreting TLC output

| Log pattern | Meaning | Action |
|---|---|---|
| `Model checking completed. No error` | All invariants hold | Pass |
| `0 distinct states found` | Model is vacuous — initial state predicate is unsatisfiable | Fix the `CONSTANTS` or `ASSUME` in the `.cfg` |
| `Invariant X is violated` | A reachable state breaks invariant X | Fix the spec or the model — do not shrink the invariant |
| `Deadlock reached` | The system can reach a state with no enabled action | Either add a stuttering action or re-examine the liveness model |
| `Error: ...` | Parse or tool error | Check `.tla` syntax; verify Java version |

---

## Relationship to the Proof Layers

```
K1–K18 (proofs/lean/)          — sequential, per-opcode properties
   |
   |  companion specs
   v
TLA+ (proofs/tla/)             — distributed/concurrent protocol properties
   |
   |  oracle differential test
   v
L3 fuzz (proofs/fuzz/)         — implementation agrees with formal model
   |
   |  L2 property fuzz
   v
L1 unit tests (zig/bun)        — implementation agrees with its own spec
```

The layers do not subsume each other. A Lean4 proof tells you the model is
correct. A TLA+ check tells you the distributed model has no reachable
violations under the abstract model. An L3 oracle check tells you the real
implementation matches the model on concrete inputs. All three are necessary.
