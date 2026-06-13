---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/FORMAL-VERIFICATION-STRATEGY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.333053+00:00
---

# Semantos Plane — Formal Verification Strategy

**Version**: 0.2
**Purpose**: Map every compliance test in the Compliance Demonstration Test Specification to a concrete proof technique, identify the proof obligations, and specify the toolchain.

---

## 1. The Core Insight

The compliance spec makes one foundational claim from which everything else follows:

> **P4.1 — Compliance properties cannot be disabled by an administrator.**

This is the only claim that distinguishes "compliance by architecture" from "compliance by control." Most compliance tests reduce to a small set of kernel invariants plus explicit cryptographic, host-import, and deployment assumptions. If we can formally prove those kernel invariants hold in the abstract model, establish strong empirical evidence that the Zig/WASM binary conforms to that model, and anchor the binary's integrity on-chain, then the compliance tests are supported by a combination of machine-checked proof and stated assumptions — not by organizational process.

The kernel invariants fall into three classes:

### Execution Invariants (proved in the abstract 2-PDA model)

| ID | Invariant | Where Enforced |
|----|-----------|----------------|
| K1 | **Linearity**: A LINEAR cell is never duplicated while live, never discarded without authorized consumption, and once consumed cannot reappear unless a distinct cell is created. | `linearity.zig` — `checkLinearity()` |
| K2 | **Authorization soundness**: Any transition that changes authenticated semantic state requires successful verification of an authorized identity proof. Purely local stack transformations (arithmetic, hashing) are excluded. | `executor.zig` + `plexus.zig` — OP_CHECKIDENTITY, host_checksig |
| K3 | **Domain isolation**: OP_CHECKDOMAINFLAG rejects unless the cell header's domain flag matches the expected value. No execution path bypasses this check. | `plexus.zig` — opcode 0xC6 |
| K4 | **Failure atomicity**: Failed Plexus opcodes leave the PDA state byte-for-byte identical to the pre-execution state. Covers all 16 Plexus opcodes 0xC0-0xCF, including OP_SIGN (`opSign`), OP_DECREMENT_BUDGET (`opDecrementBudget`), and OP_REFILL_BUDGET (`opRefillBudget`). After WP9 (Apr 2026), every per-op K4 sub-theorem is substantive: each opcode has a `_error_inversion` lemma that walks every reachable error branch of the function definition, plus an `_atomic` corollary that excludes any successful result on the same call. Adding a new error path or moving a mutation before an error return breaks the inversion lemma — the proof is no longer reflexivity-by-construction. | `plexus.zig` peek-then-mutate (Zig); `FailureAtomicK4.lean` inversion + atomicity per opcode (Lean); `plexus_atomic_fuzz.zig` empirical coverage (Zig fuzz) |
| K5 | **Deterministic termination**: No loops, bounded opcount, bounded stack depth. Every execution terminates. | `pda.zig` — 1024 main slots, 256 aux slots, no JMP |

### Object Integrity Invariants

| ID | Invariant | Where Enforced |
|----|-----------|----------------|
| K7 | **Cell immutability**: The 256-byte header is read-only after packing; no opcode in the instruction set modifies the linearity class of a cell on the stack. | `cellPacker.ts` / cell packing in Zig |
| K8 | **Demotion safety**: OP_DEMOTE permits only LINEAR→AFFINE and LINEAR→RELEVANT transitions; promotions and cross-branch transitions are rejected. | `plexus.zig` — `opDemote` / `validDemotion` |

### Wallet Tier Invariants (Phase W1+W3)

| ID | Invariant | Where Enforced |
|----|-----------|----------------|
| K11 | **Sign soundness**: OP_SIGN consumes LINEAR key cells on success; emitted signatures verify under the corresponding public key; all error paths are failure-atomic. | `plexus.zig` — `opSign` (0xCD) + `host.sign` |
| K12 | **Key custody**: LINEAR tier-key cells cannot be duplicated; tier-N signing requires an OP_CHECKDOMAINFLAG against the tier's flag before OP_SIGN. | `plexus.zig` — `opCheckDomainFlag` ↦ `opSign` template |
| K13 | **Budget monotonicity**: OP_DECREMENT_BUDGET strictly decreases `remaining_satoshis` (with positive amount); OP_REFILL_BUDGET strictly increases (with valid parent signature). | `plexus.zig` — `opDecrementBudget` (0xCE), `opRefillBudget` (0xCF) |

### Protocol/History Invariants (model-checked, not theorem-proved)

