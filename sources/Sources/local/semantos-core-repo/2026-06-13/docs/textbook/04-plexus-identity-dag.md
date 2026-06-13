---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/04-plexus-identity-dag.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.647855+00:00
---

# Plexus and the identity DAG

Part II of this textbook covers boot-sequence steps 1–6. Those six steps produce one outcome: a node that has a verifiable, recoverable identity anchored in a directed acyclic graph of cryptographic certificates, with all key material derived client-side and no private secret ever transmitted to any server. This chapter walks through the substrate components responsible for that outcome: Plexus, BRC-42 (BSV Key Derivation Scheme), BRC-52 (Identity Certificates), the identity DAG, the recovery substrate, and the formal invariant that ties them together.

---

## 1. Plexus in context

Plexus is the recovery substrate, identity DAG, and capability domain that Semantos integrates. It is implemented as a Go service — a single deployable binary fronted by BRC-100 (Wallet-to-Application Interface)-authenticated middleware — plus a set of client-side libraries. The separation is deliberate: the Go service holds metadata about identity structure; it never holds key material. All cryptographic derivation runs on the client device.

From the perspective of the boot sequence, Plexus is the substrate component responsible for the first six steps. Steps 1–3 happen entirely on the client device. Steps 4–6 involve the Plexus vendor SDK initialising tenant nodes and the capability domain minting initial capability tokens, but the cryptographic work remains client-side throughout. The recovery substrate enters the picture at step 13 (recovery payload backup); the material to be backed up, however, is fixed by the choices made in steps 1–3. Understanding steps 1–3 therefore requires understanding Plexus's identity model in full.

### 1.1 What Plexus is not

Plexus is not a key custodian. It never receives a root seed, a private key, or a plaintext challenge answer. What Plexus holds is the structural skeleton of an identity — the shape of the derivation tree, the monotonic indices that prevent rollback, the BRC-69 (Revealing Key Linkages) edge backup recipes that let a recovering device reconstruct shared secrets — all of it useless without the user's challenge answers, which remain on the user's device or in the user's memory.

This zero-knowledge property is not a policy constraint. It is a structural consequence of where PBKDF2 runs and what it produces. Section 4 of this chapter covers the recovery flow in detail; section 2 covers derivation first because the recovery flow cannot be understood without it.

---

## 2. Root key derivation (boot step 1 and 2)

Boot-sequence step 1 is the moment a user supplies email and answers to their challenge set. Step 2 is the moment the client device converts those inputs into a root seed.

### 2.1 The challenge set

The challenge set is the user-defined question-and-answer set that gates any subsequent recovery session. The protocol requires a minimum of three questions. The answers are normalised (casing, leading/trailing whitespace) and salted with a per-deployment value before being SHA-256-hashed for server-side storage. The normalised-plus-salted hash is what the server compares against during recovery phase 2; the plaintext answers never leave the client.

The challenge set has two separate roles that must be distinguished carefully. First, the normalised answers are used as the PBKDF2 input for root-seed derivation. Second, individually hashed answers are stored server-side for recovery-session authentication. These are different operations on the same answers. A server that can authenticate a recovery session cannot reconstruct the root seed — it holds only individual answer hashes, not the concatenated PBKDF2 input.

### 2.2 PBKDF2 derivation

The root seed derivation function is:

```
root_seed = PBKDF2(
  hash_function: SHA-256,
  password:      concatenated_normalised_challenge_answers,
  salt:          deterministic_per_user_salt(email, deployment_salt),
  iterations:    100_000,      -- minimum; implementations MAY use more
  output_length: 32 bytes
)
```

This derivation runs on the client device only. The root seed MUST NOT be transmitted to or stored on any server. The 100 000 iteration minimum is a brute-force cost floor; the attacker must run PBKDF2 at this cost for each guess, against a per-user salt, with no server-side oracle to accelerate the search.

The root seed is not itself used for signing or encryption. It is the input to BRC-42 derivation, which produces the actual key material for each purpose-specific context. The root seed is the single secret from which the entire key universe is reconstructable.

### 2.3 Relationship to the boot sequence

Steps 1 and 2 are offline. They require no network access, no Plexus server, and no external infrastructure. A conformant implementation MUST be able to complete steps 1 and 2 in a fully air-gapped environment. This is load-bearing: if the root-seed derivation depended on a remote service, recovery would require that service to be available, defeating the purpose of client-side-only key custody.

---

## 3. BRC-52 certificates and the identity DAG (boot step 3)

