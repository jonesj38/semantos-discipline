---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/sovereignty-cell-signing.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.635710+00:00
---

# Sovereignty implications of BKDS cell signing

D-DOG.1.0c Phase 4 retrofitted per-cell BKDS signing across the
oddjobz cell-DAG. This document captures the threat model: what each
class of compromise gives an attacker, what the operator's recovery
story is, and why the deferred cold tier is the right call for v0.

## Threat model summary

The signing model has exactly one secret on the operator's side: the
**hat-key root**, a 32-byte secret stored AES-GCM-encrypted under the
wallet KEK at `~/.semantos/data/brain/hat-root.enc`. Every cell signing
key is derived from this root via BRC-42 BKDS using the per-cell scope
`(protocolID = "oddjobz.cell-sign/v1", keyID = <cell-content-hash>,
counterparty = <operator-domain-identity>)`.

There are no other secrets at the cell layer. No threshold sigs, no
vault, no per-cell stored privkeys. Derived signing keys exist for
exactly one signature operation, then are discarded.

## Compromise classes

| Class | What the attacker has | What they can do | Operator recovery |
|---|---|---|---|
| Single derived signing key | Implausible — derived keys aren't stored anywhere | Forge that one cell's signature only (every other cell uses a different key) | Re-sign by re-deriving from root |
| Wallet KEK leak (passphrase guess / disclosure) | Can read the encrypted root file → root | See "root compromise" below | Rotate root immediately (see §rotation) |
| Hat-key root leak | The 32-byte root | Total compromise: forge ANY cell signature, past or future, that's under `oddjobz.cell-sign/v1` | Re-derive new root via BRC-52 cert flow's BRC-42 BKDS recovery enrolment; emit a `signing-protocol/v2` bump for new cells |
| Cell payload tampering on disk | Mutated bytes in `jobs.jsonl` etc. | Signature verification fails (keyID changes → derived pubkey would change → no match) | None needed — the mutation is detectable, no rollback risk |
| Cell signature stripped | Cell payload OK but `signature` field empty/zero | Cell verifiably unsigned; helm + mobile mark it with a warning | Run `brain resign-pending` (Phase 4 B.4) to re-sign |
| Brain disk loss / theft (encrypted) | The root file but not the wallet passphrase | Nothing — KEK protects the root | Restore from BRC-52 BKDS recovery enrolment |
| Brain disk + passphrase loss | Total operator-side loss | None — every BKDS escrow flow is bilateral, the operator's enrolled recovery counterparty (their phone or paired-buddy device per the existing wallet runbook) restores | Standard wallet recovery; cells re-verify under the recovered root |

## Why hot-only is sufficient (Tier 0 v0)

The earlier scoping had a tiered hot-pocket / cold-multisig vault.
**Operator clarified that's overkill for v0** because:

- No customer payments flow through oddjobz initially (Stripe may bolt
  on later).
- Customers don't have BSV — no near-term BSV-denominated invoicing.
- Therefore no operator-held economic value at the cell layer that
  needs cold-tier protection.

A signing key whose compromise costs the operator hours of cleanup
(forging some receipts, regenerating the graph from email backfill)
but no cash deserves hot-tier encumbrance, not cold. The KEK is the
right encumbrance.

## Why root compromise is total — and why that's OK

A single root + deterministic derivation means every derivable key is
forgeable once the root is known. There's no compartmentalisation
within the cell layer.

This is the right trade-off because:

1. **Privacy property is real**: each cell's `signedBy` field is a
   different pubkey. A third party with no root access cannot cluster
   cells by signing key — they see N unrelated pubkeys for N cells.
   Compartmentalisation between cells exists in the visible-outside
   sense, just not in the recover-from-root sense.

2. **Audit trail is real**: anyone with the root can verify ANY
   cell's signature deterministically. There's no black-box opaque
   lookup needed; verification = re-derive + check.

3. **Recovery cost matches the value**: when the cell layer holds
   nothing economic, "rotate root + re-sign every cell" is a
   recoverable cleanup, not a catastrophic loss. The 30-90 minutes of
   re-derivation + re-signing under a fresh root buys the simplicity.

