---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/domainflag-tag-unification.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.632156+00:00
---

# domainFlag ↔ derivation-tag unification

**Status:** Stage 0 merged · Stage 1 scoped · Stage 2 base primitive LANDED (PR #889) · recovery fork RESOLVED = option (b) per-record `kdfVersion` stamp (model 2b, §4.4) · **all 6 unilateral consumers + the P6 tier0/spend follow-on converted to kdf-v3** across stacked PRs #893 (cell-anchor) · #894 (hat-keys) · #896 (tessera) · #901 (wallet change) · #902 (native Zig anchors) · #903 (PWA change+anchor) · #908 (PWA tier0/spend, P6) — in review. **PRODUCTION CLEAN-BREAK reached:** no unilateral kdf-v2 callers remain in production. The only surviving v2 reference is the SDK's version-parametrized `deriveNodeKey` v2 branch, retained **by design** for stored test trees (§3 step 2).
**Created:** 2026-06-06
**Owner:** unassigned
**Related:** [`cw-lift-matrix.yml`](cw-lift-matrix.yml) L11 (axis-D) + L28 · [`brc-mapping.yml`](brc-mapping.yml) ·
deliverable `D-Const-domainflag-genfix` (merged, branch `feat/constants-domainflag-canonical`)

> **Why this doc exists.** prof-faustus/bsv-universal-sdk (`bsv-universal-sdk-spec.md`,
> repo 19 in the CW lift matrix) specifies pay-to-contract key tweaking as
>
> > `P' = P + H(tag ‖ m)·G`
>
> That is, byte-for-byte, our L11 `deriveSegment` primitive
> (`child = parent + SHA256(segment)·G`) — independently re-derived in a
> clean-room spec with **no** BRC or EP citations. The single divergence is
> the explicit **`tag`** (domain separator) as a *second* hash input. That
> `tag` is conceptually identical to our first-class u32 **`domainFlag`** —
> except `domainFlag` is the richer artifact, and it is **not currently
> wired into the derivation tweak at all**. This doc captures the finding,
> the current state, and a staged path to unify the two encodings.

---

## 1. The three "domain" surfaces today

semantos expresses "which domain is this" in **three** places. The first two
already share one u32 namespace; the third is a separate, parallel encoding.

| # | Surface | Encoding | Where | Enforcement |
|---|---------|----------|-------|-------------|
| 1 | **Cell-at-rest** | u32 `domainFlag` in the cell header | `core/cell-engine/src/constants.zig` (generated from `core/constants/constants.json`) | Read by `linearity.getDomainFlag(cell)` |
| 2 | **Runtime script** | same u32, asserted on stack | `OP_CHECKDOMAINFLAG` (`0xC6`) — `core/cell-engine/src/opcodes/plexus.zig` `opCheckDomainFlag`; opcode id in `core/cell-ops/src/opcodes.ts:61` | Failure-atomic; **formally proven** by `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` |
| 3 | **Key derivation** | a free-form **segment string/bytes** | `deriveSegment(parent, segment)` — `core/plexus-vendor-sdk/src/crypto.ts:49` (pub side `:96`) | None — the domain is whatever the caller textually embeds |

**Surfaces 1 & 2 are unified.** The same u32 lives in the header and is what
`OP_CHECKDOMAINFLAG` checks. Canonical values (post `D-Const-domainflag-genfix`):

```
DOMAIN_FLAG_EDGE_CREATION        = 1          # PLEXUS_RESERVED tier (1..255)
DOMAIN_FLAG_SIGNING              = 2
DOMAIN_FLAG_METERING             = 10  (0x0a)
DOMAIN_FLAG_COMMERCE_V1          = 0x0001FE01  # schema-dispatch V1 band
DOMAIN_FLAG_ANCHOR_ATTESTATION_V1= 0x0001FE02
DOMAIN_FLAG_SCG_RELATION_V1      = 0x0001FE03
# tier bounds: PLEXUS_RESERVED 1..255 · EXTENDED 256..65535 · CLIENT_DEFINED 65536..2^32-1
```

The recovery layer already reuses these values:
`cartridges/wallet-headers/brain/src/plexus/envelope.ts` validates
`KNOWN_DOMAIN_FLAGS = {0x00, 0x01, 0x04, 0x0a, 0x0b}` and routes kdf version by
`domainFlag` (`kdfVersionForDomain`).

**Surface 3 is the odd one out.** `deriveSegment` takes a single `segment`
argument and hashes it whole — `SHA256(segment)`. The domain is smuggled in
textually by each caller, with **no reference** to the u32 registry:

| Caller | Segment it builds | Domain encoding |
|--------|-------------------|-----------------|
| `cartridges/wallet-headers/brain/src/cell-anchor.ts` `deriveCellAnchorSk` | `protocolHash(16) ‖ anchorIndex_le8(8)` (24 B) | `protocolHash = anchorProtocolHash(typeHash)` — no flag |
| `cartridges/tessera/brain/src/key-derivation.ts` | `tessera/<cellType>/<cellId>/<role>` | path string — no flag |
| `runtime/semantos-brain/src/.../hat_bkds.zig` (`deriveSegment`/`deriveSegmentPub`) | invoice bytes | per-hat — no flag |
| `ecdh42.ts` change domain (`deriveChangeSk`) | `SHA-256(invoice)` | CHANGE-domain invoice — no flag |
| `apps/semantos` PWA Dart `brc42_derive.dart` (`deriveSelfChild`) | self invoice | parallel tree — no flag |

> **Note — there is a *fourth*, partial wiring** at the certificate layer.
> `deriveChildKey(parent, invoiceNumber)` (BRC-42 delegate,
> `crypto.ts:~155`) takes an `invoiceNumber` string that "encodes resourceId,
> domainFlag, and childIndex", and `buildChildPreimage(..., domainFlag, ...)`
> (`crypto.ts:~308`) folds `domainFlag` into the **cert metadata**
> (`serialNumber`/`fields`). So `domainFlag` already reaches the *bilateral*
> BRC-42 path as a string component and the cert as metadata — but it never
> reaches the *unilateral* `deriveSegment` tweak as a structural input.

### The mismatch, precisely

The SDK says `H(tag ‖ m)`. We have:
- a perfect candidate for `tag` (the u32 `domainFlag` — enforced at-rest,
  at-runtime, and machine-proven), and
- `deriveSegment` hashing only `m` (the segment), with the domain re-encoded
  ad-hoc as a string prefix that the registry knows nothing about.

So domain separation is asserted **twice in two incompatible encodings**, and
the cryptographically load-bearing one (the derivation) uses the weaker,
unregistered one.

---

## 2. Why unify

1. **Single source of truth.** Today `tessera/owner/...` strings and
   `DOMAIN_FLAG_*` u32s are two vocabularies that don't reference each other.
   This is exactly the conflation trap the canonical-schema-spine and
   "two BRC-42 ECDH conventions" lessons warn about: source-shape drift with
   no normalization seam.
2. **Key↔domain binding (security).** If `domainFlag` is folded into the
   tweak, a key derived for domain *X* can no longer be replayed to authorize
   a cell flagged domain *Y*. `OP_CHECKDOMAINFLAG` would then transitively
   gate the *derived key*, not just the cell at rest — closing the gap between
   "this cell claims domain X" and "this key was actually derived for X".
3. **External corroboration.** A second, independent CSW-family spec lands on
   the identical primitive and explicitly carries the `tag`. Matching it keeps
   us aligned with the reference design and with `brc-mapping.yml`'s
   EP3259724B1-as-foundation framing.

### Why *not* over-unify

The SDK's `m` is a **contract commitment** (pay-to-contract commits a *message*
to a key). Our `segment` is a **hierarchical path / invoice**. The `tag` ↔
`domainFlag` mapping is clean; the `m` ↔ `segment` mapping is **not**. Unify the
domain separator only — do **not** assume the whole P2C construction maps onto
our derivation.

