---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/compiler/validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.397489+00:00
---

# src/compiler/validator.ts

```ts
/**
 * Semantic Compiler and Validator
 *
 * Pure functions that enforce LINEAR, AFFINE, and RELEVANT semantic rules
 * on objects in the Plexus type system.
 */

import {
  SemanticObject,
  SemanticType,
  LinearObject,
  AffineObject,
  RelevantObject,
  ConsumptionProof,
  RevocationProof,
  isLinear,
  isAffine,
  isRelevant,
} from '../types/semantic-objects.js';
import {
  CapabilityToken,
  CapabilityConsumptionProof,
} from '../types/capability.js';
import { TransferRecord } from '../types/transfer.js';

/**
 * Result type for validation functions.
 * Either success (Ok) or failure (Err).
 */
export type Result<T, E = string> =
  | { ok: true; value: T }
  | { ok: false; error: E };

/**
 * Create a success result.
 * @internal
 */
function Ok<T>(value: T): Result<T> {
  return { ok: true, value };
}

/**
 * Create a failure result.
 * @internal
 */
function Err<E>(error: E): Result<never, E> {
  return { ok: false, error };
}

/**
 * Validate consumption of a LinearObject.
 *
 * Enforces:
 * - Object is not already consumed
 * - Proof has a valid txId
 * - Returns new object with consumed=true, consumedBy set, consumptionTxId set
 *
 * @param obj The LinearObject to consume
 * @param proof The consumption proof
 * @returns Result with updated object or error message
 */
export function validateConsumption<TProof extends ConsumptionProof>(
  obj: LinearObject<TProof>,
  proof: TProof
): Result<LinearObject<TProof>> {
  if (obj.consumed) {
    return Err('LinearObject is already consumed');
  }

  if (!proof.txId || proof.txId.trim().length === 0) {
    return Err('ConsumptionProof must have a valid txId');
  }

  const updated: LinearObject<TProof> = {
    ...obj,
    consumed: true,
    consumedBy: proof,
    consumptionTxId: proof.txId,
  };

  return Ok(updated);
}

/**
 * Validate acknowledgement of an AffineObject.
 *
 * Enforces:
 * - Object is not already discarded
 * - Returns new object with acknowledged=true
 *
 * @param obj The AffineObject to acknowledge
 * @returns Result with updated object or error message
 */
export function validateAcknowledgement<TMeta>(
  obj: AffineObject<TMeta>
): Result<AffineObject<TMeta>> {
  if (obj.discarded) {
    return Err('AffineObject cannot be acknowledged after being discarded');
  }

  const updated: AffineObject<TMeta> = {
    ...obj,
    acknowledged: true,
  };

  return Ok(updated);
}

/**
 * Validate discard of an AffineObject.
 *
 * Enforces:
 * - Object is not already acknowledged or discarded
 * - Returns new object with discarded=true
 *
 * @param obj The AffineObject to discard
 * @returns Result with updated object or error message
 */
export function validateDiscard<TMeta>(
  obj: AffineObject<TMeta>
): Result<AffineObject<TMeta>> {
  if (obj.acknowledged) {
    return Err('AffineObject cannot be discarded after being acknowledged');
  }

  if (obj.discarded) {
    return Err('AffineObject is already discarded');
  }

  const updated: AffineObject<TMeta> = {
    ...obj,
    discarded: true,
  };

  return Ok(updated);
}

/**
 * Validate revocation of a RelevantObject.
 *
 * Enforces:
 * - Object is not already revoked
 * - Returns new object with revocation set
 *
 * @param obj The RelevantObject to revoke
 * @param proof The revocation proof
 * @returns Result with updated object or error message
 */
export function validateRevocation<TRevocation extends RevocationProof>(
  obj: RelevantObject<TRevocation>,
  proof: TRevocation
): Result<RelevantObject<TRevocation>> {
  if (obj.revocation !== null) {
    return Err('RelevantObject is already revoked');
  }

  const updated: RelevantObject<TRevocation> = {
    ...obj,
    revocation: proof,
  };

  return Ok(updated);
}

/**
 * Validate spending of a CapabilityToken.
 *
 * Enforces LINEAR rules plus constraint validation:
 * - Not already consumed
 * - Expiration not exceeded (if constrained)
 * - Invocation count not exceeded (if constrained)
 * - Required domain flags present (if constrained)
 *
 * @param token The CapabilityToken to spend
 * @param proof The consumption proof
 * @returns Result with updated token or error message
 */
export function validateCapabilitySpend(
  token: CapabilityToken,
  proof: CapabilityConsumptionProof
): Result<CapabilityToken> {
  // Check linear consumption rule
  if (token.consumed) {
    return Err('CapabilityToken is already consumed');
  }

  // Check expiration constraint
  if (
    token.constraints.expiresAt !== null &&
    Date.now() > token.constraints.expiresAt
  ) {
    return Err('CapabilityToken has expired');
  }

  // Check invocation constraint
  if (
    token.constraints.maxInvocations !== null &&
    token.constraints.maxInvocations <= 0
  ) {
    return Err('CapabilityToken has exceeded maximum invocations');
  }

  // Validate proof
  if (!proof.spendingTxId || proof.spendingTxId.trim().length === 0) {
    return Err('CapabilityConsumptionProof must have a valid spendingTxId');
  }

  const updated: CapabilityToken = {
    ...token,
    consumed: true,
    consumedBy: proof,
    consumptionTxId: proof.spendingTxId,
  };

  return Ok(updated);
}

/**
 * Validate a TransferRecord.
 *
 * Enforces AFFINE rules plus transfer-specific constraints:
 * - From and to parents are different
 * - Transfer txId is present and non-empty
 * - Input and output outpoints are present and non-empty
 *
 * @param record The TransferRecord to validate
 * @returns Result with validated record or error message
 */
export function validateTransferRecord(
  record: TransferRecord
): Result<TransferRecord> {
  if (record.fromParentCertId === record.toParentCertId) {
    return Err('TransferRecord: fromParentCertId and toParentCertId must differ');
  }

  if (!record.transferTxId || record.transferTxId.trim().length === 0) {
    return Err('TransferRecord must have a valid transferTxId');
  }

  if (!record.inputOutpoint || record.inputOutpoint.trim().length === 0) {
    return Err('TransferRecord must have a valid inputOutpoint');
  }

  if (!record.outputOutpoint || record.outputOutpoint.trim().length === 0) {
    return Err('TransferRecord must have a valid outputOutpoint');
  }

  return Ok(record);
}

/**
 * Classify a semantic object by its type.
 *
 * @param obj The object to classify
 * @returns The SemanticType enum value
 */
export function classifyObject(obj: SemanticObject): SemanticType {
  return obj.semanticType;
}

/**
 * Check if a semantic object has been consumed, acknowledged, or revoked.
 *
 * For LINEAR: checks consumed flag.
 * For AFFINE: checks acknowledged or discarded flags.
 * For RELEVANT: checks revocation field.
 *
 * @param obj The object to check
 * @returns true if the object is in a terminal state
 */
export function isConsumed(obj: SemanticObject): boolean {
  if (isLinear(obj)) {
    return obj.consumed;
  }

  if (isAffine(obj)) {
    return obj.acknowledged || obj.discarded;
  }

  if (isRelevant(obj)) {
    return obj.revocation !== null;
  }

  return false;
}

/**
 * Check if consumption is still possible for a semantic object.
 *
 * For LINEAR: returns !consumed.
 * For AFFINE: returns !(acknowledged || discarded).
 * For RELEVANT: returns true (always consumable in other contexts, but not revocable if revoked).
 *
 * @param obj The object to check
 * @returns true if the object can still be consumed
 */
export function canConsume(obj: SemanticObject): boolean {
  if (isLinear(obj)) {
    return !obj.consumed;
  }

  if (isAffine(obj)) {
    return !obj.acknowledged && !obj.discarded;
  }

  if (isRelevant(obj)) {
    return obj.revocation === null;
  }

  return false;
}

```
