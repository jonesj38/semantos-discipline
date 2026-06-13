---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/30-compliance-posture.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.650539+00:00
---

# Compliance Posture

**Part VIII — Building**

This chapter describes how the kernel invariants K1 through K10 compose into a compliance posture that is structural rather than procedural. It explains what each invariant contributes to a regulatory argument, maps those contributions to named requirement categories, provides a sample regulator-facing section for a single named requirement, records the explicit assumption register that bounds every claim made here, and specifies how the WASM build hash is anchored on-chain and reproduced independently.

The chapter is addressed to two audiences simultaneously: the implementer who needs to understand what the kernel actually guarantees, and the compliance engineer who must translate those guarantees into a regulatory submission. Both audiences benefit from the same discipline — being precise about what is proved, what is tested, and what is assumed.

---

## Why Compliance Is Structural

Most compliance postures are procedural. A system declares a policy, implements a control, runs an audit, and produces documentation asserting that the control was active during the audit period. The regulator accepts the documentation as evidence of intent and capability. The posture depends on the trustworthiness of the organizational process, not on the mathematics of the system.

The Semantos kernel takes a different approach. The enforcement properties embedded in K1 through K10 cannot be disabled by an administrator, bypassed by a configuration change, or overridden by a database write. This is the content of the capstone claim P4.1 in the Formal Verification Strategy: *compliance properties cannot be disabled by an administrator.*

P4.1 is not a marketing claim. It is a technical claim with a layered proof structure:

- K1 through K5 and K7 are proved as theorems over an abstract model of the two-stack pushdown automaton (2-PDA) using the Lean 4 theorem prover. The proofs are machine-checked; they do not rely on the reviewer's judgment about whether the invariant holds.
- K6 is model-checked using TLA+ over bounded state spaces, covering all reachable interleavings of the distributed hash-chain protocol.
- K8, K9, K10 are additional invariants covering linearity promotion, hash-chain temporal composition, and the decidability of execution — each with a corresponding Lean proof or TLA+ model.
- The Zig/WASM implementation is bridged to the abstract model through 240-plus conformance tests, property-based fuzzing, differential testing, and mutation testing. This evidence is strong but not a formal proof of implementation correctness.
- The WASM binary itself is anchored on BSV at release time. Devices verify the SHA-256 of the loaded binary matches the anchored hash before the engine initialises. A mismatch refuses to load.

The combination — machine-checked proofs of the abstract model, strong empirical evidence of implementation conformance, and on-chain binary integrity — is a fundamentally different posture from "we have controls in place." It is what the Formal Verification Strategy calls a layered technical argument with machine-checked proofs at its core, explicit assumptions, and empirical evidence bridging abstract model to implementation.

This chapter operationalises that argument for a compliance context. The goal is not to claim a monolithic formal proof of full regulatory compliance. The goal is to identify precisely what the kernel contributes to each requirement, state the additional assumptions those contributions depend on, and provide a form that a regulator can inspect and reproduce.

---

## The K-Invariants as Compliance Primitives

The ten kernel invariants divide into three classes by proof method and scope.

### Execution Invariants (K1–K5)

These invariants are proved in Lean 4 over the abstract 2-PDA model. They hold for every execution trace, unconditionally within the model.

**K1 — Linearity.** A LINEAR cell is consumed exactly once. It cannot be duplicated while live; it cannot be discarded without authorized consumption; once consumed it cannot reappear unless a distinct cell is created. The distinctness is structural: any new cell with the same payload has a different `prevStateHash` (pointing to the current chain head) and a different timestamp, making it a new cell, not a reintroduction.

The compliance contribution of K1 is direct and broad. Any requirement that prohibits double-spend, replay, or unauthorised duplication of a controlled resource — a capability token, a work permit, a transaction record — is supported by K1. The invariant is enforced at the bytecode gate by `OP_CHECKLINEARTYPE` (opcode `0xC0`) and `OP_ASSERTLINEAR` (opcode `0xC5`). No execution path that bypasses the gate exists in the production binary; the production WASM is built with `embedded = true`, which removes the `kernel_set_enforcement(disabled)` debug pathway at compile time.

**K2 — Authorization soundness.** Any transition that changes authenticated semantic state requires successful verification of an authorized identity proof. Purely local stack transformations (arithmetic, hashing, data manipulation) are excluded. The enforcement point is `OP_CHECKIDENTITY` (opcode `0xC4`) and the host import `hostVerifySignature`, which is called for every BRC-100 signed envelope crossing an adapter boundary.