| ID | Invariant | Where Enforced |
|----|-----------|----------------|
| K6 | **Hash-chain integrity**: prevStateHash links form an append-only chain, externally anchored. Tampering is detectable by any party with SPV access. | `semantic-objects.ts` + BSV anchor |
| WT1 | **Key custody multi-actor safety**: At most one actor (browser tab / sovereign-node session / recovery flow) holds any tier key decrypted at any time; consumed keys cannot transition back to decrypted without going through a Plexus-mediated recovery; recovery requires prior enrollment; every unlock had a matching auth factor presented. | `proofs/tla/KeyCustody.tla` (TLC-verified, multi-actor state machine) |
| WT2 | **Tier escalation policy enforcement**: every spend was tagged with the correct tier per AmountTier; every spend had its tier's required factor presented at-or-before sign time; consecutive Tier-3 spends respect the configured cooldown window; classification is monotone in amount. | `proofs/tla/TierEscalation.tla` (TLC-verified, host-clock cooldown — refined to nSequence / CSV in v0.2) |
| WT3 | **OP_SIGN replay prevention + BRC-42 monotonic-index atomicity**: no two distinct sign actions on the same leaf pubkey; no two issuedLeaves entries share the same (context, index); derivation index is monotonic per (protocol, counterparty) under concurrent allocation. | `proofs/tla/ReplayPrevention.tla` (extended in WT3; TLC-verified atomic allocator) |

---

## 2. Proof Architecture (Three Layers)

We do NOT attempt a single monolithic proof. Instead, three layers, each using the right tool:

```
┌──────────────────────────────────────────────────────────────────┐
│  Layer 3: COMPOSITION + REGULATORY MAPPING                        │
│  "Given K1–K7 plus stated assumptions, each compliance test is   │
│   supported by identified proof obligations."                     │
│  Tool: TLA+ for protocol-level properties; paper proofs for      │
│        regulatory mapping. Explicit assumption register.          │
├──────────────────────────────────────────────────────────────────┤
│  Layer 2: KERNEL INVARIANT PROOFS (Lean 4)                       │
│  "K1–K5, K7 hold for the abstract 2-PDA model."                 │
│  "K6 holds under model checking for bounded state spaces."       │
│  Tool: Lean 4 theorem prover + TLA+/TLC model checker.          │
├──────────────────────────────────────────────────────────────────┤
│  Layer 1: IMPLEMENTATION CONFORMANCE (empirical evidence)         │
│  "Strong empirical and review-based evidence that the Zig        │
│   implementation conforms to the abstract semantics."             │
│  Tool: 240+ conformance tests, property-based fuzzing,           │
│        differential testing, mutation testing, code review,       │
│        WASM binary hash anchoring.                                │
│  NOTE: This is evidence, not proof in the Layer 2 sense.         │
└──────────────────────────────────────────────────────────────────┘
```

### Why This Split?

- **Lean 4** excels at proving properties of abstract machines (type theory, linear logic). It's the right tool for K1–K5.
- **TLA+** excels at proving properties of distributed protocols under all interleavings (temporal ordering, FSM correctness, partition resilience). It's the right tool for K6 and the multi-party protocol tests.
- **Paper proofs** with precise references to Lean/TLA+ lemmas are the right format for regulators — they need to read the argument, not run the proof checker.
- **Zig conformance tests** bridge the gap between abstract model and implementation. The 240+ tests already cover the critical paths; we augment with property-based fuzzing.

---

## 3. Layer 2 Detail — Lean 4 Kernel Proofs

### 3.1 What We Model

```lean
-- The cell: a 1024-byte value with a typed header
structure Cell where
  linearity : Linearity       -- LINEAR | AFFINE | RELEVANT | DEBUG
  domainFlag : UInt32
  typeHash : ByteArray 32
  ownerId : ByteArray 16
  payload : ByteArray 768
  deriving Repr

inductive Linearity where
  | linear | affine | relevant | debug
  deriving Repr, DecidableEq

-- The 2-PDA: two bounded stacks of cells
structure PDA where
  main : BoundedStack Cell 1024
  aux : BoundedStack Cell 256
  pc : Nat
  opcountLimit : Nat

-- Stack operations with linearity checking
inductive StackOp where
  | duplicate | discard | consume | swap | inspect
  deriving DecidableEq

def linearityPermits (l : Linearity) (op : StackOp) : Bool :=
  match l, op with
  | .linear,   .duplicate => false   -- K1: cannot duplicate LINEAR
  | .linear,   .discard   => false   -- K1: cannot discard LINEAR
  | .affine,   .duplicate => false
  | .relevant, .discard   => false
  | _,         _          => true
```

### 3.2 What We Prove

**Theorem K1 (Linearity)** — three sub-theorems:

*K1a (No duplication while live)*: For all execution traces, if a cell `c` with `c.linearity = LINEAR` is on the stacks, no operation sequence can produce a second copy of `c` on any stack.

Proof sketch: The only operations that could create a copy are DUP/OVER/PICK/2DUP/3DUP (all classified as `duplicate`). `linearityPermits linear duplicate = false`, so the linearity gate rejects before the operation executes. ∎

