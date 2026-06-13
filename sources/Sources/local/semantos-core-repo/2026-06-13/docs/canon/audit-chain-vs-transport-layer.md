---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/audit-chain-vs-transport-layer.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.624366+00:00
---

# Audit chain vs transport layer

**Status**: canonical layering distinction for semantos record-keeping vs
cell flow.
**Companion matrix**: [`docs/canon/cw-lift-matrix.yml`](cw-lift-matrix.yml) — L12.
**Origin**: lifted from prof-faustus/verifiable-accounting-chain (Craig
Wright), patent refs US12375287B2 + EP3259724B1. Authored 2026-06-04.

---

## The layering rule

Two different concerns, two different layers. Don't conflate.

| Layer                | Concern                              | Primitive                  | Direction      |
|---|---|---|---|
| **Transport**        | How cells flow between peers         | paid pubsub (multicast)    | one→many       |
| **Record-keeping**   | How events are tamper-evidently recorded | append-only audit chain | linear (by `seq`) |

`cell_routing_paid_pubsub_not_risk` memory governs the transport layer.
This canon doc governs the record-keeping layer. They complement each
other; they don't compete.

A cell may BE TRANSPORTED via paid pubsub AND ALSO BE RECORDED on an
audit chain. The transport mechanism decides who receives the cell.
The audit-chain mechanism decides whether anyone can later prove what
the sequence of cells was.

---

## When you want an audit chain

The L12 audit-chain primitive (`@semantos/anchor-attestation/audit-chain`)
is the right tool when you need:

- a **monotonic, gap-free sequence** of facts per entity (a cartridge,
  a hat, an anchor batch, …),
- with **prev-hash chaining** so any tamper invalidates all subsequent
  entries,
- **deterministically signed** by a per-link key derived from an entity
  master via L11 (so verifiers only need the master pub, not a key per
  link),
- where **integrity is recomputable** end-to-end from canonical bytes
  + the chain itself.

Concrete cases:

1. **Mint-audit chain per cartridge.** Every minted cell gets one chain
   entry; the chain is "this is what this cartridge minted, in order."
   Operator can prove (and counterparties can verify) that no minted
   cells went missing from the record.
2. **Hat lifecycle.** Admit / promote / revoke events recorded against
   the hat's master key. Anyone holding the hat master pub can walk the
   chain to verify the hat's authority history.
3. **Anchor-history chain.** Each L5 batch-anchor result becomes one
   audit-chain entry. A single root pub + the chain lets any verifier
   walk the entire anchor history from one place.
4. **L9 envelope delivery under a shared chain segment.** When two
   parties want to bilaterally derive per-link envelope keys without
   exchanging keys per-envelope, the L12 `computeCommonSecret(myPriv,
   theirPub, gv)` helper gives them a shared secret bound to a specific
   `gv` (group variable — invoice number, seq, link counter).

## When you do NOT want an audit chain

- **High-throughput per-cell broadcasting** — that's transport
  (paid pubsub). Audit chains are linear; transport is fanout.
- **Mutable cells** — audit chains are append-only. Mutation requires a
  new sub-chain (separate `entityId`) or an L9 envelope that
  authorises change disclosure under an existing chain segment.
- **Sub-second adversarial settlement** — that's payment-channel work
  (L1 Q* netting, L2 watchtower). Audit chains record events at the
  cadence of canonical facts, not at micropayment cadence.

---

## Mechanism

### Entry shape

Each entry binds five fields:

```
entityId       — human chain label (e.g. "oddjobz:invoice:abc-123")
seq            — u32, monotonic + gap-free, starts at 0
canonical      — the audit fact bytes (cartridge-defined)
canonicalHash  — SHA-256(canonical)
prevHash       — prior entry's entryHash, or zero32 at genesis
entryHash      — SHA-256(MAGIC || u8(VERSION) || u32be(seq) || prevHash || canonicalHash)
```

Wire format constants (cross-language stable):

- `AUDIT_CHAIN_MAGIC = "L12AC"` (5 ASCII bytes)
- `AUDIT_CHAIN_VERSION = 1`
- `AUDIT_CHAIN_DOMAIN_STR = "semantos.audit-chain/v1"`

The entry-hash domain separator (`L12AC`) ensures a 32-byte audit chain
hash is never confused with any other 32-byte SHA-256 in the system —
field-tree leaf (L8), L9 envelope preimage, L4 SPV merkle path, etc.

### Per-link key derivation