K2 supports requirements that demand that every state-changing action be attributable to a verified identity. It is the structural foundation for non-repudiation: a valid signature verifies back to a BRC-52 certificate, which traces to a BRC-42 root key derivation. If verification fails, the 2-PDA state is unchanged — K4 guarantees that.

**K3 — Domain isolation.** `OP_CHECKDOMAINFLAG` (opcode `0xC6`) rejects unless the cell header's domain flag matches the expected value. No execution path bypasses this check. The check reads 4 bytes at header offset 24 and compares against the expected value; the only path that pushes TRUE is the equality branch.

K3 supports zone-boundary enforcement, access-policy partitioning, and any requirement that demands separation between named administrative contexts. The domain flag namespace is partitioned into Plexus-reserved flags (`0x00000001`–`0x000000FF`), extended Plexus standards (`0x00000100`–`0x0000FFFF`), and the operator-sovereign range (`0x00010000`–`0xFFFFFFFF`). An operator who configures zone separation via domain flags receives K3's unconditional enforcement of that separation.

**K4 — Failure atomicity.** Failed Plexus opcodes leave the 2-PDA state byte-for-byte identical to the pre-execution state. The implementation uses a peek-then-mutate pattern: opcodes inspect stack state without mutation, validate the authorization condition, and only write on success. If validation fails, the function returns an error and the write step never executes.

K4 is a prerequisite for the other invariants' security properties. Without K4, a failed K2 check might leave partial state that a subsequent operation could exploit. With K4, failure is atomic: the caller sees an error and an unchanged stack.

**K5 — Deterministic termination.** Every execution terminates within `opcountLimit` steps. The instruction set is enumerated (standard Bitcoin Script plus the Plexus extension range `0x4C`–`0xD0`). None is a backward jump. The program counter increments monotonically. When `opcount >= opcountLimit`, execution halts. The two-stack bounds (1024 main slots, 256 auxiliary slots) provide the additional structural guarantee that the stack cannot grow without bound.

K5 supports availability requirements. A compliance argument that depends on the system remaining available under load cannot be weakened by an execution that diverges or exhausts resources. Deterministic termination with a bounded step count makes worst-case execution time computable, which is the prerequisite for any real-time or response-time guarantee.

### Object Integrity Invariant (K7)

**K7 — Cell immutability.** The 256-byte cell header is read-only after packing. No opcode in the instruction set modifies the linearity class, type hash, owner ID, or hash-chain pointers of a cell on the stack. The proof is direct from the instruction set: the complete enumeration of opcodes shows that none writes to cell header fields.

K7 supports audit trail integrity and model versioning requirements. A cell's type hash encodes the domain classification, operation mode, and artefact type of the semantic object. Once packed, that classification cannot be retroactively altered, even by a privileged operator. A compliance claim that audit records cannot be tampered with after creation rests on K7 combined with K6.

### Protocol and History Invariants (K6, K8–K10)

These invariants operate at the protocol and composition level. K6 is model-checked using TLA+; K8, K9, and K10 have Lean proofs augmented where appropriate with TLA+ model checks.

**K6 — Hash-chain integrity.** The `prevStateHash` chain is append-only. Tampering is detectable by any party with SPV access, because modifying any state entry changes its hash, which breaks the chain at the modification point and diverges from the anchored root. The TLA+ property `TemporalIntegrity` is checked over all reachable interleavings within the bounded state space.

K6 is the structural foundation for audit trail immutability, temporal ordering guarantees, and platform-shutdown survival. The chain persists independent of any single node's availability; a party with the chain root and SPV access to BSV can verify completeness and ordering without trusting the original operator.

**K8 — AFFINE to RELEVANT promotion preserves consumability.** Promoting a cell from AFFINE to RELEVANT linearity (from "used at most once" to "used at least once") does not create a consumption obligation where none existed or remove the prohibition on duplication. The invariant ensures that linearity-class transitions do not open gaps in the consumption model.

**K9 — Hash chains compose under projection (temporal morphism).** When a hash chain over a longer time interval is projected onto a shorter sub-interval, the projected chain is itself a valid hash chain with the correct `prevStateHash` linkages. This supports requirements that demand verifiable partial evidence exports — a regulated entity exporting a window of its audit trail to a regulator can prove the window is a contiguous fragment of the full chain.