*K1b (No unauthorized discard)*: A LINEAR cell cannot be removed from the stacks by any discard operation (DROP/2DROP/NIP). It can only leave the stacks via authorized consumption.

Proof sketch: `linearityPermits linear discard = false`, so the linearity gate rejects. The only removal path is via a `consume`-classified operation, which requires explicit authorization. ∎

*K1c (No reintroduction after consumption)*: Once a LINEAR cell is consumed (removed via an authorized consume operation), no operation can reintroduce an observationally identical cell. A new cell with the same payload would have a different creation timestamp and prevStateHash.

Proof sketch: Cell identity includes the prevStateHash and timestamp fields in the header. A consumed cell's stateHash is recorded. Any new cell with the same payload has a different prevStateHash (it points to the current chain head, not the consumed cell's predecessor) and a different timestamp. Therefore it is a *distinct* cell, not a reintroduction. ∎

**Theorem K2 (Authorization Soundness)**: *Any transition that changes authenticated semantic state (identity verification, capability check, domain flag check) requires successful verification of an authorized identity proof. If verification fails, the PDA state is unchanged (failure atomicity, K4) and no semantic state transition occurs. Purely local stack transformations (arithmetic, hashing, data manipulation) are excluded from this requirement.*

Proof: By case analysis on the Plexus opcodes (0xC0–0xCF). Each opcode that gates semantic state: (1) peeks at stack items without mutation, (2) validates the authorization condition, (3) only mutates on success. If validation fails at step 2, the function returns an error and step 3 never executes. Standard Bitcoin Script opcodes (arithmetic, hash, data) do not gate semantic state and are not subject to K2. ∎

**Theorem K3 (Domain Isolation)**: *OP_CHECKDOMAINFLAG(cell, expected_flag) returns TRUE iff `cell.header.domainFlag == expected_flag`. No execution path bypasses this check.*

Proof: Direct from the opcode implementation — reads 4 bytes at header offset 24, compares with expected value. The only code path that pushes TRUE is the equality branch.

**Theorem K5 (Deterministic Termination)**: *Every execution terminates in at most `opcountLimit` steps. The PDA has no jump or call instructions.*

Proof: The instruction set is enumerated (standard Bitcoin Script + Plexus 0xC0–0xCF). None is a backward jump. The PC increments monotonically. The opcount increments per step. When `opcount >= opcountLimit`, execution halts.

### 3.3 What We Defer (Cryptographic Assumptions)

We do NOT prove the security of SHA-256, ECDSA, or HMAC-SHA-256 in Lean. The formal model abstracts these primitives as ideal functions under standard cryptographic assumptions. This is the standard approach in formal verification of cryptographic protocols (used in seL4, CertiKOS, Ironclad, etc.).

**Important**: The axioms below are *idealized oracle assumptions*, deliberately stronger than the computational definitions (which involve PPT adversary bounds). This is standard in mechanized proofs — the Lean type system has no notion of computational complexity. The security of the real primitives rests on decades of cryptanalytic literature, not on these axioms.

```lean
-- Idealized oracle assumptions (stronger than computational definitions)
-- These model the primitives as perfect functions. The gap between
-- these idealizations and computational security is accepted practice
-- in mechanized verification.

axiom sha256_collision_free :
  ∀ (m1 m2 : ByteArray), sha256 m1 = sha256 m2 → m1 = m2
  -- Idealization of: no PPT adversary finds collisions with
  -- non-negligible probability

axiom ecdsa_existential_unforgeability :
  ∀ (pk : PubKey) (msg sig : ByteArray),
    ecdsaVerify pk msg sig = true →
    ∃ (sk : SecKey), derives pk sk
  -- Idealization of: EUF-CMA security for secp256k1
  -- Note: this does NOT claim unique signatures, only that
  -- verification implies knowledge of the secret key
```

The gap between idealized axioms and computational security definitions is well-understood in the formal methods community and does not weaken the proof structure — it means the proofs hold *conditional on* the real primitives behaving as their idealized versions, which is the standard assumption in deployed cryptographic systems.

---

## 4. Layer 3 Detail — TLA+ Protocol Model

### 4.1 What We Model

The distributed protocol involving multiple parties (operators, sensors, AI agents, auditors) interacting with semantic objects through the kernel.

```tla
VARIABLES
  objects,        \* Map: ObjectID -> SemanticObject
  evidenceChain,  \* Sequence of EvidenceItem
  bsvAnchors,     \* Set of {stateHash, blockHeight, txid}
  plexusCerts,    \* Map: CertID -> {pubkey, revoked, domainFlags}
  channels        \* Map: ChannelID -> ChannelState (FSM)

SemanticObject == [
  id        : ObjectID,
  linearity : {"LINEAR", "AFFINE", "RELEVANT"},
  stateHash : Hash,
  prevStateHash : Hash \union {NULL},
  consumed  : BOOLEAN,
  payload   : Payload,
  authorId  : CertID,
  timestamp : Nat
]
```

