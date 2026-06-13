---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/types/recovery.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.981687+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/types/recovery.ts

```ts
/**
 * Recovery Export Payload: ~3.4KB Structure
 *
 * Encapsulates the complete recovery state for a Plexus identity.
 * Sufficient to reconstruct all keys and identity relationships after loss.
 */

import type { DomainFlag } from './domain-flags.js';

/**
 * A single resource registration entry.
 * Maps a resource to its current derivation state.
 */
export interface ResourceRegistration {
  /** Hex identifier of the resource */
  resourceId: string;

  /** Hex identifier of the app that owns this resource */
  appId: string;

  /** Domain flag under which this resource is keyed */
  domainFlag: DomainFlag;

  /** Current child index in the derivation tree */
  currentIndex: number;

  /** Version of the key derivation algorithm used */
  algorithmVersion: string;
}

/**
 * A functional domain record.
 * Tracks the state of a domain flag's key derivation path.
 */
export interface FunctionalDomainRecord {
  /** The domain flag identifier */
  domainFlag: DomainFlag;

  /** Human-readable label (e.g., "Signing", "Encryption") */
  label: string;

  /** Current child index for this domain */
  currentIndex: number;

  /** Version of the key derivation algorithm */
  algorithmVersion: string;
}

/**
 * An edge in the identity graph.
 * Represents a relationship with another identity (counterparty).
 */
export interface EdgeRecord {
  /** Hex cert ID of the counterparty identity */
  counterpartyCertId: string;

  /** Index of the signing key used for this edge */
  signingKeyIndex: number;

  /** Type label for this edge (e.g., "parent", "delegate", "trustee") */
  edgeType: string;

  /** Application context (e.g., payment channel ID, attestation context) */
  appContext: string;
}

/**
 * A step in a tenant path.
 * Describes one level in the recovery of a delegated/tenant identity.
 */
export interface TenantPathStep {
  /** Type of tenant (e.g., 0 = direct child, 1 = grandchild) */
  tenantType: number;

  /** Child index within the parent's derivation tree */
  childIndex: number;
}

/**
 * Algorithm version tracking entry.
 * Documents when algorithm versions were active during key derivation.
 */
export interface AlgorithmVersionRecord {
  /** The algorithm version string (e.g., "1.0", "1.1") */
  version: string;

  /** Highest child index before this algorithm was superseded. null = still current. */
  ceilingIndex: number | null;
}

/**
 * Schema mapping for semantic types.
 * Maps raw numeric values to semantic labels and descriptions.
 */
export interface SchemaMapping {
  /** Numeric value (e.g., 0, 1, 2 for semantic types) */
  rawValue: number;

  /** Human-readable label (e.g., "LINEAR", "AFFINE") */
  label: string;

  /** Description of what this value represents */
  description: string;
}

/**
 * RecoveryExportPayload: Complete recovery state export.
 *
 * This ~3.4KB JSON structure contains all data necessary to restore
 * an identity after loss of local keys or device.
 */
export interface RecoveryExportPayload {
  /** Unix timestamp (ms) when export was created */
  exportedAt: number;

  /** Version of the export format (for compatibility) */
  exportVersion: string;

  /** Hex identifier of the identity certificate being exported */
  certId: string;

  /** Array of resource registrations */
  resourceRegistrations: ResourceRegistration[];

  /** Array of functional domain state records */
  functionalDomains: FunctionalDomainRecord[];

  /** Array of identity graph edges */
  edges: EdgeRecord[];

  /** Array of tenant path steps (for delegated identities) */
  tenantPaths: TenantPathStep[];

  /** Array of algorithm version records */
  algorithmVersions: AlgorithmVersionRecord[];

  /** Array of schema mappings */
  schemaMappings: SchemaMapping[];
}

/**
 * Create an empty recovery export payload template.
 *
 * @param certId Hex cert ID to export
 * @returns A new recovery payload with empty arrays
 */
export function createRecoveryExportPayload(certId: string): RecoveryExportPayload {
  return {
    exportedAt: Date.now(),
    exportVersion: '1.0',
    certId,
    resourceRegistrations: [],
    functionalDomains: [],
    edges: [],
    tenantPaths: [],
    algorithmVersions: [],
    schemaMappings: [],
  };
}

```
