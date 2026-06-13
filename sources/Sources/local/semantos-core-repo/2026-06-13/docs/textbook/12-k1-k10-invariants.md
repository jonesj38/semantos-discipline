---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/12-k1-k10-invariants.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.641316+00:00
---

# The K1–K13 Invariants

**Part IV — Verification (boot step 8)**

This chapter catalogues the thirteen kernel invariants that govern every execution the cell engine will accept. The invariants are not aspirational properties — they are the conditions whose conjunction defines what a conformant Semantos execution *is*. A cell engine that enforces K1–K5 and K7 satisfies the kernel-conformant level; K8, K9, and K10 extend the proof posture into the type-theoretic and temporal domains; K11, K12, and K13 specialise the proof posture to the wallet's signing semantics; K6 governs the distributed hash-chain property and is model-checked rather than theorem-proved.

Boot step 7 (`kernel_set_enforcement(1)`) is the call that activates enforcement. From that point forward the cell engine rejects any execution that would violate any of these invariants. This chapter explains what each invariant asserts, which execution path it closes off, and how it is verified. The proofs themselves — the Lean 4 mechanised proofs and the TLA+ model-check configurations — are in chapter 13.

---

## Background: what a kernel invariant is

A kernel invariant, per the glossary entry `kernel-invariant`, is a property of the cell-engine execution semantics provable mechanically over the abstract 2-PDA (two-stack pushdown automaton) model. The cell engine is deterministic, bounded, and contains no loop or jump instructions; these structural constraints make the abstract model amenable to formal proof.

The formal verification strategy (`docs/FORMAL-VERIFICATION-STRATEGY.md` §1) partitions the invariants into four classes:

| Class | Invariants | Proof method |
|---|---|---|
| Execution invariants | K1, K2, K3, K4, K5 | Lean 4 theorem prover |
| Object integrity | K7, K8 | Lean 4 theorem prover |
| Additional invariants | K9, K10 | Lean 4 |
| Wallet tier (Phase W1+W3) | K11, K12, K13 | Lean 4 + axiomatised crypto |
| Distributed / protocol | K6 + replay, revocation, partition, metering FSM, zone boundary, key custody, tier escalation | TLA+ model checker (bounded) |

The cell engine enforces K1 through K5 and K7 at the bytecode gate — the point where an opcode executes. Enforcement is structural: the Zig source has no runtime flag that disables linearity checking or domain-flag validation in production builds. The production WASM is compiled with `embedded = true`, which strips the debug code path containing `kernel_set_enforcement(0)`. A conformant deployment MUST verify `SHA-256(loaded_wasm) == anchored_hash` before the engine initialises (per §13.5 of the protocol specification).

The following sections treat each invariant individually. A summary table appears at the end of the chapter.

> **Note on the chapter filename.** This file is named `12-k1-k10-invariants.md` for historical reasons — chapter 12 originally covered K1–K10. Wave 8 of the wallet design added K11, K12, K13 (the signing semantics) and substantively promoted K4 (failure atomicity from a coverage index to per-opcode error-path inversion lemmas). The filename remains stable to preserve cross-references; the heading reflects the current scope.

---

## K1 — Linearity

**Statement (from `LinearityK1.lean`):** A LINEAR cell is consumed exactly once; it is never duplicated while live, and it is never discarded without authorised consumption. Once consumed, no operation can reintroduce an observationally identical cell.

K1 is the foundational substructural constraint. The cell header carries a linearity class at byte offset 16 (a uint32 LE value: 0 = LINEAR, 1 = AFFINE, 2 = RELEVANT, 3 = UNRESTRICTED). The cell engine reads this field before any stack operation and routes the request through the linearity gate.

### What K1 rules out

K1 has three sub-theorems, each closing a distinct failure path:

**K1a — no duplication while live.** The standard Bitcoin Script opcodes DUP, OVER, PICK, 2DUP, and 3DUP are classified as `duplicate` operations. The linearity gate evaluates `linearityPermits linear duplicate`, which returns `false`. The opcode does not execute; the engine returns an error and the stack is unchanged (failure atomicity, K4).

**K1b — no unauthorised discard.** DROP, 2DROP, and NIP are classified as `discard` operations. `linearityPermits linear discard` returns `false`. A LINEAR cell can leave the stack only via an authorised `consume`-classified operation — which requires that the cell's capability or identity conditions be met first.