When operator-held value enters the cells, this calculus flips. See
§future for the Tier 1 / Tier 2 split.

## Per-cell vs blanket re-sign after compromise

After a root compromise + rotation:

1. Derive a new root (`root_v2`) via the standard wallet flow.
2. Bump the protocol scope: `oddjobz.cell-sign/v1` → `/v2`.
3. Run `brain resign-pending --protocol v2` (extension of the Phase 4
   B.4 admin verb) to re-sign every cell under the new root + new
   scope. Existing v1 signatures stay verifiable under root_v1 — the
   compromise window's audit trail is preserved, but new cells under
   v2 use the fresh root.
4. The compromised root_v1 is destroyed; future verification of cells
   minted before rotation requires looking up which protocol version
   their `signedBy` was issued under. (The BCA module's verifier
   accepts both versions transparently.)

The dual-version coexistence is identical in shape to a TLS
certificate rotation — old certs validate old data, new certs validate
new data, the verifier accepts both during the migration window.

## Recovery story (lost brain disk, root intact via BRC-52)

The operator's standard wallet recovery flow uses BRC-52 cert
issuance + BRC-42 BKDS recovery enrolment. The recovery counterparty
(typically the operator's phone, or a paired-buddy device) holds the
escrowed root reconstruction material.

Recovery proceeds:

1. Operator initiates recovery on a fresh brain disk via the wallet's
   `brain device init --recover` path.
2. The BRC-52 cert flow re-derives the root from the recovery
   counterparty's contribution + the operator's recovery passphrase.
3. Once the root is back in `~/.semantos/data/brain/hat-root.enc`,
   `brain verify-cells --all` walks every signed cell and confirms its
   signature derives correctly under the recovered root. Mismatches
   indicate a cell that was tampered between the last backup and the
   loss event — flagged for operator review.
4. No re-signing is needed for cells that verify; the root is the
   same secret it was, the derivation is deterministic.

This is the property that makes the per-cell discard-after-sign model
viable: derived keys are cheap to recompute, expensive to store, and
recovery is a single-step root reconstruction.

## Future: Tier 1 / Tier 2 split when value enters the cells

The deferred work item, tracked separately:

When operator-held economic value enters the cell layer (Stripe-paid
invoices become signed cells, customer-facing receipts need
cryptographic provenance to outsiders, BSV-anchored cells get
exported), introduce a SECOND root with multi-component unlock:

| Tier | Cells signed under it | Encumbrance |
|---|---|---|
| Hot (v0, current) | Ordinary work-tracking cells (jobs, sites, customers, attachments) | Single root, KEK-encrypted |
| Cold (deferred) | Value-bearing cells (paid invoices, exportable receipts, anchored cells) | Multi-component unlock — operator-device + paired-buddy approval per cold sign |

The derivation pattern doesn't change. The cold root signs a
separate-but-overlapping subset of cells (the value-bearing ones); the
hot root signs everything else. Verification under either root works
identically — the cell's `signedBy` field tells the verifier which
root to derive against.

UX cost is non-trivial: cold signs require multi-device approval per
cell, which is fine for invoice-creation rate (a handful per week) but
infeasible for ratify rate (dozens per day). The Tier 1 / Tier 2 split
naturally clusters signs around the rate — high-rate ordinary signs
under hot, low-rate value signs under cold.

The operator's prior pattern ("ship the value, harden after") supports
deferring this until the cells actually carry value worth the cold-
tier UX cost. Not before.

## See also

- `docs/operator-runbooks/cell-signing-bkds.md` — the operational
  recovery procedure for re-deriving any single cell's signing key.
- `docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md` §2 — the v0
  signing model decision (revised 2026-05-04).
- `runtime/semantos-brain/src/hat_bkds.zig` — the canonicalisation + derivation
  primitives.
- `core/cell-engine/src/bca.zig` — the BRC-42 BKDS reference
  implementation underlying the derivation calls.
- The wallet's existing BRC-52 cert flow + BRC-42 BKDS recovery
  enrolment runbook (already in operator hands, not duplicated here).
