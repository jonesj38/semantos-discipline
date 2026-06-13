---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/cell-signing-bkds.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.637990+00:00
---

# BKDS cell signing — operator runbook

D-DOG.1.0c Phase 4 retrofitted per-cell BKDS (BRC-42 Bilateral Key
Derivation Scheme) signing across the oddjobz cell-DAG. Every site,
customer, job, and attachment cell minted by the Phase 2A.4 graph
translator is signed by a freshly-derived key that exists for exactly
one cell, then is discarded.

This runbook is the recovery story: how to re-derive any cell's signing
key from the operator's brain disk so signatures stay verifiable and a
lost derived key never blocks audit.

## What's stored on disk

Tier 0 keeps the model small:

| Item | Where | Encumbrance |
|---|---|---|
| Hat-key root | `<root>/data/brain/hat-root.enc` (AES-GCM, KEK-encrypted) | KEK protection only |
| Cell signatures | embedded in each cell's payload (`signedBy` + `signature`) | none — public |
| Derived signing keys | nowhere — discarded after one signature | n/a |

The root is a single 32-byte secret. Every derived signing key is a
deterministic function of `(root, protocolID, keyID, counterparty)` per
BRC-42 — given the four inputs, the same derived key falls out. This is
the property that lets us discard the derived keys and still verify
signatures later.

## Derivation parameters

Per `runtime/semantos-brain/src/hat_bkds.zig` (Phase 4 B.1):

- **protocolID**: `oddjobz.cell-sign/v1`
  - Domain + version scoped. Bumping to `/v2` is a coordinated migration
    across all cells; previously-signed cells stay verifiable under
    `/v1` indefinitely.
- **keyID**: SHA-256 of the canonicalised cell payload
  - Idempotent: same content → same derived key → same signature.
  - Any payload mutation invalidates the signature deterministically.
- **counterparty**: the operator's domain-identity public key
  - Bound to the operator's BRC-52 cert flow per existing wallet posture.

The derived public key (NOT the root pubkey) is what gets recorded in
the cell's `signedBy` field. This means:

- Each cell shows a **different** signing pubkey on the wire.
- A third party verifying the cell sees no cross-cell correlation.
- Privacy property: cells are unlinkable by signature without root access.

## Recovery: re-deriving a single cell's signing key

If the brain disk survived but the derived key for a specific cell is
needed (audit, manual re-sign of a payload-equivalent cell, reproducing
a signature), the steps are:

1. **Unlock the wallet KEK.** The standard brain first-run / recovery path
   loads the encrypted root from `<root>/data/brain/hat-root.enc` and
   decrypts under the wallet KEK derived from the operator's passphrase.

2. **Read the cell's content hash.** The keyID is the SHA-256 of the
   canonicalised cell payload — re-canonicalise the on-disk JSON line
   the same way `runtime/semantos-brain/src/hat_bkds.zig::canonicaliseCell` does
   (sorted keys, no whitespace, same field-omission rules) and SHA-256
   it. This is byte-stable for any cell that hasn't been mutated.

3. **Derive.** `derive(root, "oddjobz.cell-sign/v1", contentHash,
   counterparty) → privateKey, publicKey`. This is a single BRC-42 call
   into `core/cell-engine/src/bca.zig` (TS mirror at
   `core/protocol-types/src/bca.ts`).

4. **Verify or re-sign.** Compare the derived publicKey to the cell's
   `signedBy` field. If equal, the cell is authentic. Re-sign: feed the
   derived privateKey + the same canonical payload through the
   wallet's signature primitive; the resulting signature byte-equals
   the one already on disk (or replaces a stripped one).

The TS-side equivalent for the helm and the legacy ratify path lives in
the brain-rpc cell writer; the Zig handler is the source of truth.

## Recovery: lost brain disk

If the operator's brain disk is gone, the root can still be reached via
the existing BRC-52 cert flow's BRC-42 BKDS recovery enrolment. That's
a separate operator-runbook-level concern (the wallet's normal
recovery path applies); from the cell-signing perspective, the
derivation rules above don't change. Once the root is recovered, every
cell's signing key is recomputable via step 3 above.

## Compromise blast radius

| Event | Effect |
|---|---|
| Single derived signing key leaks (somehow — they aren't stored) | Only that one cell forgeable; every other cell uses a different key |
| Single cell's payload is mutated on disk | Signature verification fails (keyID changed → derived pubkey would change) |
| Hat-key root leaks | Total compromise: every derivable key is forgeable |
| Wallet KEK leaks but root file is intact | Read root → see compromise above |

The Tier 0 v0 stance: hot hat under wallet KEK is "good enough"
encumbrance for a model where no operator-held economic value lives at
the cell layer. When operator-held value enters the cells (Stripe-paid
invoices, BSV-anchored receipts, customer-facing provenance),
introduce a Tier 1 / Tier 2 split with cold storage — see
`docs/canon/sovereignty-cell-signing.md` §future for the rollout plan.

## Verifying a cell from the helm / mobile

Both UIs treat cell signatures as opaque. Verification happens
brain-side via the Semantos Brain `oddjobz.verify_cell` RPC (Phase 4 B.3) which:

1. Reads the cell's payload + signedBy + signature off disk.
2. Re-derives the expected signing pubkey from the root + scope +
   keyID.
3. Compares the derived pubkey to `signedBy`; verifies the signature.
4. Returns `{ok, mismatchReason?}`.

The helm + mobile don't expose this verb today (Phase 4 B.3 wired the
audit path only); the next operator-tools deliverable adds an "audit
this cell" affordance to job-detail.

## Per-cell vs blanket re-sign

The `brain resign-pending` admin verb (Phase 4 B.4) re-signs every
unsigned cell in the slot store in one shot. Use this:

- After upgrading the canonicalisation rules (would otherwise leave
  pre-upgrade signatures un-verifiable).
- After importing cells from a peer (their derived keys live under
  THEIR root; we need to re-sign under ours).
- After running `legacy migrate-to-graph` (Phase 5 G.1) — the
  migration verb mints fresh graph cells through the Phase 2A.4
  translator, which signs each one through Phase 4's BKDS. No separate
  re-sign needed; the existing v1 flat rows stay unsigned with the
  `legacy` pill (per the Phase 5 G.2 UI extension).

## Future: anchoring + cold tier

Two deferred concerns the BKDS model doesn't currently address:

1. **L1 anchoring** — cells today live in the slot store with no
   on-chain anchor. When an operator wants exportable, third-party-
   verifiable provenance, the future `D-DOG.1.0e — BSV anchoring`
   deliverable adds anchor-tx submission. The anchor wraps the cell's
   content hash; verification under BKDS doesn't change.

2. **Cold tier** — when operator-held economic value enters the cell
   layer, a SEPARATE root with multi-component unlock is introduced.
   The derivation pattern doesn't change; the hot root signs ordinary
   cells, the cold root signs value-bearing cells. UX cost is
   non-trivial (multi-device approval per cold sign) so it's deferred
   until the value justifies it. See
   `docs/canon/sovereignty-cell-signing.md` for the threat model.

## See also

- `docs/canon/sovereignty-cell-signing.md` — what compromise of which
  key gives you, and the operator's recovery story.
- `docs/operator-runbooks/job-graph.md` — graph navigation in helm +
  mobile (this runbook is the signing layer that sits beneath those
  views).
- `docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md` §2 — the signing
  model, written 2026-05-04.
- `runtime/semantos-brain/src/hat_bkds.zig` — the canonicalisation + derivation
  primitives. Read this before extending the signing surface.