---

## 3. Staged plan

### Stage 0 — single registry source ✅ DONE (`D-Const-domainflag-genfix`)

Branch `feat/constants-domainflag-canonical` (commit `e512d60`) made
`core/constants/constants.json` the canonical generator source for the u32
domain-flag registry (→ `core/cell-engine/src/constants.zig` via
`bun run generate-constants`), retired 7 dead pre-audit-B-1 legacy entries
(ATTESTATION=5, ENCRYPTION=3, MESSAGING=4, CHILD_CREATION=6, PERMISSION_GRANT=7,
DATA_SOVEREIGNTY=8, SCHEMA_SIGNING=9 — zero call-sites), and kept the live
flags + tier bounds. Suites green (cell-engine 410/410, constants 11/11).

**This is the foundation the rest builds on.** There is now one authoritative
list of domain flags.

### Stage 1 — make derivation reference the registry (NO key change)

> Goal: every `deriveSegment` caller's domain component is *derived from* the
> canonical registry rather than hand-authored, **without changing any derived
> key bytes yet.** This is pure vocabulary/seam work — safe, incremental.

Scope (own PR, builds on Stage 0):

1. **TS mirror of the registry.** Ensure `core/protocol-types` exposes the
   `constants.json` domain flags as a typed `DomainFlag` enum/const (a
   `DomainFlag` type is already re-exported from `protocol-types`; point it at
   the generated constants so TS and Zig share one source). No new values.