**K10 — Decidable execution.** The combination of the bounded 2-PDA and the `opcountLimit` counter yields a decidable execution model. Every question of the form "does this script halt and produce output X?" is decidable; the system does not admit executions that cannot be analysed. K10 is the formal statement of what K5 implies at the model level: the cell engine is not Turing-complete, and that is a feature, not a limitation.

---

## Mapped Requirements

The table below maps each kernel invariant to the compliance frameworks addressed in the Formal Verification Strategy §6. Each row states the invariant, the requirement category it supports, the additional assumptions the mapping depends on, and the proof method.

The framing follows §6 exactly: each row identifies the kernel contribution to requirement satisfaction, not full regulatory compliance. Full compliance requires procedural, operational, and organizational measures outside the kernel's scope. The kernel provides the structural foundation; the regulatory argument is that this foundation makes the procedural layer auditable and tamper-evident rather than trust-dependent.

| Invariant | Requirement Category | Named Tests (FVS §6) | Additional Assumptions | Proof Method |
|---|---|---|---|---|
| K1 | Replay prevention; work-permit gate | IEC 62443 1.1.2, 2.1.2 | Crypto axioms | Lean 4 |
| K2 | Identity-gated transitions; non-repudiation; machine identity | IEC 62443 1.1.1, 1.2.1; Cross-framework P1.1 | Host `checksig` correct | Lean 4 |
| K3 | Zone boundary enforcement; privacy by design | IEC 62443 2.1.1; GDPR 3.3 | — | Lean 4 |
| K4 | Failure does not corrupt state | Supporting invariant (enables K2, K3, K1 security) | — | Lean 4 |
| K5 | Availability; deterministic response time | NIS2 6.1 (partition resilience) | Local cert cache populated | Lean 4 |
| K6 | Audit trail immutability; temporal integrity; platform-shutdown survival | IEC 62443 3.3.1; Cross-framework P2.1, P3.1; EU AI Act 2.1, 2.3; HIPAA 5.1 | Crypto axioms; BSV available | TLA+ + paper |
| K7 | Cell immutability; model version recording; supply-chain compromise detectable | EU AI Act 2.4; NIS2 6.2 | Trusted boot; loader checks hash | Lean 4 + paper |
| K8 | Linearity promotion preserves consumability | Supporting invariant (closes gap in K1 model) | — | Lean 4 + TLA+ |
| K9 | Partial chain export is verifiable | GDPR 3.2 (data portability); HIPAA 5.2 | BSV available | Lean 4 |
| K10 | Decidable execution; analysable worst-case behaviour | Supporting invariant (underpins K5) | — | Lean 4 |

### Cross-Framework Invariants

Several requirements appear across multiple frameworks. The kernel invariants that underpin them are the same regardless of the regulatory namespace that names the requirement.

Non-repudiation (Cross-framework P1.1) depends on K2 combined with the ECDSA existential unforgeability axiom. A valid signature verifies to a known public key; that key is bound to a BRC-52 certificate; the certificate traces through the identity DAG to a root that was derived client-side and never transmitted to a server. The chain is unbroken if the host `checksig` implementation is correct — which is an explicit assumption, not a proved property.

Temporal integrity (Cross-framework P2.1) depends on K6. The TLA+ property `TemporalIntegrity` states: for any two evidence items in the chain, if the first has an earlier timestamp it appears earlier in the chain, and the second's `prevStateHash` equals the hash of the first. This is checked over all reachable interleavings within the bounded state space. An external BSV anchor pins the chain root to a block height, giving it an objective timestamp independent of any claim by the chain's custodian.

Platform-shutdown survival (Cross-framework P3.1) depends on K6 combined with the assumption that the BSV chain persists and the user retains their BRC-52 certificate. If the original operator is unreachable, a party with the evidence chain and SPV access can reconstruct the full history. The kernel's contribution is that the chain is self-verifying: no operator-provided decryption key or proprietary format is needed to validate it.

---

## Sample Regulator-Facing Section

The section below is an example of the form that a compliance submission for the Semantos kernel would take for a single named requirement. It is written in the third-person declarative register appropriate for a regulatory technical annex. The named requirement is NIS2 Test 6.2, drawn directly from the compliance mapping in Formal Verification Strategy §6.

The selection of NIS2 6.2 reflects two considerations. First, it is a binary-integrity requirement — it depends on the WASM hash anchoring mechanism that is described in detail in the WASM-hash anchoring section below, making it a suitable illustration of the end-to-end argument. Second, it depends on K7 (cell immutability) combined with a cryptographic argument about the anchored binary, which makes the kernel contribution visible rather than hidden inside a stack of process claims.