**K1c — no reintroduction after consumption.** A consumed cell's `stateHash` is recorded. Any new cell sharing the same payload has a different `prevStateHash` (pointing to the current chain head rather than the consumed cell's predecessor) and a different timestamp. The 2-PDA model treats these as distinct cells, not as a reintroduction of the consumed one.

### Practical significance

Capability tokens are the primary resource governed by K1. A capability token is a BRC-108 UTXO modelled as a LINEAR semantic resource in the cell engine. An operator or agent attempting to double-spend a capability token — consuming the same UTXO in two distinct execution branches — violates K1b and K1c simultaneously. The cell engine halts, applies K4 rollback, and produces a structured error; the semantic state is byte-for-byte unchanged.

The AFFINE and RELEVANT classes carry partial linearity. An AFFINE cell may be consumed at most once (DROP is permitted; DUP is not). A RELEVANT cell must be used at least once (DUP is permitted; DROP is not). K1 covers all four linearity classes; the sub-theorems above specialise to the LINEAR class because that is where the strongest property holds.

At the implementation layer, K1 is enforced by `linearity.zig` via `checkLinearity()`. The Lean model's `linearityPermits` function is the abstract counterpart to this check; the formal verification strategy's Layer 1 conformance evidence (240+ Zig conformance tests, property-based fuzzing over random operation sequences) bridges the abstract proof and the concrete implementation.

---

## K2 — Authorisation soundness

**Statement (from `AuthSoundnessK2.lean`):** Any transition that changes authenticated semantic state requires successful verification of an authorised identity proof. Purely local stack transformations — arithmetic, hashing, data manipulation — are excluded from this requirement.

K2 is the identity gate. The Plexus opcode range (`0xC0`–`0xCF`) includes `OP_CHECKIDENTITY` (`0xC4`), which verifies a BRC-52 certificate binding against the participant graph. Every opcode in the range that gates semantic state — capability check, domain flag check, identity check — follows the peek-then-mutate pattern: the opcode first peeks at stack items without mutation, then validates the authorisation condition, then (and only then) mutates the stack state. If validation fails, the function returns an error before any mutation; failure atomicity (K4) ensures the state remains unchanged.

### What K2 rules out

K2 closes the unsigned-command attack surface. A transition that modifies authenticated semantic state — issuing a capability token, advancing a cell's version, transferring ownership — without first satisfying `OP_CHECKIDENTITY` cannot succeed. The proof proceeds by case analysis over the Plexus opcodes: each opcode that gates semantic state can be traced to a code path where the validation precedes the mutation, and the error path exits before the mutation executes.

K2 does not apply to local stack transformations. Adding two integers, computing a SHA-256 hash, or rearranging stack items does not constitute a semantic-state transition and is not subject to the identity gate. The distinction matters: the cell engine is not an arbitrary computation sandbox with an identity bolt-on; it is a semantic-state machine in which every observable side-effect carries an identity proof.

The cryptographic assumptions underlying K2 — specifically ECDSA existential unforgeability over secp256k1 — are axiomatised in the Lean model as ideal functions (see `CryptoAxioms.lean`). The formal proof holds conditional on these axioms; the axioms themselves rest on decades of computational cryptanalysis rather than on anything the cell engine can prove.

---

## K3 — Domain isolation

**Statement (from `DomainIsolationK3.lean`):** `OP_CHECKDOMAINFLAG` (`0xC6`) is total and correct: it returns TRUE if and only if the cell header's domain flag field (bytes 24–27, read as uint32 LE) equals the expected value. No execution path bypasses this check.

Domain flags are 4-byte uint32 namespace identifiers. The namespace is partitioned: `0x00000001`–`0x000000FF` for Plexus reserved well-known domains; `0x00000100`–`0x0000FFFF` for extended Plexus standards; `0x00010000`–`0xFFFFFFFF` for operator sovereignty. K3 guarantees that an execution whose script asserts a specific domain flag cannot proceed if the cell under evaluation carries a different domain flag.

### What K3 rules out

K3 closes domain-crossing execution paths. A capability token minted for governance domain A cannot be consumed by a script asserting governance domain B, because `OP_CHECKDOMAINFLAG` at the bytecode gate compares the cell header's `DomainFlag` field against the expected value and halts if they do not match. The proof is direct: the opcode implementation reads 4 bytes at header offset 24, compares with the expected value, and the only code path that pushes TRUE is the equality branch.