2. **Map each segment author to a flag.** Annotate (not yet alter) each
   `deriveSegment` call-site with the canonical `domainFlag` its segment
   *corresponds to* (decisions confirmed 2026-06-06 — **one flag per domain**;
   the segment string already separates within a domain, so the flag isolates
   *across* domains only; new first-party flags go in the **EXTENDED band
   256–65535**):
   - cell-anchor → **`domainFlagFromTypeHash(typeHash)`** — the per-cell-type
     SOVEREIGN flag in the client-defined range (`0x00010000 | typeHash[0..2]`),
     which is **already** what `buildSchemaMapping` exports for recovery and is
     therefore the self-consistent binding flag. **NOT
     `DOMAIN_FLAG_ANCHOR_ATTESTATION_V1` (0x0001FE02)** — that is a different,
     fixed *attestation-cell header discriminator* (`cell_store_lmdb.zig`
     `is_attestation`), not the anchor-UTXO key domain. (Corrected from an
     earlier draft of this doc that named the wrong flag.)
   - tessera owner/role tree → ONE `tessera`-band flag in EXTENDED (the segment
     `tessera/<cellType>/<cellId>/<role>` already separates roles); register in
     `constants.json`.
   - change domain → `CHANGE` (0x0b, stays in PLEXUS_RESERVED — already in
     `KNOWN_DOMAIN_FLAGS`).
   - hat keys → ONE dedicated `hat`-band flag in EXTENDED (do not overload
     `SIGNING=2`; the per-hat invoice separates hats within the domain).
   - edges/messaging stay BILATERAL (BRC-42) — `EDGE_CREATION`/`MESSAGING`,
     unchanged.
3. **Allocate missing bands.** Some live segment domains (tessera roles, hat
   keys) have no registered u32 yet. Add them to `constants.json` in the
   appropriate tier and regenerate — same mechanism Stage 0 established.
4. **Lint seam.** Optional: a check that every `deriveSegment` call passes a
   registered `domainFlag` (or an explicit `{ domain: <flag> }` companion),
   so new unilateral trees can't reintroduce an unregistered string domain.