### 4.2 What We Prove (Temporal Properties)

**Property P2.1 (Temporal Integrity)**: For any two evidence items `e1` and `e2` in the chain, if `e1.timestamp < e2.timestamp` then `e1` appears before `e2` in the chain, and `e2.prevStateHash = hash(e1)`.

```tla
TemporalIntegrity ==
  \A i, j \in 1..Len(evidenceChain) :
    i < j =>
      evidenceChain[j].prevStateHash = Hash(evidenceChain[j-1])
```

**Property: Replay Impossibility (Test 1.1.2)**:

```tla
ReplayImpossible ==
  \A obj \in DOMAIN objects :
    objects[obj].linearity = "LINEAR" /\ objects[obj].consumed =>
      ~(\E action \in nextActions : action.targetId = obj /\ action.type = "consume")
```

*In words*: Once a LINEAR object is consumed, no future action in any reachable state can consume it again. This is checked by TLC (TLA+ model checker) over all reachable states.

**Property: Revocation Immediacy (Test 1.3.1)**:

```tla
RevocationImmediate ==
  \A cert \in DOMAIN plexusCerts :
    plexusCerts[cert].revoked =>
      ~(\E action \in nextActions :
          action.signerCert = cert /\ ActionSucceeds(action))
```

**Property: Partition Resilience (Test 6.1)**:

```tla
PartitionResilient ==
  \A partition \in Partitions :
    \A node \in partition.isolatedNodes :
      node.localCertCache # {} =>
        node.canValidateCommands = TRUE
```

### 4.3 Model Checking Scope

TLA+ model checking is exhaustive within the model's state space. We bound:
- Number of objects: 3–5 (enough to exercise all linearity classes)
- Number of certs: 3 (one per role: operator, sensor, admin)
- Number of domain flags: 3 (Zone 1, Zone 4, enterprise)
- Evidence chain length: up to 10 items
- Channel FSM: all 8 states

This keeps the state space tractable (< 10^9 states, checkable in hours) while covering all interesting interleavings.

---

## 5. Layer 1 Detail — Implementation Conformance

### 5.1 Existing Coverage

The 240+ Zig conformance tests already cover:
- Linearity enforcement for all three classes
- All Plexus opcodes (0xC0–0xCF)
- Cell packing/unpacking round-trips
- BCA derivation
- BEEF/BUMP verification
- Capability token verification
- Multi-cell continuation ordering

### 5.2 Gaps to Fill

| Gap | Technique | Priority |
|-----|-----------|----------|
| **Property-based fuzzing** of linearity enforcement | Generate random operation sequences, assert K1 holds | HIGH |
| **Differential testing** between Lean model and Zig | Same inputs to both, compare outputs | HIGH |
| **WASM binary hash anchoring** | Anchor the SHA-256 of the production .wasm on BSV | HIGH (this is what makes P4.1 detectable) |
| **Mutation testing** on linearity.zig | Deliberately break linearity checks, verify tests catch it | MEDIUM |
| **Coverage analysis** of plexus.zig opcodes | Ensure every branch (success + failure) is hit | MEDIUM |
| **Memory safety audit** of pda.zig | Bounds checking on stack operations | MEDIUM |
| **Phase 29.5 differential test** | CDM TS-shim evaluator and kernel `PolicyRuntime.evaluate()` agree on fixture corpus | REGRESSION (pre-cutover) |

### 5.3 Property-Based Fuzzing Strategy

Using Zig's built-in fuzz testing (available since 0.12):

```zig
test "fuzz: LINEAR cell never duplicated" {
    // Generate random sequences of stack operations
    // For each sequence:
    //   1. Push a LINEAR cell
    //   2. Apply the operation sequence
    //   3. Assert: cell appears at most once across both stacks
    //   4. Assert: if any operation was rejected, stack is unchanged (K4)
}
```

This bridges Layer 2 (abstract proof) and Layer 1 (concrete implementation). If the fuzzer finds a counterexample, either the Zig code has a bug or the Lean model is wrong.

---

## 6. Compliance Test → Proof Obligation Mapping

> **Framing note**: Each row below identifies the *kernel contribution to requirement satisfaction*, not full regulatory compliance. Full compliance also requires procedural, operational, and organizational measures outside the kernel's scope. The kernel provides the structural foundation; the regulatory argument is that this foundation makes the procedural layer auditable and tamper-evident rather than trust-dependent.