---

### NIS2 Directive — Article 21(2)(e): Supply Chain Compromise Detectable

> **Directive reference.** Directive (EU) 2022/2555 (NIS2), Article 21(2)(e): *security in network and information systems, including vulnerability handling and disclosure related to those entities' digital supply chains.*

> **Requirement in operational terms (FVS §6, Test 6.2).** A supply-chain compromise of the Semantos kernel — defined as the replacement of the production WASM binary with a modified binary that weakens or removes an enforcement invariant — must be detectable by any party with access to the BSV chain, without requiring cooperation from the operator.

**Kernel contribution.** The kernel invariant K7 (cell immutability) establishes that the 256-byte cell header is read-only after packing; no opcode in the instruction set modifies linearity class, type hash, owner ID, or hash-chain pointers. This is proved as a theorem in Lean 4 (`CellImmutabilityK7.lean`). A modified binary that relaxes this constraint would produce a binary that is not byte-identical to the production WASM.

The enforcement of this detection depends on the WASM binary hash anchoring protocol described in the WASM-hash anchoring section of this chapter. The SHA-256 hash of the production WASM binary is anchored on BSV at release time via an `OP_RETURN` output in an anchoring transaction. The transaction's merkle inclusion is proved by a BRC-74 BUMP (BSV Unified Merkle Path) proof, which any SPV client can verify independently.

At boot, the device loader computes `SHA-256(loaded_wasm)` and compares it to the anchored hash before the engine initialises. A mismatch causes the loader to refuse to load and to alert operators. This check is in the boot/loader sequence, not in the WASM binary itself — avoiding circularity.

The combination of K7 (proving that a conformant binary does not permit header mutation), the reproducible build (proving the WASM is a deterministic compilation of the verified Zig source), and the on-chain hash anchor (proving the anchored binary is the one that was verified) makes supply-chain compromise detectable: a modified binary has a different SHA-256 hash, which does not match the anchored hash, which is detectable by any SPV client.

**Additional assumptions.** The following assumptions are required for this mapping to hold. They are stated explicitly; none is a defect in the proof structure, but any claim of compliance that omits them is dishonest.

1. Trusted boot: the loader that performs the hash check must itself be trustworthy. If the loader is compromised, a modified binary can be accepted. This is the standard root-of-trust problem in measured boot architectures; it is not specific to Semantos.
2. BSV chain availability: the anchored hash must be retrievable via SPV. If the chain is permanently unavailable, on-chain verification fails (though local hash-chain proofs remain valid).
3. Crypto axioms: SHA-256 is modelled as collision-free. The mapping depends on the assumption that no adversary can produce a modified binary with the same SHA-256 hash as the production binary. This is the standard collision-resistance assumption; see the Cryptographic Assumptions section in Formal Verification Strategy §11.

**Proof layer.** K7 is proved by Lean 4 theorem. The WASM binary hash anchoring is empirically established (reproducible build verified by building twice and comparing hashes; manifest anchored on BSV). The trusted-boot dependency is an architectural claim verified by deployment audit. The combination is documented in the WASM-MANIFEST.json, which records SHA-256, Zig version, source commit, and build timestamp; the manifest hash is itself anchored on BSV.

**How a regulator reproduces this.** See the WASM-hash anchoring section of this chapter for the step-by-step reproduction procedure.

---

## Assumption Register

Every compliance mapping in this chapter depends on a bounded set of explicit assumptions. These assumptions are reproduced here verbatim from Formal Verification Strategy §13.6 (the honest assumption register) and §10 (the What This Does NOT Cover section). An audit that accepts the compliance mappings without accepting the assumptions is accepting more than the evidence supports.

The assumptions are not weaknesses. They are explicit boundary conditions that make the verification posture honest. Implementations and audits must acknowledge them.

**A1 — Cryptographic primitive security.** SHA-256, ECDSA over secp256k1, and HMAC-SHA-256 are axiomatised as ideal functions in the Lean model. The Lean model uses idealized oracle assumptions: SHA-256 is modelled as collision-free (no two distinct inputs produce the same output), ECDSA is modelled as existentially unforgeable (valid verification implies possession of the signing key), and HMAC-SHA-256 is modelled as a perfect pseudorandom function. These are stronger than the computational definitions (which involve probabilistic polynomial-time adversary bounds) and are standard practice in mechanized verification — the same approach is used in seL4, CertiKOS, and Ironclad. The real-world security of these primitives rests on decades of cryptanalytic literature. Breaking any of them would compromise most deployed cryptographic infrastructure globally.

