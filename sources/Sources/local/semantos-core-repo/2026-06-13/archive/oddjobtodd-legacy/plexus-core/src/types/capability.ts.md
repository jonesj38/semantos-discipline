---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/types/capability.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.982546+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/types/capability.ts

```ts
/**
 * Capability Tokens: BRC-108 Identity-Linked Permissions
 *
 * Capabilities are LINEAR semantic objects representing on-chain permissions.
 * Each capability is a UTXO that grants specific rights under defined constraints.
 */

import { LinearObject, ConsumptionProof, SemanticType } from './semantic-objects.js';
import type { DomainFlag } from './domain-flags.js';

/**
 * CapabilityType: Enumeration of capability classes.
 */
export enum CapabilityType {
  /** Recovery authorization (key rotation, backup restoration) */
  RECOVERY = 'RECOVERY',

  /** Permission delegation (acting on behalf of another identity) */
  PERMISSION = 'PERMISSION',

  /** Selective data access (read-only proofs, document sharing) */
  DATA_ACCESS = 'DATA_ACCESS',

  /** Computation delegation (offloaded signing, proof generation) */
  COMPUTE_DELEGATION = 'COMPUTE_DELEGATION',

  /** Usage quota on metered resources (bounded throughput/invocation) */
  METERED_ACCESS = 'METERED_ACCESS',

  /** Transfer authority (capability to transfer assets to new parent) */
  TRANSFER = 'TRANSFER',
}

/**
 * Constraints that limit capability usage.
 */
export interface CapabilityConstraints {
  /** Absolute expiration time (Unix ms). null = no expiry. */
  expiresAt: number | null;

  /** Allowed jurisdictions (ISO 3166-1 alpha-2 codes). null = unrestricted. */
  geoBounds: string[] | null;

  /** Maximum invocations allowed. null = unlimited. */
  maxInvocations: number | null;

  /** Required domain flags for usage. Empty = no restriction. */
  requiredDomainFlags: DomainFlag[];
}

/**
 * Consumption proof specific to capability spending.
 */
export interface CapabilityConsumptionProof extends ConsumptionProof {
  /** Transaction ID where capability was spent (same as txId, for clarity) */
  spendingTxId: string;

  /** Unix timestamp (ms) when spent */
  spentAt: number;

  /** Hex public key of entity that spent the capability */
  spentBy: string;
}

/**
 * CapabilityToken: A LINEAR semantic object representing an on-chain permission.
 *
 * Extends LinearObject with capability-specific fields. Must be consumed exactly once.
 */
export interface CapabilityToken extends LinearObject<CapabilityConsumptionProof> {
  semanticType: SemanticType.LINEAR;

  /** The type of capability (what it authorizes) */
  type: CapabilityType;

  /** Hex hash of the BRC-52 identity certificate that owns this capability */
  ownerCertId: string;

  /** Hex public key from certificate.subject (owner's identity key) */
  ownerPubKey: string;

  /** The locking script that secures this capability UTXO */
  lockingScript: Uint8Array;

  /** Value in satoshis */
  satoshis: number;

  /** Outpoint (txid.vout format). null until mined. */
  outpoint: string | null;

  /** Constraints on how/when the capability can be used */
  constraints: CapabilityConstraints;
}

/**
 * Create a recovery capability.
 *
 * @param ownerCertId Hex cert ID
 * @param ownerPubKey Hex public key
 * @param lockingScript The UTXO script
 * @param satoshis Value in satoshis
 * @param constraints Optional usage constraints
 * @returns A new CapabilityToken of type RECOVERY
 */
export function createRecoveryCapability(
  ownerCertId: string,
  ownerPubKey: string,
  lockingScript: Uint8Array,
  satoshis: number,
  constraints: Partial<CapabilityConstraints> = {}
): CapabilityToken {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    type: CapabilityType.RECOVERY,
    ownerCertId,
    ownerPubKey,
    lockingScript,
    satoshis,
    outpoint: null,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    constraints: {
      expiresAt: constraints.expiresAt ?? null,
      geoBounds: constraints.geoBounds ?? null,
      maxInvocations: constraints.maxInvocations ?? null,
      requiredDomainFlags: constraints.requiredDomainFlags ?? [],
    },
  };
}

/**
 * Create a permission capability.
 *
 * @param ownerCertId Hex cert ID
 * @param ownerPubKey Hex public key
 * @param lockingScript The UTXO script
 * @param satoshis Value in satoshis
 * @param constraints Optional usage constraints
 * @returns A new CapabilityToken of type PERMISSION
 */
export function createPermissionCapability(
  ownerCertId: string,
  ownerPubKey: string,
  lockingScript: Uint8Array,
  satoshis: number,
  constraints: Partial<CapabilityConstraints> = {}
): CapabilityToken {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    type: CapabilityType.PERMISSION,
    ownerCertId,
    ownerPubKey,
    lockingScript,
    satoshis,
    outpoint: null,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    constraints: {
      expiresAt: constraints.expiresAt ?? null,
      geoBounds: constraints.geoBounds ?? null,
      maxInvocations: constraints.maxInvocations ?? null,
      requiredDomainFlags: constraints.requiredDomainFlags ?? [],
    },
  };
}

/**
 * Create a data access capability.
 *
 * @param ownerCertId Hex cert ID
 * @param ownerPubKey Hex public key
 * @param lockingScript The UTXO script
 * @param satoshis Value in satoshis
 * @param constraints Optional usage constraints
 * @returns A new CapabilityToken of type DATA_ACCESS
 */
export function createDataAccessCapability(
  ownerCertId: string,
  ownerPubKey: string,
  lockingScript: Uint8Array,
  satoshis: number,
  constraints: Partial<CapabilityConstraints> = {}
): CapabilityToken {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    type: CapabilityType.DATA_ACCESS,
    ownerCertId,
    ownerPubKey,
    lockingScript,
    satoshis,
    outpoint: null,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    constraints: {
      expiresAt: constraints.expiresAt ?? null,
      geoBounds: constraints.geoBounds ?? null,
      maxInvocations: constraints.maxInvocations ?? null,
      requiredDomainFlags: constraints.requiredDomainFlags ?? [],
    },
  };
}

/**
 * Create a compute delegation capability.
 *
 * @param ownerCertId Hex cert ID
 * @param ownerPubKey Hex public key
 * @param lockingScript The UTXO script
 * @param satoshis Value in satoshis
 * @param constraints Optional usage constraints
 * @returns A new CapabilityToken of type COMPUTE_DELEGATION
 */
export function createComputeDelegationCapability(
  ownerCertId: string,
  ownerPubKey: string,
  lockingScript: Uint8Array,
  satoshis: number,
  constraints: Partial<CapabilityConstraints> = {}
): CapabilityToken {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    type: CapabilityType.COMPUTE_DELEGATION,
    ownerCertId,
    ownerPubKey,
    lockingScript,
    satoshis,
    outpoint: null,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    constraints: {
      expiresAt: constraints.expiresAt ?? null,
      geoBounds: constraints.geoBounds ?? null,
      maxInvocations: constraints.maxInvocations ?? null,
      requiredDomainFlags: constraints.requiredDomainFlags ?? [],
    },
  };
}

/**
 * Create a metered access capability.
 *
 * @param ownerCertId Hex cert ID
 * @param ownerPubKey Hex public key
 * @param lockingScript The UTXO script
 * @param satoshis Value in satoshis
 * @param constraints Optional usage constraints
 * @returns A new CapabilityToken of type METERED_ACCESS
 */
export function createMeteredAccessCapability(
  ownerCertId: string,
  ownerPubKey: string,
  lockingScript: Uint8Array,
  satoshis: number,
  constraints: Partial<CapabilityConstraints> = {}
): CapabilityToken {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    type: CapabilityType.METERED_ACCESS,
    ownerCertId,
    ownerPubKey,
    lockingScript,
    satoshis,
    outpoint: null,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    constraints: {
      expiresAt: constraints.expiresAt ?? null,
      geoBounds: constraints.geoBounds ?? null,
      maxInvocations: constraints.maxInvocations ?? null,
      requiredDomainFlags: constraints.requiredDomainFlags ?? [],
    },
  };
}

/**
 * Create a transfer capability.
 *
 * @param ownerCertId Hex cert ID
 * @param ownerPubKey Hex public key
 * @param lockingScript The UTXO script
 * @param satoshis Value in satoshis
 * @param constraints Optional usage constraints
 * @returns A new CapabilityToken of type TRANSFER
 */
export function createTransferCapability(
  ownerCertId: string,
  ownerPubKey: string,
  lockingScript: Uint8Array,
  satoshis: number,
  constraints: Partial<CapabilityConstraints> = {}
): CapabilityToken {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateResourceId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    type: CapabilityType.TRANSFER,
    ownerCertId,
    ownerPubKey,
    lockingScript,
    satoshis,
    outpoint: null,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    constraints: {
      expiresAt: constraints.expiresAt ?? null,
      geoBounds: constraints.geoBounds ?? null,
      maxInvocations: constraints.maxInvocations ?? null,
      requiredDomainFlags: constraints.requiredDomainFlags ?? [],
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
