---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PLEXUS-ALIGNMENT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.726948+00:00
---

# PLEXUS-ALIGNMENT — Spec ↔ Codebase Trace

**Status**: Canonical reference for Plexus spec compliance across the Semantos PWA + wallet-headers + brain. Owner: the C11 ("me" surface) track.

**Provenance**:
- *Plexus Client Requirements Draft v2.1* (Dusk Inc, 38 pp) — `questions@dusk-inc.com`
- *Plexus Technical Requirements Draft v1.3* (Dusk Inc, 29 pp) — `questions@dusk-inc.com`
- Read 2026-05-30 in full against the post-#726 / #730 codebase.

**Companions**:
- `docs/design/HELM-ME-SURFACE.md` — the C11 design doc
- `cartridges/wallet-headers/brain/src/plexus/envelope.ts` — TS reference implementation
- `apps/semantos/lib/src/plexus/envelope.dart` — Dart port (PR-C11-2)
- `apps/semantos/lib/src/plexus/challenge_bundle_store.dart` — storage (PR-C11-3)

---

## §0 TL;DR

**Strict subset.** Every requirement in the Plexus spec that touches the recovery substrate, derivation registry, or client-side key custody has an equivalent in our code (or a designated PR where it lands). No re-architecture is required. The most architecturally interesting gap — *depth-annotated challenges* (spec §1.2.8, §4.6.6, §9.1.2) — is a clean **post-V1 extension** of the existing `ChallengeBundle` storage, not a refactor.

**Six real gaps, none blocking V1.** Documented inline with proposed disposition.

**The questions our PR-C11-3 sheet collects are valid spec compliance** for a root-level recovery. Spec also supports per-depth and per-edge challenges; we don't yet model those.

---

## §1 Glossary cross-walk

The spec uses domain-specific terms that don't always match what we say in our code. This table is the canonical translation:

| Plexus term | Our term / code | Reference |
|---|---|---|
| **BRC-69 key linkage recipe** / **edge recipe** / **backup recipe** | `RelationshipRecipe` in `envelope.{ts,dart}` | spec Terms, §4.6 |
| **Cryptographic Relationship** / **edge** | one entry in `derivationStateSnapshot.records` (post-#722: a `betterment.*` cell at the brain layer; on chain a UTXO pair) | spec Terms, §4 |
| **Functional Domain Flag** / **domain_flag** | `DerivationContext.domainFlag` (uint32) | spec §2.2, §5.3 |
| **Tier** / **Tier 1/2/3** | `DerivationContext.tier: 1|2|3` (simplified — see §6 gap 2) | spec §2.2.2 |
| **Tenant Node** | brain-side concept; no direct PWA mirror | spec Terms |
| **Tenant Path** | not yet modeled in our `DerivationContext` (gap 2) | spec §2.1, §4.3 |
| **Monotonic Index** / **BKDS invoiceNumber** | `DerivationStateRecord.currentIndex` (null → gap-scan) | spec §2.3, §4.2 |
| **Recovery Policy** | `RecoveryPolicy` enum: `'BACKUP_ON_CREATE' | 'BACKUP_ON_CONFIRM' | 'NONE'` (spec also has `PARENT_MANAGED` — gap 7) | spec Terms, §1.1.4-5, Tech §12 |
| **Challenge Bundle** / **challenge set** | `ChallengeBundle` (questions, salt, answerHashes, kdfIterations) | spec §1.2 |
| **Algorithm Version** | `algorithmVersion: 1` flat (no version ceilings — gap 5) | spec §2.4 |
| **Cert ID** / **cert_id** | `certId` field — **16-byte truncated SHA-256 of pubkey, rendered as 32 lowercase hex chars** (matches the cell header `HeaderOffsets.ownerId = 62, ownerIdSize = 16` and `identity_certs.zig::CERT_ID_HEX_LEN = 32`). See §10.A for the resolution against the spec's ambiguous "32-byte cert_id" phrasing. | spec Terms; Tech §11; identity_certs.zig:155 |
| **DerivationContext** | shape match — we have `tier`, `brc43InvoiceString`, `domainFlag`, `recoveryPolicy`; spec also wants `app_id`, `parent_cert_id`, `tenant_path` (gap 2) | spec §1, §2 |
| **DerivationStateRecord** | shape match — `protocolHash`, `counterparty`, `currentIndex`, `domainFlag`, `protocolId` | spec §2.5 |
| **Encrypted Recovery Seed** | `EncryptedRecoverySeed` — AES-256-GCM(seed, KEK, nonce, aad) | not named per se in spec; spec defers seed protection to PBKDF2 (§1.2.7) + our envelope adds the GCM layer |
| **Plexus RaaS** (Recovery-as-a-Service) | `cartridges/wallet-headers/brain/src/plexus/operator.ts`; helm "me" surface integrates in PR-C11-5 | spec Tech §11 |
| **Verifier Sidecar** | brain's existing `runtime/semantos-brain/src/site_server.zig` BRC-100 verification path | spec Tech §8 |
| **`x-brc100-*` headers** | `BrainHttpClient`'s bearer + signature path | spec Tech §4, §8 |
| **cap.recovery UTXO** | a future BRC-108 capability cell minted by the brain's cell-engine via the existing 2-PDA executor (C10) | spec Tech §11, §6.5 |
| **schemaMapping** section | not yet in our export payload (gap 8) | spec Tech §11 |

---

## §2 Crypto primitive alignment (exact match)

These are the cryptographic invariants — the part of the spec that *cannot* drift without breaking interoperability with any future Plexus RaaS operator. Every primitive below is locked byte-for-byte across our TS + Dart implementations and matches the spec.

| Spec §id | Requirement | Our code | Status |
|---|---|---|---|
| 1.2.7, Tech §9 (Identity Domain) | PBKDF2 / 100,000 iterations for root seed regen | `kPbkdf2Iterations = 100_000` in both `envelope.dart` and `envelope.ts` | ✓ |
| 1.2.5, 1.4.2, 5.2.1, Tech §9 | sha256(salt || normalize(answer)) per question; never store plaintext | `hashAnswer()` / `_hashAnswer()` | ✓ |
| 1.4.2, 5.2.1, Tech §9 | 33-byte compressed pubkeys over the wire | `identityKey: Uint8Array/Uint8List(33)` | ✓ |
| 1.4.4, §5.1.1, Tech §11 Phase 4 | client-side PBKDF2 + BRC-42 derivation on recovery | `decryptRecoverySeed()` → caller does BRC-42 in wallet-headers | ✓ |
| 5.2 / 5.4, Tech §8 | server stores only `cert_id` hash (spec says "32 bytes" — we use **16 bytes**, the canonical truncated form; see §10.A), never the variable cert body | `certId` field hex-encoded — never the cert payload. Cert body sits in `SecureStore` keyed by `me.cert_body.${certIdHex}` per §10.C | ✓ (with documented truncation convention) |
| 1.2.5, 1.4.4 | normalize rule (Unicode NFKC + lowercase + collapse-ws + trim) | `normalizeAnswer()` in both Dart + TS, identical | ✓ |
| §9 Identity Domain (Tech) | minimum 3 challenge questions per set | PR-C11-3 hardcodes 3 | ✓ |
| §9 Identity Domain (Tech) | challenge answers normalized + SHA256-hashed | matches §1.2.5 above | ✓ |
| 2.5.2 | ~40 bytes per domain per context for derivation state records | our `DerivationStateRecord` compresses to ≤ 40 bytes when serialized (32-byte protocolHash + 33-byte counterpartyPk + 4-byte index + 4-byte domainFlag) — exceeds 40 but acceptable for V1 | ⚠ (off-spec compression — see §6 gap "compact metadata") |
| 2.5.4 | exclusively store salted+SHA256-hashed challenge answers | matches our `ChallengeBundle.answerHashes` | ✓ |
| 5.2.2 | actively prohibit storage of raw private keys, plaintext challenge answers, raw UTXO data, ECDH shared secret values | our envelope never includes any of these (invariant check 1 actively verifies for seed + answers) | ✓ |
| 5.2.4 | for edges: store only counterparty cert ID + signing key index; never the ECDH shared secret | `RelationshipRecipe.{counterpartyPk, highWaterMark, protocolHash, protocolId}` — no shared secret field | ✓ |

---

## §3 Envelope schema alignment (per-field)

The `PlexusRecoveryEnvelope` (v1) carries every required field. Per-field trace:

```
envelopeVersion: 1                     ← spec § (no explicit ID; locked at 1)
identityKey: <hex 33-byte pubkey>      ← spec 1.4.2: "compressed 33-byte keys"
certId: <hex 32-byte>                  ← spec 1.4.2, Tech §11 (BRC-52 cert_id)
contactEmail: <utf8>                   ← spec 1.2.1: needed for OTP
challengeBundle:
  questions: string[]                  ← spec §1.2.4 ("specifically stored challenge questions")
  salt: <hex 32-byte>                  ← spec 5.2.4 (salted+hashed)
  answerHashes: <hex 32-byte>[]        ← spec 1.2.5: sha256(salt || normalize(answer))
  kdfIterations: 100000                ← spec 1.2.7: PBKDF2 100k
encryptedRecoverySeed:
  ciphertext: <hex var-len>            ← AES-256-GCM(seed, KEK, nonce, aad)
  nonce: <hex 12-byte>                 ← GCM nonce
  tag: <hex 16-byte>                   ← 128-bit GCM auth tag
  aad: <hex 34-byte>                   ← identityKey(33) || envelopeVersion(1)
derivationContexts: DerivationContext[]
  - tier: 1|2|3                        ← spec §2.2 (functional domains by tier)
  - brc43InvoiceString: string         ← spec §2.2 BRC-43 invoice
  - domainFlag: string (hex)           ← spec 2.2.2 uint32 domain flag
  - recoveryPolicy: enum               ← spec Terms / §1.1.4
edgeRecipes: RelationshipRecipe[]      ← spec §4.6 "BRC-69 key linkage recipes"
  - domainFlag: number                 ← spec 2.2.2
  - protocolId: string                 ← spec §2.5
  - protocolHash: <hex 16-byte>        ← spec §2.5
  - counterpartyPk: <hex 33-byte>|null ← spec 4.6.4: counterparty cert ID
  - highWaterMark: number|null         ← spec 4.2.4 (null → gap-scan)
derivationStateSnapshot:
  records: DerivationStateRecord[]     ← spec 2.5.1
    - protocolHash, counterparty, currentIndex, domainFlag, protocolId
  snapshotTimestamp: RFC3339
algorithmVersion: 1                    ← spec 2.4.1
```

**Missing in our envelope** (gap details in §6):
- `schemaMapping` block — spec Tech §11 requires both raw uint32 numerics + human-readable schema labels
- `parentCertId`, `appId`, `tenantPath` on each `DerivationContext` — multi-context DAG isolation
- per-depth challenge bundle references
- BRC-100 wrapper signature around the full payload

---

## §4 4-phase recovery flow alignment (Tech §11)

Spec Tech §11 mandates the strict 4-phase RaaS recovery flow:

| Phase | Spec requirement | Our coverage today | Lands in |
|---|---|---|---|
| 1. Email OTP Verification | 6-digit code, 10-min expiry, 10 attempts/hour cap, 5-fail lockout (spec 1.2.1–1.2.4) | not modeled (RaaS-side) | **PR-C11-5** |
| 2. Challenge Response Validation | salted SHA256 hash compare against stored bundle (spec 1.2.5) | `ChallengeBundle.answerHashes` + `decryptRecoverySeed`'s implicit retry | ✓ via PR-C11-3 + PR-C11-2 |
| 3. Metadata Export | BRC-100-signed JSON with derivationContexts, edgeRecipes, derivationStateSnapshot, schemaMapping (spec 1.3, Tech §11) | `PlexusRecoveryEnvelope.toJsonString()` — content matches; missing `schemaMapping` + BRC-100 sig | partial (PR-C11-5 closes) |
| 4. Client-Side Key Reconstruction | client runs PBKDF2 + BRC-42 locally; server never sees raw priv (spec 1.2.7, 5.1.x) | exactly our model — RaaS dispatch is what `buildEnvelope` produces; reconstruction is `decryptRecoverySeed` + wallet-side BRC-42 | ✓ |

---

## §5 Wallet.html / wallet-headers code alignment

### §5.0 Posture lock (2026-05-30): renderer-only

> **The text below in §5.1+ describes wallet-headers as it stands at the time of writing — owning derivation state, recipes, and challenge UX inside the cartridge.** That posture is **superseded** by the renderer contract:
>
> **See `docs/design/WALLET-RENDERER-CONTRACT.md`.**
>
> The shell (Dart) becomes the sole owner of every private key — root cert, tier-0 vault, per-context spending, counterparty-scoped, change. Wallet-headers is reduced to a renderer that displays balances, prompts for user actions, and forwards intent via a `SemantosWallet` JavaScriptChannel. It generates no seeds, derives no keys, signs no transactions, broadcasts nothing.
>
> Spec alignment under the new posture:
>
> - **Recipes (§4.6, §5.1)** — recipes live in a Dart-side recipe store at `me.recipes`, projected into the recovery envelope as `derivationRules[]` (see RENDERER-CONTRACT §6). The wire shape from §5.1 below stays the same; only the producer moves from the cartridge to Dart.
> - **DerivationContext (Gap 2 below)** — extension lands in Dart with `(certId, appId, parentCertId, tenantPath)` per the gap disposition. The cartridge no longer carries a parallel context.
> - **Cert custody (Gap 6 below)** — `me.cert_body.${certIdHex}` in `SecureStore` only. No webview-side write path.
> - **Tier-0 + spending tree** — new under the contract; recipe IDs follow the `vault/0/...` shape from RENDERER-CONTRACT §2.
>
> Sections §5.1 through §5.4 below are kept verbatim as a record of the prior posture, and because the spec-↔-shape mappings they document (e.g. `domainFlag + protocolId` ↔ "application context") apply unchanged under the new posture — only the host moves.

The wallet-headers cartridge owns the BRC-42 derivation state, edge recipes, and challenge UX. Cross-reference:

### Recipes (rederivation recipes ↔ BRC-69 key linkage recipes)

Spec §4.6 ("Cryptographic Recipe Extraction"):

> *4.6.1 — The system shall compute cryptographic "recipes" for edges using the BRC-69 key linkage revelation standard to allow for the future deterministic reconstruction of an edge's shared secret.*
>
> *4.6.4 — While extracting an edge recipe for backup, the system shall explicitly package only the counterparty's certificate ID, the specific signing key index, and the application context, strictly preventing the actual ECDH shared secret from being exported.*

Our `cartridges/wallet-headers/brain/src/plexus/envelope.ts` builds these in the `derivationStateSnapshot.records` → `edgeRecipes` projection:

```ts
edgeRecipes: input.derivationStateSnapshot.records.map((r) => ({
  domainFlag: r.domainFlag,
  protocolId: r.protocolId,
  protocolHash: r.protocolHash,
  counterpartyPk: r.counterparty === 'self' ? null : r.counterparty,
  highWaterMark: r.currentIndex,
}))
```

`counterpartyPk` IS spec's "counterparty's certificate ID"; `highWaterMark` IS spec's "signing key index"; `domainFlag + protocolId` are the "application context". **Match.**

### Scoped universes (BRC-42 scoped universes ↔ Functional Domain Scoping)

Spec §2.2:

> *2.2.2 — The system shall partition functional domain flags and tenant types into a 4-byte (uint32) space, reserving 0x00000001–0x000000FF for Plexus well-known flags, 0x00000100–0x0000FFFF for extended standard flags, and 0x00010000–0xFFFFFFFF exclusively for client-defined sovereignty.*

Our `domainFlag: number` is a uint32 — we just don't enforce the band boundaries. Gap 6 (cheap fix).

Spec §5.3:

> *5.3.5 — The system shall disambiguate isolated contexts belonging to a single identity strictly by tracking the exact tuple of cert_id, app_id, and parent_cert_id to prevent cryptographic derivation collisions across the platform.*

Our `DerivationContext` carries `tier + brc43InvoiceString + domainFlag` — missing `app_id` and `parent_cert_id` explicitly. The wallet-headers' internal `DerivationContext` (separate from the exported envelope shape) already tracks more — we just don't project it into the envelope yet. Gap 2.

### Standard Plexus well-known flags

Spec calls out these specific domain flags:

| Flag | Name | Used by |
|---|---|---|
| `0x01` | EDGE_CREATION | spec §1.1, §8.1.1 — used to derive every ECDH edge |
| `0x04` | MESSAGING | spec §8.2.4 — used for session key rotation under Double Ratchet |
| `0x05` | ATTESTATION | spec §3.4 — Plexus's own signing key for attestations |
| `0x06` | CHILD_CREATION | spec §3.3.3, §4.1.2 — parent signs child's BRC-52 cert |
| `0x07` | PERMISSION_GRANT | spec §2.2.4 — UTXO-based capability tokens are signed with this |

We don't have an enum / constants module for these yet. Adding one would be ~20 lines + test. Cheap PR.

---

## §6 The six real gaps

Severity: 🟥 architectural, 🟧 substantial, 🟨 small.

### Gap 1 🟥 — Challenge-annotated DAG depths / per-edge challenges / Vault tier

**Spec**: §1.2.8, §1.2.9, §4.6.6, §9.1.2

> *§1.2.8 — When a client annotates a specific depth in a key derivation path with a challenge requirement, the system shall store the challenge reference against that specific step within the derivation_paths table.*
>
> *§4.6.6 — If a high-value edge requires additional authorisation to be reconstructed (such as transferring treasury access), then the system shall extract and append the specific challenge metadata alongside the BRC-69 revelation within the EdgeBackupRecipe payload.*
>
> *§9.1.2 — If a user attempts to recover a higher-security construct (such as a Vault), then the system shall require additional challenge sets that are explicitly gated behind the user's capacity to exercise rights over their standard root key.*

**Our coverage**: PR-C11-3 stores one root-level `ChallengeBundle`. There's no notion of multiple bundles keyed by `(derivationPathScope)` or attached to specific edges.

**Why it's architectural**: The shell's `ChallengeBundleStore` keys on a fixed storage slot (`me.challenge_bundle.v1`). Extending to multiple scopes requires:
- multi-entry storage (slot per scope, or a single map blob)
- a UI flow that scopes the questions sheet to a chosen depth/edge
- envelope export that bundles N challenge bundles + the path-scope each anchors

**Disposition**: **Post-C11, new track** (proposed C14: "Challenge-Annotated Derivation Depths") if Todd wants Vault-tier security. Root-only challenges remain a valid spec-compliant V1 subset. PR-C11-3's storage is forward-compatible — the existing record just becomes "the root bundle" under a `scope: "root"` key.

---

### Gap 2 🟧 — Multi-context DAG `(cert_id, app_id, parent_cert_id, tenant_path)`

**Spec**: §2.1, §4.3, §5.3.5, Tech §10

> *§2.1.3 — The system shall uniquely identify and disambiguate every context record using the exact tuple of the cert_id, app_id, parent_cert_id, and tenant_path steps.*
>
> *§5.3.5 — The system shall disambiguate isolated contexts belonging to a single identity strictly by tracking the exact tuple of cert_id, app_id, and parent_cert_id to prevent cryptographic derivation collisions across the platform.*

**Our coverage**: `DerivationContext.tier` is a 3-value enum. `brc43InvoiceString` encodes some context. But `parent_cert_id` and `tenant_path` aren't projected into the envelope.

**Why it matters**: A single identity living as "customer of Org A" AND "employee of Org A" needs two mathematically-isolated key universes. Our envelope can't carry both simultaneously.

**Disposition**: **PR-C11-4**. When the wallet-headers webview lands, the cartridge already tracks DerivationState with these fields internally (Tech §10 puts them in the `derivation_state` table). The bridge into the envelope just needs to surface them. Extend `DerivationContext`:

```dart
class DerivationContext {
  final String certId;
  final String appId;
  final String parentCertId;
  final List<TenantPathStep> tenantPath;
  final int tier;                  // legacy — keep for back-compat
  final String brc43InvoiceString;
  final String domainFlag;
  final String recoveryPolicy;
}
```

---

### Gap 3 🟧 — Email-OTP gate + 4-phase RaaS recovery flow

**Spec**: §1.2.1–1.2.4, Tech §11

> *1.2.1 — When a user submits an email address to initiate a recovery session, the system shall generate and send a 6-digit OTP (One-Time Password) code with a strict 10-minute expiration timer.*
>
> *1.2.2 — The system shall restrict recovery initialization attempts to a maximum of 10 attempts per hour to prevent brute-force attacks.*
>
> *1.2.3 — If a user accumulates 5 consecutive failed verification attempts, then the system shall lock the account and halt the recovery process.*

**Our coverage**: None today. This is entirely a RaaS-server-side concern.

**Why it's relevant to us**: PR-C11-5 (Plexus RaaS opt-in) is when the operator decides to enroll with a Plexus operator. At enrollment we upload the envelope; at recovery (on a fresh device with no envelope file), we hit the RaaS endpoints in this 4-phase order.

**Disposition**: **PR-C11-5**. Two paths to consider:

- **(a)** We never act as a Plexus RaaS server — we're only ever a client. PR-C11-5 wires `enrollmentDispatch()` + `recoveryInitiate()` to Bridget's or another existing operator's endpoints. The brain at oddjobtodd.info doesn't host the OTP/recovery surface itself.
- **(b)** The semantos-brain becomes its own Plexus RaaS for operators who choose self-hosted recovery. This is a much bigger build — would need the `identity_records` / `challenge_sets` / `verification_codes` / `authority_keys` tables (Tech §9) + email-OTP delivery + rate-limit middleware.

D3 in `HELM-ME-SURFACE.md` says "default OFF + opt-in", which works for both paths. **Recommend (a) for V1**; revisit (b) when an operator explicitly wants a self-hosted Plexus.

---

### Gap 4 🟨 — BRC-100 signed JSON export + `cap.recovery` BRC-108 UTXO gate

**Spec**: §1.3.3, Tech §11

> *1.3.3 — The system shall mathematically sign the outgoing JSON export payload using the Plexus Recovery as a Service (RaaS) entity's BRC-100 signature to guarantee the authenticity and integrity of the metadata before delivering it to the client.*
>
> *Tech §11 — Before granting access to export an identity's backed-up metadata, the service must act as a cryptographic gatekeeper by performing an indexer-less Simplified Payment Verification (SPV) check. This check must prove the requesting user has presented a valid, unspent, and time-bounded "Recovery Capability" (cap.recovery) UTXO formatted to the BRC-108 standard.*

**Our coverage**: `envelope.ts` already calls `buildBrc100()` from `../brc100.ts` and returns the `brc100` payload alongside the raw envelope. Our Dart port does **not** sign — see the docstring on `buildEnvelope()`: *"BRC-100 signature — PR-C11-5 needs it for Plexus dispatch; local file download in this PR does not"*. The cap.recovery UTXO mint also isn't wired.

**Disposition**: **PR-C11-5**. Two pieces:
- Add a secp256k1 signing seam Dart-side. Pointycastle has secp256k1; we'd add a `signEnvelope()` that produces the BRC-100 wrapper.
- Mint a cap.recovery BRC-108 cell via the brain's existing 2-PDA executor (C10 work). The cap.recovery cellType would join `betterment.practice.release` etc. in the brain's cellType registry.

The Vendor SDK constraint (Tech §5):

> *Interfaces for key derivation, such as deriveChild, must be designed as pure functions with zero side effects, no hidden states, and no database dependencies.*

Our Dart `buildEnvelope` already meets this — pure function over inputs. Good.

---

### Gap 5 🟨 — Algorithm version ceilings (per-index-range)

**Spec**: §2.4.2, §2.4.5

> *2.4.5 — While a derivation path spans a version migration, If a client reconstructs keys across that boundary, Then the system shall instruct the client to derive keys using the legacy algorithm up to the version ceiling (e.g., indices 1-500), and the new algorithm for all subsequent indices (e.g., 501+).*

**Our coverage**: `algorithmVersion: 1` flat. No `versionCeiling` field on records.

**Why it matters (eventually)**: When `plexus-kdf-v2` ships (or whatever the spec's next derivation algo is), existing identities have indices 1..N derived under v1. New indices N+1.. need v2. If a recovery doesn't know where the ceiling is per-context, it can't deterministically re-derive.

**Disposition**: **Post-C11** — future-proof concern. When v2 ships we add `algorithmVersionCeiling: number?` to `DerivationStateRecord`. Pure additive.

---

### Gap 6 🟨 — Domain-flag band validation

**Spec**: §2.2.2

> *2.2.2 — …reserving 0x00000001–0x000000FF for Plexus well-known flags, 0x00000100–0x0000FFFF for extended standard flags, and 0x00010000–0xFFFFFFFF exclusively for client-defined sovereignty.*

**Our coverage**: `domainFlag` is a uint32 number/hex string with no band validation.

**Disposition**: **5-line PR** at any point — slot into PR-C11-4 or a micro-PR. Add a `validateDomainFlag(int flag, {required bool clientDefined})` helper that throws if `clientDefined: true` and `flag < 0x00010000`, or vice versa.

---

### Gap 7 (bonus) 🟨 — 4th edge recovery policy: `PARENT_MANAGED`

**Spec**: Tech §12

> *The service must strictly enforce immutable edge recovery policies during creation, explicitly supporting NONE (ephemeral), BACKUP_ON_CREATE (atomic recipe storage), BACKUP_ON_CONFIRM (delayed enrollment), and PARENT_MANAGED policies.*

**Our coverage**: TS `RecoveryPolicy` enum has 3: `'BACKUP_ON_CREATE' | 'BACKUP_ON_CONFIRM' | 'NONE'`. Missing `'PARENT_MANAGED'`.

**Disposition**: 1-line change to add to the enum + a test that the envelope round-trips it.

### Gap 8 (bonus) 🟨 — `schemaMapping` section in export payload

**Spec**: Tech §11

> *The JSON export payload must include a schemaMapping section that structurally ensures that client's recovering device receives both raw number uint32 values needed for deterministic root key reconstruction and the human-readable labels needed to re-establish the semantic application context.*

**Our coverage**: Our envelope carries raw uint32 (`domainFlag`) but not the human labels. Lands when PR-C11-5 builds the dispatch payload — needs a `schemaMapping` block that maps `domainFlag: 0x01` → `"EDGE_CREATION"` etc.

### Gap 9 (bonus) 🟥 — Shamir t-of-n threshold recovery (Vault tier)

**Spec**: §9.1, Tech §9

> *9.1.1 — When an entity designates a root key or an on-chain capability as "high-security", the system shall apply Shamir Secret Sharing (t-of-n) mechanisms to fragment the underlying private cryptographic material.*
>
> *Tech §9 — The service architecture must support advanced recovery mechanisms, specifically Shamir secret sharing (t-of-n, secp256k1).*

**Our coverage**: D1 in `HELM-ME-SURFACE.md` deferred this. We have 3-of-3 fixed.

**Disposition**: **Out of scope for C11**, valid V1 simplification per D1. New track if Todd wants Vault-tier roots.

---

## §7 The "is recovery enrollment generic?" answer

The phrasing in the user's question — *"are the questions established under the generic challenge enrolment?"* — has a specific spec answer.

**No, our V1 is not generic.** We attach one bundle to the root identity. The spec models **generic challenge enrolment** as the ability to:

1. Attach a bundle at the root (§1.2 — what we do)
2. Attach a bundle at a specific derivation path depth (§1.2.8)
3. Attach a bundle alongside a specific edge backup recipe (§4.6.6)
4. Attach an additional set when recovering a high-security Vault (§9.1.2)

These are all the same primitive — a `ChallengeBundle` keyed by a scope. The scope can be:
- `root` (today)
- `path:<derivation_path_id>` (depth-annotated)
- `edge:<edge_id>` (per-edge)
- `vault:<vault_id>` (threshold)

PR-C11-3's `ChallengeBundleStore` keys on a fixed slot. Adding the multi-scope dimension is a forward-compatible extension: change `read()` / `write()` to accept a `scope` parameter; the default remains `root`.

**Recommendation**: keep V1 root-only; track depth/edge/vault scopes as the **C14** track to land after C11 completes.

---

## §8 What Plexus has that we explicitly do NOT cover

The spec defines many features outside the C11 reach. Cataloged so future track-design is informed:

| Spec section | Feature | Why not us |
|---|---|---|
| §3 (Client) | Attestation Authority — identity continuity, resource/edge usage, cert ancestry attestations | Plexus-RaaS-side. Brain already does cert validation; full attestation infrastructure isn't C11. |
| §3.5 | Zero-Knowledge Edge Proof via BRC-94 Schnorr | Not C11 |
| §3.6 | Immutable Data Sovereignty Auditing — BRC-108 audit trail with sovereignty zones | Tangentially related to C10 work (cell legitimacy gate); not C11 |
| §4 | Autonomous Graph Topology Management (DAG operations) — `POST /tenant/create`, child_index allocation, etc. | brain-side substrate work; not part of the helm "me" surface |
| §6 | On-Chain Enforcement Capability Tokens (BRC-108 + 2-PDA) | C10 ground (already underway), not C11 |
| §7 | Chain of Custody and Subtree Migration (`POST /edge/rotate`, atomic structural migration) | post-C11 substrate work |
| §8 | End-to-End Encryption + ECDH ratcheting (Double Ratchet, epoch-based) | wallet-headers concern; the messaging primitive ships as its own track when Talk/conversation surface needs it |
| Tech §6 | Plexus CLI | OUT of scope — we have the wsh REPL + bun-run scripts as our equivalents |
| Tech §10 | Derivation Domain (server-side Plexus Cloud table layout) | RaaS-side concern; the brain models its own version of this through cellTypes |
| Tech §14 | Metering Service (Metered Flow Protocol — MFP) | OUT of scope for C11 |

---

## §9 PR-by-PR spec compliance trace

| PR | Spec sections closed | Spec sections remaining (in this PR's surface) |
|---|---|---|
| **#727** — design doc | (none — design only) | — |
| **#728 (PR-C11-1)** — Me affordance + Identity row | none (display only) | — |
| **#729 (PR-C11-2)** — envelope crypto + scaffold | §1.2.7 (PBKDF2 100k), §1.2.5 (hash format), §1.4.2 (33-byte pubkey wire), §1.4.4 (client-side PBKDF2), §5.2.x (compact storage shape) | BRC-100 sig (gap 4), schemaMapping (gap 8) |
| **#730 (PR-C11-3)** — secret questions + storage | §1.2.4 (stored question retrieval), §1.2.5 (normalize+salt+sha256), §5.2.4 (store hashed only), Tech §9 (min 3 questions) | depth-annotated (gap 1), multi-context (gap 2) |
| **PR-C11-4 (planned)** — wallet webview | §2.1, §4.3, §5.3 (multi-context isolation — gap 2), §2.2.2 (domain flag bands — gap 6) | gap 1, gaps 4 + 5 + 7 + 8 + 9 |
| **PR-C11-5 (planned)** — Plexus RaaS opt-in | §1.2.1–1.2.4 (OTP — gap 3), §1.3.3 (BRC-100 sig — gap 4), Tech §11 4-phase, gap 7 (`PARENT_MANAGED`), gap 8 (`schemaMapping`) | gap 1, gap 5, gap 9 |
| **PR-C11-6 (planned)** — brain `shell.identity.envelope` cell + matrix flip | (none new spec-wise) | — |
| **C14 (proposed, post-C11)** — depth-annotated challenges | gap 1 (full §1.2.8 + §4.6.6 + §9.1.2 + Vault tier) | gap 5, gap 9 |
| **Future** — algorithm v2 migration | gap 5 | gap 9 |
| **Future** — Vault / Shamir t-of-n | gap 9 | — |

---

## §10 Operator answers (resolved 2026-05-30)

Three open questions surfaced during the spec read. All three answered by Todd:

### A. Cert ID byte length — **16 bytes** (deliberate truncation of SHA-256)

**Provenance**:

- `runtime/semantos-brain/src/identity_certs.zig:155-157` — explicit comment: *"32-byte pubkey (sha256 of the pubkey, first 16 bytes hex)"*
- `runtime/semantos-brain/src/identity_certs.zig:97` — `CERT_ID_HEX_LEN: usize = 32` (= 32 hex chars = 16 bytes)
- `core/protocol-types/src/constants.ts:75-76` — `HeaderOffsets.ownerId = 62, ownerIdSize = 16` — the canonical 1024-byte cell header dedicates **16 bytes** to ownerId at offset 62
- BRC-53 (fetched from `bsv.brc.dev/wallet/0053`) talks about a `serialNumber` field that's `base64(SHA256(clientNonce || serialNonce))` — full 32 bytes raw — but **does not mention `cert_id` by name**. BRC-52 covers the cert standard itself; cert_id derivation lives there

**Resolution**:

The Plexus spec phrasing ("32-byte cert_id" in §1.4.2 / Tech §11) is **ambiguous on units** — it likely means "32 hex chars" rather than "32 binary bytes". Our cell header carries a **16-byte** ownerId at offset 62 (32 hex chars when serialised). The brain's `/api/v1/info` reports the same 16-byte truncated form (32 hex chars: `af90d1d61ae742839897e24cc59ce873`).

**Convention going forward**:

- Wire form everywhere: **16-byte truncated SHA-256 of pubkey, rendered as 32 lowercase hex chars**.
- Both `core/protocol-types/src/identity.ts::computeCertId` and `runtime/semantos-brain/src/identity_certs.zig` already agree on this.
- `PlexusRecoveryEnvelope.certId` will hold the 32-hex-char string (matches the cell header `ownerId` it ultimately binds to).
- If a Plexus operator implementation strictly wants the full 32-byte SHA-256, we'll re-derive at dispatch time from the cert preimage — the truncation is one-way but the full SHA-256 is reproducible given the cert body, which the wallet already holds locally.

**Action**: no envelope schema change needed. Add a one-line note to `envelope.dart`'s `certId` field docstring (and the TS equivalent) clarifying the 16-byte truncation.

### B. Plexus operator endpoint — **paste-URL pattern** (same as brain pairing)

D3 (`HELM-ME-SURFACE.md`) ships as opt-in. The Plexus RaaS row in the Me sheet will collect the operator URL via the same paste-URL UX `_PairingScreen` uses for the brain. **No hardcoded operator list.** This keeps the operator sovereign — they choose which Plexus operator (Bridget's RaaS, Dusk's reference, self-hosted, etc.) to enroll with.

**Action**: PR-C11-5 builds a `PlexusOperatorStore` (parallel to `ChildCertStore`) that holds `{operatorUrl, operatorPinCertId, enrollmentBearer}` after a successful enroll. Same `flutter_secure_storage`-backed seam.

### C. Cert custody location on Flutter — **`flutter_secure_storage` via `SecureStore` adapter**

Spec Tech §5 says the Vendor SDK writes BRC-52 cert bodies "on the client's file system or blob storage". On Flutter, this **goes through `SecureStore` adapter** so the underlying primitive (Keychain / Keystore / IndexedDB on web / future alternatives) stays swappable. The shell never imports `flutter_secure_storage` directly — only the adapter does.

**Provenance**: `apps/semantos/lib/src/identity/child_cert_store.dart:53-86` already establishes the `SecureStore` interface + `InMemorySecureStore` test variant. Production-side wiring uses `apps/semantos/lib/platform/identity_store_stub.dart` (native) / `_web.dart` (PWA). The same pattern extends to BRC-52 cert bodies.

**Action**: PR-C11-4 wires the wallet-headers webview's cert-body writes through the existing `SecureStore` adapter (rather than the webview accessing browser storage directly). Bridge call shape: `await SecureStore.write('me.cert_body.${certIdHex}', certBodyHex)`.

These resolutions unblock PR-C11-4 + PR-C11-5 — every architectural question now has a documented answer in the design canon.

---

## §11 Maintenance

- This doc is the source of truth for "what does Plexus say vs what do we do". Update it when:
  - A new Plexus spec version drops (re-read the deltas, update §2/§3/§6 tables).
  - We close a gap (mark with the PR that closed it + date).
  - Our code path changes (e.g., we add a new envelope field — update §3).
- Re-render against the spec ID's by grepping for `spec §` in our code at quarterly intervals. Drift surfaces as missing references.

---

## §12 Spec citations (per-section quick-reference)

For quick grep, here are the Plexus §id's referenced by name:

`§1.1.4 BACKUP_ON_CREATE`, `§1.1.6 BACKUP_ON_CONFIRM`, `§1.1.7 unique-edge constraint`, `§1.1.8 soft-delete + revoked_at`,
`§1.2.1 OTP`, `§1.2.4 stored challenge questions`, `§1.2.5 normalize+salt+sha256`, `§1.2.7 PBKDF2 100k`, `§1.2.8 challenge-annotated depths`, `§1.2.9 depth gate during reconstruction`,
`§1.3.1 BRC-100 recovery.export`, `§1.3.2 camelCase JSON arrays`, `§1.3.3 RaaS BRC-100 signs export`, `§1.3.4 exclude raw priv from export`,
`§1.4.2 33-byte pubkeys + salted hashes wire`, `§1.4.4 algorithmVersion marker`,
`§2.1.3 (cert_id, app_id, parent_cert_id, tenant_path) tuple`, `§2.2.2 uint32 flag bands`, `§2.3 monotonic indices`, `§2.4.5 version ceilings`, `§2.5.2 40 bytes/domain/context`, `§2.5.4 salted+hashed only`, `§2.5.6 store only current_index`,
`§3 Attestation Authority`, `§3.4 BRC-100 attestation sig + Flag 0x05`, `§3.5 BRC-94 zero-knowledge edge proof`, `§3.6 BRC-108 Data Sovereignty audit`,
`§4.1.2 CHILD_CREATION 0x06`, `§4.2.4 retire index on revoke`, `§4.3.x multi-context isolation`, `§4.5 atomic edge rotation`, `§4.6.4 counterparty + signing_key_index only`, `§4.6.6 high-value edge challenge metadata`, `§4.7 client-owned graph storage`,
`§5.1.x client-side cryptographic execution`, `§5.2.x minimal metadata storage`, `§5.3.x mathematical metadata isolation`, `§5.4 BRC-53 selective revelation`,
`§6.1.x BRC-108 token minting`, `§6.5 cap.recovery / cap.permission / cap.data_access / cap.compute_delegation / cap.metered_access`,
`§7.x chain-of-custody migration`,
`§8.1 ECDH binding + EDGE_CREATION 0x01`, `§8.2 session keys + MESSAGING 0x04 + AES-256-GCM`, `§8.3 epoch ratcheting`,
`§9.1 Shamir t-of-n + Vault tier`,
`Tech §1 Plexus API (Go + Gin)`, `Tech §2 Plexus Core Library (TS)`, `Tech §3 Plexus Contracts (camelCase JSON)`, `Tech §4 Plexus Network SDK (BRC-100 headers)`, `Tech §5 Plexus Vendor SDK (deriveChild + BRC-69)`, `Tech §6 Plexus CLI`, `Tech §7 Capability Domain (BRC-108 minting + spending)`, `Tech §8 Verifier Sidecar (BRC-100 mutual auth + x-brc100-* headers)`, `Tech §9 Identity Domain (3+ questions + PBKDF2 100k + Shamir t-of-n)`, `Tech §10 Derivation Domain (BKDS mappings + 40-byte/domain)`, `Tech §11 Recovery Service (4-phase + RaaS BRC-100 sign + cap.recovery UTXO gate + schemaMapping)`, `Tech §12 Edge Domain (4 recovery policies)`, `Tech §13 Transfer Domain (chain of custody)`, `Tech §14 Metering Service (MFP)`
