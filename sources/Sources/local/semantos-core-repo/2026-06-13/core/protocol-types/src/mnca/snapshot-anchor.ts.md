---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/snapshot-anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.900629+00:00
---

# core/protocol-types/src/mnca/snapshot-anchor.ts

```ts
/**
 * Snapshot anchoring — wrap a computed MNCA snapshot cell as a pushdrop
 * UTXO so the compute result becomes a spendable, permanently-recorded
 * economic object on BSV.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §3 (pushdrop) +
 * `docs/design/WALLET-TIER-CUSTODY.md` (tiered custody / BRC-42 leaves).
 *
 * ── KEY-PROVENANCE PATTERN (preserve across C6 → Pi → M1) ──────────────
 * Per the tiered-vault model + G9 invariant: every on-chain spend uses a
 * FRESH BRC-42 leaf key — the per-tier base key never signs directly. Cell
 * anchoring is a frequent, low-value action, so it uses a **Tier-0** leaf.
 *
 * The leaf derivation is injected via the `LeafDeriver` port. That port is
 * the seam where the platform-specific ROOT plugs in:
 *   - XIAO ESP32-C6 : eFuse value as the chip-side hash input
 *   - Mac / browser : Tier-0 vault blob read from IndexedDB
 *   - Orange Pi     : Tier-0 blob from lmdb
 * The same anchoring logic runs on all three because the root lives behind
 * the port (mirrors the engine's `host_derive_leaf`). This module never
 * sees a base key or a private key.
 *
 * ── WHAT THIS IS NOT ───────────────────────────────────────────────────
 * Pure data. No signing, no @bsv/sdk, no ARC. It produces the typed
 * `AnchorPlan` a wallet consumes: the pushdrop locking script + the leaf
 * the wallet must derive-and-OP_SIGN. The actual sign + tx-build + broadcast
 * happen at the wallet/engine boundary (the mesh-bsv-sink, Week 4).
 */

import { createHash } from 'node:crypto';
import { CELL_SIZE, HeaderOffsets } from '../constants';
import {
  buildPushdropLockingScript,
  COMPRESSED_PUBKEY_SIZE,
} from '../cell-pushdrop';
import {
  buildOpFalseIfCarrierScript,
  buildOpDropP2pkhCarrierScript,
  PKH_SIZE,
  type DataCarrierShape,
} from '../cell-data-carriers';

const TYPE_HASH_OFFSET = HeaderOffsets.typeHash; // 30
const TYPE_HASH_SIZE = 32;

/**
 * BRC-42 leaf-key derivation port. Returns the 33-byte compressed pubkey of
 * a freshly-derived Tier-0 leaf for the given (protocol, counterparty,
 * index). The per-tier base key + platform root (eFuse / IndexedDB / lmdb)
 * live entirely behind this port — prod injects the real BRC-42 deriver
 * (`bsvz primitives.ec.deriveChild`); tests inject a deterministic stub.
 */
export interface LeafDeriver {
  deriveLeafPubkey(input: {
    /** 16-byte BRC-43 protocolID hash. */
    protocolHash: Uint8Array;
    /** 33-byte counterparty pubkey (e.g. self / "anyone"). */
    counterparty: Uint8Array;
    /** BKDS invoice number — a fresh value yields a fresh leaf (G9). */
    index: bigint;
  }): Uint8Array; // 33-byte compressed pubkey
}

/** A pure-data plan a wallet uses to anchor a snapshot UTXO. */
export interface AnchorPlan {
  /** Locking-script bytes, shape determined by `carrier`. */
  lockingScript: Uint8Array;
  /** Which carrier shape produced lockingScript — caller's L13 choice. */
  carrier: DataCarrierShape;
  /** Satoshi value to lock into the anchor output. */
  satoshis: bigint;
  /** The fresh Tier-0 BRC-42 leaf pubkey owning the output. */
  ownerPubkey: Uint8Array;
  /** The BKDS invoice index the leaf was derived at (so the wallet re-derives + OP_SIGNs it). */
  leafIndex: bigint;
  /** The snapshot cell bytes anchored (recoverable from the locking script). */
  cellBytes: Uint8Array;
}

export interface BuildSnapshotAnchorPlanInput {
  /** A 1024-byte computed cell to anchor. */
  snapshotCell: Uint8Array;
  /** The leaf-derivation port (platform root behind it). */
  deriver: LeafDeriver;
  /** 16-byte BRC-43 protocolID hash for the anchor protocol. */
  protocolHash: Uint8Array;
  /** 33-byte counterparty pubkey. */
  counterparty: Uint8Array;
  /** BKDS invoice index — MUST be fresh per anchor (G9: no leaf reuse). */
  index: bigint;
  /** Satoshi value for the anchor output (> 0). */
  anchorSats: bigint;
  /**
   * If provided, assert the cell's typeHash (offset 30) equals this — the
   * caller passes `computeMncaTypeHash("mnca.snapshot")` to guarantee only
   * snapshot cells are anchored under this protocol. Omit to anchor any cell.
   */
  expectedTypeHash?: Uint8Array;
  /**
   * Carrier-script shape for the locking script. Defaults to `'pushdrop'`
   * (the historical behaviour — `<cell> OP_DROP <pubkey> OP_CHECKSIG`,
   * 1063 bytes for a 1024B cell).
   *
   * L13 alternatives:
   *   - `'op_false_op_if'`: `OP_FALSE OP_IF <cell> OP_ENDIF <pubkey> OP_CHECKSIG`
   *     (1065 bytes). IF body is unreachable; cell is pure data carriage.
   *     Decouples data from drop semantics — useful when downstream BSV
   *     indexers get confused by OP_DROP-of-large-push.
   *   - `'op_drop_p2pkh'`: `<cell> OP_DROP OP_DUP OP_HASH160 <pkh20> OP_EQUALVERIFY OP_CHECKSIG`
   *     (1053 bytes). Trailing P2PKH = most wallet-compatible spend
   *     shape. Verified live on Teranode regtest (idattr-onchain anchor
   *     tx 068093ae…97840580, 2026-06-02). pkh20 is hash160 of the
   *     ownerPubkey, computed inline.
   *
   * CW Lift L13 (docs/canon/cw-lift-matrix.yml).
   */
  carrier?: DataCarrierShape;
}

/** True when the cell's typeHash (offset 30) equals `typeHash`. */
export function cellHasType(cell: Uint8Array, typeHash: Uint8Array): boolean {
  if (cell.length < TYPE_HASH_OFFSET + TYPE_HASH_SIZE) return false;
  if (typeHash.length !== TYPE_HASH_SIZE) return false;
  for (let i = 0; i < TYPE_HASH_SIZE; i++) {
    if (cell[TYPE_HASH_OFFSET + i] !== typeHash[i]) return false;
  }
  return true;
}

/**
 * Build a pushdrop anchor plan for a computed snapshot cell. Derives a fresh
 * Tier-0 BRC-42 leaf via the injected port and locks the cell under it.
 */
export function buildSnapshotAnchorPlan(input: BuildSnapshotAnchorPlanInput): AnchorPlan {
  const { snapshotCell, deriver, protocolHash, counterparty, index, anchorSats } = input;

  if (snapshotCell.length !== CELL_SIZE) {
    throw new Error(`buildSnapshotAnchorPlan: cell must be ${CELL_SIZE} bytes (got ${snapshotCell.length})`);
  }
  if (anchorSats <= 0n) {
    throw new Error(`buildSnapshotAnchorPlan: anchorSats must be > 0 (got ${anchorSats})`);
  }
  if (protocolHash.length !== 16) {
    throw new Error(`buildSnapshotAnchorPlan: protocolHash must be 16 bytes (got ${protocolHash.length})`);
  }
  if (counterparty.length !== COMPRESSED_PUBKEY_SIZE) {
    throw new Error(`buildSnapshotAnchorPlan: counterparty must be ${COMPRESSED_PUBKEY_SIZE} bytes (got ${counterparty.length})`);
  }
  if (input.expectedTypeHash && !cellHasType(snapshotCell, input.expectedTypeHash)) {
    throw new Error('buildSnapshotAnchorPlan: cell typeHash does not match expectedTypeHash (not a snapshot)');
  }

  // Fresh Tier-0 leaf (G9: never reuse a leaf / never sign with the base key).
  const ownerPubkey = deriver.deriveLeafPubkey({ protocolHash, counterparty, index });
  if (ownerPubkey.length !== COMPRESSED_PUBKEY_SIZE) {
    throw new Error(`buildSnapshotAnchorPlan: deriver must return a ${COMPRESSED_PUBKEY_SIZE}-byte compressed pubkey (got ${ownerPubkey.length})`);
  }

  const carrier: DataCarrierShape = input.carrier ?? 'pushdrop';
  const lockingScript = buildLockingScriptForCarrier(carrier, snapshotCell, ownerPubkey);
  return {
    lockingScript,
    carrier,
    satoshis: anchorSats,
    ownerPubkey: ownerPubkey.slice(),
    leafIndex: index,
    cellBytes: snapshotCell.slice(),
  };
}

/**
 * Build the locking-script bytes for a given L13 carrier choice.
 * Variants (a) and (b) use the 33-byte ownerPubkey directly; variant
 * (c) hashes it to a 20-byte pkh inline (hash160 = RIPEMD160(SHA256)).
 */
function buildLockingScriptForCarrier(
  carrier: DataCarrierShape,
  cellBytes: Uint8Array,
  ownerPubkey: Uint8Array,
): Uint8Array {
  switch (carrier) {
    case 'pushdrop':
      return buildPushdropLockingScript(cellBytes, ownerPubkey);
    case 'op_false_op_if':
      return buildOpFalseIfCarrierScript(cellBytes, ownerPubkey);
    case 'op_drop_p2pkh': {
      const pkh = hash160(ownerPubkey);
      if (pkh.byteLength !== PKH_SIZE) {
        // Defensive: hash160 always yields 20 bytes; this would only fire
        // on a node:crypto-environment bug.
        throw new Error(
          `buildLockingScriptForCarrier: hash160 produced ${pkh.byteLength} bytes (expected ${PKH_SIZE})`,
        );
      }
      return buildOpDropP2pkhCarrierScript(cellBytes, pkh);
    }
    default: {
      // Exhaustiveness check — the type system catches new carriers
      // added to DataCarrierShape without a corresponding case here.
      const _exhaustive: never = carrier;
      throw new Error(`buildLockingScriptForCarrier: unknown carrier ${_exhaustive}`);
    }
  }
}

/**
 * hash160 = RIPEMD-160(SHA-256(input)) — the canonical BSV/Bitcoin
 * key-hash derivation. Used by carrier `'op_drop_p2pkh'` to convert
 * a 33-byte compressed pubkey into the 20-byte pkh that P2PKH locks
 * pay to.
 */
function hash160(input: Uint8Array): Uint8Array {
  const sha = createHash('sha256').update(input).digest();
  const ripe = createHash('ripemd160').update(sha).digest();
  return new Uint8Array(ripe);
}

/**
 * Build anchor plans for a batch of snapshots, each under its OWN fresh leaf
 * (index i+startIndex). Returns one plan per cell, index-aligned. Useful when
 * a node anchors several tiles' snapshots in one wallet round.
 */
export function buildSnapshotAnchorBatch(
  cells: Uint8Array[],
  shared: Omit<BuildSnapshotAnchorPlanInput, 'snapshotCell' | 'index'> & { startIndex: bigint },
): AnchorPlan[] {
  return cells.map((snapshotCell, i) =>
    buildSnapshotAnchorPlan({
      snapshotCell,
      deriver: shared.deriver,
      protocolHash: shared.protocolHash,
      counterparty: shared.counterparty,
      anchorSats: shared.anchorSats,
      expectedTypeHash: shared.expectedTypeHash,
      carrier: shared.carrier,
      index: shared.startIndex + BigInt(i),
    }),
  );
}

/** Total satoshis a batch of anchor plans will lock on-chain. */
export function totalAnchorCostSats(plans: AnchorPlan[]): bigint {
  return plans.reduce((sum, p) => sum + p.satoshis, 0n);
}

```