### Part 1: IEC 62443

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| 1.1.1 Command requires identity | K2 (Auth soundness) | Host `checksig` correct | Lean 4 | Theorem: unsigned command ⇒ no semantic state transition |
| 1.1.2 Replay prevention | K1 (Linearity) | Crypto axioms | Lean 4 + TLA+ | Theorem: consumed LINEAR ⇒ re-consumption impossible |
| 1.2.1 Machine identity required | K2 (Auth soundness) | Host `checksig` correct | Lean 4 | Same as 1.1.1 — cert requirement is identity-agnostic |
| 1.3.1 Revoked cert rejected | K2 + K6 | Revocation propagation timely | TLA+ | RevocationImmediate under model checking |
| 2.1.1 Zone boundary enforcement | K3 (Domain isolation) | — | Lean 4 | Theorem: OP_CHECKDOMAINFLAG total and correct |
| 2.1.2 Work permit gates access | K1 (Linearity) | — | Lean 4 | Theorem: missing LINEAR capability ⇒ rejected |
| 3.3.1 Audit trail immutable | K6 (Hash-chain) | Crypto axioms, BSV available | TLA+ + paper | TemporalIntegrity + collision resistance |
| 3.4.1 Sensor reading not spoofable | K2 (Auth soundness) | Sensor private key secure, host `checksig` correct | Lean 4 | Theorem: invalid sig ⇒ reading rejected |

### Part 2: EU AI Act

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| 2.1 AI decision traceable | K6 + K7 | Application records all decisions as state transitions | TLA+ | Evidence chain completeness |
| 2.2 AI decision not alterable | K6 + crypto axioms | BSV available | Paper proof | Anchor + collision resistance |
| 2.3 Human override recorded | K6 + K2 | Application models overrides as state transitions | TLA+ | Override requires auth; chain records it |
| 2.4 Model version recorded | K7 (Cell immutability) | Application populates compilerVersion field | Lean 4 | Header read-only after pack |

### Part 3: GDPR

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| 3.1 Right to erasure | K6 (payload ≠ stateHash) | Application separates PII from structural data | Paper + TLA+ | Payload erasable, chain intact |
| 3.2 Data portability | K6 + K2 | Export tooling exists | Paper proof | Self-contained objects with provenance |
| 3.3 Privacy by design | K3 (Domain isolation) | Application uses domain flags for access policy | Lean 4 | Kernel-level filtering via domain flags |

### Part 4: Basel III/IV

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| 4.1 Settlement integrity | K1 + K6 | Crypto axioms, BSV available | Lean 4 + TLA+ | LINEAR consumption + hash-chain anchoring |
| 4.2 Counterparty identity bound | K2 | Cert issuance chain valid | Lean 4 | Auth is mandatory; cert refs in object |

### Part 5: HIPAA

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| 5.1 Every access recorded | K6 | Application routes all access through kernel | TLA+ | Evidence chain structural, not optional |
| 5.2 Medical record alteration detectable | K6 + crypto axioms | BSV available | Paper proof | Hash-chain + anchor |
| 5.3 Transmission security | K2 + K3 | Recipient cert pubkey correct, host crypto correct | Lean 4 | Encryption to cert; access logged |

### Part 6: NIS2

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| 6.1 Partition resilience | K2 + K5 | Local cert cache populated pre-partition | TLA+ | WASM validates locally; no central dependency |
| 6.2 Supply chain compromise detectable | K7 + crypto axioms | Trusted boot/measurement root exists | Paper proof | WASM hash on BSV; tampered ≠ anchored |

### Part 7: Cross-Framework

| Test | Kernel Contribution | Additional Assumptions | Proof Layer | Technique |
|------|--------------------|-----------------------|-------------|-----------|
| P1.1 Non-repudiation | K2 + ECDSA axiom | Private key never leaves device | Lean 4 | Signature ⇒ key possession ⇒ identity |
| P2.1 Temporal integrity | K6 | BSV available for external anchor | TLA+ | TemporalIntegrity property |
| P3.1 Platform shutdown survival | K6 | BSV chain persists; user retains cert | Paper proof | Reconstructable from chain + cert |
| P4.1 Cannot be disabled | K1–K7 + trusted boot | Binary integrity verified before load | All layers | The capstone: see Section 7 |

---

## 7. The P4.1 Proof (Capstone)

P4.1 is not a single theorem — it's the *conjunction* of everything above, plus a trusted measurement root and an explicit statement of what each layer contributes.

**Claim**: The only way to disable the verified enforcement properties is to replace the measured binary, and that replacement is externally detectable.

**Proof structure (ordered by dependency)**:

1. **Trusted boot / measurement root** (PREREQUISITE — this comes first, not last):
   - P4.1 is only meaningful if there is a trusted verifier *outside* the WASM binary that checks its integrity before loading.
   - Devices verify `SHA-256(loaded_wasm) == anchored_hash` at boot, before the engine initializes.
   - This check is in the boot/loader sequence, not in the WASM binary itself (avoiding circularity).
   - Hash mismatch → device refuses to load → alerts operators (Test 6.2).
   - The anchored hash is on BSV, independently verifiable by any SPV client.
   - **Without this step, the rest of the argument is vacuous.** An attacker who controls the loader can bypass everything.

