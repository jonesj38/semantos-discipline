---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/cw-lift-matrix.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.626858+00:00
---

# docs/canon/cw-lift-matrix.yml

```yml
# The CW Lift Matrix — tracking artifact for lifting Craig Wright's
# `prof-faustus` external research repos into semantos-core.
#
# Scope: 10 public BSV-research repos audited 2026-06-01:
#   anchorchain, bonded-subsat-channel, cardtable, M840,
#   overlay-broadcast, triple-entry-evidence, triple-entry-evidence-bsv,
#   verifiable-accounting, verifiable-accounting-bsv,
#   verifiable-accounting-chain.
#
# Schema parallel to docs/canon/canonicalization-matrix.yml and
# docs/canon/singularity-matrix.yml.
#
# Companion roadmap: docs/prd/CW-LIFT-ROADMAP.md.
#
# Status legend:
#   ✓   — done / extracted / wired / verified at this stage
#   ⚠   — partial / in progress
#   ✗   — not started
#   n/a — not applicable on this (track, axis) pair
#
# Each track is one external mechanism considered for lift into semantos.
# Tracks are L1..L20 in source-repo grouping order; priority ordering
# (value × ease) is in the companion roadmap, not encoded in the track id.
#
# Per-track preamble fields:
#   id          — L<n>
#   name        — short label
#   source      — prof-faustus repo + canonical file path
#   target      — proposed semantos location (path may be new)
#   value       — strategic value to semantos, 1-5
#                 5 = closes a missing primitive semantos provably needs
#                 4 = strong improvement to an existing surface
#                 3 = useful adjacency, no current consumer
#                 2 = niche / future-only
#                 1 = different problem, file-and-forget
#   ease        — porting + integration ease, 1-5
#                 5 = small algorithm, drop-in
#                 4 = self-contained module, single-language rewrite
#                 3 = needs adapter layer + tests
#                 2 = heavy cross-language port or surface conflict
#                 1 = redesign-class
#   priority    — value × ease (rendered for sorting; NOT a deliverable
#                 sequence — see roadmap for ordering with deps)
#   blockedBy   — list of L-ids this lift requires
#   memory      — list of related auto-memory slugs (no [[link]] form
#                 here because this file isn't an auto-memory)
#
# Axis definitions (A..J) — stages each lift passes through:
#   A. Source identified       — exact upstream path(s) captured
#   B. Target chosen           — destination path in semantos picked,
#                                no surface conflict
#   C. License / attribution   — MIT noted, credit footer prepared
#   D. Mechanism understood    — protocol/algorithm fully grokked,
#                                edge cases enumerated
#   E. Ported                  — rewritten in target language / shape
#   F. Wired                   — imports + registry + dispatch hooked
#                                into semantos surface
#   G. Tests / vectors         — upstream golden vectors imported,
#                                semantos test suite green
#   H. Live verification       — exercised end-to-end in a semantos run
#                                (live brain, MNCA, cartridge, etc.)
#   I. Docs                    — canon doc / CLAUDE.md / README updated;
#                                memory entries written if applicable
#   J. Hardening               — forbidden-token lint pass, KAT pin
#                                vs upstream, no-regression on the
#                                surface this lift touches
#
# Deliverable IDs follow D-CW-{TrackID}-{Axis} (e.g. D-CW-L4-E).

tracks:
  # ─────────────────────────────────────────────────────────────────
  # bonded-subsat-channel cluster
  # ─────────────────────────────────────────────────────────────────
  - id: L1
    name: Q* sub-satoshi netting
    source: |
      prof-faustus/bonded-subsat-channel @ src/channel/accounting.py
      (Python). Channel state a = (a_1..a_n) in micro-units summing to
      k*S; on-chain settlement floor(a_i/k) + deterministic +1 to the
      top-R parties by a_i mod k (ties by smaller index). Provably
      0 ≤ R < n, sums to S.
    target: cartridges/shared/relay/q-star-netting.ts (new)
    value: 4
    ease: 5
    priority: 20
    blockedBy: []
    memory:
      - bsv_no_cltv_use_nlocktime
      - cell_routing_paid_pubsub_not_risk
    note: |
      Solves the sub-1-sat cell-routing-fee problem semantos hits at
      Skyminer scale: relays accumulate fractional credits between
      whole-sat on-chain settlements, with deterministic rounding.
      Pure-function algorithm, no protocol entanglement; easiest lift
      in the channel cluster.
    axes:
      A: { status: "✓", deliverable: D-CW-L1-A, note: "Path captured: src/channel/accounting.py" }
      B: { status: "✓", deliverable: D-CW-L1-B, note: "cartridges/shared/relay/q-star-netting.ts landed (lift/l1-q-star-netting, PR forthcoming)" }
      C: { status: "✓", deliverable: D-CW-L1-C, note: "MIT — attribution in file header (bonded-subsat-channel @ src/channel/accounting.py)" }
      D: { status: "✓", deliverable: D-CW-L1-D, note: "Algorithm ported: floor(a_i/k) + +1 to top-R parties by (a_i mod k DESC, index ASC). Bigint throughout for unbounded-scale safety. Conservation precondition enforced (sum(balances) === k*S)." }
      E: { status: "✓", deliverable: D-CW-L1-E, note: "Pure-function TS port: qStarNetting(input) -> { allocations, breakdown, remainderDistributed }. No protocol coupling." }
      F: { status: "⚠", deliverable: D-CW-L1-F, note: "Module exported. Wiring into cashlanes-bridge.ts deferred to follow-up (separate cartridge consumer change)." }
      G: { status: "✓", deliverable: D-CW-L1-G, note: "19/19 tests green: happy-path worked examples, tie-break by index, all 4 invariants asserted (conservation, R bounds, per-party error < 1, determinism). Property sweep: n∈[2,12]×k∈[1,16]×S∈[1,20] (7086 expect() calls) verifies 0 ≤ R < n. fail-closed precondition checks. Bigint correctness beyond Number.MAX_SAFE_INTEGER. 8-party Skyminer scenarios." }
      H: { status: "✗", deliverable: D-CW-L1-H, note: "Pending: live cell-routing relay accumulating fractional credits and triggering Q* settlement on threshold" }
      I: { status: "✗", deliverable: D-CW-L1-I, note: "Pending: docs/runbooks for sub-sat fee accumulation pattern" }
      J: { status: "⚠", deliverable: D-CW-L1-J, note: "Self-tests cover the algorithmic invariants. 9000-party scale-test from bonded-subsat-channel's test_scale.py not yet cross-checked — the algorithm is identical in shape (Python ↔ TS); would need bigint inputs that exercise the same scale." }

  - id: L2
    name: D14 custody-free watchtower
    source: |
      prof-faustus/bonded-subsat-channel @ src/channel/watchtower/
      tower.py + cluster.py. Tower signs nothing. Pre-signed forfeit
      tx pays the tower a fixed tower_fee in its FIRST output;
      counterparties sign SIGHASH_ALL|FORKID pinning the whole tx so
      tampering invalidates the multisig at the interpreter. Cluster
      = k independent watchers, single-spend rule picks one winner.
    target: |
      runtime/semantos-brain/src/federation/watchtower.ts (new) +
      cartridges/shared/relay/forfeit-template.ts (new)
    value: 5
    ease: 4
    priority: 20
    blockedBy: []
    memory:
      - craig_no_keys_on_device_stance
      - semantos_brain_single_threaded_reactor
    note: |
      Exact match for the Plexus brain-monitor role on device fleets:
      brain holds NO keys, only pre-signed-by-source forfeit txs;
      the SIGHASH-ALL pin makes broadcasting the exact bytes the only
      profitable move. Aligns 1:1 with Craig's "devices verify+act,
      wallets sign" rule. Mechanism is simple; the integration work is
      defining what semantos's "offender broadcasts stale state" trip
      condition is for a cell-relay context (likely: stale anchor
      attestation supersession).
    axes:
      A: { status: "✓", deliverable: D-CW-L2-A, note: "Paths captured: tower.py, cluster.py, registry, mempool observer" }
      B: { status: "✓", deliverable: D-CW-L2-B, note: "cartridges/shared/relay/forfeit-template.ts landed (lift/l2-watchtower, PR forthcoming). Brain-side mempool observer is runtime integration deferred to follow-up Zig PR." }
      C: { status: "✓", deliverable: D-CW-L2-C, note: "MIT — attribution in file header (bonded-subsat-channel watchtower module cited)" }
      D: { status: "✓", deliverable: D-CW-L2-D, note: "D14 incentive scheme: fee in vout 0 + SIGHASH_ALL pin → interpreter enforces honesty. Acting → fee; tampering → broadcast fails (script rejects); doing nothing → no fee." }
      E: { status: "✓", deliverable: D-CW-L2-E, note: "Primitive layer landed: ForfeitTemplate type, ChannelStateTx type, WatchtowerRegistry interface, MempoolObservation type, detectStaleState (pure function), assertD14Incentive (5 fail-closed checks), InMemoryWatchtowerRegistry reference impl." }
      F: { status: "⚠", deliverable: D-CW-L2-F, note: "Cartridge-side primitive complete. Brain mempool observer + actual tx broadcasting is runtime integration (Zig); separate PR pending." }
      G: { status: "✓", deliverable: D-CW-L2-G, note: "18/18 tests pass: registry round-trip + supersession + channel-isolation + null-on-unregistered; detectStaleState across 4 branches (stale/equal/newer/unregistered) + defensive cross-channel reject; assertD14Incentive happy path + 3 fail-closed axes (TOWER_ADDRESS_MISMATCH, TOWER_FEE_MISMATCH, INSUFFICIENT_SIGNERS) + quorum-superset; end-to-end primitive composition." }
      H: { status: "✗", deliverable: D-CW-L2-H, note: "Pending: live brain mempool observer + tx-broadcast wiring + first real channel registration. Pairs with L3 (bonded channel construction)." }
      I: { status: "✗", deliverable: D-CW-L2-I, note: "Pending: docs/runbooks/D14-WATCHTOWER.md explaining the incentive model + registration flow + cluster-mode (Cluster impl from bonded-subsat-channel)" }
      J: { status: "⚠", deliverable: D-CW-L2-J, note: "Self-tests cover D14 incentive validation invariants. SIGHASH_ALL verification is wallet-layer responsibility (this primitive trusts the caller's verified signer set); cluster-mode (k watchers, single-spend rule) deferred to follow-up." }

  - id: L3
    name: Bonded forfeiture channel construction
    source: |
      prof-faustus/bonded-subsat-channel @ src/channel/scripts.py
      + lifecycle.py + bond.py. Funding tx has n+1 outputs: vout 0 =
      n-of-n CMS of value S, vouts 1..n = bond outputs with IF/ELSE
      script (owner cooperative-return vs counterparties forfeiture).
    target: |
      cartridges/shared/relay/bonded-channel/ (new package)
    value: 4
    ease: 2
    priority: 8
    blockedBy: [L1, L2]
    memory:
      - bsv_no_cltv_use_nlocktime
    note: |
      The full channel + bond pattern. Significant change to semantos's
      payment surface (MFP / cashlanes today don't model bonds).
      Worth lifting only after L1 (netting) and L2 (watchtower) prove
      their value in semantos's relay context. Otherwise risks
      premature commitment to a payment-channel architecture
      semantos may not need.
    axes:
      A: { status: "✓", deliverable: D-CW-L3-A }
      B: { status: "✗", deliverable: D-CW-L3-B }
      C: { status: "✗", deliverable: D-CW-L3-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L3-D, note: "n+1 funding outputs, IF=owner-return / ELSE=counterparty-forfeit; lifecycle = open/transfer/coop-close/contested" }
      E: { status: "✗", deliverable: D-CW-L3-E }
      F: { status: "✗", deliverable: D-CW-L3-F }
      G: { status: "✗", deliverable: D-CW-L3-G }
      H: { status: "✗", deliverable: D-CW-L3-H }
      I: { status: "✗", deliverable: D-CW-L3-I }
      J: { status: "✗", deliverable: D-CW-L3-J }

  # ─────────────────────────────────────────────────────────────────
  # anchorchain cluster
  # ─────────────────────────────────────────────────────────────────
  - id: L4
    name: Two-tree SPV verify composition
    source: |
      prof-faustus/anchorchain @ packages/api/src/service.ts
      `AnchorChainService.verifyInclusion`. Four explicit steps:
      (1) memory-leaf → batch-root via lower Merkle path,
      (2) batch-root parsed from anchor tx OP_RETURN,
      (3) anchor txid → block Merkle root via supplied branch,
      (4) block-root vs header chain at height.
    target: |
      core/anchor-attestation/src/verify-inclusion.ts (new) — composes
      the existing pieces in core/anchor-attestation/operations.ts +
      core/protocol-types/zig/bsv/spv_verify.zig into ONE call.
    value: 5
    ease: 5
    priority: 25
    blockedBy: []
    memory:
      - mnca_anchor_onchain_mainnet
      - cell_wire_format_location
    note: |
      Semantos has every piece — the BRC-10 BUMP proof, the SPV intent
      wire format, the anchor attestation schema v2 — but split across
      three modules. Anchorchain's `verifyInclusion` is a single
      composed call. Highest-value low-effort lift in the matrix:
      cleans up MNCA verify path without inventing anything new.
    axes:
      A: { status: "✓", deliverable: D-CW-L4-A }
      B: { status: "✓", deliverable: D-CW-L4-B, note: "core/anchor-attestation/src/verify-inclusion.ts landed (lift/l4-spv-verify-composition, PR forthcoming)" }
      C: { status: "✓", deliverable: D-CW-L4-C, note: "MIT — attribution in file header doc-comment" }
      D: { status: "✓", deliverable: D-CW-L4-D, note: "4-stage composition: attestation (verifyAnchor) → txid_binding (leaf==attestation.txid) → merkle (proof.root==expected + verifyMerkleProof) → block_hash (optional caller-supplied HeaderChain assertion). Each fail-closed with stage label." }
      E: { status: "✓", deliverable: D-CW-L4-E, note: "verifyInclusion composes existing pieces; no new mechanism" }
      F: { status: "✓", deliverable: D-CW-L4-F, note: "Survey 2026-06-02 (#823): ZERO existing call sites do the manual 3-call dance against the new AnchorAttestation (RM-042) schema. Legacy bsv-anchor-adapter operates on AnchorProof shape, requires RM-042 migration. First HIGHER-LEVEL CONSUMER landed 2026-06-02 (lift/mnca-verify-inclusion-consumer): core/anchor-attestation/src/verify-against-chain.ts ships verifyAnchorAttestationInclusion + TrustedHeaderChain interface + InMemoryHeaderChain reference impl. Wraps verifyInclusion with a chain-backed assertHeaderChainContainsBlock callback so wallets/brain/indexers get a one-call verifier instead of having to wire the chain lookup themselves." }
      G: { status: "✓", deliverable: D-CW-L4-G, note: "10/10 tests green covering happy path + each fail-closed stage (TARGET_MISMATCH, PAYLOAD_ROOT_MISMATCH, TXID_LEAF_MISMATCH, MERKLE_ROOT_MISMATCH, MERKLE_PATH_INVALID, HEADER_CHAIN_REJECTED). 21/21 pass for whole anchor-attestation suite (no regression)." }
      H: { status: "✓", deliverable: D-CW-L4-H, note: "End-to-end verifier demonstrated through verifyAnchorAttestationInclusion: 14 tests covering happy-path (chain + attestation + merkle + block_hash) + every fail-closed stage of the wrapper (HEADER_NOT_IN_CHAIN, HEADER_CHAIN_LOOKUP_FAILED, MERKLE_ROOT_MISMATCH when chain returns mismatched root, TARGET_MISMATCH/PAYLOAD_ROOT_MISMATCH propagation from stage 1, async TrustedHeaderChain Promise<BlockHeader|null> handling). Pattern is the natural entry point for live mainnet anchor verify (re-verify of 5d592c26… and 5ab00c65… from the runbook's PR-8b-x proof-of-execution would just need a fixture-loaded TrustedHeaderChain with the right block heights from WhatsOnChain)." }
      I: { status: "✗", deliverable: D-CW-L4-I, note: "Pending: update docs/runbooks/MNCA-ANCHOR-REAL-TXID with the composed verify path" }
      J: { status: "⚠", deliverable: D-CW-L4-J, note: "Pure-function composition; no forbidden-token surface. Anchorchain repro_v1.json cross-check pending (semantos's per-cell shape differs from anchorchain's per-batch; vector mapping needed)." }

  - id: L5
    name: Per-batchId idempotent anchoring
    source: |
      prof-faustus/anchorchain @ packages/anchor/src/index.ts
      `Anchorer.anchorBatch()`. Second call with the same batchId
      returns the existing manifest rather than emitting a duplicate
      transaction. Manifest = {txid, root, leafCount, batchId, blob}.
    target: |
      cartridges/bsv-anchor-bundle/brain/src/anchorer.ts (new) +
      core/anchor-attestation/src/idempotency.ts (new)
    value: 5
    ease: 5
    priority: 25
    blockedBy: []
    memory:
      - mnca_anchor_onchain_mainnet
    note: |
      Today MNCA anchoring is per-cell. Adding a per-batch idempotency
      layer with a deterministic batchId derived from (cell roots +
      logical-time interval) lets one anchor tx commit many cells,
      cheaper at scale, and prevents accidental double-anchors on
      retry. Small wrapper around the existing anchor path.
    axes:
      A: { status: "✓", deliverable: D-CW-L5-A }
      B: { status: "✓", deliverable: D-CW-L5-B, note: "core/anchor-attestation/src/idempotency.ts landed (lift/l5-idempotent-anchor, PR forthcoming). Cartridge wiring (cartridges/bsv-anchor-bundle/brain/src/anchorer.ts) deferred to follow-up." }
      C: { status: "✓", deliverable: D-CW-L5-C, note: "MIT — attribution in file header doc-comment (anchorchain analogue cited)" }
      D: { status: "✓", deliverable: D-CW-L5-D, note: "batchId = SHA-256('semantos.anchor.batch/v1' || varint(|window|) || window || varint(N) || sortedRoot_0..N-1). Domain-separator + sorted-roots → idempotent; window scopes batches in logical time." }
      E: { status: "✓", deliverable: D-CW-L5-E, note: "Primitives + InMemoryAnchorStore landed: computeBatchId, sortCellRoots, requestAnchor, IdempotentAnchorStore interface" }
      F: { status: "✓", deliverable: D-CW-L5-F, note: "Cartridge consumer wiring landed 2026-06-02 (lift/anchor-bundle-l5-consumer): cartridges/bsv-anchor-bundle/brain/src/idempotent-batch-anchorer.ts ships IdempotentBatchAnchorer that wraps any AnchorAdapter with L5's requestAnchor + IdempotentAnchorStore. Same (cellRoots, window) twice → same manifest + same AnchorProof[] without re-broadcasting. Failed-not-cached contract preserved; AnchorProof[] reconstituted from manifest.attestationPayload on cache hit." }
      G: { status: "✓", deliverable: D-CW-L5-G, note: "16/16 tests green: sortCellRoots invariants, computeBatchId determinism + domain separation + window scoping + empty-input rejection + KAT pin (bfbaf7ec...) + requestAnchor cached-vs-fresh paths + failed-not-cached + listByStatus" }
      H: { status: "✓", deliverable: D-CW-L5-H, note: "End-to-end demonstrated via 9 tests: cache miss + persist; cache hit (no second inner call) with proof-array reconstitution; reordered cellRoots → same batchId; distinct windows → distinct manifests; failure paths (inner throw + empty proofs); proofs returned from cache carry all fields needed for downstream L4 verifyInclusion / verifyAnchorAttestationInclusion (#835). 60/60 across anchor-attestation + bsv-anchor-bundle suites — zero regression." }
      I: { status: "✗", deliverable: D-CW-L5-I, note: "Pending: docs/runbooks update for batch-anchor flow" }
      J: { status: "⚠", deliverable: D-CW-L5-J, note: "Self-KAT pin in tests (wire format frozen at bfbaf7ec...). Anchorchain cross-check pending — semantos's per-batch shape differs slightly from anchorchain's so vector mapping needed." }

  - id: L6
    name: Pedersen credit ledger + Bulletproof range proofs
    source: |
      prof-faustus/anchorchain @ packages/credit/src/index.ts +
      packages/privacy/src/bulletproofs.ts (266 LOC, real
      inner-product argument, 16 group elements @ 64 bits).
      C(v,r) = v·G + r·H; debit = (newCommitment, Schnorr
      conservation proof old = new + amount·G, range proof on new).
    target: |
      core/protocol-types/src/privacy/ (new package — bulletproofs +
      pedersen + schnorr-conservation) + cartridges/shared/credit/
    value: 2
    ease: 3
    priority: 6
    blockedBy: []
    memory:
      - cell_routing_paid_pubsub_not_risk
    note: |
      Semantos has no confidential-amounts requirement yet. Worth
      lifting only if x402 / paid-pubsub / Bridget-philanthropy flows
      land a real need for hidden balances. Note: the va (Rust)
      `legacy/` rejected the same Bulletproofs path on philosophical
      grounds ("hidden-value cryptography is not audit evidence") —
      semantos's call whether to follow anchorchain (keeps Pedersen)
      or va-bsv (rejects it).
    axes:
      A: { status: "✓", deliverable: D-CW-L6-A }
      B: { status: "✗", deliverable: D-CW-L6-B }
      C: { status: "✗", deliverable: D-CW-L6-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L6-D }
      E: { status: "✗", deliverable: D-CW-L6-E }
      F: { status: "✗", deliverable: D-CW-L6-F }
      G: { status: "✗", deliverable: D-CW-L6-G, note: "Anchorchain has deterministic-size + live-timing benches in BENCHMARKS.md" }
      H: { status: "✗", deliverable: D-CW-L6-H }
      I: { status: "✗", deliverable: D-CW-L6-I }
      J: { status: "✗", deliverable: D-CW-L6-J }

  - id: L7
    name: Threshold Schnorr custody (honest disclaimer)
    source: |
      prof-faustus/anchorchain @ packages/custody/src/
      thresholdschnorr.ts. Partial sigs s_j = k_j + e·λ_j·x_j
      aggregated over commitment-then-reveal nonce protocol. The
      key is NEVER reconstructed. Explicitly labelled "not FROST-
      hardened for concurrent sessions; sign one session at a time."
    target: |
      runtime/semantos-brain/src/federation/threshold-schnorr.ts (new)
    value: 4
    ease: 3
    priority: 12
    blockedBy: []
    memory:
      - pb_utxo_discovery_primitive
      - semantos_federation_transport
    note: |
      Useful for brain-quorum co-signing (e.g. attestation co-sign,
      shared-UTXO operations in the PB primitive). The disclaimer is
      load-bearing: do NOT silently upgrade this label to "threshold
      ECDSA" or "FROST" — anchorchain's discipline of honest crypto
      labelling is the model to copy.

      2026-06-02 cross-ref: L27 (threshold ECDH via Lagrange-in-the-
      exponent, from cto-bsv) is the ECDSA-curve-side relative for
      non-custodial threshold operations. L7 = Schnorr-shaped; L27 =
      ECDH-shaped; L15 = full GG20 threshold ECDSA-signing (heaviest).
      Use L7 for brain-side Schnorr co-sign, L27 for ECDH ops where
      key reconstruction would be a security violation.
    axes:
      A: { status: "✓", deliverable: D-CW-L7-A }
      B: { status: "✗", deliverable: D-CW-L7-B }
      C: { status: "✗", deliverable: D-CW-L7-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L7-D }
      E: { status: "✗", deliverable: D-CW-L7-E }
      F: { status: "✗", deliverable: D-CW-L7-F }
      G: { status: "✗", deliverable: D-CW-L7-G }
      H: { status: "✗", deliverable: D-CW-L7-H }
      I: { status: "✗", deliverable: D-CW-L7-I, note: "Preserve the 'not FROST-hardened, sign one session at a time' caveat verbatim" }
      J: { status: "✗", deliverable: D-CW-L7-J }

  # ─────────────────────────────────────────────────────────────────
  # verifiable-accounting / TEA cluster
  # ─────────────────────────────────────────────────────────────────
  - id: L8
    name: Per-field intra-tx Merkle tree
    source: |
      prof-faustus/verifiable-accounting-bsv @ packages/evidence/src/
      fieldtree.ts. Each field of an accounting record is a leaf in
      an intra-transaction Merkle tree with "VARP" magic + schema.
      Root carried via OP_FALSE OP_IF <push> OP_ENDIF envelope
      (see L13). Selective disclosure = release one field + path.
    target: |
      core/protocol-types/src/field-tree/ (new) — analog of
      anchor-attestation but per-field instead of per-cell-payload.
    value: 5
    ease: 4
    priority: 20
    blockedBy: []
    memory:
      - cell_is_the_wire_format
      - cell_wire_format_location
    note: |
      Semantos has no per-field selective disclosure surface today.
      Useful for any cell that needs to expose ONE field to a verifier
      without revealing the rest of the cell payload — likely future
      Traceport / Bridget-philanthropy / brem-cartridge use cases.
      Adapter shape: the cell remains the 1024-byte wire-format unit;
      the field-tree commits to fields within the cell payload.
      Does NOT replace cell-pushdrop; complements it.

      2026-06-02 cross-ref: triple-entry-bsv-sql's `crypto-core/`
      ECDH-HMAC keystone (~600 LOC Go, byte-exact Go+TS+C parity,
      KAT-pinned) is a WORKING IMPLEMENTATION of the per-field commit +
      counterparty-derivable shape. Could shortcut the port — lift
      crypto-core's M(c)→GV→CS→K_hmac→tag pipeline directly instead of
      reimplementing fieldtree.ts.

      2026-06-02 SQL deep-dive (post-#802): triple-entry-bsv-sql's PG
      surface is small and transparent — 159 LOC across one schema
      file (5 tables + 1 trigger + 1 installer + 2 query functions).
      The PG layer is JUST a capture mechanism (AFTER trigger writes
      one outbox row per changed column, atomic with commit); it does
      no crypto (plpgsql can't do secp256k1). The load-bearing work is
      the Go writer drainage + crypto-core ECDH-HMAC. So: lift Go
      crypto-core, optionally adapt the trigger+outbox pattern to
      semantos's storage tier, but the SQL is not where the IP lives.
    axes:
      A: { status: "✓", deliverable: D-CW-L8-A }
      B: { status: "✓", deliverable: D-CW-L8-B, note: "core/protocol-types/src/field-tree/index.ts landed (lift/l8-field-tree, PR forthcoming)" }
      C: { status: "✓", deliverable: D-CW-L8-C, note: "MIT — attribution in file header (va-bsv + triple-entry-bsv-sql cited)" }
      D: { status: "✓", deliverable: D-CW-L8-D, note: "Per-field SHA-256 leaves with domain separator + magic + version + schema-fingerprint binding. Canonical lex-ascending sort by label. Duplicate labels rejected, empty trees rejected." }
      E: { status: "✓", deliverable: D-CW-L8-E, note: "Primitives landed: computeFieldLeaf, buildFieldTree, discloseField, verifyFieldDisclosure, FIELD_TREE_MAGIC/VERSION/DOMAIN constants." }
      F: { status: "✓", deliverable: D-CW-L8-F, note: "TWO consumers landed 2026-06-02: (1) oddjobz cartridge — cartridges/oddjobz/brain/src/cell-types/field-tree-adapter.ts ships buildCellFieldTree/disclose/verify on CellTypeDef. Worked example: invoice cell disclosure without leaking customer PII. (2) tessera cartridge (lift/tessera-l8-l11-consumers) — cartridges/tessera/brain/src/field-tree-adapter.ts ships the parallel surface for tessera's opaque-JSON bodies. schemaFingerprint computed via SHA-256(\"tessera.cell-type/v1/\" + cellType) since tessera doesn't use CellTypeDef. Worked examples: bottle cell consumer/retailer scenarios + care-event auditor disclosure. PASSES tessera's strict adapter-consumption gate (no @bsv/sdk, no @plexus/vendor-sdk; only @semantos/protocol-types/field-tree)." }
      G: { status: "✓", deliverable: D-CW-L8-G, note: "24/24 protocol-types + 13/13 oddjobz adapter + 15/15 tessera adapter tests (incl. bottle producer/consumer/retailer disclosure scenarios, care-event auditor disclosure, cross-cell-type binding privacy invariant, fail-closed across 5 axes). All disclosure proofs verify that undisclosed fields (cost_basis, internal_sku, distributor_margin) appear in NEITHER plaintext NOR hex form in the disclosed proof body." }
      H: { status: "✓", deliverable: D-CW-L8-H, note: "Two cartridges integrated end-to-end with zero regression. oddjobz: 181/181 cell-types + state-machines green. tessera: 28/28 across all tessera tests + adapter-consumption gate. Both pattern variants documented — CellTypeDef-bound (oddjobz) for cartridges with typed cell schemas; opaque-JSON-with-cellType-key (tessera) for greenfield-discipline cartridges that don't import @bsv/sdk." }
      I: { status: "✗", deliverable: D-CW-L8-I, note: "Pending: cross-ref from cellHeader.domainPayloadRoot docs explaining when to use field-tree root vs whole-payload SHA-256" }
      J: { status: "⚠", deliverable: D-CW-L8-J, note: "Self-KAT pin in tests (wire format frozen). Anchorchain shard.ts proof-sharding cross-check pending — semantos's per-field tree is the simpler primitive; sharding is a separate concern." }

  - id: L9
    name: Scoped-disclosure signed envelope
    source: |
      prof-faustus/triple-entry-evidence-bsv @ crates/disclosure/src/
      lib.rs. Envelope binds note_id ‖ field_label ‖ H(K_field) ‖
      verifier_id ‖ engagement_id ‖ purpose ‖ expiry ‖ nonce.
      Releases ONE field key to ONE verifier with expiry.
    target: |
      core/protocol-types/src/disclosure/ (new) — complement to L8.
    value: 4
    ease: 4
    priority: 16
    blockedBy: [L8]
    memory:
      - shell_cartridges_hats_model
    note: |
      Natural complement to the field-tree (L8): the field-tree commits
      to fields; the envelope authorises disclosure of a specific field
      key to a specific verifier for a specific purpose with an expiry.
      Maps onto the hat-context model: a hat-scoped envelope can release
      tenant-specific fields without exposing cross-tenant data.

      2026-06-02 cross-ref: triple-entry-bsv-sql implements the same
      shape via ECDH-HMAC (counterparty derives K_hmac from shared
      secret + commit-style change_image). Same shortcut consideration
      as L8 — could lift the working implementation rather than port
      from spec.

      2026-06-02 SQL deep-dive (post-#802): the disclosure binding
      itself stays a crypto-core concern (not PG). What the SQL adds
      is enforced-at-storage integrity: tea-package's
      `0022_address_shared_ecdh.sql` requires every SHARED_ECDH
      address to reference a KEY_DERIVATION canonical record that is
      already chained in `evid.audit_chain`, enforced by trigger —
      makes it impossible to persist an unrooted ECDH address. That
      pattern (envelope or commitment references audit-chain row,
      checked at INSERT) is worth absorbing if/when L9 lands.
    axes:
      A: { status: "✓", deliverable: D-CW-L9-A }
      B: { status: "✓", deliverable: D-CW-L9-B, note: "core/protocol-types/src/disclosure/ landed (lift/disclosure-envelope-l9). Subpath export @semantos/protocol-types/disclosure added." }
      C: { status: "✓", deliverable: D-CW-L9-C, note: "MIT — attribution in file header (tea-bsv crates/disclosure/src/lib.rs cited)" }
      D: { status: "✓", deliverable: D-CW-L9-D, note: "8-tuple binding (noteId 32B, fieldLabel utf-8, leafCommitment 32B = L8 leaf hash, verifierId 33B SEC1 compressed pubkey, engagementId 32B, purpose utf-8, expiry u64 BE, nonce 16B). Canonical preimage: 'L9DS' magic + version + domain separator + varint-prefixed fields + u64 BE expiry." }
      E: { status: "✓", deliverable: D-CW-L9-E, note: "Primitives landed: DisclosureEnvelope + SignedDisclosureEnvelope types, ENVELOPE_MAGIC/VERSION/DOMAIN constants, canonicalDisclosureEnvelopePreimage (signature-agnostic preimage builder), signDisclosureEnvelope (default ECDSA via @bsv/sdk), verifyDisclosureEnvelope (sig + expiry + verifier-id + optional leaf-commitment pin)." }
      F: { status: "⚠", deliverable: D-CW-L9-F, note: "API exported via subpath. First consumer adopting envelope-issuance for a real cell (e.g. oddjobz invoice / tessera bottle auditor flow) is the next step — composes naturally with the existing L8 adapters from #827 + #832." }
      G: { status: "✓", deliverable: D-CW-L9-G, note: "17/17 tests pass: preimage determinism + 'L9DS' magic + 'every field affects preimage' invariant + size-field validation; sign/verify round-trip + non-trivial DER signature; fail-closed on VERIFIER_MISMATCH + EXPIRED (boundary) + LEAF_COMMITMENT_MISMATCH + INVALID_VERIFIER_PUBKEY (3 variants) + INVALID_SIGNATURE (tampered envelope) + INVALID_SIGNATURE (tampered sig bytes) + INVALID_SIGNATURE (foreign issuer pubkey)." }
      H: { status: "✓", deliverable: D-CW-L9-H, note: "End-to-end with L8 demonstrated: producer signs envelope binding a field-tree leaf commitment; auditor verifies envelope (L9) AND field-tree proof (L8) AND that the proof leaf matches the envelope binding. Cross-check rejection — auditor fed a proof of `memo` under an envelope authorising `amount` is rejected via LEAF_COMMITMENT_MISMATCH (the L8 ∘ L9 pin)." }
      I: { status: "✗", deliverable: D-CW-L9-I, note: "Pending: cartridge adoption — oddjobz invoice auditor flow + tessera bottle consumer scan flow are the natural first consumers (both already use L8 via #827/#832)." }
      J: { status: "⚠", deliverable: D-CW-L9-J, note: "Self-tests cover all sign/verify axes + L9 ∘ L8 composition. Wire-format KAT pin (single fixed-input preimage hex) pending; tea-bsv cross-vector check pending." }

  - id: L10
    name: TEA primitives — sub-keys + ECDH linkage tags
    source: |
      prof-faustus/triple-entry-evidence (Python) @ refimpl.py +
      triple-entry-evidence-bsv (Rust) @ crates/tea/src/lib.rs.
      Sub-key derivation, ECDH affine-x → HKDF master key,
      per-field commit C = SHA256(K_field ‖ label ‖ value),
      K_field = HKDF-Expand(K_master, "commit" ‖ note_id ‖ label),
      bilateral linkage tags L_inv, L_pay cross-binding two notes.
    target: |
      core/plexus-vendor-sdk/src/crypto.ts (extend) — add HKDF
      sub-key derivation alongside the existing BRC-42 deriveChildKey.
    value: 3
    ease: 4
    priority: 12
    blockedBy: []
    memory:
      - mnca_anchor_onchain_mainnet
    note: |
      Semantos already has BRC-42 (Self-derivation) via deriveEdgeSk +
      ecdh42.ts. TEA's sub-key + linkage-tag pattern is an alternative
      / complementary shape for bilateral cross-binding (e.g. linking
      an outgoing cell to its inbound counterpart). The Rust impl is
      the reference; port to TS in the vendor-sdk.
    axes:
      A: { status: "✓", deliverable: D-CW-L10-A }
      B: { status: "✗", deliverable: D-CW-L10-B }
      C: { status: "✗", deliverable: D-CW-L10-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L10-D }
      E: { status: "✗", deliverable: D-CW-L10-E }
      F: { status: "✗", deliverable: D-CW-L10-F }
      G: { status: "✗", deliverable: D-CW-L10-G, note: "tea-py + tea-bsv both have deterministic worked-example vectors" }
      H: { status: "✗", deliverable: D-CW-L10-H }
      I: { status: "✗", deliverable: D-CW-L10-I }
      J: { status: "✗", deliverable: D-CW-L10-J }

  - id: L11
    name: EP3259724B1 base derivation — foundation primitive (BRC-42 = bilateral case)
    source: |
      prof-faustus/verifiable-accounting-chain @ packages/keys/src/
      derive.ts (+ hierarchy.ts, sign.ts). child = parent + H(segment)
      mod n; matching pubkey side via point-add. Patent refs:
      EP3259724B1, EP3420669B1. `segment` is arbitrary input (path
      string, account label, counter, an HMAC output, anything) — the
      primitive is unilateral; bilateral binding is achieved by
      choosing `segment = HMAC(ECDH-shared-secret, data)` (which is
      what BRC-42 happens to be).
    target: |
      core/plexus-vendor-sdk/src/crypto.ts (extend) — add `deriveSegment`
      as the BASE primitive. Refactor existing `deriveChildKey` (BRC-42)
      as a one-line composition:
        deriveChildKey(parent, shared, data) =
          deriveSegment(parent, HMAC(shared, data))
      Existing BRC-42 call sites unchanged at signature level.
      Update docs/canon/brc-mapping.yml to reflect the canonical
      hierarchy (EP3259724B1 = base, BRC-42 = the bilateral
      specialisation that semantos happened to lift first).
    value: 5
    ease: 5
    priority: 25
    blockedBy: []
    memory:
      - mnca_anchor_onchain_mainnet
      - brain_auth_model_intent
    note: |
      RE-SCORED 2026-06-02 (this PR) — promoted Tier 2 → Tier 1
      (priority 16 → 25).

      Todd's framing (2026-06-02): "the BRC-42 stuff was just a
      bilateral arrangement" of CSW's underlying patent. Under the
      stance that CSW's patents are canonical for semantos, the
      foundation primitive is EP3259724B1 and what semantos ships
      today is a bilateral specialisation of it — not a separate
      primitive. The matrix should reflect that hierarchy.

      Framing (corrected):
        EP3259724B1 (foundation):  child = parent + H(segment) mod n
                                    where `segment` = any input
        BRC-42 (specialisation):    child = parent +
                                            HMAC(ECDH-shared-secret, data)
                                            mod n
                                    (i.e. EP3259724B1 with
                                     segment = HMAC(shared, data))

      So semantos doesn't have "two primitives" with one missing — it
      has ONE primitive (Craig's), with only the bilateral specialisation
      surfaced. Wherever an internal key tree is needed today (operator
      cell-tree, hat-internal keys, cartridge-local paths) we either
      pretend BRC-42 applies with a degenerate ECDH or hand-roll —
      both are debt that this lift retires.

      Why Tier 1 (V=5, E=5):
        - Value=5: foundation-level. Every key derivation in semantos
          eventually flows through this primitive. The L11 lift puts
          the right primitive at the bottom of the stack; everything
          else (L9, L10, L12, L22, L23, L27) builds cleanly on top.
        - Ease=5: ~30 LOC of TS for `deriveSegment` (point-add of a
          hashed scalar); refactoring `deriveChildKey` as a
          composition is a one-line change; canon doc update is
          mechanical; KAT pin against va-chain `chain_v1.json` is
          one test. No breaking changes — existing BRC-42 callers
          continue working unchanged.

      Unblocks L12 (linkPub is derived via this primitive) and
      simplifies L10 (TEA sub-keys are an HKDF-shaped segment).
      Order in §2.1 sequence: ship in Week 1 alongside L26/L14/L4.
    axes:
      A: { status: "✓", deliverable: D-CW-L11-A, note: "Path: packages/keys/src/derive.ts + hierarchy.ts + sign.ts" }
      B: { status: "✓", deliverable: D-CW-L11-B, note: "Extended core/plexus-vendor-sdk/src/crypto.ts with deriveSegment + deriveScalar (lift/l11-derive-segment, PR forthcoming)" }
      C: { status: "✓", deliverable: D-CW-L11-C, note: "MIT — attribution in crypto.ts header doc-comments" }
      D: { status: "✓", deliverable: D-CW-L11-D, note: "child = parent + SHA-256(segment) mod n via @bsv/sdk BigNumber + Curve.n; pubkey side matches via point-add. CORROBORATED 2026-06-06 by bsv-universal-sdk (L28 repo): its pay-to-contract `P' = P + H(tag || m)·G` independently re-derives this same tweak from a clean-room spec with no BRC/EP citations. DIVERGENCE → OPEN DESIGN QUESTION (full writeup: docs/canon/domainflag-tag-unification.md): their construction takes an explicit `tag` (domain separator) as a SECOND hash input; our deriveSegment (core/plexus-vendor-sdk/src/crypto.ts:49) takes a single `segment` with the domain embedded textually (e.g. cell-anchor.ts segment = protocolHash(16)‖anchorIndex_le8(8); tessera = `tessera/<cellType>/<role>`). Meanwhile semantos ALREADY has a first-class u32 `domainFlag` namespace — canonical source core/constants/constants.json → generated into core/cell-engine/src/constants.zig (per merged deliverable D-Const-domainflag-genfix), stored in the cell header, asserted at runtime by OP_CHECKDOMAINFLAG (0xC6, failure-atomic), formally proven by proofs/lean DomainIsolationK3. So the SDK's `tag` === our domainFlag, except domainFlag is the RICHER version (enforced at-rest + at-runtime + proven), and it is currently NOT folded into the deriveSegment tweak — the segment strings are a SECOND, parallel encoding. UNIFICATION staged in the design doc: Stage 0 (single registry source = constants.json) DONE via D-Const-domainflag-genfix; Stage 1 (TS/segment authors reference the registry) = scoped; Stage 2 'L11.5' (bind the flag into the tweak `H(domainFlag ‖ segment)`) = a key-changing cutover, deferred deliberately with the same KAT + clean-cutover discipline L11 used. Semantic caveat: the SDK's `m` is a contract commitment, our segment is a hierarchical path — the tag role maps, the commitment role does not; don't over-unify." }
      E: { status: "✓", deliverable: D-CW-L11-E, note: "Two primitives landed: deriveSegment (string/Uint8Array→SHA-256→scalar-add) and deriveScalar (raw 32-byte→scalar-add). deriveChildKey kept as @bsv/sdk delegate; equivalence asserted in tests" }
      F: { status: "✓", deliverable: D-CW-L11-F, note: "Existing BRC-42 call sites unchanged at signature level; VendorSDK.ts smoke-tested + oddjobz device-pair refactored 2026-06-02 — first real consumer." }
      G: { status: "✓", deliverable: D-CW-L11-G, note: "Three test surfaces: (1) plexus-vendor-sdk/__tests__/derive-segment.test.ts — 12 tests (priv-side + pub-side); (2) protocol-types/__tests__/identity-derive-segment-public-key.test.ts — 12 tests (stub + Local impl + PARITY byte-equal to L11 primitive + cartridge use-case smoke). Priv↔pub symmetry verified across 4 segments. BRC-42 pubkey-side composition byte-equal to bsv-sdk's deriveChild.toPublicKey()." }
      H: { status: "✓", deliverable: D-CW-L11-H, note: "THREE consumer adoptions: (1) REFACTOR via @plexus/vendor-sdk: cartridges/oddjobz/brain/src/device-pair-client.ts (#829) — hand-rolled curve math collapsed to single deriveScalarPub call. (2) SUBSTRATE-SIDE PORT (#833): IdentityAdapter.deriveSegmentPublicKey(parentPubKeyHex, segment) → childPubKeyHex added — exposes L11 to greenfield-discipline cartridges. (3) FIRST GREENFIELD CARTRIDGE CONSUMER: cartridges/tessera/brain/src/key-derivation.ts — TesseraKeyDerivation routes per-cell owner/handler/scanner derivations through the substrate IdentityAdapter port. Cartridge passes the strict consumption gate (only imports @semantos/protocol-types types). 43/43 across tessera tests + adapter-consumption gate." }
      I: { status: "✗", deliverable: D-CW-L11-I, note: "docs/canon/brc-mapping.yml update still pending: EP3259724B1 = base, BRC-42 = bilateral specialisation. Doc-comments in crypto.ts carry the framing for now." }
      J: { status: "⚠", deliverable: D-CW-L11-J, note: "Self-KAT pin against @bsv/sdk's deriveChild (byte-equal). External KAT pin against va-chain chain_v1.json still pending — needs lifting the vector format too." }

  - id: L12
    name: ECDH-linked spend-chain audit primitive
    source: |
      prof-faustus/verifiable-accounting-chain @ packages/chain/src/
      chain.ts + ecdh.ts + link.ts. Append-only TransactionChain;
      each link spends prev outpoint, signed by deterministically
      derived linkPub (via L11). ECDH commonSecret
      pointMul(theirMasterPub + gv·G, myMasterPriv + gv) for
      point-to-point bundle delivery. Patent refs: US12375287B2,
      EP3259724B1.
    target: |
      core/anchor-attestation/src/audit-chain/ (new) — append-only
      tamper-evident chain primitive, layered atop L11 for linkPub
      derivation. Plus `commonSecret` helper in
      core/plexus-vendor-sdk/src/crypto.ts (standalone, usable by L9).
    value: 4
    ease: 3
    priority: 12
    blockedBy: [L11]
    memory:
      - cell_routing_paid_pubsub_not_risk
      - mnca_anchor_onchain_mainnet
    note: |
      RE-SCORED 2026-06-01 after discussion: original "conflicts with
      paid-pubsub" framing conflated TRANSPORT with RECORD-KEEPING.

      cell_routing_paid_pubsub_not_risk is about how cells flow between
      peers (transport). va-chain's TransactionChain is how events are
      RECORDED for audit (a tamper-evident on-chain spine). Different
      layers; they complement rather than compete.

      Semantos has no audit-chain primitive today. Cell-mint history,
      hat lifecycle, anchor history all live in per-store SQLite with
      no on-chain tamper-evident spine.

      Immediate use cases:
        - Mint-audit chain per cartridge (oddjobz licensing,
          Bridget philanthropy donor trail).
        - Hat lifecycle (admit/revoke as chain links signed by
          deterministically derived hat linkPub).
        - Anchor-history chain — links L5's per-batch anchors so any
          verifier can walk the full anchor history from one txid.
        - ECDH commonSecret as a standalone primitive for L9
          scoped-disclosure envelope delivery (point-to-point auditor
          handoff, no per-recipient key exchange round).

      Part of the Craig-family triangle: L10 + L11 + L12 + L9 all root
      in EP3259724B1 / US12375287B2. Lifting L11 first unblocks this.

      2026-06-02 SQL deep-dive (post-#802): tea-package's PG migration
      `0006_evid_audit_chain.sql` is the PRODUCTION-SHAPED REFERENCE
      for the chain primitive. It implements `audit_chain (entity_id,
      seq, canonical_id, prev_hash, entry_hash)` + a BEFORE INSERT
      trigger `fn_audit_append()` that:
        - takes pg_advisory_xact_lock(hashtext('audit_chain'),
          entity_id) for single-writer-per-entity (REQ-DATA-0036),
        - asserts seq = last_seq + 1 (gap-free, REQ-DATA-0032),
        - asserts prev_hash = last entry_hash or zero32 at genesis
          (REQ-DATA-0034),
        - recomputes entry_hash = SHA-256(prev_hash || canonical_sha256)
          and rejects on mismatch (REQ-DATA-0033),
      plus an immutability trigger that rejects UPDATE/DELETE, plus
      `fn_verify_chain(entity_id)` walker returning the first broken
      seq or NULL. Chain integrity is enforced at the STORAGE TIER,
      independent of the application writer.

      Material implication for L12 lift: pair the spend-chain primitive
      with a storage-tier verification trigger so cell-mint history /
      hat lifecycle / anchor history get tamper-detection even if the
      application layer is bypassed. tea-package's 73-line trigger is
      the model.
    axes:
      A: { status: "✓", deliverable: D-CW-L12-A, note: "Paths: packages/chain/src/{chain,ecdh,link}.ts + tea-package migrations/0006_evid_audit_chain.sql (storage-tier reference)" }
      B: { status: "✓", deliverable: D-CW-L12-B, note: "core/anchor-attestation/src/audit-chain/ landed (lift/l12-audit-chain) — exposed via @semantos/anchor-attestation/audit-chain subpath. computeCommonSecret helper landed in core/plexus-vendor-sdk/src/crypto.ts. sqlite-or-pg storage-tier trigger pattern deferred to follow-up (axis E note)." }
      C: { status: "✓", deliverable: D-CW-L12-C, note: "MIT — attribution in file headers (va-chain packages/chain cited, patents US12375287B2 + EP3259724B1 referenced)." }
      D: { status: "✓", deliverable: D-CW-L12-D, note: "Append-only spend-link with deterministically derived linkPub via L11; ECDH commonSecret = pointMul(theirPub + gv·G, myPriv + gv); storage-tier integrity = advisory-lock + gap-free + prev/entry recompute trigger" }
      E: { status: "✓", deliverable: D-CW-L12-E, note: "Application-tier port complete: types.ts (AuditChainEntry, SignedAuditChainEntry, AUDIT_CHAIN_MAGIC='L12AC' v1, ZERO_HASH, LinkSegmentDeriver), append.ts (genesisEntry, appendEntry, signEntry + genesisSignedEntry/appendSignedEntry convenience, default linkSegment), verify.ts (verifyAuditChain — 9 fail-closed codes), index.ts. computeCommonSecret(myMasterPriv, theirMasterPub, gv) composes deriveScalar + deriveScalarPub + computeSharedSecret (string + raw-scalar overloads). Storage-tier trigger pattern from tea-package 0006 deferred to follow-up." }
      F: { status: "✓", deliverable: D-CW-L12-F, note: "First cartridge consumer landed (lift/l12-anchor-history-consumer): cartridges/bsv-anchor-bundle/brain/src/anchor-history-chain.ts ships AnchorHistoryChain wrapping #836's IdempotentBatchAnchorer. Each FRESH successful anchor (cache miss + broadcast/confirmed) appends ONE L12 chain entry whose canonical bytes pack batchId + statusCode + txid + vout + anchorHeight + window + sortedCellRoots in a frozen wire format (magic 'AHX1' v1). Cache hits do NOT append duplicates; failed anchors do NOT append. Exposed via @semantos/bsv-anchor-bundle/anchor-history-chain subpath. InMemoryAnchorHistoryStore reference impl. AnchorHistoryRecord recomputability — decoded sortedCellRoots+window re-derive the L5 batchId via computeBatchId (proven in tests). Mint-audit chain (oddjobz) and hat-lifecycle chains remain as follow-up consumers." }
      G: { status: "✓", deliverable: D-CW-L12-G, note: "23/23 tests pass: 17 audit-chain (wire-format constants, happy path 3-link, KAT pin for entryHash at fixed canonical 'hello-l12-genesis' → 'cfe4e70e7f4267067a2c9686a733d43955494b9e9c2c41c275895022511dd938', 9 fail-closed axes covering all 9 enum codes — SEQ_NOT_MONOTONIC, SEQ_GAP, GENESIS_PREV_HASH_NOT_ZERO, PREV_HASH_MISMATCH, CANONICAL_HASH_MISMATCH, ENTRY_HASH_MISMATCH, LINK_PUB_KEY_MISMATCH, INVALID_SIGNATURE, ENTITY_ID_MISMATCH — plus empty-chain ok + custom segmenter happy-path and wrong-segmenter rejection); 6 computeCommonSecret (Alice↔Bob symmetry for both string and raw-scalar overloads, composition equivalence with deriveSegment/deriveSegmentPub and deriveScalar/deriveScalarPub, distinct-gv → distinct-secret, distinct-counterparty → distinct-secret). va-chain chain_v1.json cross-vector pending." }
      H: { status: "⚠", deliverable: D-CW-L12-H, note: "End-to-end demonstrated programmatically: bsv-anchor-bundle's AnchorHistoryChain drives 3 anchors through inner L5 batch-anchorer + appends 3 L12 chain entries + verifies the chain end-to-end against the operator master pub. Cross-check: decoded canonical bytes recover the L5 batchId via computeBatchId (proves the chain is recomputable from canonical+window alone). Live brain integration — wiring the consumer into the mint-batch loop on a real BSV adapter — still pending." }
      I: { status: "✓", deliverable: D-CW-L12-I, note: "docs/canon/audit-chain-vs-transport-layer.md landed — canonical layering distinction (transport vs record-keeping, paid-pubsub vs append-only audit). Cites US12375287B2 + EP3259724B1, cross-links L4/L5/L9/L11 + cell_routing_paid_pubsub_not_risk memory. Storage-tier trigger pattern from tea-package 0006 documented as deferred follow-up." }
      J: { status: "⚠", deliverable: D-CW-L12-J, note: "Wire-format KAT pin landed (entryHash hex for fixed canonical 'hello-l12-genesis' frozen at first ship). va-chain chain_v1.json cross-vector + storage-tier integrity test (bypasses application writer) deferred to follow-ups." }

  - id: L13
    name: OP_FALSE OP_IF <push> OP_ENDIF data carrier
    source: |
      prof-faustus/verifiable-accounting-bsv @ packages/bsv/src/
      scriptdataenvelope.ts. Explicitly forbids OP_RETURN; carries
      data inside an unreachable script branch. Enforced in CI by
      forbidden-token scan (see L14).
    target: |
      core/protocol-types/src/cell-pushdrop.ts (alternative codec) +
      core/protocol-types/zig/bsv/ (Zig mirror)
    value: 4
    ease: 5
    priority: 20
    blockedBy: []
    memory:
      - cell_wire_format_location
      - cell_is_the_wire_format
    note: |
      Alternative to PushDrop (`<cell> OP_DROP <pk> OP_CHECKSIG`):
      `OP_FALSE OP_IF <cell> OP_ENDIF <pk> OP_CHECKSIG`. The IF body
      is unreachable so the cell is pure data carriage and the
      OP_CHECKSIG tail remains spendable. Decouples data from the
      drop semantics. Tiny script change, big architectural clarity.
      Worth at least adding as an OPTION in cell-pushdrop.ts even if
      PushDrop stays the default.

      2026-06-02 update: THIRD carrier option from prof-faustus/
      idattr-onchain — `<root> OP_DROP OP_DUP OP_HASH160 <pkh>
      OP_EQUALVERIFY OP_CHECKSIG`. The root is dropped, the trailing
      native P2PKH keeps the output a genuinely spendable UTXO. Craig's
      SCARCITY-compliant alternative; verified live on Teranode regtest
      block 309 (anchor tx 068093ae…97840580, 2026-06-02). Three
      options now on the table:
        (a) PushDrop:              <cell> OP_DROP <pk> OP_CHECKSIG
        (b) OP_FALSE OP_IF:        OP_FALSE OP_IF <cell> OP_ENDIF <pk> OP_CHECKSIG
        (c) OP_DROP P2PKH:         <cell> OP_DROP OP_DUP OP_HASH160 <pkh> OP_EQUALVERIFY OP_CHECKSIG
      All three avoid OP_RETURN. (c) emits a standard P2PKH spendable
      output (better wallet-compat); (b) leaves an unreachable branch
      (cleanest semantically); (a) is what semantos ships today.
    axes:
      A: { status: "✓", deliverable: D-CW-L13-A }
      B: { status: "✓", deliverable: D-CW-L13-B, note: "core/protocol-types/src/cell-data-carriers.ts landed (lift/l13-data-carriers, PR forthcoming). Existing cell-pushdrop.ts unchanged — (a) re-exported." }
      C: { status: "✓", deliverable: D-CW-L13-C, note: "MIT — attribution in file header (anchorchain + va-bsv + idattr-onchain cited)" }
      D: { status: "✓", deliverable: D-CW-L13-D, note: "3 carrier shapes: (a) PushDrop, (b) OP_FALSE OP_IF (from va-bsv), (c) <root> OP_DROP <P2PKH> (from idattr-onchain). All avoid OP_RETURN; all leave spendable tail." }
      E: { status: "⚠", deliverable: D-CW-L13-E, note: "TS encoder + parser + universal discriminator landed. Zig mirror (core/protocol-types/zig/bsv/) for byte-identical guarantee still pending — separate PR." }
      F: { status: "✓", deliverable: D-CW-L13-F, note: "First consumer landed 2026-06-02 (lift/anchor-bundle-l13-carrier-policy): core/protocol-types/src/mnca/snapshot-anchor.ts — THE canonical MNCA anchor builder — extended with optional `carrier?: DataCarrierShape` field. AnchorPlan now reports which shape it produced. Backward-compat default = 'pushdrop' (no existing call site needs changes). For (c) op_drop_p2pkh, hash160(ownerPubkey) computed inline via node:crypto. Forwards through buildSnapshotAnchorBatch automatically." }
      G: { status: "✓", deliverable: D-CW-L13-G, note: "17/17 tests pass: per-variant byte-layout pins (1063/1065/1053), round-trips, fail-closed rejections, universal discriminator parses all 3, OP_RETURN/unknown shapes rejected. 18/18 pre-existing cell-pushdrop.test.ts still green (no regression)." }
      H: { status: "⚠", deliverable: D-CW-L13-H, note: "End-to-end demonstrated programmatically: 12 carrier-choice tests cover default-pushdrop (backward compat), op_false_op_if (1065 B canonical), op_drop_p2pkh with hash160-of-pubkey (1053 B canonical, matches idattr-onchain shape), cell-bytes-recoverable-from-all-three invariant, distinct script-bytes across carriers, batch builder forwards choice. Live mainnet anchor via (b) or (c) carrier still pending — the canonical MNCA anchor flow (snapshot-anchor.ts → wallet sign → ARC broadcast) just needs an operator decision to switch the carrier default for a real mint." }
      I: { status: "✗", deliverable: D-CW-L13-I, note: "Pending: update docs/runbooks/MNCA-ANCHOR-REAL-TXID with the 3-carrier choice rationale + how to select shape per cartridge" }
      J: { status: "⚠", deliverable: D-CW-L13-J, note: "TS-side wire format pinned. Zig-side mirror + byte-identical KAT pending." }

  - id: L14
    name: Forbidden-token CI lint
    source: |
      prof-faustus/anchorchain @ scripts/forbidden-scan.mjs (also
      verifiable-accounting-bsv + verifiable-accounting-chain).
      Scans content, filenames, commit messages for "btc",
      "blockstream", "pedersen", "bulletproof", "satoshi" (in BTC
      context), "cltv", "csv", "lightning", "taproot", "segwit",
      "rust-bitcoin", "op_checklocktimeverify", "op_checksequenceverify".
    target: |
      scripts/forbidden-tokens.mjs (new) +
      .github/workflows/forbidden-tokens.yml (new CI job)
    value: 4
    ease: 5
    priority: 20
    blockedBy: []
    memory:
      - bsv_no_cltv_use_nlocktime
      - semantos_no_ai_in_substrate
    note: |
      Semantos enforces BSV-only + post-Genesis discipline informally
      via memory + reviewer attention. Anchorchain's lint script makes
      it mechanical. Customise the token list for semantos: keep the
      altcoin-ticker + CLTV/CSV bans; add semantos-specific bans
      (e.g. "openai" / "anthropic" inside core/ per
      semantos_no_ai_in_substrate). Zero new mechanism, immediate
      hygiene win.

      2026-06-02 extension: prof-faustus/revocable-nft-tee ships an
      xtask "overclaim" lint that flags claims-without-test-coverage
      ("X holds" without a passing test that proves it). Mirrors the
      same discipline as no_hardcoded_workarounds memory. Combined
      with forbidden-token, this becomes a 2-axis hygiene gate:
        - axis 1: forbidden tokens (BSV-only / non-AI / post-Genesis)
        - axis 2: overclaim (claim-vs-test traceability)
      Adopt both as a single CI gate group.

      2026-06-02 SQL deep-dive (post-#802): tea-package's migration
      `0027_prohibition_constraints.sql` adds a THIRD prohibition
      layer — a DATABASE-RESIDENT BSV-script guard via plpgsql IMMUTABLE
      function `wallet.fn_assert_allowed_script(BYTEA)` invoked from
      BEFORE INSERT/UPDATE trigger on `wallet.utxo`. Raw opcode byte
      matching (0x6a=OP_RETURN data-carrier → reject; 0xa9..0x14...0x87
      = script-hash template → reject; 0x76 0xa9 0x14 ... 0x88 0xac =
      P2PKH → allow; anything else → reject). Comment says "Layer 3 of
      four independent prohibition layers" — opcodes matched by byte
      so the migration itself stays clean under the CI prohibition
      gate.

      Combined model for semantos = 3 (or 4) layers of enforcement:
        - Layer 1: CI static scan (forbidden tokens, overclaim)
        - Layer 2: runtime application (assertion in script-builder)
        - Layer 3: storage-tier (DB trigger or sqlite check on persist)
        - Layer 4: protocol-tier (network adapter rejects on wire)
      Lift Layer 3 from tea-package's pattern; semantos has Layer 1
      capacity informally and Layer 2 via reviewer attention. A
      cell-mint trigger that rejects forbidden locking-script bytes
      at the cell-store INSERT path closes the bypass route.
    axes:
      A: { status: "✓", deliverable: D-CW-L14-A }
      B: { status: "✓", deliverable: D-CW-L14-B, note: "scripts/forbidden-tokens.mjs + scripts/forbidden-tokens.config.json + scripts/__tests__/forbidden-tokens.test.ts landed (lift/l14-forbidden-token-lint, PR forthcoming)" }
      C: { status: "✓", deliverable: D-CW-L14-C, note: "MIT — anchorchain + va-bsv attribution in script header" }
      D: { status: "✓", deliverable: D-CW-L14-D, note: "Layer 1 of 4-layer prohibition stack. Pattern + regex matchers, per-rule scope (include/exclude globs), severity (error/warn), report-mode default + --strict opt-in" }
      E: { status: "✓", deliverable: D-CW-L14-E, note: "Ported as scripts/forbidden-tokens.mjs. Semantos-customised rules: op_checklocktimeverify (error), op_checksequenceverify (error), blockstream/rust-bitcoin/taproot/segwit (warn), openai/anthropic inside core/ (error per semantos_no_ai_in_substrate). 'pedersen' + 'bulletproof' explicitly NOT in list (semantos may want L6)." }
      F: { status: "✓", deliverable: D-CW-L14-F, note: ".github/workflows/forbidden-tokens.yml landed 2026-06-02 (ci/l14-forbidden-tokens-workflow). Runs on push to main + pull_request to main. Two steps: (1) lint in report mode (always exits 0), (2) self-test via bun test. continue-on-error: true so a hit does NOT block merge initially — the report surfaces in the check output for author awareness. Flip to PR-blocking by dropping continue-on-error + changing the run line to `--strict`; the comment in the workflow file pins both edits explicitly. Confirmed clean on latest main (3027 files, 8 rules, 0 errors) + self-test 5/5." }
      G: { status: "✓", deliverable: D-CW-L14-G, note: "5/5 self-tests pass: repo clean against shipped ruleset; strict-mode also clean; detects introduced violation via alt-config; warn-only does not fail strict; exclude pattern actually suppresses hits. Repo CLEAN against shipped rules: 3027 files scanned (up from 3017 at L14 ship — Tier 1 lifts added ~10 new TS files; all pass), 8 rules, 0 errors." }
      H: { status: "✓", deliverable: D-CW-L14-H, note: "PR-blocking pathway demonstrated mechanically (alt-config + --strict triggers exit 1) and wired into the workflow as a one-line flip (drop continue-on-error + add --strict to the run line). Until that flip, the workflow surfaces hits without blocking — telemetry-first approach matches the script's report-mode default." }
      I: { status: "✗", deliverable: D-CW-L14-I, note: "Pending: brief canon doc + section in CONTRIBUTING.md or canon/README explaining how to add a rule + how to whitelist a legitimate mention" }
      J: { status: "✓", deliverable: D-CW-L14-J, note: "Self-application: lint passes on itself + its config + its test. Whitelisting was needed for 3 files where the forbidden tokens appear in legitimate doc-comments / opcode-constant definitions / metadata-about-what-is-absent — each exclude has a _excludeRationale field." }

  # ─────────────────────────────────────────────────────────────────
  # overlay-broadcast cluster
  # ─────────────────────────────────────────────────────────────────
  - id: L15
    name: GG20 threshold ECDSA + ZK proofs
    source: |
      prof-faustus/overlay-broadcast @ crates/custody/src/gg20.rs +
      paillier.rs + zk-proofs + echo.rs + type7.rs. Full Gennaro-
      Goldfeder 2020 with initiator range proof, responder
      consistency proof, modulus Π_N, Goldwasser-Lindell echo-
      broadcast for identifiable abort, Type-7 final-share-fault
      attribution.
    target: |
      DEFER. If ever needed: core/protocol-types/zig/custody/ or
      a Rust sidecar (mirrors the bsv-rs primitives pattern).
    value: 3
    ease: 1
    priority: 3
    blockedBy: []
    memory:
      - pb_utxo_discovery_primitive
    note: |
      Reference-quality implementation but no immediate consumer in
      semantos. If the PB shared-UTXO discovery primitive needs true
      non-custodial threshold ECDSA (vs L7 threshold Schnorr),
      revisit. Otherwise file-and-forget; lifting GG20 is a multi-
      month undertaking, not a "lift".
    axes:
      A: { status: "✓", deliverable: D-CW-L15-A }
      B: { status: "✗", deliverable: D-CW-L15-B, note: "Deferred until a consumer emerges" }
      C: { status: "✗", deliverable: D-CW-L15-C, note: "MIT" }
      D: { status: "⚠", deliverable: D-CW-L15-D, note: "GG20 mechanism understood at protocol level; ZK proof details would need a re-read at lift time" }
      E: { status: "✗", deliverable: D-CW-L15-E }
      F: { status: "✗", deliverable: D-CW-L15-F }
      G: { status: "✗", deliverable: D-CW-L15-G }
      H: { status: "✗", deliverable: D-CW-L15-H }
      I: { status: "✗", deliverable: D-CW-L15-I, note: "Mention in canon as known external reference for if/when needed" }
      J: { status: "✗", deliverable: D-CW-L15-J }

  - id: L16
    name: On-chain session-tx group lifecycle
    source: |
      prof-faustus/overlay-broadcast @ crates/session/src/lib.rs.
      Single BSV tx encodes group rekeying: n member input/output
      pairs + broadcaster pair + OP_FALSE OP_RETURN payload.
      Members sign SIGHASH_SINGLE (only their output); broadcaster
      signs SIGHASH_ALL sealing the payload. Member outputs are
      bare multisig OP_1 <P_M> <P_B> OP_2 OP_CHECKMULTISIG
      (renewal vs revocation).
    target: |
      Possibly cartridges/hats/src/lifecycle.ts if hat lifecycle ever
      gets an on-chain commitment. Otherwise skip.
    value: 2
    ease: 2
    priority: 4
    blockedBy: []
    memory:
      - shell_cartridges_hats_model
    note: |
      Solves a different problem (group encryption lifecycle for
      LKH broadcast). The SIGHASH_SINGLE-per-member +
      SIGHASH_ALL-by-broadcaster pattern is interesting in isolation
      — a way to compose a multi-party tx where each party signs
      only their own output. Worth remembering if hat membership
      ever needs on-chain consent.
    axes:
      A: { status: "✓", deliverable: D-CW-L16-A }
      B: { status: "n/a", note: "No current consumer" }
      C: { status: "n/a" }
      D: { status: "✓", deliverable: D-CW-L16-D, note: "Pattern understood: SIGHASH_SINGLE per member + SIGHASH_ALL for broadcaster" }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-CW-L16-I, note: "Mention in canon as alternative composition pattern" }
      J: { status: "n/a" }

  - id: L17
    name: LKH group broadcast encryption (GB 2623780)
    source: |
      prof-faustus/overlay-broadcast @ crates/broadcast/src/graph.rs +
      rekey.rs. Power-of-two binary tree, root = message key, leaves
      = user keys. Three packaging strategies: KeyOriented /
      GroupOriented / UserOriented.
    target: n/a — different mechanism from semantos pubsub.
    value: 1
    ease: 2
    priority: 2
    blockedBy: []
    memory:
      - cell_routing_paid_pubsub_not_risk
    note: |
      LKH solves group encryption; semantos solves group ROUTING via
      paid pubsub. Different problems. Skip; do not adopt.
    axes:
      A: { status: "✓", deliverable: D-CW-L17-A }
      B: { status: "n/a", note: "Skip — different mechanism" }
      C: { status: "n/a" }
      D: { status: "✓", deliverable: D-CW-L17-D }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "n/a" }
      J: { status: "n/a" }

  # ─────────────────────────────────────────────────────────────────
  # cardtable cluster
  # ─────────────────────────────────────────────────────────────────
  - id: L18
    name: 3-branch IF/ELSE script (action / timeout / recovery)
    source: |
      prof-faustus/cardtable @ packages/script-templates/src/
      round-state.ts. State UTXO with three branches:
      (1) action — OP_HASH256 <successor_hash> OP_EQUALVERIFY
                   <acting_pk> OP_CHECKSIG,
      (2) timeout — preimage + n-of-n CMS, nSequence
                    relative-blocks (no in-script CSV),
      (3) recovery — n-of-n CMS, nLockTime absolute
                     (no in-script CLTV).
    target: |
      Reference pattern for cartridges/games/* and any cell that
      ever needs on-chain dispute resolution.
    value: 3
    ease: 4
    priority: 12
    blockedBy: []
    memory:
      - bsv_no_cltv_use_nlocktime
    note: |
      Clean reference for encoding multi-party FSM transitions
      without CLTV/CSV (all timing at tx-level via nLockTime +
      nSequence). Useful if any semantos cartridge ever ships a
      dispute-resolvable state machine (e.g. cardgammon, ad-list
      escrow). Lift the PATTERN, not the code: cardtable's
      script-templates use hand-rolled BIP-143 instead of @bsv/sdk.

      2026-06-02 extension: prof-faustus/bsv-poker hardens the pattern
      with a 109-byte BRANCH-BINDING PREFIX on every locking script:
        bindingBytes(b) OP_DROP <rest of script>
      where bindingBytes = gid(8) ‖ rulesetHash(32) ‖ round(u32) ‖
      stateHash(32) ‖ actingSeat(u8) ‖ successorCommitment(32) (109B).
      Pushdata carried in live script (never OP_RETURN; lint enforced).
      Prevents replay of a state-transition tx against a different
      game/round/state. Generalises to: any cell that mints a
      successor transaction should prefix the locking script with a
      branch-binding pushdata over (cell_id, sequence, predecessor_hash,
      successor_commitment) so the tx cannot be replayed against a
      different branch of the cell DAG. Directly applicable to Tessera
      wave's generic mint path per tessera_wave_branch_state.

      L25 generalises L18 further: L18 is the single-FSM pattern; L25
      is the DFA registry that composes many FSMs as data-defined JSON.
    axes:
      A: { status: "✓", deliverable: D-CW-L18-A }
      B: { status: "✗", deliverable: D-CW-L18-B, note: "Pattern doc, not a single file target" }
      C: { status: "✗", deliverable: D-CW-L18-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L18-D }
      E: { status: "✗", deliverable: D-CW-L18-E, note: "Adopt pattern when a consumer needs it" }
      F: { status: "✗", deliverable: D-CW-L18-F }
      G: { status: "✗", deliverable: D-CW-L18-G }
      H: { status: "✗", deliverable: D-CW-L18-H }
      I: { status: "✗", deliverable: D-CW-L18-I, note: "Document in docs/canon/ as a sanctioned on-chain-FSM pattern" }
      J: { status: "✗", deliverable: D-CW-L18-J }

  - id: L19
    name: Commit-reveal mental poker (Fisher-Yates)
    source: |
      prof-faustus/cardtable @ packages/crypto-cards/src/entropy.ts
      + shuffle.ts. Two-round: H(entropy_i ‖ playerId ‖ gameId)
      commit then plaintext reveal; combined seed drives a
      SHA-256 counter-mode PRG; Fisher-Yates with rejection
      sampling.
    target: n/a — semantos doesn't ship card games today.
    value: 1
    ease: 3
    priority: 3
    blockedBy: []
    memory:
      - jam_room_live_vs_dead_engine
    note: |
      Worth flagging: this is NOT collusion-resistant against a
      last-revealer attacker (excludes the non-revealer but lets
      them grief deck shape). If semantos ever ships card games,
      do real mental-poker (commutative encryption à la
      Schindelhauer) instead of this pattern.
    axes:
      A: { status: "✓", deliverable: D-CW-L19-A }
      B: { status: "n/a" }
      C: { status: "n/a" }
      D: { status: "✓", deliverable: D-CW-L19-D, note: "Mechanism + collusion-vulnerability understood" }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-CW-L19-I, note: "Note the collusion-vulnerability in canon for any future game cartridge" }
      J: { status: "n/a" }

  # ─────────────────────────────────────────────────────────────────
  # M840 (math, not code)
  # ─────────────────────────────────────────────────────────────────
  - id: L20
    name: M840 spectral mesh design heuristics
    source: |
      prof-faustus/M840 (Open University dissertation, May 2026).
      Three operator-level results:
      (i)   λ₂(L) = nb for the symmetric two-block model — algebraic
            connectivity governed only by cross-cut weight,
      (ii)  Rayleigh cut-capacity bound λ₂(L) ≤ n·C(S,S̄)/(|S|·|S̄|),
      (iii) Probabilistic cut-thinning under Hoeffding — structured
            attacks beat diffuse attacks of equal total mass.
    target: |
      docs/canon/mesh-spectral-design.md (new) — heuristics applied
      to skyminer N=8 + future federation topologies.
    value: 3
    ease: 5
    priority: 15
    blockedBy: []
    memory:
      - skyminer_n8_mesh_live
      - semantos_federation_transport
    note: |
      Pure reading + a single canon doc. The two-block theorem in
      particular is useful for designing the cross-link weight
      between Skyminer's N=8 mesh and the laptop / brain.utxoengineer
      bridge: λ₂ collapses linearly in the weakest cross-cut, so
      adding internal redundancy without addressing cross-links is
      wasted effort. Cheap, immediate, no code.
    axes:
      A: { status: "✓", deliverable: D-CW-L20-A }
      B: { status: "✗", deliverable: D-CW-L20-B }
      C: { status: "n/a", note: "Dissertation — cite, don't copy" }
      D: { status: "✓", deliverable: D-CW-L20-D, note: "All three results grokked at operator-level" }
      E: { status: "n/a", note: "No code to port" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-CW-L20-I, note: "Write docs/canon/mesh-spectral-design.md citing M840 + Skyminer N=8" }
      J: { status: "n/a" }

  # ─────────────────────────────────────────────────────────────────
  # 2026-06-02 expansion — 8 substantive new prof-faustus repos:
  #   identity-attribution, idattr-onchain, tee-sim, revocable-nft-tee,
  #   cto-bsv, bsv-poker, triple-entry-bsv-sql, tea-package.
  # New tracks L21..L27. Existing tracks L7/L8/L9/L13/L14/L18 also
  # updated below to reference patterns from these repos.
  # ─────────────────────────────────────────────────────────────────

  - id: L21
    name: Sigma-OR age-predicate ZK + sparse Merkle registry
    source: |
      prof-faustus/identity-attribution @ crates/idattr-zkp/src/lib.rs
      (~537 LOC) + crates/idattr-smt/src/lib.rs (~495 LOC).
      Bit-decomposition + Schnorr-OR per bit; age via clever
      C_delta = threshold_year·G − C_birth → range-proof delta ≥ 0.
      256-deep sparse Merkle with non-inclusion-as-revocation.
      NOT Bulletproofs in-tree (those live in anchorchain bridge).
    target: |
      core/protocol-types/src/zk-predicates/ (new) + a registry-spine
      module under core/anchor-attestation/src/sparse-merkle/ (new).
    value: 4
    ease: 3
    priority: 12
    blockedBy: []
    memory:
      - mnca_anchor_onchain_mainnet
      - bridget_philanthropy_cartridge
    note: |
      Semantos has no ZK predicate primitives today. The age-predicate
      construction (`verifier recomputes C_delta = threshold·G − C_birth`
      from issuer's commitment) is the exact shape needed for "is this
      entity allowed to do X without revealing attribute value" —
      Plexus credential surface, Bridget-philanthropy donor-eligibility,
      hat-based age/region gates.

      Two-step lift question to resolve:
        (a) Lift the Ristretto sigma-OR (linear, simpler, ~300 LOC) and
            accept the curve mismatch with semantos's secp256k1 surface, OR
        (b) Port the anchorchain Bulletproof (secp256k1, logarithmic,
            heavier crypto, see L6) and federate predicates via that bridge.

      The sparse Merkle (256-deep, empty-subtree precomputed, non-inclusion
      proofs) is the registry-spine semantos lacks. Use for federated
      revocation: anchored SMT root on chain (via L4/L5 + idattr-onchain's
      `<root> OP_DROP <P2PKH>` carrier — see L13 update).
    axes:
      A: { status: "✓", deliverable: D-CW-L21-A, note: "Paths: crates/idattr-zkp + crates/idattr-smt + crates/idattr-anchor" }
      B: { status: "✗", deliverable: D-CW-L21-B }
      C: { status: "✗", deliverable: D-CW-L21-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L21-D, note: "Sigma-OR per bit (32 BitProofs); C_delta age trick; SMT non-inclusion = revocation; live KAT against BSV mainnet block root" }
      E: { status: "✗", deliverable: D-CW-L21-E, note: "Curve choice unresolved — see (a)/(b) above" }
      F: { status: "✗", deliverable: D-CW-L21-F }
      G: { status: "✗", deliverable: D-CW-L21-G, note: "identity-attribution has 28 workspace tests + proptest; 10k-identity corpus run reported" }
      H: { status: "✗", deliverable: D-CW-L21-H }
      I: { status: "✗", deliverable: D-CW-L21-I }
      J: { status: "✗", deliverable: D-CW-L21-J }

  - id: L22
    name: Ed25519 device attestation + binding — closes brain-auth T7
    source: |
      prof-faustus/identity-attribution @ crates/idattr-device/src/
      lib.rs (~473 LOC) + prof-faustus/tee-sim @ src/lib.rs (~420 LOC).
      Three domain-separators:
        ATTEST_DOMAIN = "idattr-device/attestation/v1"
        BIND_DOMAIN   = "idattr-device/binding/v1"
        CERT_DOMAIN   = "idattr-device/device-cert/v1"
      Attestation body: DOMAIN ‖ measurement(32) ‖ device_pub(32)
      ‖ non_exportable(1) ‖ len(nonce) u64-LE ‖ nonce, signed by
      attestation root. Binding: SHA-256(DOMAIN ‖ len(nonce) u64-LE
      ‖ nonce ‖ len(transcript) u64-LE ‖ transcript), signed by
      device key. tee-sim is byte-identical via pinned KAT.
    target: |
      runtime/semantos-brain/src/identity/device-attestation.ts (new) +
      platforms/flutter/semantos_shell_native_identity/lib/attestation/
      (new). Plus tee-sim sibling-process binary for dev.
    value: 5
    ease: 3
    priority: 15
    blockedBy: []
    memory:
      - brain_auth_model_intent
      - semantos_parked_identity_phase1b
      - craig_no_keys_on_device_stance
    note: |
      DIRECTLY closes brain-auth gap T7. Memory `brain_auth_model_intent`
      states Todd's intended design: BRC-52 cert + capability + Plexus-
      challenge satisfaction; current code degenerates to bearer token.
      Adding hardware-pinned (or simulator-pinned) device attestation
      makes it cert + capability + freshness + hardware-pin.

      Wire format is byte-stable; soundness check is unusually strong —
      tee-sim and idattr-device are independently implemented but pinned
      to the same KAT bytes (Ed25519 determinism via RFC 8032). semantos
      can adopt the wire format wholesale; pluggable backends (Software
      sim now, StrongBox/Secure Enclave/SGX later).

      tee-sim's "/info always reports simulation: true" + huge SIM_BANNER
      is the discipline pattern: never present a software simulator as a
      hardware boundary. Adopt the labelling discipline along with the
      code.

      Cross-ref: lifting this on top of L11 (EP3259724B1 base derivation)
      gives semantos a clean four-axis auth: cert(BRC-52) + cap(brokered)
      + derived-key(EP3259724B1) + device-attest(L22). Resolves the
      brain-auth surface end-to-end.
    axes:
      A: { status: "✓", deliverable: D-CW-L22-A }
      B: { status: "✓", deliverable: D-CW-L22-B, note: "Brain-side verifier + Flutter shell attestation plugin" }
      C: { status: "✗", deliverable: D-CW-L22-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L22-D, note: "Three domain separators; attestation + binding + device-cert; non-exportable bit in body" }
      E: { status: "✗", deliverable: D-CW-L22-E, note: "Port wire format to TS (brain verifier); platform-specific backends for Flutter" }
      F: { status: "✗", deliverable: D-CW-L22-F, note: "Wire into brain-auth path; replace bearer-token check with cert+cap+device-attest" }
      G: { status: "✗", deliverable: D-CW-L22-G, note: "Pin against tee-sim KAT bytes; integration test brain ↔ tee-sim subprocess" }
      H: { status: "✗", deliverable: D-CW-L22-H, note: "Live brain.utxoengineer.com round-trip with attested device" }
      I: { status: "✗", deliverable: D-CW-L22-I, note: "Update brain_auth_model_intent memory; cross-ref in canonicalization-matrix.yml" }
      J: { status: "✗", deliverable: D-CW-L22-J, note: "KAT pin; SIMULATION banner preserved verbatim where dev backend is used" }

  - id: L23
    name: Forward-revocable LKH rekey with on-chain SPV proof
    source: |
      prof-faustus/revocable-nft-tee @ crates/rnft/src/revocation.rs +
      flows.rs. forward_revoke(prior, revoked) builds new GB session
      at prior.index+1 for members\{revoked}, padded to power-of-two
      with reserved padding leaves. RevocationProof = {revoked,
      session_index, rekey_txid}. verify_revocation checks:
      (a) new session grants revoked no leaf,
      (b) rekey tx is SPV-verified against v1 HeaderChain trust root.
    target: |
      core/anchor-attestation/src/forward-revocation/ (new). Layered
      on overlay-broadcast's broadcast crate via L26 path-dep pattern,
      NOT forked. Stands alongside L12 (audit-chain) — different
      mechanism, different use case.
    value: 4
    ease: 2
    priority: 8
    blockedBy: [L26]
    memory:
      - soft_revoke_folded_patches
      - cell_routing_paid_pubsub_not_risk
    note: |
      semantos has soft-revoke (curator-signed revoke_fact.v0 marks
      fact as no-longer-load-bearing). revocable-nft-tee is the
      HARD-revoke complement: cryptographic forward-revocation of
      capability with publicly verifiable on-chain anchor of the
      rekeying event.

      Forward secrecy of PRIOR plaintext is explicitly NOT claimed
      (Statements A-D in cto-bsv discipline). Claim is FUTURE: no new
      ciphertext under the new session is reachable to the revoked
      party. This boundary must be preserved in any lift.

      Different mechanism from L12 audit-chain: L12 is record-keeping
      (linked spend chain of events), L23 is capability-revocation
      (LKH key-graph rekey + SPV-proof of the rekey tx). Both are
      semantos-useful but in different surfaces.

      blockedBy: [L26] — depends on the path-dep pattern landing first
      so we can consume overlay-broadcast's broadcast/session/keygraph
      crates without forking.
    axes:
      A: { status: "✓", deliverable: D-CW-L23-A }
      B: { status: "✗", deliverable: D-CW-L23-B }
      C: { status: "✗", deliverable: D-CW-L23-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L23-D, note: "LKH rekey + power-of-two padding + SPV-verified rekey tx; forward-only, never claims past plaintext recovery prevention" }
      E: { status: "✗", deliverable: D-CW-L23-E, note: "Pulls in 5+ overlay-broadcast crates via L26 path-dep; substantial lift" }
      F: { status: "✗", deliverable: D-CW-L23-F }
      G: { status: "✗", deliverable: D-CW-L23-G, note: "Live BSV regtest evidence in revocable-nft-tee/evidence/live-regtest.md" }
      H: { status: "✗", deliverable: D-CW-L23-H }
      I: { status: "✗", deliverable: D-CW-L23-I, note: "Update soft_revoke_folded_patches memory: soft-revoke + hard-revoke (L23) co-exist" }
      J: { status: "✗", deliverable: D-CW-L23-J }

  - id: L24
    name: TEE-trait "key never leaves" + fail-closed SPV freshness
    source: |
      prof-faustus/revocable-nft-tee @ crates/tee/src/tee.rs +
      freshness.rs. `Tee` trait by construction has NO method that
      returns the provisioned key. `provision_key` accepts; `decrypt_
      gated` emits only OutputForm (watermarked tile / framebuffer /
      audio bytes); never raw plaintext. spv_eligibility calls SPV
      INSIDE the trust boundary against HeaderChain trust root —
      chain unreachable → ChainUnreachable (fail-closed); holder-
      supplied assertions → ForgedEligibility (rejected).
    target: |
      docs/canon/tee-trait-shape.md (new) — pattern + reference
      implementation, NOT a code lift directly. Cell-engine
      capability-containment seam in core/cell-engine/src/capability.ts.
    value: 4
    ease: 4
    priority: 16
    blockedBy: []
    memory:
      - craig_no_keys_on_device_stance
      - semantos_brain_single_threaded_reactor
      - cell_engine_static_5mb_unfit_for_mcu
    note: |
      ARCHITECTURAL PATTERN, not a discrete module lift. Two parts:

      (1) "Key never leaves" trait shape — TypeScript expressed as a
      type-level capability containment: `provisionKey(k): void` accepts
      but there is no exported method that returns it. Stronger than
      runtime guards because the API surface itself prevents key
      extraction. Maps to craig_no_keys_on_device_stance.

      (2) Fail-closed SPV freshness INSIDE the trust boundary — any
      cell that needs a chain fact runs SPV itself, against a passed-in
      HeaderChain trust root, and fails closed on unreachability.
      Holder-asserted "I am eligible" gets rejected. This is the right
      pattern for cell-engine capability checks that depend on on-chain
      state (e.g. cell-mint authority, anchor freshness).

      Lift = canon doc + a few trait-shape examples + integration
      pattern for cell-engine's existing capability surface. Pairs with
      L22 (device attestation): brain runs SPV inside the trust
      boundary, holder presents attested device; both checks
      fail-closed independently.
    axes:
      A: { status: "✓", deliverable: D-CW-L24-A }
      B: { status: "✓", deliverable: D-CW-L24-B, note: "canon doc + cell-engine integration seam" }
      C: { status: "✗", deliverable: D-CW-L24-C, note: "MIT for any code; canon doc original" }
      D: { status: "✓", deliverable: D-CW-L24-D }
      E: { status: "✗", deliverable: D-CW-L24-E, note: "Pattern-lift mostly; small typed trait + SPV-inside-boundary integration" }
      F: { status: "✗", deliverable: D-CW-L24-F }
      G: { status: "✗", deliverable: D-CW-L24-G, note: "Type-level test: capability extraction should fail to type-check" }
      H: { status: "✗", deliverable: D-CW-L24-H }
      I: { status: "✗", deliverable: D-CW-L24-I, note: "docs/canon/tee-trait-shape.md authoritative" }
      J: { status: "✗", deliverable: D-CW-L24-J }

  - id: L25
    name: DFA-on-UTXO engine — generic state-machine substrate
    source: |
      prof-faustus/triple-entry-bsv-sql @ services-go/edi/dfa.go
      (~475 LOC Go). Generic DFA engine where state transitions =
      spend prior UTXO + emit successor envelope output carrying
      re-keyed controller. Used in same repo for both 22 EDI document
      DFAs (PO/INV/BOL/etc.) and the master consignment DFA
      (CREATED→BOOKED→…→SETTLED with DISPUTED/RECOVERED branches).
      DFAs defined as DATA in JSON, not code.
    target: |
      cartridges/shared/fsm-utxo/ (new) — generalises L18's 3-branch
      pattern. Reference shape for any cartridge needing title-transfer
      semantics (B/L-as-token, grant-as-token, voucher-as-token).
    value: 3
    ease: 3
    priority: 9
    blockedBy: []
    memory:
      - tessera_wave_branch_state
      - bridget_philanthropy_cartridge
    note: |
      semantos cells are typed-multicast routes (paid pubsub) by design
      — orthogonal to UTXO-lineage. But for cartridges that need
      TRANSFERABLE RIGHTS (donation pledges, grant entitlements,
      voucher claims, bill-of-lading title transfer), the DFA-on-UTXO
      pattern is the right shape: a transferable right is a cell whose
      successor carries a journalled state-transition with re-keyed
      controller.

      Data-defined extension is the key feature: 22 document DFAs +
      4 token types are JSON, not code. Adding a new document/token is
      a JSON row. Aligns with semantos cartridge model (cartridges add
      JSON, not core code).

      Don't unify with cell routing — keep transferable-rights cells as
      a separate mechanism, exactly as triple-entry-bsv-sql keeps tokens
      as a separate UTXO lineage on top of the same crypto core.

      Generalises L18 (cardtable's 3-branch IF/ELSE script): L18 is the
      single-state-FSM pattern; L25 is the DFA registry that composes
      many of them.
    axes:
      A: { status: "✓", deliverable: D-CW-L25-A }
      B: { status: "✗", deliverable: D-CW-L25-B }
      C: { status: "✗", deliverable: D-CW-L25-C, note: "MIT" }
      D: { status: "✓", deliverable: D-CW-L25-D, note: "state-transition = spend prior + emit successor with re-keyed controller; DFAs as JSON data" }
      E: { status: "✗", deliverable: D-CW-L25-E, note: "475 LOC Go port to TS; OR keep Go and consume via subprocess (cf L34 pattern)" }
      F: { status: "✗", deliverable: D-CW-L25-F, note: "First consumer: Bridget philanthropy grant-as-token" }
      G: { status: "✗", deliverable: D-CW-L25-G }
      H: { status: "✗", deliverable: D-CW-L25-H }
      I: { status: "✗", deliverable: D-CW-L25-I }
      J: { status: "✗", deliverable: D-CW-L25-J }

  - id: L26
    name: Path-dep + pinned-rev cross-repo pattern — closes oss-carve
    source: |
      prof-faustus/revocable-nft-tee @ Cargo.toml. v2 consumes v1
      (overlay-broadcast) via:
        bsv = { path = "../overlay-broadcast/crates/bsv" }
        cipher = { path = "../overlay-broadcast/crates/cipher",
                   package = "cipher" }  # rev pinned
        ...
      Pinned to git rev 374b1b16d3c342…. v2 crates MAY depend on v1;
      v1 SHALL NOT depend on v2 (REQ-GOV-V2-002). No forking.
    target: |
      docs/canon/cross-repo-path-dep-pattern.md (new) — process
      pattern + reference workspace template. Affects ALL future
      cross-repo decisions in the semantos ecosystem.
    value: 5
    ease: 5
    priority: 25
    blockedBy: []
    memory:
      - oss_substrate_carve_parked
      - semantos_worktree_hygiene
    note: |
      DIRECTLY addresses the parked oss_substrate_carve_parked
      decision. The OSS carve was parked because of cartridge variety
      concerns + "single-repo only, no divergent mirrors." Craig's
      pattern is the answer: don't carve, don't mirror — path-dep with
      pinned rev. Lower-tier consumes upper-tier; reverse-deps
      forbidden in workspace policy.

      Applies wherever semantos needs to add capabilities on top of a
      stable substrate (pask, cell-engine, plexus contracts) without
      either (a) carving the substrate out into its own repo or
      (b) forking. Both have failure modes (a) loses single-source-of-
      truth, (b) creates divergent mirrors. Path-dep with pinned-rev
      preserves substrate integrity while enabling extension.

      Code lift = zero. Canon doc + reference workspace template
      (e.g. cartridges/shared/template/Cargo.toml-or-package.json
      showing the path-dep + pinned-rev pattern) + governance line
      in CLAUDE.md or canon: "cartridge extensions MAY consume core
      crates via path-dep; core crates MUST NOT depend on cartridges."

      Blocks L23 (forward-revocation needs to consume overlay-broadcast
      crates without forking). Indirectly blocks L24 (TEE trait
      patterns ship cleanest when path-dep is the established pattern).
    axes:
      A: { status: "✓", deliverable: D-CW-L26-A }
      B: { status: "✓", deliverable: D-CW-L26-B, note: "Canon doc landed: docs/canon/cross-repo-path-dep-pattern.md + 2 reference templates under docs/canon/templates/" }
      C: { status: "n/a", note: "Pattern, not code" }
      D: { status: "✓", deliverable: D-CW-L26-D, note: "Pattern grokked: path-dep + pinned-rev + workspace policy (REQ-GOV-V2-002 equivalent)" }
      E: { status: "n/a", note: "No code to port" }
      F: { status: "✓", deliverable: D-CW-L26-F, note: "First application landed (lift/l26-first-application): the IN-MONOREPO governance line is now mechanically enforced. tests/gates/substrate-one-way-dep.test.ts scans every core/<pkg>/src/ (excl. __tests__/tests) and rejects any import that resolves into cartridges/* or runtime/* — neither via relative path nor via @semantos/<extension> alias (deny-list of 19 cartridge+runtime package names). Governance line + cross-link to L26 canon doc applied to core/protocol-types, core/cell-engine, core/anchor-attestation, core/plexus-vendor-sdk CLAUDE.md. New canon template docs/canon/templates/substrate-governance-line.md.template for future substrate packages." }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-CW-L26-I, note: "Canon doc shipped (PR #809). First application + template references shipped (lift/l26-first-application). oss_substrate_carve_parked memory: update to point at this canon doc as the resolution mechanic (pending PR-side memory edit)." }
      J: { status: "n/a" }

  - id: L27
    name: Threshold ECDH via Lagrange-in-the-exponent
    source: |
      prof-faustus/cto-bsv @ packages/tier-threshold/{ts,go}.
      Shamir over GF(256) + threshold ECDH where the private key d
      is NEVER reconstructed. Lagrange interpolation happens in the
      EXPONENT (i.e. on group elements), not on the scalar d.
      Cross-validated TS ↔ Go byte-equal.
    target: |
      runtime/semantos-brain/src/federation/threshold-ecdh.ts (new) —
      complements L7 (threshold Schnorr). L27 is for ECDSA-shaped
      operations where key reconstruction would be a security
      violation.
    value: 4
    ease: 3
    priority: 12
    blockedBy: []
    memory:
      - pb_utxo_discovery_primitive
      - craig_no_keys_on_device_stance
    note: |
      Stronger relative of L7 (threshold Schnorr custody): L7 is
      Schnorr-shaped and ships with the honest "not FROST-hardened,
      sign one session at a time" disclaimer; L27 is ECDH-shaped
      (the curve operation is multiplication of group elements, not
      scalar reconstruction), so the private key d truly never
      reconstructs.

      Use cases:
        - Brain-quorum federated ECDH for cross-brain bundle delivery
        - Shared-UTXO ECDH ops in the PB discovery primitive
        - Encrypted-envelope handoff to an auditor without any single
          party holding the recipient's key

      anchorchain has Shamir-reconstruct (whole key exists briefly in
      memory during sign — explicitly NOT threshold ECDSA, called out).
      cto-bsv's Lagrange-in-the-exponent is the proper non-custodial
      shape. Preserve cto-bsv's honest labelling discipline (Statements
      A-D about what is and isn't claimed).

      Cross-ref: L15 (GG20 threshold ECDSA — full Gennaro-Goldfeder
      with all ZK proofs) remains the heavyweight option if true
      threshold ECDSA signing (not just ECDH) is needed. L27 is the
      midpoint: non-custodial threshold for ECDH ops specifically.
    axes:
      A: { status: "✓", deliverable: D-CW-L27-A }
      B: { status: "✗", deliverable: D-CW-L27-B }
      C: { status: "✗", deliverable: D-CW-L27-C, note: "UNLICENSED in cto-bsv tree — verify Craig's intent re: license before lift; may need to ask" }
      D: { status: "✓", deliverable: D-CW-L27-D, note: "Lagrange-in-the-exponent: group-element interpolation, scalar never reconstructs" }
      E: { status: "✗", deliverable: D-CW-L27-E, note: "TS and Go both available; lift the TS as reference" }
      F: { status: "✗", deliverable: D-CW-L27-F }
      G: { status: "✗", deliverable: D-CW-L27-G, note: "cto-bsv has TS↔Go byte-equal KATs" }
      H: { status: "✗", deliverable: D-CW-L27-H }
      I: { status: "✗", deliverable: D-CW-L27-I, note: "Update L7 entry to cross-ref L27 as ECDSA-side relative" }
      J: { status: "✗", deliverable: D-CW-L27-J }

  # ─────────────────────────────────────────────────────────────────
  # bsv-universal-sdk cluster (repo 19, audited 2026-06-06)
  #   prof-faustus/bsv-universal-sdk @ bsv-universal-sdk-spec.md
  #   v0.1 DRAFT spec-only (no implementation code by intent). NO BRC
  #   refs, NO patent refs — a clean-room architecture spec, NOT a
  #   standards/provenance source like the EP3259724B1 repos.
  #   CONFIRMS (no lift, design validation): nLockTime-only timing
  #   (bsv_no_cltv_use_nlocktime), non-custodial sole-key-custody
  #   (craig_no_keys_on_device_stance), append-only committed journal
  #   with NO SQL substrate (semantos_canonical_schema_spine), dual-path
  #   speed+canonical propagation + unconfirmed progression (cell routing
  #   as paid pubsub), byte-for-byte TS↔Go differential determinism
  #   (our TS-oracle→Zig discipline), P2C pubkey-tweak as the OP_RETURN
  #   replacement (L13 data-carrier, their chosen option).
  #   Biggest finding recorded under L11 axis-D note: the spec's core
  #   crypto `P' = P + H(tag || m)·G` INDEPENDENTLY re-derives our L11
  #   deriveSegment (`parent + SHA256(segment)·G`) — external corroboration
  #   that the EP3259724B1-as-foundation reframe was right. The one
  #   divergence (their explicit `tag` arg vs our domain-in-the-segment-
  #   string) opens the domainFlag↔tag unification question — full design
  #   doc at docs/canon/domainflag-tag-unification.md (see L11 axis-D).
  # ─────────────────────────────────────────────────────────────────
  - id: L28
    name: Covenant locking-template family
    source: |
      prof-faustus/bsv-universal-sdk @ bsv-universal-sdk-spec.md §3.1 L0
      + §8. A named, composable script-template set: fundingLocking,
      actionLocking, settlementLocking, revealOrTimeoutLocking,
      branchBindingPrefix + new primitives conditionalTransferLocking,
      journalEntryLocking, registryDeedLocking, multiPartyMPCLocking.
      All avoid OP_RETURN/CLTV/CSV; timing is tx-level nLockTime only.
      Paired with a pure/deterministic ContractModule<S> engine
      interface (§8.1: init | getLegalActions | apply | isTimeoutEligible
      | isComplete | settle | serialize | deserialize) driven by
      replay(module, transcript).
    target: |
      core/cell-engine/ (template vocabulary) — generalises the scattered
      L1/L2 channel scripts + L18 IF/ELSE FSM + L25 DFA-on-UTXO under
      one named family. journalEntryLocking maps onto cell-as-journal-
      entry; the ContractModule replay shape is adjacent to the
      cell-engine transition model + snapshot/replay determinism.
    value: 3
    ease: 3
    priority: 9
    blockedBy: []
    memory:
      - bsv_no_cltv_use_nlocktime
      - semantos_release_pipeline
      - cell_routing_paid_pubsub_not_risk
    note: |
      Lift the VOCABULARY/shape, not necessarily code (the spec ships no
      code). Value is having one named, composable covenant family rather
      than re-deriving funding/action/settlement/timeout scripts per
      cartridge. journalEntryLocking is the standout — it is the cell as
      an append-only committed-journal entry, the same idea as L12's
      audit-chain but expressed as a locking template. The ContractModule
      replay engine is a clean state-machine contract worth borrowing for
      shape even if the cell-engine executor stays as-is.

      License caveat: I did not see a LICENSE in the fetched spec. The
      other ten audited repos are MIT; CONFIRM this repo's license before
      lifting anything beyond patterns (cf. L27 cto-bsv UNLICENSED trap).
    axes:
      A: { status: "✓", deliverable: D-CW-L28-A, note: "Path: bsv-universal-sdk-spec.md §3.1 + §8" }
      B: { status: "✗", deliverable: D-CW-L28-B }
      C: { status: "✗", deliverable: D-CW-L28-C, note: "UNKNOWN — no LICENSE seen in fetched spec; verify before lift" }
      D: { status: "✓", deliverable: D-CW-L28-D, note: "Covenant family + ContractModule replay interface understood; spec-only, no code to port" }
      E: { status: "✗", deliverable: D-CW-L28-E }
      F: { status: "✗", deliverable: D-CW-L28-F }
      G: { status: "✗", deliverable: D-CW-L28-G, note: "Spec mandates `pnpm reproduce` differential TS↔Go vectors — none published in the spec doc itself" }
      H: { status: "✗", deliverable: D-CW-L28-H }
      I: { status: "✗", deliverable: D-CW-L28-I }
      J: { status: "✗", deliverable: D-CW-L28-J }

  - id: L29
    name: Salted domain-separated Merkle-field-tree leaf (refines L8)
    source: |
      prof-faustus/bsv-universal-sdk @ bsv-universal-sdk-spec.md.
      Merkle field-tree commitment for multi-field selective disclosure
      with SALTED, domain-separated leaf construction (grounded in the
      read shuffle/poker sources). Same family as L8 (per-field intra-tx
      Merkle) but adds the per-leaf salt + explicit domain separation.
    target: |
      core/protocol-types/src/field-tree/ — refine L8's computeFieldLeaf
      to optionally carry a per-leaf salt + domain tag (L8 today is
      SHA-256 leaf with magic+version+schema-fingerprint binding but no
      per-leaf salt).
    value: 3
    ease: 4
    priority: 12
    blockedBy: [L8]
    memory:
      - cell_is_the_wire_format
    note: |
      L8 already shipped per-field Merkle leaves with domain-separator +
      schema-fingerprint binding. What L29 adds is the per-leaf SALT,
      which hardens against leaf-value guessing on low-entropy fields
      (e.g. a boolean or a small enum where the committed value is
      brute-forceable from the leaf hash alone). Small, additive refinement
      to L8's computeFieldLeaf — not a new primitive. Fold in if/when a
      real selective-disclosure consumer exposes a low-entropy field.
    axes:
      A: { status: "✓", deliverable: D-CW-L29-A }
      B: { status: "✓", deliverable: D-CW-L29-B, note: "Refines existing core/protocol-types/src/field-tree/" }
      C: { status: "✗", deliverable: D-CW-L29-C, note: "UNKNOWN license — same caveat as L28" }
      D: { status: "✓", deliverable: D-CW-L29-D, note: "Salted + domain-separated leaf; refinement of L8's leaf construction" }
      E: { status: "✗", deliverable: D-CW-L29-E }
      F: { status: "✗", deliverable: D-CW-L29-F }
      G: { status: "✗", deliverable: D-CW-L29-G }
      H: { status: "✗", deliverable: D-CW-L29-H }
      I: { status: "✗", deliverable: D-CW-L29-I }
      J: { status: "✗", deliverable: D-CW-L29-J }

# ─────────────────────────────────────────────────────────────────
# Priority-ordered summary (for the roadmap render).
#
# Tier 1 (priority ≥ 20, do first):
#   L4  Two-tree SPV verify composition          [25]
#   L5  Per-batchId idempotent anchoring         [25]
#   L11 EP3259724B1 base derivation              [25]  (foundation; BRC-42 = bilateral case)
#   L26 Path-dep + pinned-rev cross-repo pattern [25]  (canon doc; closes oss-carve)
#   L1  Q* sub-satoshi netting                   [20]
#   L2  D14 custody-free watchtower              [20]
#   L8  Per-field intra-tx Merkle tree           [20]
#   L13 OP_FALSE OP_IF data carrier              [20]  (+ <root> OP_DROP P2PKH variant)
#   L14 Forbidden-token CI lint                  [20]  (+ overclaim lint + DB-resident L3)
#
# Tier 2 (priority 12-16, do once Tier 1 settled):
#   L9  Scoped-disclosure signed envelope        [16]  blockedBy: L8
#   L24 TEE-trait "key never leaves" + SPV freshness [16]
#   L29 Salted domain-sep Merkle-field leaf      [12]  blockedBy: L8 (refines)
#   L22 Ed25519 device attestation + binding     [15]  (closes brain-auth T7)
#   L20 M840 spectral mesh design heuristics     [15]
#   L7  Threshold Schnorr custody                [12]  (cf. L27 ECDSA-side)
#   L10 TEA primitives (sub-keys + linkage tags) [12]
#   L12 ECDH-linked spend-chain audit primitive  [12]  blockedBy: L11
#   L18 3-branch IF/ELSE FSM script              [12]  (+ branch-binding prefix)
#   L21 Sigma-OR ZK + sparse Merkle registry     [12]
#   L27 Threshold ECDH (Lagrange-in-the-exponent) [12]
#
# Tier 3 (priority 6-9, opportunistic):
#   L25 DFA-on-UTXO engine                       [9]
#   L28 Covenant locking-template family         [9]   (spec-only; lift vocabulary)
#   L23 Forward-revocable LKH + on-chain SPV     [8]   blockedBy: L26
#   L3  Bonded forfeiture channel construction   [8]   blockedBy: L1, L2
#   L6  Pedersen + Bulletproofs                  [6]
#
# Tier 4 (priority ≤ 4, watch-list / skip):
#   L16 On-chain session tx — WATCH (no consumer)
#   L15 GG20 threshold ECDSA — WATCH (no consumer; cf. L27 for non-custodial ECDH)
#   L19 Commit-reveal poker  — SKIP (collusion-vulnerable, no card games)
#   L17 LKH broadcast        — SKIP (different mechanism)
#
# Re-scoring history:
#   2026-06-01 — L11 (was prio=4 SKIP) → prio=16 Tier 2: original
#                "duplicate of BRC-42" framing had the hierarchy
#                backwards; EP3259724B1 is the parent primitive.
#   2026-06-01 — L12 (was prio=4 SKIP) → prio=12 Tier 2: original
#                "conflicts with pubsub" framing conflated transport
#                with record-keeping; they're different layers.
#   2026-06-02 — L21..L27 added: 8 substantive new prof-faustus repos
#                published 2026-06-01 to 2026-06-02 (identity-attribution,
#                idattr-onchain, tee-sim, revocable-nft-tee, cto-bsv,
#                bsv-poker, triple-entry-bsv-sql, tea-package). L22 closes
#                brain-auth T7; L26 closes oss-carve direction. Existing
#                tracks L7/L8/L9/L13/L14/L18 updated below to cross-ref
#                patterns from these repos (no priority change).
#   2026-06-02 — L8/L9/L12/L14 textually augmented (PR #806) after a
#                proper SQL deep-dive of triple-entry-bsv-sql + tea-package.
#                No tier movement; corrections to scope (SQL is thin
#                capture in triple-entry-bsv-sql; the production-shaped
#                chain trigger lives in tea-package 0006; DB-resident
#                script guard in tea-package 0027 added as L3 of L14's
#                prohibition stack).
#   2026-06-02 — L11 promoted Tier 2 → Tier 1 (prio 16 → 25). Todd's
#                framing: "the BRC-42 stuff was just a bilateral
#                arrangement" of CSW's underlying patent. Under CSW-
#                canonical, EP3259724B1 is the foundation primitive,
#                BRC-42 is its bilateral specialisation, not a separate
#                primitive. Matrix should reflect that hierarchy with
#                L11 at the bottom of the stack. Ship in Week 1
#                alongside L4/L26/L14.
#   2026-06-06 — L28/L29 added: bsv-universal-sdk (repo 19) audited.
#                Spec-only v0.1, no BRC/EP refs → confirms more than it
#                contributes. L28 covenant locking-template family (Tier
#                3, vocabulary lift), L29 salted Merkle-field leaf (Tier
#                2, refines L8). Its pay-to-contract `P+H(tag||m)·G`
#                independently re-derives L11 deriveSegment — recorded in
#                L11 axis-D + full design doc docs/canon/domainflag-tag-
#                unification.md (domainFlag↔tag; Stage 0 done via D-Const-
#                domainflag-genfix, Stage 1 scoped, Stage 2 'L11.5'
#                deferred). License UNKNOWN — verify before any code lift.

```