The TLA+ model augments K3 with a model-checked zone-boundary property (`ZoneBoundary.tla`) that verifies domain-flag isolation holds under all interleavings of concurrent operations — a property that the Lean proof, which models a single sequential execution, does not cover.

---

## K4 — Failure atomicity

**Statement (from `FailureAtomicK4.lean`):** Failed Plexus opcodes leave the 2-PDA state byte-for-byte identical to the pre-execution state. No partial mutation persists after a failed opcode.

K4 is a precondition for the correctness of every other invariant. Without it, a failed K1 check could leave a LINEAR cell in a partially consumed state; a failed K2 check could leave an identity binding partially recorded. K4 ensures that the cell engine's state is always in a well-defined pre- or post-execution configuration, never in a partially-applied intermediate.

### What K4 rules out

K4 closes partial-application state corruption. The peek-then-mutate pattern in the Plexus opcode implementations is the implementation mechanism: opcodes read from the stack without modifying it, validate all preconditions, and only then apply the mutation. If the validation fails, the function returns an error and the mutation step is never reached.

K4 also guarantees that a cell engine under adversarial input — scripts designed to trigger partial failure paths — cannot corrupt its own state. An attacker who sends a malformed capability-check opcode does not gain a partially-authenticated execution context; the engine returns to the pre-execution state as if the opcode had never been attempted.

### How K4 is proven (the inversion + atomicity pattern)

The Lean proof of K4 establishes the property in two layers per opcode, one substantive and one mechanical:

1. **Error-path inversion lemma** (`k4_<op>_error_inversion`). For each of the sixteen dispatched Plexus opcodes (`0xC0`–`0xCF`), the lemma states that any `.error _` outcome corresponds to one of an enumerated set of structural failure conditions on the input PDA. Proven by `unfold <op>` followed by a case-split through every match arm and if-branch in the opcode's definition. The prover walks every reachable error path; if a future refactor introduces a new error variant (or moves a mutation before an error return), the inversion lemma's exhaustiveness is no longer satisfied and the proof breaks.

2. **Atomicity corollary** (`k4_<op>_atomic`). Once the inversion lemma has shown the function returned `.error _`, the type-level disjointness of the `Except` monad's two constructors precludes any `.ok _` outcome on the same evaluation. Discharged uniformly via the `except_error_not_ok` helper.

The first layer is where the falsifiable content lives — the inversion lemma is what would catch a regression. The second layer is type-mechanical and follows for free. Earlier versions of K4 stated only the trivial `pda = pda` reflexivity claim, which held regardless of the function's actual behaviour; Wave 8's substantive promotion replaced those with the inversion lemmas (see `docs/design/PROOFS-WP9-K4-PROMOTION.md` for the full ledger).

### The three layers of K4 coverage

K4 is the clearest illustration of the three-layer verification posture from `docs/FORMAL-VERIFICATION-STRATEGY.md`. Each layer catches a class of regression the others miss:

- **Lean per-opcode inversions** catch a regression in the structural shape of an opcode definition. A new error path that isn't declared in the inversion lemma's disjunction breaks the proof immediately.
- **Zig fuzz** (`core/cell-engine/fuzz/plexus_atomic_fuzz.zig`) catches a regression where the inversion lemma is correct in the model but the Zig binary mutates state on an error path that the model didn't capture. Adversarial cell content over 50,000 iterations exercises the actual binary's failure paths.
- **WASM hash anchor** catches a regression where neither layer would help: the deployed binary has been swapped out for one that doesn't match the verified source. The on-chain anchored SHA-256 of the WASM blob, verified at boot step 7, is what ties the binary to the model.

Removing any one of these layers leaves a class of regression undetected. All three together is what the security guarantee actually is.

---

## K5 — Deterministic termination

**Statement (from `TerminationK5.lean`):** Every execution terminates in at most `opcountLimit` steps. The 2-PDA has no loop, jump, or call instructions; the program counter advances monotonically; the opcount increments per step and the engine halts when `opcount >= opcountLimit`.

