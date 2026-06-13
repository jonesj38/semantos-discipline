---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/21-recovery-substrate.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.652274+00:00
---

# Recovery substrate

Part VI of this textbook covers the three substrate components that boot steps 12–14 activate: the hash-chain time model (chapter 19), the universal intent and evidence chain (chapter 20), and the recovery substrate — the subject of this chapter. Boot step 13 is the moment the node backs its identity up to the Plexus Recovery Service. Before that moment the node's keys exist only on-device; after it, the node is recoverable from any device that can supply the same challenge set.

This chapter works through the four-phase recovery flow in full, including a worked example that shows the exact payload shape at each phase. It then covers threshold recovery for high-security roots and multi-party group recovery. The chapter closes by noting that boot-sequence step 13 is now unlocked.

---

## Background: what recovery is protecting

A sovereign node's keys are derived entirely on the client side. The root seed — from which every other key in the identity DAG is deterministically derived — is never transmitted anywhere. The Plexus Recovery Service stores routing metadata and derivation state, not secrets.

This design means a device loss, browser wipe, or hardware failure would be unrecoverable without a separate mechanism. That mechanism is the recovery substrate: a protocol that lets a user reconstruct their full key universe on a new device using only two inputs — the challenge set answers they originally registered, and the recovery payload stored server-side.

The recovery payload is approximately 3.4 KB of BRC-100-signed JSON. It contains the derivation-state records, domain-ceiling values, edge backup recipes, tenant path steps, and schema mappings that a recovering device needs to re-derive all keys via BRC-42 (BSV Key Derivation Scheme). The payload is cryptographically useless without the user's challenge answers — an attacker with full server access cannot impersonate a user, derive their keys, or decrypt their data. The zero-knowledge property is structural, not a policy promise.

The challenge set is the user-defined question-and-answer set that gates a recovery session. A minimum of three questions are required. Answers are normalised, salted, and SHA-256 hashed before server-side storage. The challenge set is used only for session authentication — the root seed comes from a separate PBKDF2 derivation over the answer concatenation, performed client-side only, and never repeated on the server.

BRC-42 is the key derivation standard underpinning every derived key in the substrate. PBKDF2 is run with SHA-256 at a minimum of 100 000 iterations against the normalised concatenation of challenge answers. The output is the root seed; from it, all child keys are derived deterministically using domain flags as namespace separators. The work factor makes offline brute-force of a captured recovery payload computationally expensive.

BRC-69 (Revealing Key Linkages) is the standard that defines the mathematical recipe used to store edge backup data. An edge is a peer-to-peer ECDH relationship between two cert nodes; the BRC-69 recipe lets a recovering device reconstruct a previously established ECDH shared secret without Plexus ever holding the secret itself. Per the protocol specification, the edge is the primary recoverable unit, and the recovery substrate is designed around edge persistence.

---

## The four-phase recovery flow

Recovery is a four-phase protocol. No single phase is sufficient to authorise reconstruction; all four must complete in order.

```
[FIGURE — needs real graphic for layout pass]

Phase 1                 Phase 2                   Phase 3                     Phase 4
─────────────────────   ───────────────────────   ─────────────────────────   ──────────────────────────
Email OTP               Challenge-response        Recovery payload export     Client-side reconstruction
User initiates →        User answers challenge  → Server assembles and      → Client derives root key
Server sends OTP        questions; server         exports recovery payload      locally; re-derives full
to registered email     validates hashes          (~3.4 KB BRC-100 JSON)       identity DAG from recipes
```

### Phase 1 — Email OTP

The user navigates to the recovery entry point and identifies themselves by email address. The Plexus Recovery Service sends a one-time password to that email address. Possession of the OTP proves the user's claim to the registered email address.

Phase 1 is necessary but not sufficient. Email possession is a single factor and is recoverable by an attacker who controls the user's email account. Phase 1 alone does not permit payload export; it opens the session for the subsequent challenge phase.

Rate limiting applies at the recovery initialisation surface: a maximum of ten attempts per hour. The brute-force surface here is the email guessing space, which is bounded by the registered email addresses in the system, so the primary protection at this phase is account enumeration prevention. Context enrollment and edge creation are separately rate-limited to prevent enumeration at those surfaces.

**Phase 1 payload (sent by the server):**

```json
{
  "session_token": "<ephemeral session token>",
  "otp_sent_to":   "<masked email>",
  "expires_at":    "<unix timestamp>"
}
```

The session token is opaque to the client; it carries the session context through phases 2 and 3. The OTP itself is delivered out of band.

### Phase 2 — Challenge-response