**A2 — Hardware correctness.** The CPU correctly executes WASM instructions. A compromised CPU — through speculative execution bugs, rowhammer attacks, or similar physical-layer vulnerabilities — could violate any software property. This is outside scope for all software verification and is not specific to Semantos.

**A3 — Host import correctness.** The WASM binary imports `hostSha256`, `hostHmacSha256`, `hostVerifySignature`, and `hostCheckBump` from a TypeScript host. The host is not formally verified. The compliance tests that depend on this assumption include IEC 62443 1.1.1 (command requires identity), IEC 62443 1.3.1 (revoked cert rejected), IEC 62443 3.4.1 (sensor reading not spoofable), and Cross-framework P1.1 (non-repudiation). Strengthening this assumption would require a formally verified cryptographic library (such as HACL* or Fiat-Crypto) in the host implementation.

**A4 — Side channels.** Timing attacks, power analysis, cache attacks, and similar physical-layer side channels are not modelled. The Lean and TLA+ proofs are about functional correctness, not physical security. Constant-time implementation of cryptographic operations is a separate concern; the protocol spec (§13.3) requires constant-time comparison for all secret-comparison operations, but this requirement is not formally verified.

**A5 — BSV chain availability.** The on-chain anchoring story depends on the BSV chain remaining available for anchoring and SPV verification. If the chain becomes permanently unavailable, on-chain verification fails. Local hash-chain proofs remain valid, but the external timestamp and tamper-evidence properties that depend on BSV are lost. Requirements that depend on this assumption include IEC 62443 3.3.1 (audit trail immutable), Cross-framework P2.1 (temporal integrity), Cross-framework P3.1 (platform-shutdown survival), and NIS2 6.2 (supply-chain compromise detectable).

**A6 — Trusted boot integrity.** The capstone claim P4.1 depends on the boot loader correctly verifying the WASM binary hash before loading. If the loader is compromised, binary replacement is undetectable. This is the standard root-of-trust problem in all measured-boot architectures. A deployment that cannot establish trust in the loader cannot benefit from the on-chain binary integrity argument.

**A7 — Implementation conformance gap.** Layer 1 (Zig implementation conformance to the abstract Lean model) is established by 240-plus conformance tests, property-based fuzzing across four harnesses, differential testing of same inputs through the Lean model and Zig implementation, and mutation testing targeting 100 percent kill rate. This evidence is strong but is not a formal proof of implementation correctness. A verified compiler for Zig to WASM does not exist. There is a non-zero probability that the Zig code diverges from the Lean model in an untested execution path. The conformance test suite is the primary mitigation.

**A8 — Application-layer routing.** Several compliance tests require the application layer to correctly route all relevant operations through the kernel. The kernel enforces the invariants on the operations it receives; it cannot enforce invariants on operations that bypass it. Requirements in this category include EU AI Act 2.1 (AI decision traceable), EU AI Act 2.3 (human override recorded), GDPR 3.1 (right to erasure), and HIPAA 5.1 (every access recorded). The kernel contribution column in the mapped requirements table makes this explicit: "application routes all access through kernel" appears as an additional assumption for these tests.

---

## WASM-Hash Anchoring

The production Semantos cell engine is compiled from Zig source to a WebAssembly binary. The SHA-256 hash of that binary is anchored on BSV at release time. This section describes the mechanism and the procedure by which a regulator or independent auditor can reproduce and verify the anchor.

### The Anchoring Protocol

At release time, the build process produces the production WASM binary under the `embedded = true` compile-time flag. This flag removes debug code paths — including the `kernel_set_enforcement(disabled)` pathway that exists only in development builds. The binary is deterministic: given the same Zig version, compiler flags, and source commit, the build produces byte-identical output. Determinism is verified by building twice from the same source and comparing the SHA-256 hashes of the two outputs.

The build process records the following fields in `WASM-MANIFEST.json`:

```json
{
  "sha256": "<64-character hex SHA-256 of the production .wasm binary>",
  "zigVersion": "<zig version string, e.g. 0.13.0>",
  "sourceCommit": "<git commit SHA of the semantos-core repository>",
  "buildTimestamp": "<ISO 8601 UTC timestamp of the build>",
  "profile": "embedded",
  "opcountLimit": 1000000
}
```