The `opcountLimit` is configurable, with a default of 1 000 000 opcodes per script. The 2-PDA has a main stack of 1 024 cells and an auxiliary stack of 256 cells; stack overflow is a bounded halting condition, not an unbounded computation.

### What K5 rules out

K5 closes the halting-problem escape hatch. A conformant cell engine cannot be induced to loop indefinitely by a malformed or adversarial script. The instruction set enumeration — standard Bitcoin Script opcodes plus the Plexus extension range `0xC0`–`0xCF` — contains no backward-jump opcode. The proof enumerates the instruction set and verifies that none is a backward jump, that the PC increments monotonically, and that the opcount bound guarantees termination.

K5 is also the prerequisite for execution-time predictability. Because every script terminates in at most `opcountLimit` steps, a conformant deployment can bound the wall-clock time for any script execution and allocate resources accordingly. This property is required for the metering model (chapter 22) and for the Verifier Sidecar's per-request budget (chapter 14).

K5 also interacts with K10. K5 proves that individual executions terminate; K10 proves that the execution model as a whole is decidable. Together they mean: not only does every script halt, but there is an algorithm — not merely a bound — that determines what any script will produce for any input before running it.

---

## K7 — Cell immutability

**Statement (from `CellImmutabilityK7.lean`):** The 256-byte cell header is read-only after packing. No opcode in the instruction set modifies the linearity class, type hash, owner identifier, or hash-chain pointers (`parentHash`, `prevStateHash`) of a cell on the stack.

K7 is an object integrity invariant rather than an execution invariant. The cell header is packed by the cell packer (`core/cell-ops/src/packer/cell-packer.ts`); once packed, the header fields are frozen. The cell engine reads header fields — it must do so to enforce K1 and K3 — but it writes no header field.

### What K7 rules out

K7 closes header-mutation attacks. An adversarial script that attempts to alter a cell's linearity class from LINEAR to UNRESTRICTED, or to rewrite its `prevStateHash` to sever the hash chain, would be constructing a new cell with a modified header — it cannot mutate the existing cell's header in place. The Lean proof establishes this by verifying that no opcode in the instruction set writes to the header region of a cell on the stack.

K7 also provides the foundation for the hash-chain integrity arguments in K6 and K9. If the `prevStateHash` field were mutable post-packing, the hash chain could be silently rewritten. K7 guarantees that chain integrity, once established at pack time, cannot be undone by execution.

---

## K8 — Demotion safety (AFFINE → RELEVANT promotion)

**Statement (from `DemotionK8.lean`, with TLA+ supplement):** Promoting a cell's linearity class from AFFINE to RELEVANT preserves consumability. Specifically, the set of authorised consume operations on the cell is unchanged; no new consume paths are introduced; no existing consume paths are blocked.

K8 addresses a subtlety in the linearity hierarchy. AFFINE cells may be consumed at most once; RELEVANT cells must be used at least once. A promotion from AFFINE to RELEVANT might seem to relax constraints — and in one direction it does (the RELEVANT cell must be used, so it cannot simply be discarded). K8 establishes that this relaxation is safe: the promotion does not introduce new execution paths by which a cell could be consumed under conditions that the AFFINE class would have rejected.

### What K8 rules out

K8 closes promotion-based privilege escalation. Without K8, a script could hypothetically promote a cell to a linearity class that permits operations the original class forbade, consume the cell under those operations, and then claim the consumption was authorised by the original class. K8 establishes that promotion is monotone with respect to consumability: what was authorised before remains authorised after; what was forbidden before remains forbidden after. The TLA+ supplement model-checks K8 under concurrent promotions, verifying that no interleaving of concurrent promotion and consumption operations produces an authorisation bypass.

---

## K9 — Temporal morphism

**Statement (from `TemporalMorphismK9.lean`):** Hash chains compose under projection. Formally: if a sequence of state transitions produces a hash chain `H₀ → H₁ → H₂ → … → Hₙ`, then any projection of that chain — a subsequence preserving the temporal ordering — itself forms a valid hash chain under the same chaining rule.

K9 connects the per-cell hash chain (the `prevStateHash` linkage) to the broader temporal structure of the substrate. The protocol specification (§3.6) requires that every state transition produce a new state snapshot with incremented version, a typed patch recording the delta, and a fresh `stateHash`, with `prevStateHash` set to the previous state's `stateHash`. K9 establishes that this structure is compositional: partial views of the chain — selective disclosure proofs over a subset of states — are themselves valid chains.