With the OTP verified, the server presents the set of challenge questions registered by the user. The user supplies their answers; the client normalises the answers (lowercasing, trimming whitespace, collapsing internal spaces), concatenates them in registration order, and submits the result. The server computes SHA-256 over the normalised, salted concatenation and compares the result against the stored hash in constant time.

Constant-time comparison is mandatory. Timing differences would leak the number of bytes that match, allowing incremental guessing. The protocol specification requires constant-time comparison at every secret-comparison surface throughout the substrate.

On successful validation, the server issues a recovery authorisation token. On failure, the attempt count increments. Five consecutive failures lock the account for 24 hours. The lock-out window prevents automated online guessing while keeping the recovery path accessible to a legitimate user who makes a small number of mistakes.

Maximum ten attempts per hour applies at the challenge surface as well, compounding the phase 1 rate limit.

**Phase 2 payload (submitted by the client):**

```json
{
  "session_token":       "<phase-1 token>",
  "challenge_responses": [
    "<normalised answer 1>",
    "<normalised answer 2>",
    "<normalised answer 3>"
  ]
}
```

**Phase 2 payload (issued by the server on success):**

```json
{
  "recovery_auth_token": "<short-lived authorisation token>",
  "expires_at":          "<unix timestamp>"
}
```

### Phase 3 — Recovery payload export

With the recovery authorisation token, the client requests the recovery payload. The server assembles the payload and signs it as a BRC-100-signed JSON blob. The payload is approximately 3.4 KB compressed and contains all the derivation metadata the client needs — but none of the secrets.

The required fields are:

| Field | Description |
|---|---|
| `version` | Recovery payload format version |
| `userCertId` | Root `cert_id` — the 32-byte SHA-256 hash identifying the user's root BRC-52 certificate |
| `derivationStates` | Sequence of `(resourceId, domainFlag, currentIndex, algorithmVersion)` tuples |
| `domainCeilings` | Per-domain monotonic-index ceilings, allowing reconstruction to validate that no replay is occurring |
| `edgeBackupRecipes` | Sequence of BRC-69 key linkage revelation recipes, one per enrolled edge |
| `tenantPathSteps` | DAG-traversal path for each enrolled tenant |
| `schemaMappings` | Deterministic mappings between schema versions |
| `signature` | BRC-100 signature over the canonical preimage |

The payload does not contain raw private keys, the root seed, or plaintext challenge answers. It contains the routing metadata — derivation state and domain ceilings — that lets a new device reconstruct the same derivation hierarchy that the original device computed. An attacker who captures this payload has the map but not the key; the map is useless without PBKDF2 over the challenge answers.

**Phase 3 payload (returned by the server):**

```json
{
  "version": 1,
  "userCertId": "<32-byte hex>",
  "derivationStates": [
    {
      "resourceId":        "<resource identifier>",
      "domainFlag":        "0x02",
      "currentIndex":      42,
      "algorithmVersion":  1
    }
  ],
  "domainCeilings": {
    "0x01": 7,
    "0x02": 42,
    "0x06": 3
  },
  "edgeBackupRecipes": [
    {
      "edgeId":      "<edge identifier>",
      "recipe":      "<BRC-69 key linkage revelation data>",
      "counterpart": "<counterpart cert_id>"
    }
  ],
  "tenantPathSteps": [
    {
      "tenantId":  "<tenant identifier>",
      "pathSteps": ["<step 1>", "<step 2>"]
    }
  ],
  "schemaMappings": [],
  "signature": "<BRC-100 signature hex>"
}
```

The domain ceilings are the per-domain monotonic-index maximums recorded at the time of export. During reconstruction, the client re-derives keys up to each ceiling and validates the results. Any attempt to use an index below the recorded ceiling is a replay, and the substrate rejects it. Monotonic guarantees — child indices, rotation indices, and state versions MUST only increase and MUST never be reused — are enforced throughout the substrate to prevent rollback attacks.

### Phase 4 — Client-side reconstruction

The client now has two things: the recovery payload (from phase 3) and the user's challenge answers (which the user supplies locally, never transmitting them). Phase 4 is entirely local. The network is not involved.

The reconstruction procedure:

1. Normalise the challenge answers exactly as in phase 2: lowercase, trim whitespace, collapse internal spaces.
2. Run PBKDF2 with SHA-256, a minimum of 100 000 iterations, the per-deployment salt, and the normalised answer concatenation as the password. The output is the 32-byte root seed.
3. Derive the root BRC-52 certificate from the root seed. Compute `SHA-256(canonical_preimage)` to obtain the `cert_id`. Compare against `userCertId` from the payload; if they do not match, the challenge answers are wrong, or the payload has been tampered with.
4. For each entry in `derivationStates`, re-derive the child key using the BRC-42 derivation path encoded in the `resourceId` and `domainFlag`. The domain flag namespace (§4.5 of the protocol specification) ensures mathematically isolated key universes per domain; keys derived in one governance domain are not mathematically related to keys in another.
5. For each entry in `edgeBackupRecipes`, apply the BRC-69 recipe to reconstruct the ECDH shared secret for that edge. The recipe is the mathematical inverse of the original edge-creation computation; it produces the shared secret deterministically from the root seed and the counterpart cert's public key, without either party ever revealing the secret.
6. Traverse the `tenantPathSteps` to re-register each tenant in the live structural DAG.
7. Apply `schemaMappings` to normalise any schema version differences between registration time and recovery time.

At the end of phase 4, the recovering device has a complete key universe identical to the original device's key universe at the time the recovery payload was last updated. The server has zero knowledge of the root seed or any derived key at any point in this process.

The Plexus Recovery Service does not learn that reconstruction was successful or unsuccessful. The client simply proceeds; if it derived the wrong root seed (wrong challenge answers), the subsequent identity operations will produce invalid signatures and be rejected by the Verifier Sidecar.

---

## Worked example — four phases end to end

The following example traces a complete recovery for a user whose node was wiped. The user's email is on record; they registered three challenge questions. The recovery payload was backed up at boot step 13 when the node first came online.

> **Context.** The user's cert_id is `a3f2...c7e1` (32-byte hex, abbreviated). Three edges are enrolled: one to a colleague, one to a service tenant, one to a backup guardian. Domain ceilings at backup time: SIGNING (0x02) at index 42, CHILD_CREATION (0x06) at index 3.

**Phase 1.** The user initiates recovery and supplies their email address. The server sends an OTP to `user@example.invalid`. The user supplies the OTP. The server issues a session token `sess_<nonce>` valid for 15 minutes.

**Phase 2.** The server returns three challenge questions. The user supplies:
- Question 1: "What is the name of your first pet?" → answer: `"biscuit"`
- Question 2: "What street did you grow up on?" → answer: `"baker street"`
- Question 3: "What was your childhood nickname?" → answer: `"skip"`

Normalised concatenation: `biscuit|baker street|skip`. The server hashes the normalised, salted concatenation, compares against the stored hash in constant time, and issues a recovery authorisation token `auth_<nonce>`.

**Phase 3.** The client presents `auth_<nonce>`. The server returns the recovery payload (abbreviated):

```json
{
  "version": 1,
  "userCertId": "a3f2...c7e1",
  "derivationStates": [
    { "resourceId": "root", "domainFlag": "0x02", "currentIndex": 42, "algorithmVersion": 1 },
    { "resourceId": "root", "domainFlag": "0x06", "currentIndex": 3,  "algorithmVersion": 1 }
  ],
  "domainCeilings": { "0x02": 42, "0x06": 3 },
  "edgeBackupRecipes": [
    { "edgeId": "edge-colleague",  "recipe": "<BRC-69 recipe 1>", "counterpart": "b7d1...a2f0" },
    { "edgeId": "edge-service",    "recipe": "<BRC-69 recipe 2>", "counterpart": "c9e3...b4d2" },
    { "edgeId": "edge-guardian",   "recipe": "<BRC-69 recipe 3>", "counterpart": "d5f7...e8c3" }
  ],
  "tenantPathSteps": [
    { "tenantId": "tenant-primary", "pathSteps": ["root", "primary"] }
  ],
  "schemaMappings": [],
  "signature": "<BRC-100 signature>"
}
```

**Phase 4.** Locally, the client:
1. Normalises the challenge answers to `biscuit|baker street|skip`.
2. Runs PBKDF2-SHA256 (100 000 iterations, deployment salt) → 32-byte root seed.
3. Derives the root BRC-52 certificate from the root seed → computes `cert_id`. Matches `a3f2...c7e1`. Derivation is confirmed correct.
4. Re-derives the SIGNING key at BRC-42 domain `0x02` up to index 42. Re-derives the CHILD_CREATION key at domain `0x06` up to index 3.
5. Applies BRC-69 recipe 1 to reconstruct the shared ECDH secret with `b7d1...a2f0` (the colleague). Applies recipes 2 and 3 likewise.
6. Registers the primary tenant via `["root", "primary"]`.

The recovering device now holds all keys identical to the original device at backup time. The server was never involved in the reconstruction and holds no record of whether it succeeded.

---

## Threshold recovery for high-security roots