**Exit:** every unilateral derivation site names a registered `domainFlag`;
no key bytes changed; KATs unchanged. This closes the "two vocabularies"
duplication and *sets up* Stage 2 cleanly.

### Stage 2 — "L11.5": bind the flag into the tweak (KEY-CHANGING, DEFERRED)

> Goal: change `deriveSegment` to `child = parent + SHA256(domainFlag ‖ segment)·G`,
> literally matching the SDK's `H(tag ‖ m)`. **This changes every unilateral
> derived key** → byte-incompatible → a cutover exactly like L11 was.

This is **deferred as a deliberate decision**, not folded into Stage 1.
Treat with the same discipline the L11 cutover used:

1. **Clean cutover, no v1 retention on the Zig side** — same call Todd made for
   L11 (the on-chain artifacts are throwaway prototyping objects with no spend
   paths; do it before any mainnet-action consumer exists). The SDK side keeps
   v1 for stored test trees (`KdfVersion`), as in L11.
2. **New primitive shape — DONE (PR #889).** Added `deriveDomainSegment(parent,
   domainFlag, segment)` / `deriveDomainSegmentPub` where the preimage is
   `u32_be(domainFlag) ‖ segment`, plus the Zig mirror in `derive_segment.zig`.
   **Decision (deviates from the original draft below):** rather than break the
   existing `deriveSegment` signature, the v3 primitive is ADDED alongside (v2
   `deriveSegment` untouched), and the `KdfVersion` union gains
   `'plexus-kdf-v3'`. The clean-break of v2 happens implicitly as the last
   consumer is converted. `deriveScalar`/BRC-42 bilateral path unchanged.
3. **Cross-language KAT — DONE (PR #889).** 3 vectors pinned in BOTH the TS test
   and the Zig test, proven byte-identical (TS 7/7, Zig 6/6). PWA Dart vector
   added when the Dart consumer is converted.
4. **Recovery notation — OPEN DESIGN FORK (gates the consumer sweep).**
   `envelope.ts kdfVersionForDomain(domainFlag)` today returns `v1` for
   bilateral, else `v2` — a flag→version *mapping*. During an INCREMENTAL sweep,
   some unilateral domains are converted (v3) and some are not (still v2), so a
   single mapping can't stay correct unless updated per-consumer-PR. Two options:
   - **(a) Extend the flag→version mapping** per consumer as it converts (e.g.
     anchor sovereign-range → v3 once cell-anchor lands). Simple, but couples
     recovery correctness to a hand-maintained flag→version table and to sweep
     ordering — fragile on the mainnet anchor path.
   - **(b) Stamp `kdfVersion` per `DerivationStateRecord`** at key-creation time
     so recovery reads the stored version instead of re-deriving it from the
     flag. More robust (each record self-describes), bigger change. **Recommended**
     — decouples recovery from sweep ordering.
   **This fork must be decided before converting any unilateral consumer**, since
   getting it wrong means recovery reconstructs anchor keys with the wrong
   derivation and can't find/spend the UTXOs.
5. **Consumers to convert** (incremental stacked PRs, confirmed order):
   cell-anchor → hat_bkds (+verifier) → tessera key-derivation → wallet change →
   native Zig wallet anchors (`wallet_exports.zig`, `wallet_op_http.zig`) →
   PWA Dart tree (still mid-rearchitecture per L11 P6). Each PR: convert the
   site to `deriveDomainSegment` with its confirmed flag + a KAT cross-check +
   the recovery-version update per the §4.4 decision.
   - **cell-anchor binds `domainFlagFromTypeHash(typeHash)`** (see Stage 1 map) —
     fold it into the existing 24-byte invoice: `tweak = SHA-256(u32_be(flag) ‖
     protocolHash(16) ‖ anchorIndex_le8(8))`. Safe to re-key: the existing
     on-chain anchors are throwaway artifacts with no spend/binding intent.
6. **The payoff to verify end-to-end:** derive a key under domain X, attempt to
   use it to satisfy `OP_CHECKDOMAINFLAG` for a cell flagged Y → must fail at
   the derivation/identity layer, not just the cell check.

**Status:** base primitive landed (PR #889). **Recovery fork resolved: option
(b)** — per-record `kdfVersion` stamp (model 2b). For change, the stamp is set at
`recordContext` key-creation (`wallet-ops.ts`) and the envelope recipe prefers it
(`r.kdfVersion ?? kdfVersionForDomain(...)`); `envelope.ts ALGORITHM_VERSION` stays
2 (v3 rides the existing era per-recipe; the operator validates `∈ [1,2]`). For
anchors, recovery routes via the already-per-record `SchemaMapping.kdfVersion`.

**Consumer sweep — all 6 converted** (stacked PRs, in review):

| # | Consumer | Flag bound | PR |
|---|----------|-----------|----|
| 1 | cell-anchor (`cell-anchor.ts`) | `domainFlagFromTypeHash(typeHash)` | #893 |
| 2 | hat-keys (`hat_bkds.zig` + verifier) | `HAT_SIGNING` (256) | #894 |
| 3 | tessera (`key-derivation.ts` + port) | tessera page `0x00010400` | #896 |
| 4 | wallet change (`ecdh42.ts`) | `CHANGE` (0x0b) | #901 |
| 5 | native Zig anchors (`wallet_exports.zig`, `wallet_op_http.zig`) | `domainFlagFromTypeHash` | #902 |
| 6 | PWA change + anchor (`brc42_derive.dart` …) | 0x0b / `domainFlagFromTypeHash` | #903 |
| P6 | PWA tier0 + spend (`tier0_cache.dart` …) | `WALLET_TIER0` (257) / `WALLET_SPEND` (258) | #908 |

**Production clean-break reached.** With P6 (#908) the PWA `tier0`/`spend` trees
fold their EXTENDED-band flags (`WALLET_TIER0`/`WALLET_SPEND`, registered in
`constants.json`), so **no unilateral kdf-v2 caller remains in production**. The
only surviving v2 reference is the SDK's version-parametrized `deriveNodeKey` v2
branch — retained **by design** for stored test trees (step 2), not a leftover.

---

## 4. Open questions for Todd

1. **Greenlight Stage 2** — ✅ greenlit 2026-06-06; base primitive landed (#889).
2. **Tier placement** — ✅ EXTENDED band (256–65535) for new first-party flags
   (tessera, hat); CHANGE stays in PLEXUS_RESERVED (0x0b).
3. **Granularity** — ✅ one flag per domain (segment separates within-domain).
4. **`m` vs `segment` semantics** — keep `segment` as a path/invoice; adopt only
   the `tag` half of P2C (assumed; confirm if anyone proposes otherwise).
5. **Recovery routing for the v2→v3 transition** (see §3 step 4) — ✅ RESOLVED:
   option (b) per-`DerivationStateRecord` stamped `kdfVersion` (model 2b). The
   stamp is set at key-creation and the recovery recipe prefers it over the
   flag→version map; the envelope era (`ALGORITHM_VERSION` / `kAlgorithmVersion`)
   stays 2 on both brain and PWA so v3 rides the existing format per-recipe.

---

## 5. Provenance

- SDK source: `prof-faustus/bsv-universal-sdk @ bsv-universal-sdk-spec.md`
  (v0.1 DRAFT, spec-only, **license UNKNOWN** — verify before any code lift).
- Our primitive: `core/plexus-vendor-sdk/src/crypto.ts` `deriveSegment`/
  `deriveSegmentPub`; Zig `runtime/semantos-brain/src/derive_segment.zig`.
- Registry: `core/constants/constants.json` → `core/cell-engine/src/constants.zig`.
- Enforcement: `OP_CHECKDOMAINFLAG` (`core/cell-engine/src/opcodes/plexus.zig`),
  proof `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean`.
