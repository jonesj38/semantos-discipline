---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.938809+00:00
---

# core/anchor-attestation/src/types.ts

```ts
/**
 * Anchor-attestation types — RM-042 / H §4.5.
 *
 * An `AnchorAttestation` is a cell that records the on-chain anchor
 * for some target cell. Replaces the pre-RM-042 `OnChainBinding`
 * header region (bytes 160–223 of the target cell's header).
 *
 * The attestation cell:
 *   - has `domain_flag = ANCHOR_ATTESTATION` (0x0001FE02; relocated
 *     from 0x00010102 — audit B-1, SUBSTRATE_SCHEMA page)
 *   - payload is encoded under `anchorAttestationSchemaV2` from
 *     `@semantos/plexus-schema-registry/schemas/anchor-attestation`.
 *     v2 retires the zombie 24B `bumpHash` field (BRC-74 BUMP carries
 *     `blockHeight` natively, not a 24B Merkle-root variant) and
 *     promotes `anchor_height: u64` to a first-class queryable field
 *     so the brain reorg substrate can range-query by height.
 *   - `domainPayloadRoot` in its header binds the payload bytes
 *   - anchoring a cell is now "create an attestation cell pointing at
 *     it" rather than "mutate the target cell's header"
 */

/**
 * Structured anchor-attestation record. Mirrors the field set of
 * `anchorAttestationSchemaV2` so consumers can construct typed
 * attestations before encoding to the schema's byte layout.
 */
export interface AnchorAttestation {
  /** 32B cell-id of the cell being anchored. */
  readonly targetCellId: Uint8Array;
  /** 32B on-chain TXID. */
  readonly txid: Uint8Array;
  /**
   * BSV block height that mined the anchor TX. `u64` is unsafe to
   * coerce into JS `number`, so a `bigint` is used end-to-end.
   * Extracted from the BUMP proof at attestation-mint time.
   */
  readonly anchorHeight: bigint;
  /** Output index within that transaction. */
  readonly vout: number;
  /** Wallet derivation index for the spend that produced the anchor. */
  readonly derivationIndex: number;
}

/** Result of anchor verification — structural success or a typed reason. */
export type VerifyAnchorResult =
  | { ok: true; attestation: AnchorAttestation }
  | { ok: false; code: VerifyAnchorErrorCode; message: string };

export type VerifyAnchorErrorCode =
  | 'TARGET_MISMATCH'      // attestation.targetCellId != requested target
  | 'PAYLOAD_ROOT_MISMATCH' // domainPayloadRoot does not match recomputed root
  | 'INVALID_SCHEMA'        // payload bytes do not decode under anchorAttestationSchemaV2
  | 'INVALID_LENGTHS';      // structural field-length violation (e.g. txid != 32B)

```