### What K9 rules out

K9 closes selective-history attacks. An adversary attempting to present a partial evidence chain that omits inconvenient intermediate states cannot produce a valid chain under projection without those states. The projection property means that any valid sub-chain must be derivable from a valid full chain; a sub-chain that skips a state in the middle is not a valid projection and the hash-chain verification rejects it.

K9 also licenses the state merkle envelope format (§10.4 of the protocol specification): inscribing one merkle root over the state hash chain, rather than N individual state hashes on-chain, is valid because the envelope's selective disclosure proofs are projections of the full chain, and K9 guarantees that valid projections exist for any honest sub-sequence.

---

## K10 — Decidable execution model

**Statement (from `TuringCompletenessK10.lean`):** The combination of the 2-PDA and the bounded opcount limit yields a decidable execution model. For any script `s` and any initial state `q`, there exists an algorithm that determines in finite time whether `s` halts on `q` and what the resulting state is.

K10 is distinct from K5 (termination). K5 establishes that executions terminate; K10 establishes that the execution model as a whole is decidable — the halting problem has a definite answer for every input. The 2-PDA with bounded stack depth and bounded opcount is a finite-state machine in disguise: the state space is the cross-product of the two bounded stacks and the program counter, which is finite.

### What K10 rules out

K10 closes the class of attacks that rely on undecidability. In a Turing-complete execution environment, whether a script terminates — and what it produces if it does — may be undecidable in general. An adversary could construct a script that the execution environment cannot determine to be safe without running it. K10 eliminates this class: the cell engine's execution model is decidable, so safety analysis of scripts is computationally tractable without running them.

K10 is also the formal justification for the Verifier Sidecar's static pre-validation step. Because the execution model is decidable, the Sidecar can determine whether a script will satisfy K1 through K5 and K7 before invoking the cell engine, at a cost proportional to the script length rather than the execution trace length.

---

## K11 — Sign soundness (Phase W1)

**Statement (from `SignSoundnessK11.lean`):** `OP_SIGN` (`0xCD`) is sound in three respects: (a) on success, the LINEAR key cell is consumed (popped from the main stack before the signature is pushed); (b) the emitted signature verifies under the public key derived from the same secret key; (c) every error path in `opSign` returns before any `spop` or `spush` is invoked.

K11 is the wallet-tier specialisation of the per-opcode soundness story. The cell engine does not store keys. Each tier-N base key cell is loaded onto the stack at unlock time, used for one signing burst, and either consumed (if LINEAR — the leaf-key fast path) or kept on the stack (if AFFINE — the Tier-0 budget cell with embedded private key). K11 proves the on-stack discipline is enforced by the engine, irrespective of which actor or script invoked the sign.

### What K11 rules out

K11 closes three classes of regression in `opSign`:

- **Stack discipline failures.** A LINEAR key cell that is not consumed on a successful sign would leak a still-live tier-N capability into the post-execution stack — a critical violation of the wallet's single-use leaf discipline. K11a establishes that the success branch's three pops execute before the signature push.
- **Cryptographic correctness.** A signature whose verification under the corresponding public key fails would mean the engine is producing junk that can be trivially rejected, or worse, signatures that don't bind the correct message. K11b rules this out via the `ecdsa_sign_verifies` axiom in `CryptoAxioms.lean`, which idealises the host's signing primitive as a verifying ECDSA oracle. The empirical bridge to the actual binary is the `bsvz` differential test in `core/cell-engine/tests/sign_conformance.zig`.
- **Error-path mutation.** A failure path in `opSign` that touches the stack before returning would violate K4 for this opcode and silently consume a tier key without producing a signature — a denial-of-service that costs the user a leaf without giving them what they asked for. K11c (which is the K4 inversion lemma specialised to `opSign`) rules this out.

K11 carries the same axiomatised-crypto caveat as K2: the proof is sound conditional on the ECDSA primitives behaving as their idealised counterparts. The host import (`host_sign`) is empirically validated against the audited `bsvz` secp256k1 implementation; the Lean axiom is the assumption that links the two.

---

## K12 — Key custody (Phase W1)

**Statement (from `KeyCustodyK12.lean`):** No script execution path can copy a LINEAR tier key cell into a non-linear cell, and tier-N signing flows always present the correct domain flag before invoking `OP_SIGN`.