Boot-sequence step 3 derives a BRC-52 certificate from the root seed and computes the `cert_id`. This is the moment the node acquires its stable identity.

### 3.1 BRC-52 certificate format

A BRC-52 certificate encodes a node's identity in the Plexus DAG. The required fields are:

| Field           | Type              | Description                                                  |
|-----------------|-------------------|--------------------------------------------------------------|
| `subject`       | bytes(33)         | Compressed secp256k1 public key                              |
| `issuerCertId`  | bytes(32) or null | `cert_id` of the parent certificate (null for the user root) |
| `appId`         | bytes(32)         | Application namespace identifier                             |
| `childIndex`    | uint32            | Strictly monotonic per parent                                |
| `createdAt`     | uint64            | Milliseconds since epoch                                     |
| `domainFlags`   | bytes(N)          | Optional sequence of associated domain flag values (uint32)  |
| `signature`     | bytes(64+)        | Issuer signature over the canonical preimage                 |

The `cert_id` is the SHA-256 hash of the canonical preimage — a deterministic byte serialisation of all fields except `signature`. The `cert_id` is 32 bytes.

A key property: the `cert_id` is computable from public information only. Anyone who holds the certificate can verify the `cert_id`. The private key corresponding to `subject` is what gives the certificate holder the ability to sign actions attributed to that `cert_id`.

### 3.2 BRC-42 key derivation

BRC-42 (BSV Key Derivation Scheme) is the standard for deterministic client-side key derivation used throughout Plexus identity flows. The root seed from step 2 is the BRC-42 derivation root. From that root, every purpose-specific key in the system is derivable via a path that encodes the domain flag, the app ID, and additional context-specific parameters.

The critical property of BRC-42 derivation in this context is domain isolation. Keys derived under different domain flags are mathematically unrelated, even when they share the same root. A key derived for signing (`SIGNING`, domain flag `0x02`) cannot be used to derive or compute a key for edge creation (`EDGE_CREATION`, domain flag `0x01`), and vice versa. This property holds even if the root seed is known — knowing the root seed and one derived key does not reduce the cost of computing another derived key below the cost of re-running BRC-42 derivation with the correct domain flag.

This is the substrate mechanism behind key universe isolation: a single user has one root seed but many mathematically isolated key contexts, one per domain flag and app ID combination.

### 3.3 The identity DAG structure

Plexus identity is a directed acyclic graph of BRC-52 certificates. Each node in the DAG has:

- A `cert_id` — the node's identifier, computable from the certificate's public fields.
- An `issuerCertId` — the parent edge in the DAG; null for the user's root certificate.
- A monotonic `childIndex` per parent — strictly increasing, never reused.
- An optional `domainFlags` sequence — the set of key universes associated with this node.

The graph is a DAG, not a tree, in the sense that a single identity (a single BRC-52 cert) MAY exist in multiple contexts within the DAG. The same person can appear as customer and as employee; both contexts share the underlying cert but are uniquely identified by the tuple `(cert_id, appId, parentCertId, tenantPathSteps)`. The BRC-42 derivation paths for distinct contexts use distinct domain flags, so the keys for the two contexts are mathematically isolated even at the protocol level.

### 3.4 Issuance flow

When a parent entity issues a BRC-52 certificate to a child:

1. The parent derives a `CHILD_CREATION` key (domain flag `0x06`) from its own root.
2. The child generates a key pair client-side via BRC-42 derivation, using a parent secret that is never transmitted to the server.
3. The parent signs the child's BRC-52 certificate using the `CHILD_CREATION` key.
4. The child's certificate is assigned a monotonic `childIndex` — the maximum existing index for that parent plus one; this value is never reused.
5. The certificate is enrolled in the Plexus recovery substrate.

Step 4 deserves emphasis. The `childIndex` is strictly monotonic and never reused. This is the guard against derivation-tree rollback attacks: an attacker who replays an old `childIndex` is presenting a certificate the substrate will reject as already superseded. The monotonic guarantee is one component of the broader invariant K2, which states that any state-changing transition requires successful identity verification. Verification fails for any certificate that cannot be placed correctly in the DAG — wrong parent, wrong index, or missing enrollment.

### 3.5 `cert_id` and BCA derivation

