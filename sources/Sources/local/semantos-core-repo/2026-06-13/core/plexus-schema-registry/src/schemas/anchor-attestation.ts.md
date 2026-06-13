---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/schemas/anchor-attestation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.949056+00:00
---

# core/plexus-schema-registry/src/schemas/anchor-attestation.ts

```ts
/**
 * Anchor-attestation domain schema — RM-042 / H §4.5.
 *
 * Anchoring a cell on-chain no longer mutates the target cell's header
 * (the old `OnChainBinding` region at bytes 160–223). Instead, an
 * `AnchorAttestation` cell is created whose payload binds the tuple
 * `(targetCellId, txid, anchorHeight, vout, derivationIndex)` via this
 * schema. Verifiers walk the attestation cell.
 *
 * Registered under `SemantosDomainFlags.ANCHOR_ATTESTATION = 0x0001FE02`
 * per RM-004 (relocated from 0x00010102 — audit B-1, SUBSTRATE_SCHEMA page).
 *
 * ## Schema version
 *
 * This is the **v2** payload. v1 carried a 24B `bumpHash` field that was
 * never read or written outside test scaffolding — BRC-74 BUMP encodes
 * `blockHeight` natively rather than a 24B Merkle-root variant, so the
 * field was substrate noise rather than substrate truth. v2 retires
 * `bumpHash` and promotes `anchor_height: u64` to a first-class
 * queryable field; the height is what the brain's reorg-sweep substrate
 * needs to enumerate "every attestation whose anchor block is in the
 * rolled-back height range" via the `cells_by_anchor_height` projection.
 *
 * Cutover is hard: no v1 decoder is shipped, because there are no v1
 * attestation cells in production (V1 production is test data; see
 * project memory `v1_production_is_test_data.md`).
 *
 * NB on the constant name `ANCHOR_ATTESTATION_V1` (in
 * `core/constants/constants.json`'s `domainFlags` block) and its
 * generated Zig form `DOMAIN_FLAG_ANCHOR_ATTESTATION_V1`: the `V1`
 * suffix there refers to the **dispatch-value generation** (the
 * post-audit-B-1 canonical wire value at the substrate-schema page),
 * NOT to the schema version. Schema and dispatch-value are
 * independently versioned: dispatch stays V1 (one canonical value),
 * the payload layout is now v2. The constant name is intentionally
 * preserved to avoid rippling the rename through every Zig caller.
 *
 * ## Field layout (80 bytes encoded; padded to 80 by `encodePayload`):
 *
 *   - targetCellId    u256 @ 0   — the cell being anchored (32B)
 *   - txid            u256 @ 32  — the on-chain TXID (32B)
 *   - anchor_height   u64  @ 64  — BSV block height that mined the
 *                                  anchor TX, little-endian (8B). Extracted
 *                                  from the BUMP proof at attestation-mint
 *                                  time. Promoted to a first-class field
 *                                  in v2 so the brain's reorg substrate
 *                                  can range-query by height directly.
 *   - vout            u32  @ 72  — output index in that TX (4B)
 *   - derivationIndex u32  @ 76  — wallet derivation index for the
 *                                  spend that produced the anchor (4B)
 *
 * Field-ordering rationale: `targetCellId` (offset 0) and `txid`
 * (offset 32) are unchanged from v1 so the brain's attestation
 * observer (`cell_store_lmdb.zig:doPut`) and the
 * `cells_by_anchor_txid` reverse index keep their existing offsets.
 * `anchor_height` takes the slot where `bumpHash` used to live
 * (payload offset 64); the smaller scalars (`vout`, `derivationIndex`)
 * shift left correspondingly, packing the payload to 80B total.
 */
import type { DomainSchema } from '../types.js';

export const ANCHOR_ATTESTATION_DOMAIN_FLAG = 0x0001fe02;

export const anchorAttestationSchemaV2: DomainSchema = {
  domainFlag: ANCHOR_ATTESTATION_DOMAIN_FLAG,
  version: 2,
  commitmentMode: 'payload-digest',
  fields: [
    { name: 'targetCellId', offset: 0, size: 32, type: 'u256' },
    { name: 'txid', offset: 32, size: 32, type: 'u256' },
    { name: 'anchor_height', offset: 64, size: 8, type: 'u64' },
    { name: 'vout', offset: 72, size: 4, type: 'u32' },
    { name: 'derivationIndex', offset: 76, size: 4, type: 'u32' },
  ],
};

/** Anchor-attestation payload shape — what `encodePayload(anchorAttestationSchemaV2, ...)` expects. */
export interface AnchorAttestationPayload {
  /** 32B cell-id of the cell being anchored. */
  targetCellId: Uint8Array;
  /** 32B on-chain transaction ID. */
  txid: Uint8Array;
  /**
   * BSV block height that mined the anchor TX. `u64` doesn't fit
   * safely in JS `number`, so this is a `bigint`. Stored little-endian
   * in the payload bytes (matching the rest of the cell's numeric
   * encoding); the LMDB key in `cells_by_anchor_height` separately
   * uses big-endian so lexicographic sort matches numeric sort for
   * range queries.
   */
  anchor_height: bigint;
  /** Output index in that transaction. */
  vout: number;
  /** Wallet derivation index for the spend that produced the anchor. */
  derivationIndex: number;
}

```