2. **K1–K5 are proved in Lean 4** as properties of the abstract 2-PDA model.
   - This is machine-checked proof over an abstract semantics.
   - The proofs hold unconditionally within the model (no probabilistic bounds, no assumptions beyond the crypto axioms).

3. **The Zig implementation conforms to the abstract model** — established by strong empirical and review-based evidence (NOT proof in the Layer 2 sense):
   - 240+ conformance tests (existing, Phases 0–6)
   - Property-based fuzzing with 4 harnesses × 60s each (new)
   - Differential testing: same inputs to Lean model and Zig implementation, outputs compared (new)
   - Mutation testing: 10 deliberate breaks, 100% caught (new)
   - Structured code review of critical modules against the Lean model
   - **Honesty note**: This evidence is strong but not a formal proof of implementation correctness. A verified compiler (like CompCert for C) would close this gap but does not exist for Zig→WASM. We rely on testing, fuzzing, and review.

4. **The WASM binary is the deterministic compilation of the Zig source** — established by:
   - Reproducible build (same Zig version + flags → same .wasm bytes, verified by building twice)
   - WASM-MANIFEST.json records: SHA-256, Zig version, source commit, build timestamp
   - The manifest hash is anchored on BSV at release time

5. **No configuration pathway disables enforcement** — established by:
   - Code audit: `kernel_set_enforcement(enabled)` exists but is compile-time gated to debug builds only
   - Production WASM is built with `embedded = true`, which strips debug code paths at compile time
   - The Lean proof does not model a "disable linearity" pathway because none exists in the abstract model
   - The Zig `build_options` module (`build.zig` line ~51) controls this at compile time, not at runtime

6. **Database modifications are irrelevant** — established by:
   - The WASM engine reads cell headers directly (in-memory, from the stack)
   - It does not query any external database for linearity class, domain flags, or capability type
   - An administrator who modifies the database changes nothing about how the engine evaluates cells
   - The engine's only inputs are: the script bytes, the cells on the stack, and the host imports

**Epistemic status of each step**:
- Step 1 (trusted boot): Architectural claim, verified by deployment audit. Not machine-checked.
- Step 2 (Lean proofs): Machine-checked proof over abstract semantics. Strongest layer.
- Step 3 (implementation conformance): Strong empirical evidence. Not proof. This is the weakest link in the chain.
- Step 4 (reproducible build): Empirically verified (build twice, compare hashes). Deterministic compilation is a property of the toolchain.
- Step 5 (no config pathway): Code audit + compile-time verification. The Lean model corroborates by not modeling a disable path.
- Step 6 (database irrelevant): Architectural claim, directly verifiable from the WASM binary's import table (it imports no database functions).

The combination is not a monolithic mathematical proof. It is a layered argument where the strongest layer (machine-checked proofs of the abstract model) is supported by empirical evidence (conformance testing) and architectural reasoning (trusted boot, no config pathway). This is strictly stronger than any purely procedural compliance claim, but we should not overstate it as a single end-to-end formal proof.

---

## 8. Toolchain and Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| **Lean 4** | ≥ 4.8.0 | Kernel invariant proofs (K1–K5, K7) |
| **Mathlib4** | latest | Lean 4 mathematical library (for crypto axioms, finite maps) |
| **TLA+ / TLC** | ≥ 2.18 | Protocol model checking (K6, temporal properties, FSM) |
| **Apalache** | ≥ 0.44 | Symbolic TLA+ model checking (for larger state spaces) |
| **Zig** | ≥ 0.13 | Fuzz testing, mutation testing of implementation |
| **wasm-tools** | latest | WASM binary inspection and validation |

### File Structure (Proposed)