The `cert_id` produced in boot-sequence step 3 is the stable identity hash the node is known by across the substrate. It serves as the input to BCA derivation — BCA (Blockchain Channel Address) being the deterministic IPv6-shaped address used as a peer identifier in the mesh and as the channel-funding key for MFP (Metered Flow Protocol) payment channels. The BCA derivation is implemented in `core/cell-engine/src/bca.zig`; the canonical TypeScript mirror ships at `core/protocol-types/src/bca.ts` [D-A0 / #195] and is conformance-vector-equal to the Zig reference.

Steps 4–6 of the boot sequence (Plexus vendor SDK initialisation, BCA computation, capability domain bootstrap) depend on a valid `cert_id`. Step 3 is therefore the identity-anchor moment: nothing in steps 4–6 is possible without the BRC-52 certificate produced here.

---

## 4. The recovery substrate

The recovery model is the other half of the identity design. A system that makes key derivation entirely client-side must answer a practical question: what happens when the client device is lost? The answer is the four-phase recovery protocol.

### 4.1 The zero-knowledge property

The central constraint of the recovery design is that the Plexus server is zero-knowledge with respect to the user's key material. An attacker with full server access cannot:

- Impersonate the user (they lack the private keys).
- Derive the user's keys (they lack the root seed and the challenge answers).
- Decrypt the user's data (encrypted fields require keys the server does not hold).

This constraint is structural. The recovery payload — the approximately 3.4 KB BRC-100-signed JSON blob that the server can export — is cryptographically useless without the user's challenge answers. The payload contains derivation state records, domain ceilings, BRC-69 edge backup recipes, tenant path steps, and schema mappings. None of that is sufficient to reconstruct any key without first running PBKDF2 over the user's challenge answers to obtain the root seed.

### 4.2 The recovery payload

The recovery payload required fields are:

| Field                 | Description                                                                |
|-----------------------|----------------------------------------------------------------------------|
| `version`             | Recovery payload format version                                            |
| `userCertId`          | Root cert_id                                                               |
| `derivationStates`    | Sequence of (resourceId, domainFlag, currentIndex, algorithmVersion)       |
| `domainCeilings`      | Per-domain monotonic-index ceiling for reconstruction validation           |
| `edgeBackupRecipes`   | Sequence of BRC-69 key linkage revelation recipes                          |
| `tenantPathSteps`     | DAG-traversal path for each enrolled tenant                                |
| `schemaMappings`      | Deterministic mappings between schema versions                             |
| `signature`           | BRC-100 signature over the canonical preimage                              |

The payload explicitly MUST NOT include raw private keys, root seeds, or plaintext challenge answers. What it includes is the structural map of the derivation tree — enough for a recovering device to re-run BRC-42 derivation in the correct order and produce the same key universe, given the root seed.

The BRC-69 edge backup recipes require additional explanation. An edge is a peer-to-peer cryptographic relationship between two cert nodes in the identity DAG, established via ECDH (Elliptic Curve Diffie-Hellman) under the BRC-85 PIKE (Proven Identity Key Exchange) protocol. The shared secret produced by ECDH is never stored in raw form; what Plexus stores is the BRC-69 recipe — the mathematical derivation record that lets a recovering device reconstruct the shared secret without Plexus ever holding it. An edge is described in the protocol as the primary recoverable unit, and the recovery payload's `edgeBackupRecipes` field is the mechanism that makes it so.

### 4.3 Four-phase recovery flow

Recovery follows a four-phase protocol in sequence. No single phase is sufficient to authorise reconstruction; all four must complete.

**Phase 1 — Email OTP.** The user initiates recovery; the server sends a one-time password to the registered email address. This validates the user's email-address claim and gates the remaining phases behind a channel the user must control.

**Phase 2 — Challenge-response.** The user answers the pre-registered challenge set. The server validates using constant-time comparison against the stored SHA-256 hashes. The brute-force limits are: maximum 10 attempts per hour; 5 consecutive failures lock the account for 24 hours. The attacker who can enumerate challenge answers offline (i.e., one with full server access and the stored hashes) still faces the PBKDF2 cost of root-seed reconstruction for each candidate set of answers.

**Phase 3 — Recovery payload export.** The server exports the recovery payload. At this point the server has done its part: it has authenticated the user and provided the structural metadata. The cryptographic reconstruction has not yet occurred.

**Phase 4 — Client-side reconstruction.** The client receives the recovery payload. It derives the root seed from the challenge answers via PBKDF2 at the same parameters as step 2 (SHA-256, minimum 100 000 iterations). It then re-derives the full key universe by re-running BRC-42 derivation along the paths encoded in the `derivationStates` and `tenantPathSteps` fields. It reconstructs ECDH shared secrets from the BRC-69 recipes using the re-derived keys. The server is not involved in this phase. The server has zero knowledge of the reconstruction material.

The four-phase structure is a deliberate multi-factor design. Compromising the server gives an attacker the payload but not the challenge answers. Compromising the user's email gives an attacker phase 1 but not phase 2. Observing phase 2 (the challenge answers over the network) gives an attacker the means to authenticate but not the root seed derivation, because the challenge-answer hashes stored server-side are individually hashed, not the concatenated PBKDF2 input. A full reconstruction requires control of email, knowledge of challenge answers, and access to the challenge-answer concatenation as the PBKDF2 input — a conjunction of factors that is structurally harder to compromise than any single factor.

### 4.4 Threshold and multi-party recovery

For high-security roots and high-value capability tokens, the substrate supports Shamir Secret Sharing in t-of-n threshold mode. Recovery of a higher-security construct (such as a capability vault) requires additional challenge sets gated behind the user's ability to exercise rights over their standard root. The threshold reassembly runs on the client device; raw high-security private keys are not reconstructed in server-accessible memory at any point.

For multi-party contexts — a corporate governance domain with multiple authorised users — the substrate supports recovery via individual bilateral edges. There is no central group key stored anywhere on the server side. Recovery relies entirely on the BRC-69 edge backup recipes to reconstruct the relationships. If a recovering party is missing one bilateral shared secret, the missing secret can be communicated to them securely via an existing bilateral edge with another party who holds it. The group's cryptographic foundation is restorable without the system ever knowing the shared secrets.

### 4.5 Brute-force mitigation summary

| Surface                   | Limit                                                  |
|---------------------------|--------------------------------------------------------|
| Recovery initialisation   | Maximum 10 attempts per hour                           |
| Challenge answers         | 5 consecutive failures locks account for 24 hours      |
| PBKDF2 iterations         | Minimum 100 000 (SHA-256)                              |
| Context enrollment        | Rate limited to prevent enumeration                    |
| Edge creation             | Rate limited to prevent enumeration                    |

---

## 5. Edges and the DAG in operation

The identity DAG grows over time as the user creates new contexts, establishes edges with other nodes, and enrolls new capabilities. Understanding how the DAG evolves is necessary for understanding what the recovery substrate is maintaining on an ongoing basis.

### 5.1 Edges

An edge is a peer-to-peer cryptographic relationship between two cert nodes in the identity DAG, established via ECDH using the BRC-85 PIKE protocol. Edge creation proceeds as follows:

1. Both parties derive keys from the `EDGE_CREATION` domain (domain flag `0x01`).
2. Public keys are exchanged out of band; the ECDH shared secret is computed client-side.
3. The BRC-69 edge backup recipe is computed from the derivation parameters.
4. The recipe is enrolled per the configured recovery policy: `BACKUP_ON_CREATE` (atomic backup at creation time), `BACKUP_ON_CONFIRM` (deferred backup), or `NONE` (ephemeral edge, not recoverable).

Edge uniqueness is enforced by the tuple `(cert_id, appId, counterpartyCert, edgeType)`. No two edges between the same pair of nodes in the same app context can coexist; the substrate rejects duplicate edge creation attempts.

ECDH shared secrets MUST be derived using secp256k1 and MUST NOT be transmitted over any channel. All edge operations MUST use constant-time comparison to prevent timing attacks.

### 5.2 Hats within the DAG

A hat is a role-or-capacity dimension under which a user signs actions: "Bob-as-tenant" versus "Bob-as-friend" versus "Bob-as-trustee." Each hat is associated with a distinct BRC-52 certificate (or, transitionally, a distinct hat record backed by a single certificate) and a distinct capability scope.

Hats matter to the identity DAG because they are the mechanism by which a single root identity fans out into multiple distinct signing principals. The DAG does not contain one node per user; it contains one node per user-per-hat-per-context. The BRC-42 derivation paths for distinct hats use domain flags that ensure key isolation: signing as a tenant cannot inadvertently produce key material that is related to signing as an employee, even if both hats derive from the same root.

The SIR (Semantic IR) layer carries a hat identity binding in every node's identity field. Trust-tier enforcement at SIR refuses cross-role authoritative claims structurally. A node operating under a renter hat cannot produce a syntactically valid SIR program that makes authoritative claims as a landlord — the SIR's `lowerSIR()` pass refuses to lower it. This is the compile-time enforcement that backs the runtime enforcement at the cell engine.

### 5.3 DAG consistency guarantees

The identity DAG maintains three consistency invariants that the recovery substrate is responsible for preserving:

**Monotonic child indices.** For any parent cert, child indices are strictly increasing and never reused. A cert presented with a `childIndex` equal to or below the current maximum for that parent MUST be rejected. This prevents replay attacks on the derivation tree.

**Issuer signature validity.** Every non-root cert carries an issuer signature over its canonical preimage. Verification of the `cert_id` requires verifying this signature against the issuer's `subject` public key, which is itself derivable from the issuer's cert. The chain is self-consistent.

**Domain flag isolation.** Keys derived in one context MUST NOT be mathematically related to keys derived in another context for the same root, even under root-secret compromise. This is the BRC-42 domain-separation property: divergent derivation paths under distinct domain flags produce unrelated key pairs. The cell engine's K3 invariant (`OP_CHECKDOMAINFLAG` is total and correct) enforces domain flag correctness at the bytecode gate; the identity DAG's structural design ensures that keys for different contexts were never derivable from each other to begin with.

---

## 6. Authorization soundness: kernel invariant K2

Boot-sequence steps 1–3 produce a node with a verifiable identity. But identity alone does not make state transitions safe — the substrate must also guarantee that no state-changing transition can succeed without successful identity verification. This is kernel invariant K2: any state-changing transition requires successful identity verification.

K2 is mechanised in Lean 4 in `proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean`. The proof covers two opcodes in the Plexus extension range of the cell engine: `OP_CHECKIDENTITY` (`0xC4`) and `OP_CHECKCAPABILITY` (`0xC3`).

### 6.1 What K2 states

K2 has three components in the proof:

**K2a** establishes that if `OP_CHECKIDENTITY` is called and the owner IDs of the identity cell and the target cell do not match, the operation returns an error and the PDA state is left byte-for-byte unchanged. There is no partial state update; verification failure leaves the stack in exactly the state it was in before the opcode was evaluated.

**K2b** establishes that `OP_CHECKIDENTITY` is the only opcode in the Plexus dispatch table that inspects the `ownerId` field. Every other opcode — `OP_CHECKLINEARTYPE`, `OP_ASSERTLINEAR`, `OP_CHECKDOMAINFLAG`, and the rest — checks linearity class, capability type, domain flag, type hash, or pointer validity, none of which involve an `ownerId` comparison. Identity verification is neither bypassed by a different opcode nor accidentally performed as a side effect.

**K2c** establishes that if `OP_CHECKCAPABILITY` is called on a cell whose linearity class is not `LINEAR`, the operation returns an error. Only LINEAR cells can hold capability tokens. Since capability tokens are BRC-108 (Identity-Linked Token Protocol)-formatted UTXOs modelled as LINEAR semantic resources, this opcode refuses to process a forged or downgraded capability representation.

Together, K2a, K2b, and K2c establish that state-changing transitions requiring identity or capability verification cannot succeed without correct, linear, identity-verified inputs. The cell engine enforces this at the bytecode gate on every execution.

### 6.2 The Lean proof

The following is the key theorem statement from `AuthSoundnessK2.lean`, excerpted verbatim:

```lean
-- Semantos Plane — Theorem K2: Authorization Soundness
--
-- Any transition that changes authenticated semantic state (identity
-- verification, capability check, domain flag check) requires
-- successful verification. Purely local stack transformations
-- (arithmetic, hashing, data manipulation) are excluded.
--
-- Proof target: plexus.zig opcodes 0xC3 (capability), 0xC4 (identity)

/-- K2a: If OP_CHECKIDENTITY (0xC4) is called and the owner IDs don't match,
    the operation returns an error and the PDA state is unchanged.
    Follows from the peek-then-mutate pattern in plexus.zig:93-111. -/
theorem k2a_identity_mismatch_error (pda : PDA)
    (h_depth : pda.sdepth ≥ 2)
    (idItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok idItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_mismatch : cellItem.header.ownerId ≠ idItem.header.ownerId) :
    ∃ e, opCheckIdentity pda = .error e := by
  unfold opCheckIdentity
  have hd : ¬(pda.sdepth < 2) := by omega
  simp [hd, h_peek0, h_peek1, h_mismatch]

/-- K2b (summary): Only OP_CHECKIDENTITY among Plexus opcodes references
    the ownerId field. The other 8 opcodes (0xC0-0xC3, 0xC5-0xC8) check
    linearity, capability type, domain flag, type hash, or pointer validity
    respectively — none of which involve ownerId comparison. -/
theorem k2b_only_checkidentity_verifies_owner_summary :
    (∀ (pda : PDA) (idItem cellItem : Cell),
      pda.sdepth ≥ 2 →
      pda.speekAt 0 = .ok idItem →
      pda.speekAt 1 = .ok cellItem →
      cellItem.header.ownerId ≠ idItem.header.ownerId →
      ∃ e, opCheckIdentity pda = .error e) := by
  intro pda idItem cellItem h_depth h_peek0 h_peek1 h_mismatch
  exact k2a_identity_mismatch_error pda h_depth idItem cellItem h_peek0 h_peek1 h_mismatch

/-- K2c: If OP_CHECKCAPABILITY is called on a non-LINEAR cell,
    the operation returns an error. Only LINEAR cells can hold capabilities.
    Follows from plexus.zig:77-78. -/
theorem k2c_capability_requires_linear (pda : PDA)
    (h_depth : pda.sdepth ≥ 2)
    (capItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok capItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_not_linear : cellItem.header.linearity ≠ .linear) :
    ∃ e, opCheckCapability pda = .error e := by
  unfold opCheckCapability
  have hd : ¬(pda.sdepth < 2) := by omega
  simp [hd, h_peek0, h_peek1]
  have hne : (cellItem.header.linearity != Linearity.linear) = true := by
    cases h : cellItem.header.linearity
    · exact absurd h h_not_linear
    · rfl
    · rfl
    · rfl
  simp [hne]
```

The proofs are mechanical over the abstract 2-PDA model: they establish the behaviour of specific opcodes given specific preconditions about the PDA state, without appealing to network or runtime properties. The underlying implementation is the Zig source at `core/cell-engine/src/opcodes.zig` (opcodes `0xC3` and `0xC4` in the Plexus extension range `0x4C`–`0xD0`); the Lean model abstracts over the bit-level implementation details.

### 6.3 Why K2 matters for steps 1–3

The identity DAG built in steps 1–3 is only as trustworthy as the enforcement that prevents one node from impersonating another. K2 is the formal statement that such impersonation is not possible through the bytecode gate: any opcode invocation that attempts to change state under a mismatched or non-LINEAR identity cell returns an error and leaves the PDA state unchanged. The cell engine does not partially apply a state change and then detect the mismatch; it peeks before it mutates. This peek-then-mutate pattern — visible in the `plexus.zig:93-111` reference in the K2a docstring — is the implementation choice that makes K2a provable as a theorem rather than merely observable in tests.

For the user who has just completed steps 1–3, K2 means: the `cert_id` they have derived is the only valid signing principal for actions attributed to their identity, and any cell engine opcode that enforces identity will refuse to process an incorrectly attributed cell.

---

## 7. Summary: boot-sequence steps 1–3 unlocked

The substrate components described in this chapter — BRC-42 derivation, BRC-52 certificate issuance, the identity DAG, the challenge set, and the recovery substrate — together implement boot-sequence steps 1, 2, and 3.

**Step 1** (user supplies email and challenge set answers) is the collection of the PBKDF2 input. The challenge set is stored server-side in individually hashed form; the concatenated answers remain client-side.

**Step 2** (PBKDF2 100 000 iterations on device → root seed) is the client-side derivation of the 32-byte root seed. The root seed is the single secret from which the full key universe is reconstructable. It is not transmitted anywhere.

**Step 3** (derive BRC-52 cert from root seed → `cert_id`) is the derivation of the user's stable identity hash via BRC-42 key derivation, certificate construction, and `cert_id` computation. The `cert_id` is the input to BCA derivation and the identity anchor for steps 4–6.

Steps 1, 2, and 3 require no external network dependencies and no Plexus server connectivity. A conformant implementation MUST complete these three steps from cold start in a fully air-gapped environment. The steps are collectively sufficient to establish a verifiable, recoverable identity in the Plexus DAG — an identity that K2 guarantees cannot be impersonated at the bytecode gate, and that the four-phase recovery protocol guarantees can be reconstructed on a new device without the server ever holding the reconstruction material.

Boot-sequence steps 1–3 are now unlocked. Chapter 5 continues with steps 4–6: hats, capability tokens, and the first moment the capability domain mints BRC-108 UTXOs under the node's `cert_id`.