K12 is the bridge between the per-opcode soundness of K11 and the multi-step custody story modelled in TLA+ (chapter 13). Within a single execution, K12 establishes that the LINEAR-class discipline of K1 specialises correctly to tier-N base keys: no `OP_DEMOTE` path takes a LINEAR key to AFFINE without consuming it; no opcode duplicates a LINEAR cell into a non-linear container; and the standard wallet prelude (`OP_CHECKAFFINETYPE` → `OP_CHECKDOMAINFLAG` → `OP_SIGN`) cannot be bypassed by any script template the wallet emits.

### What K12 rules out

K12 closes the within-script paths by which a tier key could be re-used or re-typed:

- **Duplication into a non-linear cell.** A LINEAR key cannot be duplicated under any opcode (K1a). K12 specialises this to the wallet's tier keys: even via `OP_DEMOTE` (which is the only opcode that changes a cell's linearity class), the source must be LINEAR and the target must be AFFINE or RELEVANT — there is no LINEAR→LINEAR copy path, and no path that produces two LINEAR cells from one.
- **Domain-flag-bypass signing.** K12b establishes that any `OP_SIGN` invocation in a tier-N flow was preceded by an `OP_CHECKDOMAINFLAG` against that tier's flag. The tier-flag mapping (Tier 1 = `0x10000003`, Tier 2 = `0x10000004`, Tier 3 = `0x10000005`, Tier 0 hot = `0x10000001`) is enforced at the script-template builder, and the Lean theorem witnesses that the structure of the prelude makes the check unbypassable from inside the script.

K12 is the per-opcode side of the custody story; the cross-actor / multi-session side (no two browser tabs decrypt the same tier key concurrently; consumed keys cannot resurrect without a Plexus-mediated recovery) lives in the TLA+ `KeyCustody` model covered in chapter 13.

---

## K13 — Budget monotonicity (Phase W3)

**Statement (from `BudgetMonotonicityK13.lean`):** `OP_DECREMENT_BUDGET` (`0xCE`) strictly decreases `remaining_satoshis` when the call succeeds with a positive amount; `OP_REFILL_BUDGET` (`0xCF`) strictly increases `remaining_satoshis` when the call succeeds with a positive amount and a valid parent capability signature.

K13 governs the Tier-0 budget cell — the AFFINE cell carrying the wallet's authorised micropayment envelope. The cell payload contains a 64-bit unsigned `remaining_satoshis` field at byte offset 32 (relative to the payload start). `OP_DECREMENT_BUDGET` is the engine's primitive for a Tier-0 spend; `OP_REFILL_BUDGET` is the parent-authorised re-credit path. Both are subject to K1 (linearity), K3 (domain isolation against the Tier-0 hot flag), and K4 (failure atomicity) — and K13 specialises the arithmetic correctness on top.

### What K13 rules out

K13 closes the budget arithmetic regressions:

- **Spending more than the balance.** `OP_DECREMENT_BUDGET` checks `amount ≤ remaining` before any mutation. K13a establishes that the call's success implies `remaining' = remaining - amount` and `remaining' < remaining` when `amount > 0` — the new state is strictly less than the old.
- **Refilling without parent authorisation.** `OP_REFILL_BUDGET` requires a parent capability signature over `HASH256(cell.header || amount_LE8)`. K13b establishes that a successful refill implies the signature was valid under the embedded parent public key — without a valid sig, the call cannot succeed.
- **Overflow on credit.** A refill that would overflow `remaining + amount` into a wraparound is rejected by the overflow guard (`remaining > maxU64 - amount`). K13b inherits this through the model's abstract `budgetCheck` oracle.

K13 is the structural arithmetic correctness; the cross-actor enforcement (concurrent debits from two tabs, refill races, replay of refill signatures) lives in the TLA+ wallet models covered in chapter 13.

---

## K6 — Hash-chain integrity (protocol-level, TLA+ model-checked)

**Statement (`ReplayPrevention.tla`, `EvidenceChain.tla`):** The `prevStateHash` chain is append-only. Every state's `prevStateHash` equals the SHA-256 of the immediately preceding state's canonical serialisation. Tampering is detectable by any party with SPV access to the on-chain anchor.