```
semantos-core/
├── proofs/
│   ├── lean/
│   │   ├── Semantos/
│   │   │   ├── Cell.lean              -- Cell structure, header format
│   │   │   ├── Linearity.lean         -- Linearity types and rules
│   │   │   ├── PDA.lean               -- 2-PDA model (bounded stacks)
│   │   │   ├── Opcodes.lean           -- Standard + Plexus opcode semantics
│   │   │   ├── Executor.lean          -- Execution model
│   │   │   ├── CryptoAxioms.lean      -- SHA-256, ECDSA axioms
│   │   │   └── Theorems/
│   │   │       ├── LinearityK1.lean   -- K1: LINEAR consumed at most once
│   │   │       ├── AuthSoundnessK2.lean -- K2: no transition without sig
│   │   │       ├── DomainIsolationK3.lean -- K3: CHECKDOMAINFLAG correct
│   │   │       ├── FailureAtomicK4.lean   -- K4: failed ops leave stack unchanged
│   │   │       ├── TerminationK5.lean     -- K5: all executions terminate
│   │   │       └── CellImmutabilityK7.lean -- K7: header read-only after pack
│   │   └── lakefile.lean
│   │
│   ├── tla/
│   │   ├── SemanticProtocol.tla       -- Core protocol specification
│   │   ├── EvidenceChain.tla          -- Hash-chain integrity (K6)
│   │   ├── MeteringFSM.tla            -- 8-state channel FSM
│   │   ├── PartitionResilience.tla    -- NIS2 network partition model
│   │   ├── ReplayPrevention.tla       -- LINEAR consumption under concurrency
│   │   └── MC_SemanticProtocol.cfg    -- Model checker configuration
│   │
│   └── paper/
│       ├── compliance-proof.tex       -- Human-readable proof document
│       └── figures/                   -- Proof architecture diagrams
│
├── packages/cell-engine/
│   ├── fuzz/
│   │   ├── linearity_fuzz.zig         -- Property-based fuzzing for K1
│   │   ├── opcode_fuzz.zig            -- Opcode correctness fuzzing
│   │   └── stack_bounds_fuzz.zig      -- Stack overflow/underflow fuzzing
│   └── ...existing...
```

---

## 9. Execution Plan

### Phase A: Foundation (Weeks 1–4)

1. Set up Lean 4 project with lakefile
2. Model Cell, Linearity, PDA in Lean
3. Prove K1 (linearity) — this is the keystone
4. Prove K5 (termination) — straightforward from instruction set enumeration

### Phase B: Kernel Completion (Weeks 5–8)

5. Prove K2 (authentication totality)
6. Prove K3 (domain isolation)
7. Prove K4 (failure atomicity)
8. Prove K7 (cell immutability)
9. Write TLA+ protocol model

### Phase C: Protocol Properties (Weeks 9–12)

10. Model check K6 (hash-chain integrity)
11. Model check temporal integrity (P2.1)
12. Model check replay impossibility (1.1.2)
13. Model check revocation immediacy (1.3.1)
14. Model check partition resilience (6.1)
15. Model check metering FSM (all 8 states)

### Phase D: Implementation Bridge (Weeks 13–16)

16. Property-based fuzzing for linearity.zig
17. Differential testing: Lean model vs Zig implementation
18. Mutation testing on linearity.zig and plexus.zig
19. WASM binary reproducibility verification
20. WASM hash anchoring on BSV testnet

### Phase E: Composition and Documentation (Weeks 17–20)

21. Write P4.1 capstone proof (paper)
22. Write compliance mapping document (test → proof → regulatory clause)
23. Peer review of Lean proofs
24. Peer review of TLA+ model
25. Package for regulatory submission

---

## 10. What This Does NOT Cover (Honest Limitations)

**Explicit assumption register** — every assumption the proof structure depends on:

1. **Cryptographic primitive security**: We axiomatize SHA-256, ECDSA, HMAC as ideal functions (see Section 3.3). We do not re-prove their security. This is standard practice — seL4, CompCert, CertiKOS, and Ironclad all treat crypto primitives as axioms. The gap between our idealized axioms and the computational security definitions is accepted in the mechanized verification community.

2. **Hardware correctness**: We assume the CPU correctly executes WASM instructions. A compromised CPU (e.g., rowhammer, speculative execution bugs) could violate any software property. This is outside scope for all software verification.

3. **Host import correctness**: The WASM binary imports `host_checksig`, `host_sha256`, `host_hash256`, `host_checkmultisig`, etc. from the TypeScript host. We assume these implementations are correct. This is a real gap — the host is not formally verified. It could be strengthened by using a verified crypto library (e.g., HACL* or Fiat-Crypto). Several compliance tests (notably 1.1.1, 1.3.1, 3.4.1, P1.1) depend on this assumption.

4. **Side channels**: Timing attacks, power analysis, cache attacks, etc. are not modeled. The proofs are about functional correctness, not physical security. Constant-time implementation of crypto operations is a separate concern.

5. **BSV chain availability**: We assume the BSV chain remains available for anchoring and verification. If the chain becomes permanently unavailable, the anchoring proofs lose their external verification capability (though local hash-chain proofs remain valid). Tests 3.3.1, P2.1, P3.1, and 6.2 depend on this.

6. **Social engineering**: An operator who voluntarily hands over their private key breaks non-repudiation. The system prevents *technical* bypasses, not *social* ones.

7. **Implementation conformance gap**: Layer 1 (Zig ↔ Lean conformance) is established by testing, fuzzing, and review — not by formal proof. A verified compiler for Zig→WASM does not exist. This means there is a non-zero (though empirically small) probability that the Zig code diverges from the Lean model in an untested path. We mitigate this with mutation testing (100% kill rate target) and differential test vectors, but we cannot eliminate it.