The standard four-phase protocol is sufficient for ordinary operational roots. For high-security roots — roots associated with high-value on-chain capabilities, vault constructs, or multi-million-satoshi capability UTXOs — the substrate provides threshold recovery via Shamir Secret Sharing.

When an entity designates a root key or on-chain capability as high-security, the substrate applies Shamir Secret Sharing to the key material before enrolling it in the recovery substrate. The key is split into t-of-n shares; no single share is sufficient to reconstruct the key. The shares are distributed across multiple recovery parties or hardware tokens.

Recovery of a higher-security construct requires two gating steps that extend the standard four-phase flow:

1. The user must first complete the standard four-phase flow for their operational root. This proves they hold the challenge set and establishes session trust.
2. Recovery of the high-security construct then requires gathering the required quorum of shares (t of n) from the designated holders. Share holders are reached via their existing bilateral edges — the edge backup recipe mechanism means the communication channel is itself recoverable.

The mathematical reassembly of threshold shares is executed by the client's local device. Raw high-security private keys must not be reconstructed, exposed, or transmitted to the server-side infrastructure at any point. The substrate reconstructs the key locally, uses it for the specific operation, and discards it; it does not persist high-security key material in any durable store beyond what was in the original threshold-protected form.

This discipline applies the same zero-knowledge property to high-security roots that the standard recovery protocol applies to operational roots: the server never holds the assembled key, and an attacker with server access cannot force reconstruction.

### Threshold recovery and the challenge set

The challenge set gates the standard four-phase flow. For threshold recovery, the challenge set gates access to the first phase, and the quorum of shares gates access to the high-security construct. The two factors are independent: losing the challenge-set answers means the user cannot authenticate the first step; losing quorum means the user cannot reconstruct the high-security key even if the first step completes.

This separation is deliberate. It means that compromising the challenge-set answers does not by itself give an attacker access to high-security roots — they still need to compromise the quorum of share holders. The attack surface for the most sensitive constructs requires compromising both the user's knowledge factor (challenge set) and the distributed custody of share holders, an operationally much harder target.

---

## Multi-party group recovery

When multiple users share a governance domain — a corporate deployment where several users are authorised to sign on behalf of the entity — the recovery substrate must handle the case where the group's shared state must be reconstructed after a node loss.

The protocol does not store a central group key anywhere in the server-side architecture. Instead, the group's cryptographic foundation is the set of bilateral edges between the authorised users. Each bilateral edge has a BRC-69 backup recipe. Recovery of the group is recovery of the edges.

The procedure is:

1. The recovering party completes the standard four-phase recovery for their own operational root.
2. The recovering party re-derives the bilateral shared secret with each other member of the group using the BRC-69 recipes in their recovery payload.
3. If the recovering party is missing a bilateral shared secret — for example, because the counterpart's cert was rotated after the recovering party's last backup — the missing secret is communicated to the recovering party via one of their existing, already-reconstructed bilateral edges. The communication is encrypted to the recovering party's key using the existing edge, and the server never sees the content.

The group's cryptographic foundation is restorable without the system ever knowing the shared secrets. This is the edge-as-primary-recoverable-unit design that the protocol specification establishes in §4.6: the edge is the unit around which recovery semantics are built, not the group key.

For large groups — many-member governance domains where the full bilateral matrix becomes operationally unwieldy — the substrate permits hierarchical edge structures. A designated recovery coordinator holds edges to each member; members hold edges to the coordinator. Recovery via the coordinator requires only one bilateral secret per member rather than n*(n-1)/2 pairwise secrets. The trade-off is that the coordinator's node becomes a higher-value recovery target. The choice between flat bilateral matrix and hierarchical coordinator is an operator decision made at domain-creation time, recorded in the domain's governance policy.

---

## Brute-force mitigation summary

The recovery flow is designed to make offline and online attacks computationally expensive and operationally constrained. The mitigations are not independent — each addresses a different attack surface.

| Surface | Limit |
|---|---|
| Recovery initialisation | Maximum 10 attempts per hour |
| Challenge answers | 5 consecutive failures locks the account for 24 hours |
| PBKDF2 iterations | Minimum 100 000 (SHA-256) |
| Context enrollment | Rate limited to prevent enumeration |
| Edge creation | Rate limited to prevent enumeration |

The PBKDF2 work factor is the primary defence against offline attacks on a captured recovery payload. At 100 000 iterations of SHA-256, each guess takes approximately 300 ms on commodity hardware (the actual figure depends on the attacker's hardware and the deployment's chosen salt). A six-answer challenge set with four possible answers per question has 4 096 combinations at the low end; realistic challenge sets with free-text answers have combinatorial spaces many orders of magnitude larger.