K6 is not an execution invariant in the cell-engine sense — it governs the distributed hash chain across the full substrate, including the on-chain anchoring layer. It is model-checked in TLA+ rather than theorem-proved in Lean 4, because the distributed protocol involves concurrent operations across multiple nodes, interleavings that TLA+'s `TLC` model checker can exhaustively enumerate within bounded state spaces.

### What K6 rules out

K6 closes retroactive history rewriting. Once a state is anchored on-chain via the `OP_RETURN` output carrying the state merkle root, the SHA-256 collision-resistance assumption guarantees that an adversary cannot produce a different state with the same `stateHash`. Any modification to the history produces a different hash chain that diverges from the on-chain anchor; the divergence is detectable by any SPV client that holds the block header.

K6 also interacts with K7: because cell headers are immutable post-packing (K7), the `prevStateHash` field cannot be altered after the cell is packed. The combination of K6 (chain integrity) and K7 (header immutability) means that the hash chain is both anchored externally and internally non-writable — both the chain and the pointers that form it are protected.

For compliance contexts, K6 is the invariant that satisfies the audit-trail-immutability requirement: any evidence chain submitted to an auditor can be independently verified against the on-chain anchor without trusting any party that assembled the chain. The hash-chain integrity argument is detailed in the formal verification strategy's §6 compliance-test mapping, where K6 contributes to test 3.3.1 (immutable audit trail) across IEC 62443, EU AI Act, GDPR, HIPAA, and NIS2.

The TLA+ model checks K6 over bounded state spaces (3–5 objects, chain length up to 10 items) covering all interleavings of concurrent evidence-chain appends, state rollbacks, and revocation events.

---

## Invariant summary table

The following table states each invariant, its primary proof method, and the specific class of execution it rules out.

| ID | Invariant | Proof method | Rules out |
|---|---|---|---|
| K1 | A LINEAR cell is consumed exactly once; never duplicated, never discarded without authorised consumption | Lean 4 (`LinearityK1.lean`) | Capability-token double-spend; silent discard of LINEAR resources |
| K2 | Any state-changing transition requires successful identity verification | Lean 4 (`AuthSoundnessK2.lean`) | Unsigned state transitions; identity-bypass attacks |
| K3 | `OP_CHECKDOMAINFLAG` is total and correct | Lean 4 (`DomainIsolationK3.lean`) | Cross-governance-domain capability consumption; domain-crossing execution |
| K4 | Failed Plexus opcodes leave the PDA state byte-for-byte unchanged (per-opcode error-path inversion + atomicity corollary) | Lean 4 (`FailureAtomicK4.lean`) + Zig fuzz + WASM hash anchor | Partial-application state corruption; half-applied identity bindings; silent stack mutation on failure |
| K5 | Every execution terminates within `opcountLimit` steps | Lean 4 (`TerminationK5.lean`) | Infinite loops; unbounded resource consumption; undecidable halting |
| K6 | The `prevStateHash` chain is append-only | TLA+ model check (`EvidenceChain.tla`, `ReplayPrevention.tla`) | Retroactive history rewriting; replay of consumed LINEAR resources across nodes |
| K7 | The 256-byte cell header is read-only after packing | Lean 4 (`CellImmutabilityK7.lean`) | Header-mutation attacks; linearity-class forgery; hash-chain pointer rewrites |
| K8 | LINEAR → AFFINE / LINEAR → RELEVANT demotion is the only valid linearity transition | Lean 4 + TLA+ (`DemotionK8.lean`) | Promotion-based privilege escalation; new consume paths introduced by linearity transitions |
| K9 | Hash chains compose under projection (temporal morphism); peek-then-mutate enforces attestation-before-commitment | Lean 4 (`TemporalMorphismK9.lean`) | Selective-history attacks; invalid sub-chains presented as honest projections |
| K10 | 2-PDA + bounded opcount yields a decidable execution model | Lean 4 (`TuringCompletenessK10.lean`) | Undecidability-based attacks; non-tractable static safety analysis |
| K11 | `OP_SIGN` consumes the LINEAR key cell, emits a verifying signature, and is failure-atomic on every error path | Lean 4 (`SignSoundnessK11.lean`) + axiomatised ECDSA + bsvz differential | Tier-key leak after sign; junk signatures; silent leaf consumption on error |
| K12 | LINEAR tier keys cannot be duplicated into non-linear cells; tier-N signing requires a domain-flag check | Lean 4 (`KeyCustodyK12.lean`) | Within-script tier-key copy paths; domain-flag-bypass signing |
| K13 | `OP_DECREMENT_BUDGET` strictly decreases `remaining_satoshis`; `OP_REFILL_BUDGET` strictly increases it under valid parent signature | Lean 4 (`BudgetMonotonicityK13.lean`) | Spending more than the balance; refill without parent authorisation; overflow on credit |