The SHA-256 of the WASM-MANIFEST.json is computed and anchored on BSV via an `OP_RETURN` output in an anchoring transaction. The anchor transaction is constructed as an atomic-BEEF envelope (BRC-95), ensuring that its full transaction ancestry can be verified by any party with access to the BSV chain. The merkle inclusion of the anchor transaction is proved by a BRC-74 BUMP proof, which is stored in the continuation cell of type `0x01` associated with the anchor record. The anchor record itself is stored in the cell engine's state chain, making it verifiable through the same hash-chain integrity mechanism (K6) that protects all other state.

The anchoring uses the `OP_RETURN` output at the point in the anchor transaction's output script designated for this purpose. The payload of the `OP_RETURN` output is:

```
[4 bytes: magic 0x534D5453 ("SMTS")] [32 bytes: SHA-256 of WASM-MANIFEST.json]
```

The magic bytes allow any BSV chain scanner to locate Semantos binary anchors without scanning every `OP_RETURN` output.

### Boot-Time Verification

At boot, before the cell engine initialises, the device loader executes the following check:

```
computed_hash = SHA-256(loaded_wasm_bytes)
anchored_hash = retrieve_from_manifest_or_chain()
if computed_hash != anchored_hash:
    refuse_to_load()
    alert_operators()
    exit(1)
```

The check is in the boot/loader sequence, not in the WASM binary itself. This is essential: a check inside the binary being verified would be circular — a modified binary could simply remove the check. The loader is a distinct executable that is verified through the deployment's own trusted-boot mechanism (a separate root-of-trust question, assumption A6 above).

The `kernel_set_enforcement(1)` call at boot step 7 of the 15-step boot sequence marks the point at which the kernel begins enforcing all invariants. The loader's hash check occurs before this call, as a precondition of reaching step 7.

### Independent Reproduction Procedure

A regulator or independent auditor who has received the WASM-MANIFEST.json and wishes to verify the anchor independently follows these steps:

1. Obtain the WASM-MANIFEST.json from the release record. The manifest identifies the `sourceCommit` (a Git commit SHA in the `semantos-core` repository) and the `zigVersion`.

2. Check out the identified source commit. Build the WASM binary using the identified Zig version with the `embedded = true` profile flag:

```sh
zig build -Dembedded=true -Doptimize=ReleaseSafe
```

3. Compute the SHA-256 of the produced binary:

```sh
sha256sum zig-out/lib/semantos-cell-engine.wasm
```

4. Compare the computed hash against the `sha256` field in WASM-MANIFEST.json. The hashes must be byte-identical.

5. Compute the SHA-256 of the WASM-MANIFEST.json file itself:

```sh
sha256sum WASM-MANIFEST.json
```

6. Locate the anchor transaction on BSV. The anchor transaction's `txId` is recorded in the release record. Using any BSV SPV client, verify that the transaction is included in a block (via the BUMP merkle proof) and that the `OP_RETURN` output carries the payload `0x534D5453` followed by the SHA-256 of the WASM-MANIFEST.json computed in step 5.

7. If all comparisons succeed: the binary on the device is the deterministic compilation of the audited source, and the anchored hash proves that this specific binary was the release binary at the time of anchoring. The anchoring timestamp is the block timestamp of the block that includes the anchor transaction — an objective timestamp independent of any claim by the operator.

If step 4 fails (computed hash differs from manifest): the binary on the device is not the release binary. Either the build is non-reproducible (a build toolchain error) or the binary has been modified after release.

If step 6 fails (anchor transaction not found or payload mismatch): the manifest itself may have been modified, or the anchoring step was not completed for this release. The release record should be consulted to determine which case applies.

The full procedure is deterministic and requires no cooperation from the original operator. It requires access to: the `semantos-core` source repository at the identified commit, the identified Zig toolchain version, and any BSV SPV client capable of BUMP verification.

### WASM Profiles and the Production Constraint

The cell engine ships in two compile-time profiles. The full profile (approximately 185 KB) includes native cryptographic primitives (SHA-256, RIPEMD-160, secp256k1) and is used for standalone server and CLI deployments. The embedded profile (approximately 29 KB) delegates cryptographic operations to host imports and is used for browser applications and deployments where the host provides its own verified crypto library.

Both profiles MUST execute byte-identical opcode programs and produce byte-identical results given byte-identical inputs. The only difference is the source of cryptographic primitives.

The production WASM for compliance purposes MUST be the embedded profile built with `embedded = true`. This is the profile whose SHA-256 is anchored on BSV. A deployment that uses the full profile is not covered by the anchored hash and must manage its own binary integrity claims.

---

*End of Chapter 30.*