Each entry is signed by a per-link key derived from the entity's master
via L11:

```
linkPriv = deriveSegment(masterPriv, segment(entityId, seq))
linkPub  = deriveSegmentPub(masterPub, segment(entityId, seq))
```

Default `segment(entityId, seq) = "${entityId}/${seq}"`. Callers may
supply a custom `LinkSegmentDeriver` if their cartridge needs different
domain separation (e.g. tenant-scoped chains, hat-scoped chains).

Verifier reconstructs `linkPub` from `masterPubKeyHex` + the same
segmenter, then checks the signature over `entryHash`.

### Verification (`verifyAuditChain`)

Walks the chain entry-by-entry, six fail-closed axes per entry:

1. `entityId` consistent across the chain
2. `seq` gap-free + monotonic starting at 0
3. `canonicalHash` recomputes from `canonical`
4. `prevHash` matches prior entry's `entryHash` (zero32 at genesis)
5. `entryHash` recomputes from `{seq, prevHash, canonicalHash}`
6. `linkPubKeyHex` matches `deriveSegmentPub(masterPub, segment)`
7. ECDSA signature verifies over `entryHash` under `linkPub`

Returns `{ ok: true }` or `{ ok: false, failedAtIndex, seq, code, message }`
with codes:

```
GENESIS_PREV_HASH_NOT_ZERO  PREV_HASH_MISMATCH    SEQ_GAP
SEQ_NOT_MONOTONIC           CANONICAL_HASH_MISMATCH  ENTRY_HASH_MISMATCH
LINK_PUB_KEY_MISMATCH       INVALID_SIGNATURE     ENTITY_ID_MISMATCH
```

Empty input is treated as ok (trivially consistent).

### The bilateral-derivation helper (`computeCommonSecret`)

The va-chain "common secret" pattern is:

```
commonSecret = ECDH(myMasterPriv + gv,  theirMasterPub + gv·G)
```

`gv` ("group variable") is any segment both parties apply — a per-link
counter, an invoice number, a chain seq. By ECDH symmetry both parties
land on the same shared bytes without per-link key exchange.

In semantos this is exposed as `computeCommonSecret(myPriv, theirPub, gv)`
in `@plexus/vendor-sdk`. Pure composition of L11 (`deriveScalar` /
`deriveScalarPub`) + the existing `computeSharedSecret`. The standalone
helper is also usable by L9 (scoped-disclosure envelope delivery
point-to-point under a chain segment).

---

## Storage-tier integrity (deferred follow-up)

tea-package's PG migration `0006_evid_audit_chain.sql` is the
production-shaped reference for enforcing chain integrity at the
storage tier — `BEFORE INSERT` trigger with `pg_advisory_xact_lock`
+ gap-free + prev-hash + entry-hash recompute, plus an immutability
trigger rejecting UPDATE/DELETE.

The TS primitive in this canon doc lives at the application tier. A
storage-tier port (sqlite or PG) is the follow-up that closes the
"writer bypass" route: even if a cartridge accidentally skips the
application primitive, the storage tier rejects a malformed chain
write. See L12 axis E note in the matrix for the deferred work.

---

## Cross-references

- Matrix: [`docs/canon/cw-lift-matrix.yml`](cw-lift-matrix.yml) — L12.
- Memory: `cell_routing_paid_pubsub_not_risk` — transport layer.
- Memory: `mnca_anchor_onchain_mainnet` — anchor-history chain candidate.
- L4: [`core/anchor-attestation/src/verify-inclusion.ts`](../../core/anchor-attestation/src/verify-inclusion.ts) — composes naturally with audit chains (each chain entry can be SPV-verified separately).
- L5: [`core/anchor-attestation/src/idempotency.ts`](../../core/anchor-attestation/src/idempotency.ts) — batch anchors are a natural audit-chain entry stream.
- L9: [`core/protocol-types/src/disclosure/index.ts`](../../core/protocol-types/src/disclosure/index.ts) — envelopes can deliver per-chain-link disclosure under a shared `gv`.
- L11: [`core/plexus-vendor-sdk/src/crypto.ts`](../../core/plexus-vendor-sdk/src/crypto.ts) — `deriveSegment` + `deriveSegmentPub` underlie linkPub derivation.
- Source (Craig Wright, MIT): `prof-faustus/verifiable-accounting-chain`, `packages/chain/src/{chain,ecdh,link}.ts`. Patents cited: US12375287B2, EP3259724B1.