The lock-out on consecutive failures is the primary defence against online guessing. Five attempts before lock-out is aggressive; the assumption is that a legitimate user will not fail five times in a row. Operators may configure a less aggressive threshold for deployments where the user population has lower challenge-answer recall fidelity, but the protocol specifies five as the default because it is the safe baseline.

Constant-time comparison is not a rate limit — it is a structural property that prevents timing-based enumeration of the correct answer by eliminating the time difference between a correct and incorrect comparison.

---

## Recovery payload lifecycle

The recovery payload is backed up at boot step 13. It is not a one-time export — it must be kept current as the user's derivation state evolves. Each time the user creates a new edge, rotates a key, adds a tenant, or increments a domain index, the recovery payload becomes stale with respect to that change. The substrate maintains a dirty flag per recovery session; when the flag is set, the adapters schedule a payload refresh.

The refresh is atomic from the server's perspective: the server accepts a new signed payload, validates the BRC-100 signature against the `userCertId`, checks that all domain ceilings are monotonically increasing relative to the previous payload, and atomically replaces the stored payload. Rollback is rejected: a payload with domain ceilings lower than the current stored ceilings is not accepted. This enforces the monotonic-guarantee property at the recovery layer, consistent with the substrate-wide prohibition on index reuse.

The payload's `signature` field contains the BRC-100 signature over the canonical preimage of all other fields. The Verifier Sidecar verifies this signature before the payload is processed at any recovery session. A payload with an invalid signature is rejected before phase 3 can complete — the server will not export a payload it cannot verify as authentic.

---

## The role of domain ceilings in replay prevention

Domain ceilings are the per-domain monotonic-index maximums recorded in the recovery payload at export time. Their purpose is replay prevention during reconstruction.

When a recovering device re-derives keys up to a given ceiling, it also validates that the ceiling is no lower than the highest index it has locally observed. If the payload presents a ceiling lower than the recovering device's local records — an unusual situation that could indicate a stale export or a targeted rollback attempt — the reconstruction MUST halt and surface the discrepancy to the operator.

In normal operation the flow is the reverse: the recovering device has no prior local state (its storage was wiped), so it accepts the ceiling from the payload as authoritative and derives up to that point. The ceiling prevents the recovering device from treating a key at a superseded index as valid: if the original device had already rotated the SIGNING key at domain `0x02` to index 42, the ceiling of 42 tells the recovering device that any key derived at index 41 or below is stale and must not be used for new operations. The monotonic-guarantee property, enforced throughout the substrate (K6, the hash-chain append-only invariant at the distributed layer), propagates through to the recovery substrate via domain ceilings.

## What recovery does not cover

The recovery substrate reconstructs the key universe. It does not reconstruct:

- Application-layer state (documents, task boards, calendar events, kanban cards) — that state lives in the VFS and is replicated via the mesh; it survives independently of device loss as long as at least one peer holds a copy.
- Metered Flow Protocol channel balances — open MFP channels are settled on-chain on close; the settlement transaction is the permanent record. Channels that were open at the moment of device loss must be resolved by the counterparty broadcasting the latest tick's settlement transaction.
- Capability token UTXOs that were consumed before the backup — a consumed LINEAR capability token is spent; recovery does not undo consumption, and nor should it. The capability was used; its use is the on-chain record.

These exclusions are consistent with the substrate's linearity semantics. The recovery substrate is the mechanism for recovering the signing authority — the ability to author new cells, issue new capability tokens, and participate in new edges. It recovers the key; what was done with the key before loss is history.

---

## Boot-sequence step 13 is now unlocked

Boot-sequence step 13 is: *Recovery payload backed up to Plexus Recovery Service.*

The step requires that the node has completed the standard four-phase registration flow (in the onboarding direction, not the recovery direction), that the recovery payload has been assembled and signed by the Plexus Recovery Service, and that the payload has been accepted and stored. The node's dirty flag is cleared; the node's recovery posture transitions from unrecovered to recoverable.

After step 13 completes, the node's identity is portable. The user can lose their device, recover on a new one, and resume with an identical key universe. No single point of failure holds the keys; the server holds routing metadata, the user holds challenge answers, and the combination is sufficient for reconstruction.

Step 14 — opening MFP cashlanes — proceeds from step 13 because metered services require a recoverable identity. A node that has not backed up its recovery payload is not a suitable counterparty for a payment channel: if the node loses its keys, the channel cannot be settled by the node's side. The recovery substrate is therefore a prerequisite for metered participation, not a post-hoc concern.

Chapter 22 covers the Metered Flow Protocol (MFP) and the eight-state channel FSM in full. Boot-sequence step 14 is unlocked there.
