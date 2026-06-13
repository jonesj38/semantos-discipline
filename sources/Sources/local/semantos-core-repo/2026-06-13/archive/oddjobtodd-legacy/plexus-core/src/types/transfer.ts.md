---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/types/transfer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.982831+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/types/transfer.ts

```ts
/**
 * Transfer Records: Chain-of-Custody for Identity Objects
 *
 * Transfer records are AFFINE semantic objects that track the movement
 * of identity objects between parents in the identity graph.
 */

import { AffineObject, SemanticType } from './semantic-objects.js';

/**
 * Metadata accompanying a transfer record.
 */
export interface TransferMetadata {
  /** Outpoint of the cap.transfer token that authorized this transfer (txid.vout). null if no token. */
  capTransferOutpoint: string | null;

  /** Whether the edge between old and new parent was verified */
  edgeVerified: boolean;

  /** The child index in the previous parent's tree */
  previousChildIndex: number;

  /** The child index in the new parent's tree */
  newChildIndex: number;
}

/**
 * TransferRecord: An AFFINE semantic object tracking ownership transfer.
 *
 * Represents the movement of an identity object from one parent to another.
 * Can be acknowledged (locked in) or discarded (abandoned).
 */
export interface TransferRecord extends AffineObject<TransferMetadata> {
  semanticType: SemanticType.AFFINE;

  /** Hex hash of the object being transferred (BRC-52 cert or other) */
  objectCertId: string;

  /** Hex hash of the identity certificate that currently owns the object */
  fromParentCertId: string;

  /** Hex hash of the identity certificate that will own the object */
  toParentCertId: string;

  /** Transaction ID where the transfer occurs (hex string) */
  transferTxId: string;

  /** Outpoint of the previous owner's identity output (txid.vout) */
  inputOutpoint: string;

  /** Outpoint of the new owner's identity output (txid.vout) */
  outputOutpoint: string;

  /** Unix timestamp (ms) when transfer was executed */
  transferredAt: number;
}

/**
 * Create a transfer record.
 *
 * @param objectCertId Hex cert ID of object being transferred
 * @param fromParentCertId Hex cert ID of current owner
 * @param toParentCertId Hex cert ID of new owner
 * @param transferTxId Hex transaction ID
 * @param inputOutpoint Outpoint of previous owner (txid.vout)
 * @param outputOutpoint Outpoint of new owner (txid.vout)
 * @param metadata Optional transfer metadata
 * @returns A new TransferRecord
 */
export function createTransferRecord(
  objectCertId: string,
  fromParentCertId: string,
  toParentCertId: string,
  transferTxId: string,
  inputOutpoint: string,
  outputOutpoint: string,
  metadata: Partial<TransferMetadata> = {}
): TransferRecord {
  return {
    semanticType: SemanticType.AFFINE,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    objectCertId,
    fromParentCertId,
    toParentCertId,
    transferTxId,
    inputOutpoint,
    outputOutpoint,
    transferredAt: Date.now(),
    acknowledged: false,
    discarded: false,
    metadata: {
      capTransferOutpoint: metadata.capTransferOutpoint ?? null,
      edgeVerified: metadata.edgeVerified ?? false,
      previousChildIndex: metadata.previousChildIndex ?? 0,
      newChildIndex: metadata.newChildIndex ?? 0,
    },
  };
}

/**
 * Generate a unique resource ID (hex string).
 * @internal
 */
function generateResourceId(): string {
  // In production, use a proper UUID or crypto random
  return Math.random().toString(16).slice(2) + Date.now().toString(16);
}

```