8. **Trusted boot integrity**: P4.1 depends on the boot/loader sequence correctly verifying the WASM binary hash before loading. If the loader itself is compromised, binary replacement is undetectable. This is the standard "root of trust" problem in all measured boot architectures.

9. **Application-layer correctness**: Several compliance tests (2.1, 2.3, 3.1, 5.1) require the application layer to correctly route all operations through the kernel. The kernel provides the enforcement substrate, but if the application bypasses the kernel (e.g., writing directly to a database without creating a semantic object), the compliance properties are not guaranteed. The kernel contribution column in Section 6 makes this explicit.

---

## 11. The Regulatory Argument (What We Tell Auditors)

The deliverable for regulators is NOT the Lean/TLA+ source code. It's a document that says:

> "We have mechanically verified that the Semantos Plane kernel satisfies execution invariants K1–K5 and object integrity invariant K7, under an abstract model of the 2-PDA. We have model-checked protocol invariant K6 under bounded state spaces. We have strong empirical evidence (240+ conformance tests, property-based fuzzing, differential testing, 100% mutation kill rate) that the Zig implementation conforms to the abstract model. Here is the SHA-256 of the WASM binary, reproducibly built from the verified source, anchored on BSV. Here is how each invariant contributes to your regulatory requirements, alongside the explicit assumptions each mapping depends on. The proofs, models, and test results are available for independent verification."

This is a fundamentally different posture from:

> "We have controls in place. Here are our policies. Here are our audit logs. Trust us."

The first is a layered technical argument with machine-checked proofs at its core, explicit assumptions, and empirical evidence bridging abstract model to implementation. The second is an organizational claim backed by process. That difference — and the honest acknowledgment of where each layer's evidence is strongest and weakest — is the entire point of P4.1.

---

## Appendix A: Key Source Files for Proof Targets

| File | Lines | What to Model |
|------|-------|---------------|
| `packages/cell-engine/src/linearity.zig` | ~200 | K1: Linearity enforcement rules |
| `packages/cell-engine/src/pda.zig` | ~300 | K5: Stack structure, bounds, operations |
| `packages/cell-engine/src/opcodes/plexus.zig` | ~400 | K2, K3, K4: Plexus opcodes |
| `packages/cell-engine/src/executor.zig` | ~500 | K2, K5: Execution loop, opcount |
| `packages/cell-engine/src/cell.zig` | ~200 | K7: Cell packing, header format |
| `packages/cell-engine/src/beef.zig` | ~400 | SPV verification (supports K6 anchor) |
| `src/types/semantic-objects.ts` | ~300 | K6: State hash chaining |
| `src/compiler/validator.ts` | ~200 | K1: TypeScript-level linearity validation |
| `src/metering/channel-fsm.ts` | ~200 | FSM correctness (TLA+ target) |

## Appendix B: Cryptographic Assumptions (Two Levels)

The proof structure uses cryptographic assumptions at two levels. This distinction matters.

### Level 1: Idealized Axioms (used in Lean proofs)

The Lean model treats crypto primitives as *perfect functions*. This is stronger than the real-world computational definitions but is standard practice in mechanized verification (the Lean type system has no notion of computational complexity or PPT adversary bounds).

1. **SHA-256 as injection**: `m1 ≠ m2 → H(m1) ≠ H(m2)` — perfect collision freedom
2. **ECDSA existential unforgeability**: valid verification implies existence of signing key
3. **HMAC as injection**: keyed HMAC on distinct messages produces distinct outputs

These are *idealizations*. The proofs hold conditional on the real primitives behaving as their idealized versions.

### Level 2: Computational Assumptions (the real-world justification for Level 1)

The idealized axioms are justified by the following standard computational assumptions, which have decades of cryptanalytic support:

1. **SHA-256 collision resistance**: No PPT adversary can find `m1 ≠ m2` such that `SHA-256(m1) = SHA-256(m2)` with non-negligible probability. (Justifies Level 1.1)

2. **ECDSA unforgeability (secp256k1)**: Under the EUF-CMA game, no PPT adversary with access to a signing oracle can produce a valid signature on a message not previously queried. (Justifies Level 1.2)

3. **HMAC-SHA-256 PRF security**: HMAC-SHA-256 keyed with a uniformly random key is computationally indistinguishable from a random function. (Justifies Level 1.3)

4. **HKDF security**: HKDF-SHA-256 produces outputs computationally indistinguishable from uniform when the input keying material has sufficient min-entropy.

Breaking any of these would have consequences far beyond Semantos — it would compromise most deployed cryptographic infrastructure globally. The gap between Level 1 and Level 2 is well-understood in the formal methods community and is accepted practice in projects of comparable rigor (seL4, CertiKOS, Ironclad Apps).
