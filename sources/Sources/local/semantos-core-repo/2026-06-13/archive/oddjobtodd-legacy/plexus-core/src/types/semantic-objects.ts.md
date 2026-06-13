---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/types/semantic-objects.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.983116+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/types/semantic-objects.ts

```ts
/**
 * Semantic Object Type System
 *
 * The core innovation of Plexus: a classification system that enforces
 * consumption rules on stored cryptographic objects.
 */

/**
 * SemanticType enum classifies objects by their consumption semantics.
 */
export enum SemanticType {
  /** Must be consumed exactly once. No reuse. */
  LINEAR = 'LINEAR',
  /** Can be consumed (acknowledged) or discarded. Optional consumption. */
  AFFINE = 'AFFINE',
  /** Always accessible, never consumed, can be revoked separately. */
  RELEVANT = 'RELEVANT',
}

/**
 * Base interface for all semantic objects.
 * Every Plexus-managed object must implement this.
 */
export interface SemanticObject {
  /** The semantic classification of this object */
  semanticType: SemanticType;

  /** Unique identifier for the resource (hex string) */
  resourceId: string;

  /** Unix timestamp (ms) when object was created */
  createdAt: number;

  /** Schema version for evolution tracking */
  schemaVersion: number;
}

/**
 * Proof that a LinearObject was consumed.
 */
export interface ConsumptionProof {
  /** Transaction ID where consumption occurred (hex string) */
  txId: string;

  /** Unix timestamp (ms) of consumption */
  timestamp: number;

  /** Hex public key of the consumer */
  consumerId: string;

  /** Hex signature proving authorization */
  signature: string;
}

/**
 * Proof that a RelevantObject was revoked.
 */
export interface RevocationProof {
  /** Unix timestamp (ms) when revocation occurred */
  revokedAt: number;

  /** Hex public key of the revoker */
  revokedBy: string;

  /** Human-readable reason for revocation */
  reason: string;

  /** Outpoint where revocation was recorded (txid.vout format) */
  revocationOutpoint: string;
}

/**
 * LinearObject: Must be consumed exactly once.
 *
 * Represents single-use resources: capability UTXOs, payment channel states,
 * authorization tokens. Once consumed, cannot be used again.
 *
 * @template TConsumptionProof The proof type for consumption (defaults to ConsumptionProof)
 */
export interface LinearObject<TConsumptionProof = ConsumptionProof>
  extends SemanticObject {
  semanticType: SemanticType.LINEAR;

  /** Whether this object has been consumed */
  consumed: boolean;

  /** Proof of consumption (null if not yet consumed) */
  consumedBy: TConsumptionProof | null;

  /** Transaction ID where consumption occurred (null if not yet consumed) */
  consumptionTxId: string | null;
}

/**
 * AffineObject: Can be consumed (acknowledged) or discarded.
 *
 * Represents optional-consumption resources: transfer records, proof-of-custody docs.
 * Can transition to acknowledged (consumed once and locked) or discarded (never acknowledged).
 *
 * @template TMeta Type of metadata attached to the object
 */
export interface AffineObject<TMeta = null> extends SemanticObject {
  semanticType: SemanticType.AFFINE;

  /** Whether this object has been acknowledged (consumed) */
  acknowledged: boolean;

  /** Whether this object has been discarded without acknowledgement */
  discarded: boolean;

  /** Optional metadata associated with this object */
  metadata: TMeta | null;
}

/**
 * RelevantObject: Always accessible, can be revoked separately.
 *
 * Represents long-lived, repeatedly-accessible resources: BRC-52 identity certificates,
 * schema definitions. Never "consumed" but can be revoked by issuer.
 *
 * @template TRevocation Type of revocation proof (defaults to RevocationProof)
 */
export interface RelevantObject<TRevocation = RevocationProof>
  extends SemanticObject {
  semanticType: SemanticType.RELEVANT;

  /** Revocation proof (null if not revoked) */
  revocation: TRevocation | null;

  /** Unix timestamp (ms) of last validation against the blockchain */
  lastValidatedAt: number;
}

/**
 * Type guard: Check if object is LINEAR.
 */
export function isLinear<T extends SemanticObject>(
  obj: T
): obj is T & LinearObject {
  return obj.semanticType === SemanticType.LINEAR;
}

/**
 * Type guard: Check if object is AFFINE.
 */
export function isAffine<T extends SemanticObject>(
  obj: T
): obj is T & AffineObject {
  return obj.semanticType === SemanticType.AFFINE;
}

/**
 * Type guard: Check if object is RELEVANT.
 */
export function isRelevant<T extends SemanticObject>(
  obj: T
): obj is T & RelevantObject {
  return obj.semanticType === SemanticType.RELEVANT;
}

```