---

## Closing: what each invariant rules out

**K1** rules out the consumption of any LINEAR resource more than once. No script can duplicate a LINEAR cell or silently discard it without authorised consumption — which means capability tokens, as LINEAR resources, cannot be double-spent and cannot vanish without a traceable authorised consumption event.

**K2** rules out unsigned state transitions. No execution path that modifies authenticated semantic state — capability issuance, version advancement, ownership transfer — succeeds without a verified identity proof. The identity gate is not optional; it is a structural precondition of every semantic-state opcode.

**K3** rules out cross-governance-domain execution. A script asserting governance domain A cannot be used to consume a cell carrying governance domain B. The domain flag check is total — it applies to every cell, on every execution, in every governance domain — and correct — the only TRUE result comes from an exact match.

**K4** rules out partial-application state corruption. A failed opcode leaves the stack as it was before the opcode was attempted. There are no partially-applied mutations, no half-recorded identity bindings, no inconsistent intermediate states.

**K5** rules out non-terminating execution. Every script the cell engine accepts terminates in a bounded number of steps. The instruction set contains no backward jump; the opcount is monotonically increasing and bounded.

**K6** rules out retroactive history rewriting. The `prevStateHash` chain is append-only; once a state is anchored on-chain, the anchor is externally verifiable by any SPV client. An adversary who modifies the history produces a divergent hash chain that any honest verifier will detect.

**K7** rules out header-mutation attacks. The linearity class, type hash, owner identifier, and hash-chain pointers of a packed cell cannot be modified by any opcode. A cell's substructural type is fixed at pack time and cannot be upgraded or downgraded by a script.

**K8** rules out promotion-based privilege escalation. Promoting a cell's linearity class from AFFINE to RELEVANT does not introduce new execution paths that the AFFINE class would have forbidden. Promotion is monotone with respect to consumability.

**K9** rules out selective-history attacks. Any valid sub-chain is a projection of a valid full chain. A chain that skips intermediate states is not a valid projection and does not verify against the on-chain anchor or against any honest hash-chain verifier.

**K10** rules out undecidability-based attacks. The execution model is decidable: for any script and any initial state, there exists a finite algorithm that determines whether the script halts and what it produces. Static pre-validation by the Verifier Sidecar is computationally tractable.

**K11** rules out three classes of `OP_SIGN` regression: tier-key leakage on a successful sign (the LINEAR key cell is provably consumed before the signature is pushed), production of signatures that don't verify under the corresponding public key (cryptographic correctness via the axiomatised ECDSA primitive), and silent leaf consumption on a failed sign (every error path returns before any stack mutation).

**K12** rules out within-script tier-key duplication and domain-flag-bypass signing. No opcode can copy a LINEAR tier key into a non-linear cell; every tier-N sign flow is preceded by an `OP_CHECKDOMAINFLAG` against that tier's flag. The wallet's standard prelude is structurally unbypassable from inside the script.

**K13** rules out budget arithmetic regressions. `OP_DECREMENT_BUDGET` cannot consume more than `remaining_satoshis`; `OP_REFILL_BUDGET` cannot credit without a valid parent capability signature, and cannot wrap around on overflow. The arithmetic discipline is monotone: debits strictly decrease, credits strictly increase.

The mechanised proofs of K1 through K5, K7, K8, K9, K10, K11, K12, and K13 in Lean 4, and the TLA+ model-check configurations for K6, the distributed protocol properties (replay prevention, cert revocation, partition resilience, metering FSM, zone boundary, demotion safety, transaction DAG), and the wallet system-level properties (key custody, tier escalation, OP_SIGN replay prevention, BRC-42 monotonic-index allocator atomicity), are the subject of the next chapter (see chapter 13 for the Lean and TLA+ proofs).
