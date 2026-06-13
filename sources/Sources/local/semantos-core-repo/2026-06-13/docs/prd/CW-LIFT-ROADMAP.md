---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CW-LIFT-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.700641+00:00
---

# CW Lift Roadmap — Lifting prof-faustus (Craig Wright) research into semantos-core

> Companion to [`docs/canon/cw-lift-matrix.yml`](../canon/cw-lift-matrix.yml).
> Source: 10 public repos audited 2026-06-01.
> Authorial profile: BSV-native, patent-aware, NPR/JPL-coding-standard-aware,
> spec-led, post-Genesis discipline, honest crypto labelling. All MIT.

This roadmap ranks 20 lift candidates by **priority = value × ease**, then
sequences them with dependencies and surface-area conflicts considered.
Skip-list at the bottom for transparency.

---

## §1. Strategic picture

Audit history: original 10 repos audited 2026-06-01 (PR #790, re-scoring
PR #792). Expansion audit 2026-06-02 added 8 substantive new repos
(identity-attribution, idattr-onchain, tee-sim, revocable-nft-tee, cto-bsv,
bsv-poker, triple-entry-bsv-sql, tea-package) plus 3 stubs. Lifts L21–L27
added in this expansion.

Six areas now yield genuine semantos uplift:

1. **MNCA anchor surface cleanup** (anchorchain L4 + L5) — semantos has every
   piece but they're split across three modules; anchorchain's composition
   pattern is a 1-day refactor.
2. **Selective disclosure surface** (va-bsv L8 + tea-bsv L9) — semantos has
   no per-field disclosure today. Note 2026-06-02: triple-entry-bsv-sql's
   ECDH-HMAC keystone is a working byte-exact implementation of this shape
   (Go + TS + C parity, KAT-pinned) and could shortcut the L8/L9 ports.
3. **Payment-channel patterns** (bonded-subsat-channel L1 + L2 + L3) — the
   custody-free watchtower with SIGHASH-pinned incentives is the right shape
   for a Plexus brain-monitor on device fleets; sub-satoshi netting solves
   the Skyminer fractional-fee problem. bsv-poker (2026-06-02) now binds
   bonded-subsat-channel as a real subprocess — proving the channel works
   end-to-end against an application.
4. **Craig-family derivation foundation** (**L11** + L12 + L10 + L9) — all
   root in EP3259724B1 / US12375287B2 / EP3420669B1. **L11 (EP3259724B1) is
   the foundation primitive `child = parent + H(segment) mod n` — BRC-42 is
   just the bilateral specialisation** (`segment = HMAC(ECDH-shared, data)`).
   Under CSW-canonical, semantos doesn't have "two primitives" with one
   missing; it has ONE primitive (Craig's), with only the bilateral case
   surfaced. L11 puts the right primitive at the foundation of the stack
   so L12 (audit chain), L10 (TEA sub-keys), L9 (envelope keys), L22
   (device-attest keys), L27 (threshold ECDH) all compose cleanly above.
   **Promoted Tier 2 → Tier 1 on 2026-06-02** — ships Week 1 (30 LOC +
   one-line refactor, no breaking changes).
5. **Identity + device attestation surface** (L21 + **L22** + L24) — NEW
   2026-06-02. identity-attribution provides ZK-predicate identity
   attribution with sparse Merkle registry; tee-sim provides a byte-KAT-
   matched device-attestation simulator. **L22 directly closes brain-auth
   gap T7** (`brain_auth_model_intent`): cert + capability + freshness +
   hardware-pin instead of bearer token. L24 adds the architectural
   discipline (TEE-trait "key never leaves" + fail-closed SPV inside the
   trust boundary).
6. **Confidential transferable objects + non-custodial threshold** (L27 +
   L23) — NEW 2026-06-02. cto-bsv generalises revocable-NFT-TEE; the key
   primitive is **threshold ECDH via Lagrange-in-the-exponent** (private
   key d truly never reconstructs — stronger than L7 Schnorr and stronger
   than anchorchain's Shamir-reconstruct). L23 adds forward-revocable
   capability with on-chain SPV-checkable rekey anchor.

Hygiene wins on top: forbidden-token CI lint (L14) + overclaim lint
extension (revocable-nft-tee xtask), an alternative data carrier (L13)
now with a third option (`<root> OP_DROP <P2PKH>` from idattr-onchain),
and a single canon doc applying M840's mesh-spectral results to Skyminer
N=8 (L20).

Process governance lift: **L26 (path-dep + pinned-rev cross-repo pattern)**
— directly closes the parked `oss_substrate_carve_parked` decision.
revocable-nft-tee consumes overlay-broadcast via path-dep with pinned rev;
v2 may depend on v1, v1 SHALL NOT depend on v2 (REQ-GOV-V2-002 equivalent).
This is the answer to "don't carve, don't mirror" — code-zero canon doc
with a reference workspace template. Priority 25.

Four items remain explicit **skips** — no consumer for the pattern (L16),
multi-month port with no consumer for ECDSA signing specifically (L15;
note L27 covers ECDH non-custodially as the midpoint), collusion-vulnerable
+ no card-game cartridge (L19), different mechanism solving a different
problem (L17).

---

## §2. Tier 1 — priority ≥ 20 (do first)

Nine lifts in Tier 1 (L11 promoted 2026-06-02). All independently scoped;
all MIT-attributable.

| # | Lift | Source | Target | Value | Ease | Prio | Deps |
|---|---|---|---|---|---|---|---|
| L4 | Two-tree SPV verify composition | anchorchain `packages/api/src/service.ts` | `core/anchor-attestation/src/verify-inclusion.ts` (new) | 5 | 5 | **25** | — |
| L5 | Per-batchId idempotent anchoring | anchorchain `packages/anchor/src/index.ts` | `cartridges/bsv-anchor-bundle/brain/src/anchorer.ts` + `core/anchor-attestation/src/idempotency.ts` (new) | 5 | 5 | **25** | — |
| **L11** | **EP3259724B1 base derivation** (foundation; BRC-42 = bilateral case) | va-chain `packages/keys/src/derive.ts` | `core/plexus-vendor-sdk/src/crypto.ts` (extend with `deriveSegment`; refactor `deriveChildKey` as composition) | 5 | 5 | **25** | — |
| **L26** | **Path-dep + pinned-rev cross-repo pattern** | revocable-nft-tee `Cargo.toml` + REQ-GOV-V2-002 | `docs/canon/cross-repo-path-dep-pattern.md` (new) | 5 | 5 | **25** | — |
| L1 | Q\* sub-satoshi netting | bonded-subsat-channel `src/channel/accounting.py` | `cartridges/shared/relay/q-star-netting.ts` (new) | 4 | 5 | **20** | — |
| L2 | D14 custody-free watchtower | bonded-subsat-channel `src/channel/watchtower/{tower,cluster}.py` | `runtime/semantos-brain/src/federation/watchtower.ts` + `cartridges/shared/relay/forfeit-template.ts` (new) | 5 | 4 | **20** | — |
| L8 | Per-field intra-tx Merkle tree | verifiable-accounting-bsv `packages/evidence/src/fieldtree.ts` (or shortcut via triple-entry-bsv-sql `crypto-core/`) | `core/protocol-types/src/field-tree/` (new) | 5 | 4 | **20** | — |
| L13 | Data carrier — 3 options (PushDrop / OP_FALSE OP_IF / OP_DROP+P2PKH) | va-bsv `scriptdataenvelope.ts` + idattr-onchain `<root> OP_DROP <P2PKH>` | `core/protocol-types/src/cell-pushdrop.ts` (extend) + Zig mirror | 4 | 5 | **20** | — |
| L14 | Forbidden-token CI lint + overclaim lint + DB-resident script guard | anchorchain `scripts/forbidden-scan.mjs` + revocable-nft-tee xtask + tea-package `migrations/0027` | `scripts/forbidden-tokens.mjs` + `scripts/overclaim-check.mjs` + storage-tier trigger + `.github/workflows/hygiene.yml` | 4 | 5 | **20** | — |

### §2.1 Recommended sequence

```
Week 1: L11  (deriveSegment foundation — every key derivation flows through this)
Week 1: L26  (path-dep canon doc — process governance ships first)
Week 1: L14  (lint — ships before everything else, gates future PRs)
Week 1: L4   (SPV verify composition — pure refactor, no new surface)
Week 2: L5   (per-batchId idempotent anchor — small wrapper around L4)
Week 2: L13  (3-option data carrier — additive variants in cell-pushdrop)
Week 3: L8   (field-tree — new primitive, no consumer required yet)
Week 4: L1   (Q* netting — pure-function algorithm, easy port)
Week 5: L2   (D14 watchtower — depends on brain mempool-observer wiring)
```

L11 ships Week 1 — it's a ~30-LOC `deriveSegment` addition + one-line
refactor of `deriveChildKey` as composition. Once landed, it unblocks
L12 (Tier 2, blockedBy L11) and simplifies L10 (TEA sub-keys are
HKDF-shaped segments).

### §2.2 Per-item briefs (Tier 1)

**L11 — EP3259724B1 base derivation** (`D-CW-L11-*`) — *foundation lift*

Promoted Tier 2 → Tier 1 on 2026-06-02. Under the stance that CSW's
patents are canonical for semantos, BRC-42 is **just the bilateral
specialisation** of CSW's underlying derivation primitive — not a
separate primitive. The matrix should reflect that hierarchy at the
foundation.

```
EP3259724B1 (foundation):   child = parent + H(segment) mod n
                             where `segment` = any input
BRC-42 (specialisation):    child = parent + HMAC(ECDH-shared, data) mod n
                             ≡ EP3259724B1 with segment = HMAC(shared, data)
```

What changes in semantos: extend
[`core/plexus-vendor-sdk/src/crypto.ts`](../../core/plexus-vendor-sdk/src/crypto.ts)
with `deriveSegment(parent, segment) → child` as the base primitive.
Refactor existing `deriveChildKey` as the one-line composition
`deriveSegment(parent, HMAC(shared, data))`. **Existing BRC-42 call
sites unchanged at signature level** — no breaking changes, no
breaking tests. Update [`docs/canon/brc-mapping.yml`](../canon/brc-mapping.yml)
to reflect the hierarchy (EP3259724B1 base; BRC-42 the bilateral
case semantos happened to ship first). KAT pin against va-chain's
`chain_v1.json`.

Why foundation: every key derivation in semantos eventually flows
through this primitive — operator cell-trees, hat-internal keys,
cartridge-local paths, the L22 device-attestation key tree, the L12
spend-chain `linkPub`, the L10 TEA sub-keys, the L9 envelope keys.
Putting the right primitive at the bottom of the stack means every
downstream lift composes cleanly.

**Sweep finding (2026-06-05).** The Plexus vendor SDK is converted:
node derivation now uses `deriveNodeKey` (canonical kdf-v2 =
`deriveSegment`; legacy kdf-v1 = BRC-42 self-derive), version-gated and
stamped per tree on the root cert. A full repo sweep for the *other*
unilateral trees corrected an earlier overclaim: the degenerate-ECDH
self-derivations in `hat_bkds.zig` (`deriveChildPrivScoped`), the wallet
change keys (`ecdh42.ts` `deriveChangeSk`/`buildChangeLock`), the cell
anchors (`cell-anchor.ts`, `wallet_exports.zig`, `wallet_op_http.zig`),
and the MNCA anchor leaf do NOT freely "retire." Each produces a key or
signature already broadcast to BSV mainnet or persisted in cells/audit
logs, so swapping the algorithm in place would break verification and
recovery of live artifacts. They are convertible ONLY behind the same
`kdf_version` gate (new trees → v2, existing → v1), which is a
coordinated, mainnet-touching migration — not an in-place edit. The one
genuinely off-chain unilateral site, `session_addr.zig` `deriveIidT3`,
is a pubkey→IPv6-IID hash, not a key derivation, so it is out of scope.
Net: `deriveSegment` is the canonical primitive and the SDK leads;
the Zig brain/wallet/cell-engine trees migrate later, version-gated.

Why Week 1: ~30 LOC of TS for `deriveSegment` (point-add of a hashed
scalar), one-line composition refactor for `deriveChildKey`, mechanical
canon doc update, one KAT pin. Tiny in surface area, foundational in
position. Unblocks L12 (Tier 2, currently `blockedBy: L11`) and
simplifies L10 (TEA sub-keys are HKDF-shaped segments — fall out of
the composition).

L4 + L5 + L13 land in the MNCA anchor area together; L8 stands alone; L1 + L2
pair up for the relay surface. L14 leads everything because it's enforcement
infrastructure that should be in place before new code lands.

### §2.2 Per-item briefs

**L4 — Two-tree SPV verify composition** (`D-CW-L4-*`)

Semantos has the BRC-10 BUMP proof, the SPV intent wire format, and the
anchor attestation schema v2. Anchorchain has a single composed
`verifyInclusion` call that walks: leaf → batch-root → block-root → header
chain. Replace direct uses of the three separate operations with the
composed call. Verify against the 2026-05-22 mainnet MNCA anchor as the live
test ([`mnca_anchor_onchain_mainnet`](memory: tx a5277713…b2a78c)).

**L5 — Per-batchId idempotent anchoring** (`D-CW-L5-*`)

Today MNCA anchoring is per-cell. Add a per-batch idempotency layer keyed on
`batchId = H(sorted cell-roots ‖ logical-time-window)`. Second call with the
same batchId returns the existing manifest, never emits a duplicate tx.
Cheap at scale, prevents accidental double-anchors on retry.

**L1 — Q\* sub-satoshi netting** (`D-CW-L1-*`)

For sub-1-sat cell-routing fees: relays accumulate fractional credits in
units of `k*S` micro-sats; on-chain settlement is `floor(a_i / k)` sats plus
`+1` to the top-R parties by `a_i mod k` (ties by smaller index). Sums to S.
Pure-function algorithm, ~50 LOC, no protocol entanglement. Lift into
`cashlanes-bridge.ts`.

**L2 — D14 custody-free watchtower** (`D-CW-L2-*`)

Brain holds NO keys; only pre-signed-by-source forfeit txs. The pre-signed
forfeit pays the brain a fixed `tower_fee` in its first output; counterparties
sign `SIGHASH_ALL|FORKID` so the brain can only broadcast the exact bytes.
Tamper → interpreter rejects. Matches Craig's "devices verify+act, wallets
sign" rule ([`craig_no_keys_on_device_stance`](memory)). Integration question:
what's the "stale state supersession" trigger for a semantos cell-relay
context? Likely: stale anchor attestation higher-sequence supersedes.

**L8 — Per-field intra-tx Merkle tree** (`D-CW-L8-*`)

Semantos has no per-field selective disclosure surface today. Lift the
`fieldtree.ts` shape: per-field leaves with schema fingerprint, canonical
serialise, "VARP" magic. Cell remains the 1024-byte wire-format unit; the
field-tree commits to fields *within* the cell payload. Does NOT replace
cell-pushdrop; complements it. Sets up L9 (scoped disclosure) as a follow-up.

*SQL deep-dive 2026-06-02:* triple-entry-bsv-sql's PG surface is small and
transparent — 159 LOC, 5 tables + 1 capture trigger + query functions, no
crypto in plpgsql. The Go writer + crypto-core ECDH-HMAC keystone is where
the IP lives; SQL is just the capture mechanism. Lift Go crypto-core; the
trigger+outbox pattern is optional adaptation for semantos's storage tier.

**L13 — `OP_FALSE OP_IF <push> OP_ENDIF` data carrier** (`D-CW-L13-*`)

Alternative to PushDrop. Script: `OP_FALSE OP_IF <cell> OP_ENDIF <pk> OP_CHECKSIG`.
IF body is unreachable so the cell is pure data carriage; the `OP_CHECKSIG`
tail remains spendable. Decouples data carriage from drop semantics. Add as
an OPTION in [`cell-pushdrop.ts`](../../core/protocol-types/src/cell-pushdrop.ts);
PushDrop can stay the default. Both TS encoder + Zig mirror needed for the
byte-identical guarantee ([`cell_wire_format_location`](memory)).

**L14 — Forbidden-token CI lint + overclaim lint + DB-resident script guard** (`D-CW-L14-*`)

Port `scripts/forbidden-scan.mjs`. Customise the token list:
- **Keep** from upstream: altcoin tickers, "cltv", "csv", "lightning",
  "taproot", "segwit", "rust-bitcoin", `op_checklocktimeverify`,
  `op_checksequenceverify`.
- **Drop**: "pedersen", "bulletproof" (semantos may want these — see L6).
- **Add (semantos-specific)**: "openai", "anthropic" inside `core/` per
  [`semantos_no_ai_in_substrate`](memory); "fork" / "btc" tickers; perhaps
  `console.log` in production paths.

Self-test: the lint must pass on itself, and on the repo today (whitelist
existing hits explicitly).

*SQL deep-dive 2026-06-02:* tea-package's
`migrations/0027_prohibition_constraints.sql` adds a THIRD prohibition layer
— a plpgsql IMMUTABLE function `wallet.fn_assert_allowed_script(BYTEA)`
invoked from BEFORE INSERT/UPDATE trigger on `wallet.utxo`. Raw opcode
byte-matching: `0x6a` (OP_RETURN data-carrier) → reject; the
script-hash template `0xa9 0x14 ... 0x87` → reject; P2PKH
`0x76 0xa9 0x14 ... 0x88 0xac` → allow; anything else → reject. Opcodes
matched by byte value so the migration itself stays clean under the CI
prohibition gate. Combined model for semantos = up to **4 prohibition
layers**: (1) CI static scan, (2) runtime application assertion in
script-builder, (3) storage-tier DB or sqlite trigger on persist, (4)
network-adapter rejection on wire. Today semantos has Layer 1 capacity
informally and Layer 2 via reviewer attention. Adding Layer 3 to the
cell-store INSERT path closes the bypass route entirely.

---

## §3. Tier 2 — priority 12-16 (do once Tier 1 settled)

Ten lifts in Tier 2 after L11's promotion to Tier 1 (2026-06-02). L22 + L24
are the identity/attestation lift pair that closes brain-auth gap T7.

| # | Lift | Source | Value | Ease | Prio | Deps |
|---|---|---|---|---|---|---|
| L9 | Scoped-disclosure signed envelope | tea-bsv `crates/disclosure/src/lib.rs` | 4 | 4 | **16** | L8 |
| **L24** | **TEE-trait "key never leaves" + fail-closed SPV freshness** | revocable-nft-tee `crates/tee/src/{tee,freshness}.rs` | 4 | 4 | **16** | — |
| **L22** | **Ed25519 device attestation + binding** (closes brain-auth T7) | identity-attribution `crates/idattr-device/` + tee-sim | 5 | 3 | **15** | — |
| L20 | M840 spectral mesh design heuristics | prof-faustus/M840 dissertation | 3 | 5 | **15** | — |
| L7 | Threshold Schnorr custody | anchorchain `packages/custody/src/thresholdschnorr.ts` | 4 | 3 | **12** | — |
| L10 | TEA primitives — sub-keys + linkage tags | tea-py + tea-bsv | 3 | 4 | **12** | — |
| L12 | ECDH-linked spend-chain audit primitive | va-chain `packages/chain/src/{chain,ecdh,link}.ts` | 4 | 3 | **12** | L11 |
| L18 | 3-branch IF/ELSE FSM script (+ branch-binding prefix) | cardtable `packages/script-templates/src/round-state.ts` + bsv-poker | 3 | 4 | **12** | — |
| **L21** | **Sigma-OR ZK + sparse Merkle registry** | identity-attribution `crates/idattr-zkp` + `crates/idattr-smt` | 4 | 3 | **12** | — |
| **L27** | **Threshold ECDH (Lagrange-in-the-exponent)** | cto-bsv `packages/tier-threshold/{ts,go}` | 4 | 3 | **12** | — |

**L9 — Scoped-disclosure signed envelope.** Natural follow-up to L8.
8-tuple binding: `note_id ‖ field_label ‖ H(K_field) ‖ verifier_id ‖
engagement_id ‖ purpose ‖ expiry ‖ nonce`. Maps onto the hat-context model
([`shell_cartridges_hats_model`](memory)): hat-scoped envelope releases
tenant-specific fields without exposing cross-tenant data.

*SQL deep-dive 2026-06-02:* tea-package's
`migrations/0022_address_shared_ecdh.sql` shows a worth-absorbing pattern
for the disclosure-envelope binding: every SHARED_ECDH address must
reference a `KEY_DERIVATION` canonical record that is **already chained in
`evid.audit_chain`**, enforced by trigger. Makes it impossible to persist
an unrooted disclosure context. Translates to: any L9 envelope must
reference an L12 chain row that exists, belongs to the same hat/entity,
and is chained — checked at INSERT.

**L12 — ECDH-linked spend-chain audit primitive.** Semantos has no
audit-chain primitive today — cell-mint history, hat lifecycle, anchor
history all live in per-store SQLite with no on-chain tamper-evident spine.
va-chain's `TransactionChain` provides one: each link spends prev outpoint,
signed by deterministically derived `linkPub` (via L11), with ECDH
`commonSecret = pointMul(theirPub + gv·G, myPriv + gv)` for point-to-point
bundle delivery. Distinct layer from semantos's paid-pubsub transport
([`cell_routing_paid_pubsub_not_risk`](memory)) — pubsub is transport,
spend-chain is record-keeping; they complement.

*SQL deep-dive 2026-06-02:* tea-package's
`migrations/0006_evid_audit_chain.sql` is the **production-shaped reference
for the chain primitive at the storage tier**. 73-line plpgsql BEFORE
INSERT trigger that:
- takes `pg_advisory_xact_lock(hashtext('audit_chain'), entity_id)` for
  single-writer-per-entity,
- asserts gap-free sequence (`seq == last_seq + 1`),
- asserts prev_hash linkage (or zero32 at genesis),
- recomputes `entry_hash = SHA-256(prev_hash || canonical_sha256)` and
  rejects on mismatch,
- plus an immutability trigger rejecting UPDATE/DELETE,
- plus `fn_verify_chain(entity_id)` walker returning the first broken seq
  or NULL.

Chain integrity enforced at the storage tier independent of the application
writer. Material implication: pair the L12 spend-chain primitive with a
sqlite-or-pg verification trigger so cell-mint history / hat lifecycle /
anchor history get tamper-detection even if the application layer is
bypassed.

Target:
`core/anchor-attestation/src/audit-chain/` (new) + `commonSecret` helper in
vendor-sdk. First consumers: mint-audit chain per cartridge (oddjobz
licensing, Bridget philanthropy donor trail), hat lifecycle, anchor-history
chain linking L5's batch anchors.

**L20 — M840 spectral mesh heuristics.** Pure reading task, single canon
doc. Apply the two-block theorem to Skyminer N=8 + brain-bridge link weight:
`λ₂(L) = nb` says algebraic connectivity (= convergence-rate ceiling on any
gossip/averaging) collapses linearly in the weakest cross-cut weight. Don't
spend on internal redundancy until cross-links are the right weight. Single
deliverable: `docs/canon/mesh-spectral-design.md`.

**L7 — Threshold Schnorr custody.** Useful for brain-quorum co-signing
(attestation co-sign, shared-UTXO operations in the PB primitive). Partial
sigs `s_j = k_j + e·λ_j·x_j`; key NEVER reconstructed. **Critical**:
preserve anchorchain's honest disclaimer verbatim — "not FROST-hardened for
concurrent sessions; sign one session at a time." Do not silently upgrade
the label.

**L10 — TEA primitives.** Sub-key derivation + ECDH affine-x → HKDF master
+ per-field commit `C = SHA256(K_field ‖ label ‖ value)` + bilateral
linkage tags. Complements BRC-42 (semantos already has Self-derivation);
TEA's pattern is the alternative shape for bilateral cross-binding. Port
the Rust impl (tea-bsv `crates/tea/`) to TS in
[`core/plexus-vendor-sdk/src/crypto.ts`](../../core/plexus-vendor-sdk/src/crypto.ts).

**L18 — 3-branch IF/ELSE FSM script pattern.** Reference pattern for any
cell that needs on-chain dispute resolution. All timing at tx-level via
`nLockTime` + `nSequence` ([`bsv_no_cltv_use_nlocktime`](memory)). Don't lift
cardtable's code (it hand-rolls BIP-143 instead of using `@bsv/sdk`); lift
the pattern into a canon doc. **2026-06-02 extension**: bsv-poker hardens
the pattern with a 109-byte branch-binding prefix
(`gid ‖ rulesetHash ‖ round ‖ stateHash ‖ actingSeat ‖ successorCommitment`)
on every locking script as anti-replay. Applies directly to the Tessera
wave generic mint path ([`tessera_wave_branch_state`](memory)).

**L24 — TEE-trait "key never leaves" + fail-closed SPV freshness.**
Architectural pattern, not a discrete module lift. Two parts:
(1) **Key never leaves** — a typed trait where `provisionKey(k): void`
exists but no method *returns* k. Type-level capability containment.
Stronger than runtime guards. Maps to
[`craig_no_keys_on_device_stance`](memory). (2) **Fail-closed SPV inside
the trust boundary** — any cell that needs a chain fact runs SPV itself
against a passed-in HeaderChain trust root; fails closed on
unreachability; rejects holder-asserted eligibility. Pairs with L22.
Lift = canon doc + cell-engine integration seam.

**L22 — Ed25519 device attestation + binding** *(closes brain-auth T7)*.
**Highest-impact new lift in the expansion.** Three domain separators:
`idattr-device/attestation/v1`, `binding/v1`, `device-cert/v1`. Wire
format is byte-stable; `tee-sim` (software) and `idattr-device` are
independently implemented but pinned to the same KAT bytes (Ed25519
determinism). Combined with the BRC-52 cert surface
([`brain_auth_model_intent`](memory) — Todd's intended design), this
gives cert + capability + freshness + hardware-pin in place of the
current bearer token. Brain-side TS verifier + Flutter shell
attestation backend + tee-sim sibling-process binary for dev. Preserve
the SIM banner discipline verbatim where the dev backend is used.

**L21 — Sigma-OR age-predicate ZK + sparse Merkle registry.** Two
primitives semantos lacks today. The age-predicate trick (verifier
recomputes `C_delta = threshold·G − C_birth` from issuer's commitment,
range-proves `delta ≥ 0`) is the exact shape for "entity allowed to do
X without revealing attribute value" — Plexus credential surface,
Bridget-philanthropy donor-eligibility, hat-based gates. Open choice:
(a) lift Ristretto sigma-OR directly (simpler, ~300 LOC, curve mismatch),
or (b) port anchorchain's secp256k1 Bulletproof via the agebridge
pattern (logarithmic, heavier, no curve mismatch). The sparse Merkle
(256-deep, empty-subtree precomputed, non-inclusion-as-revocation) is
the registry spine.

**L27 — Threshold ECDH (Lagrange-in-the-exponent).** Stronger than L7
(Schnorr) and stronger than anchorchain's Shamir-reconstruct: private
key d is NEVER reconstructed because Lagrange interpolation happens on
group elements, not scalars. Use for brain-quorum federated ECDH,
shared-UTXO ops in the PB primitive ([`pb_utxo_discovery_primitive`]
(memory)), encrypted-envelope handoff to an auditor. cto-bsv has it in
both TS and Go (byte-equal KATs). **License caveat**: cto-bsv is
UNLICENSED in tree — verify Craig's licensing intent before lift.

---

## §4. Tier 3 — priority 6-8 (opportunistic)

| # | Lift | Value | Ease | Prio | Notes |
|---|---|---|---|---|---|
| **L25** | **DFA-on-UTXO engine** | 3 | 3 | **9** | Generalises L18 — for cartridges needing title-transfer |
| **L23** | **Forward-revocable LKH + on-chain SPV anchor** | 4 | 2 | **8** | Blocked by L26 (path-dep pattern) |
| L3 | Bonded forfeiture channel construction | 4 | 2 | **8** | Blocked by L1, L2 |
| L6 | Pedersen + Bulletproof range proofs | 2 | 3 | **6** | Only if confidential amounts ever land |

**L25 — DFA-on-UTXO engine.** From triple-entry-bsv-sql (`services-go/edi/
dfa.go`, ~475 LOC Go). Generic state-machine substrate where each
transition spends prior UTXO + emits successor envelope with re-keyed
controller. Used in same repo for 22 EDI document DFAs + master
consignment DFA, all defined as JSON data (not code). Useful for
cartridges that need TRANSFERABLE RIGHTS (donation pledges, grant
entitlements, B/L-as-token). Don't unify with cell routing — keep
transferable-rights as separate mechanism. Generalises L18 (single-FSM
pattern → DFA registry).

**L23 — Forward-revocable LKH + on-chain SPV anchor.** From
revocable-nft-tee. `forward_revoke(prior, revoked)` builds new GB session
at `prior.index+1` for `members \ {revoked}`; `RevocationProof` =
`{revoked, session_index, rekey_txid}` SPV-verified against header chain.
HARD-revoke complement to semantos's existing soft-revoke
([`soft_revoke_folded_patches`](memory) — curator-signed marker). Forward
secrecy of PRIOR plaintext is NOT claimed (Statements A-D discipline).
Blocked by L26 because it consumes 5+ overlay-broadcast crates and needs
the path-dep pattern landed.

**L3.** The full channel + bond pattern. Lift only after L1 (netting) and L2
(watchtower) prove their value in semantos's relay context. Premature lift
risks committing to a payment-channel architecture semantos may not need.

**L6.** Anchorchain has a genuine 266-LOC Bulletproof inner-product impl.
Useful **only** if x402 / paid-pubsub / Bridget-philanthropy lands a real
confidential-balances requirement. Note: va (Rust) `legacy/` rejected this
same primitive on the grounds that "hidden-value cryptography is not audit
evidence." If semantos lifts L6, it should consciously side with anchorchain
over va on this philosophical point.

---

## §5. Tier 4 — skip / watch-list

| # | Lift | Why skip |
|---|---|---|
| L17 | LKH group broadcast encryption | Different mechanism (encryption, not routing). Skip. |
| L15 | GG20 threshold ECDSA | Multi-month lift, no current consumer. File-and-forget; revisit if PB primitive needs true non-custodial threshold ECDSA. |
| L16 | On-chain session-tx group lifecycle | No current consumer. Pattern (SIGHASH_SINGLE per member + SIGHASH_ALL for broadcaster) worth remembering if hat lifecycle ever goes on-chain. |
| L19 | Commit-reveal mental poker (Fisher-Yates) | Not collusion-resistant against last-revealer. If semantos ever ships card games, do real mental poker (commutative encryption) instead. |

### Re-scoring history

- **2026-06-01 (PR #790 follow-up, merged as #792)** — L11 and L12 moved
  out of the skip-list into Tier 2 after discussion. L11 was originally
  marked "duplicate of BRC-42" but the hierarchy is inverted: EP3259724B1
  is the PARENT primitive (`child = parent + H(segment) mod n`); BRC-42 is
  the bilateral specialisation (`segment = HMAC(ECDH-shared-secret, data)`).
  L12 was originally marked "conflicts with paid-pubsub" but that conflated
  transport (pubsub) with record-keeping (spend-chain); they sit at
  different layers and complement rather than compete. Both elevated under
  Todd's stance that CSW's patents are canonical for semantos.

- **2026-06-02 (this PR)** — Expansion audit of 8 substantive new
  prof-faustus repos published 2026-06-01 to 2026-06-02
  (identity-attribution, idattr-onchain, tee-sim, revocable-nft-tee,
  cto-bsv, bsv-poker, triple-entry-bsv-sql, tea-package; 3 stubs ignored:
  BitCoin, estates, nft-wallet-bsv). Added 7 new lifts:
  - L21 Sigma-OR ZK + sparse Merkle registry (Tier 2, prio 12)
  - **L22 Ed25519 device attestation + binding (Tier 2, prio 15)** —
    closes brain-auth gap T7 ([`brain_auth_model_intent`](memory))
  - L23 Forward-revocable LKH + on-chain SPV anchor (Tier 3, prio 8,
    blockedBy L26)
  - L24 TEE-trait "key never leaves" + fail-closed SPV freshness
    (Tier 2, prio 16)
  - L25 DFA-on-UTXO engine (Tier 3, prio 9)
  - **L26 Path-dep + pinned-rev cross-repo pattern (Tier 1, prio 25)** —
    closes parked `oss_substrate_carve_parked` direction
  - L27 Threshold ECDH via Lagrange-in-the-exponent (Tier 2, prio 12)

  Existing lifts updated with cross-references to expansion repos (no
  priority change): L7 (cf. L27 ECDSA-side), L8 + L9 (cf. triple-entry-
  bsv-sql ECDH-HMAC keystone shortcut), L13 (added `<root> OP_DROP <P2PKH>`
  third carrier option from idattr-onchain), L14 (added overclaim lint
  from revocable-nft-tee xtask), L18 (added 109-byte branch-binding
  prefix anti-replay from bsv-poker).

  Strategic-picture §1 expanded from 4 areas to 6 (added identity +
  attestation surface, confidential transferable objects + non-custodial
  threshold).

- **2026-06-02 (SQL deep-dive follow-up)** — The 2026-06-02 expansion
  audit characterised the SQL surface of triple-entry-bsv-sql and
  tea-package at the structural level but did not read either repo's
  SQL files directly. Corrections after a proper SQL deep-dive:
  - **Fact correction**: the "27 SQL migrations" attribution belonged
    to tea-package, NOT triple-entry-bsv-sql. The latter has only
    159 LOC of SQL across `001_te_schema.sql` + `002_demo.sql`.
  - **L8/L9 framing refined**: triple-entry-bsv-sql's PG layer is a
    transparent capture mechanism (5 tables + 1 trigger + query
    functions, no crypto in plpgsql). The load-bearing work is the
    Go writer + crypto-core ECDH-HMAC. Lift the Go; the SQL is
    optional adaptation.
  - **L12 augmented**: tea-package's `0006_evid_audit_chain.sql` is
    the production-shaped storage-tier reference for the chain
    primitive — 73-line BEFORE INSERT trigger that takes an advisory
    lock, asserts gap-free seq, recomputes prev_hash linkage and
    entry_hash, rejects on any mismatch. Plus `fn_verify_chain` walker.
    Material implication: pair L12 with a sqlite-or-pg verification
    trigger so the chain is tamper-detectable at the storage tier even
    if the application writer is bypassed.
  - **L14 augmented**: tea-package's `0027_prohibition_constraints.sql`
    adds a THIRD prohibition layer — a DB-resident plpgsql guard on
    `wallet.utxo` that rejects forbidden locking-script bytes at INSERT
    time by raw opcode matching. Combined model is now 3 (or 4)
    enforcement layers: CI-static + runtime-application + storage-tier
    + (optionally) network-adapter. Lift Layer 3 from this migration's
    pattern.
  - **L9 augmented**: tea-package's `0022_address_shared_ecdh.sql`
    shows a binding pattern worth absorbing — every SHARED_ECDH
    address must reference a `KEY_DERIVATION` canonical record that is
    already chained, enforced by trigger. Translates to: any L9
    envelope must reference an L12 chain row that exists, belongs to
    the same hat/entity, and is chained — checked at INSERT.

  No tier movements; matrix scores unchanged. Updates are textual
  augmentation of existing track notes + 4 roadmap-body sections.

- **2026-06-02 (this PR)** — L11 promoted Tier 2 → Tier 1, score
  bumped V=4/E=4/prio=16 → V=5/E=5/prio=25, joining L4/L5/L26 at the
  top. Todd's framing: "the BRC-42 stuff was just a bilateral
  arrangement" of CSW's underlying patent. Under CSW-canonical,
  EP3259724B1 is the foundation primitive and BRC-42 is its bilateral
  specialisation, not a separate primitive — the matrix should reflect
  that hierarchy with the foundation primitive at the bottom of the
  stack, not at Tier 2 alongside follow-on work it unblocks. Ships
  Week 1 alongside L4/L26/L14. Tier 1 grows from 8 to 9; Tier 2
  shrinks from 11 to 10. Strategic-picture §1 now leads area 4 with
  L11 explicitly framed as the foundation primitive and BRC-42 as
  the bilateral specialisation.

---

## §6. Cross-cutting hygiene

Three patterns to copy from prof-faustus's discipline regardless of which
individual lifts land:

1. **Honest crypto labelling.** Anchorchain refuses to call selective
   disclosure "ZK", Shamir-reconstruct "threshold ECDSA", Pedersen-commit-
   ledger "anonymous". When semantos adds privacy primitives, mirror this
   language discipline. The cost of an inflated label is a future security
   review that finds the gap and loses trust.
2. **Reproducible vectors with `reproduce.txt` committed evidence.**
   Anchorchain, va-bsv, va-chain, tea-bsv all commit golden vectors AND the
   output of regenerating them. Semantos has KAT discipline in the Zig
   substrate; extend it to anchor / disclosure / netting paths.
3. **Per-package CI gates.** va-bsv runs forbidden-token-scan → format-check
   → strict typecheck → tests → selftest → reproduce → store-study →
   assurance-study, in that order. Adopt the early-gate pattern at minimum
   (L14 is step one).

---

## §7. Attribution

All 10 source repos are MIT. Per-file attribution footer template:

```
// Adapted from prof-faustus/<repo>@<commit>, MIT.
// Original: <upstream-path>
// Mechanism unchanged unless noted; semantos-side adaptations: <list>.
```

The repos are by **Craig Wright** (per Todd's note 2026-06-01). Treat as a
serious external counterparty if semantos ever needs to engage on BSV-
substrate questions; the code quality and post-Genesis discipline are real.

---

## §8. Update protocol

Update the matrix cell whenever a lift advances on an axis. Render this
roadmap from the matrix via a future `docs/canon/render/cw-lift-to-roadmap.ts`
(parallel to the existing `matrix-to-roadmap.ts`); manual sync until that
renderer exists.

Source of truth for status: `docs/canon/cw-lift-matrix.yml`.
