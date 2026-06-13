---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/recovery/recovery/src/export-payload.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.450768+00:00
---

# packages/recovery/recovery/src/export-payload.ts

```ts
/**
 * Recovery export payload assembly.
 * Constructs the ~3.4KB recovery export JSON blob sent to client during recovery.
 */

/**
 * A recovery export payload — the JSON blob sent to client during recovery.
 */
export interface RecoveryExportPayload {
  exportedAt: number;
  exportVersion: number;
  certId: string; // hex, BRC-52 cert hash
  resourceRegistrations: ResourceRegistration[];
  functionalDomains: FunctionalDomainRecord[];
  edges: EdgeExportRecord[];
  tenantPaths: TenantPathRecord[];
  algorithmVersions: AlgorithmVersionRecord[];
  schemaMappings: SchemaMapping[];
}

export interface ResourceRegistration {
  resourceId: string; // hex
  appId: string; // hex
  domainFlag: number; // uint32
  currentIndex: number; // monotonic rotation index
  algorithmVersion: string;
}

export interface FunctionalDomainRecord {
  domainFlag: number;
  label: string;
  currentIndex: number;
  algorithmVersion: string;
}

export interface EdgeExportRecord {
  counterpartyCertId: string; // hex
  signingKeyIndex: number;
  edgeType: string;
  appContext: string;
}

export interface TenantPathRecord {
  contextLabel: string;
  steps: Array<{ tenantType: number; childIndex: number }>;
}

export interface AlgorithmVersionRecord {
  version: string;
  ceilingIndex: number | null; // null = current/latest
}

export interface SchemaMapping {
  rawValue: number;
  label: string;
  description: string;
}

/**
 * Parameters for assembling a recovery export payload.
 */
export interface AssembleParams {
  certId: string;
  registrations: ResourceRegistration[];
  domains: FunctionalDomainRecord[];
  edges: EdgeExportRecord[];
  tenantPaths: TenantPathRecord[];
  versions: AlgorithmVersionRecord[];
  schemas: SchemaMapping[];
  exportVersion?: number;
}

/**
 * Assembles a recovery export payload from raw database records.
 * Canonicalizes to camelCase JSON and sorts arrays deterministically.
 *
 * @param params - Raw records and metadata
 * @returns Assembled and canonicalized payload
 */
export function assembleExportPayload(
  params: AssembleParams
): RecoveryExportPayload {
  return {
    exportedAt: Date.now(),
    exportVersion: params.exportVersion ?? 1,
    certId: params.certId,
    resourceRegistrations: [...params.registrations].sort((a, b) =>
      a.resourceId.localeCompare(b.resourceId)
    ),
    functionalDomains: [...params.domains].sort(
      (a, b) => a.domainFlag - b.domainFlag
    ),
    edges: [...params.edges].sort((a, b) =>
      a.counterpartyCertId.localeCompare(b.counterpartyCertId)
    ),
    tenantPaths: [...params.tenantPaths].sort((a, b) =>
      a.contextLabel.localeCompare(b.contextLabel)
    ),
    algorithmVersions: [...params.versions].sort((a, b) =>
      a.version.localeCompare(b.version)
    ),
    schemaMappings: [...params.schemas].sort(
      (a, b) => a.rawValue - b.rawValue
    ),
  };
}

/**
 * Estimates the approximate byte size of a recovery export payload JSON.
 * Typical payloads are around 3,400 bytes.
 *
 * @param payload - The payload to measure
 * @returns Approximate byte size
 */
export function estimatePayloadSize(payload: RecoveryExportPayload): number {
  const json = canonicalizePayload(payload);
  return new TextEncoder().encode(json).length;
}

/**
 * Type guard: validates that an unknown value matches RecoveryExportPayload shape.
 */
export function validateExportPayload(
  payload: unknown
): payload is RecoveryExportPayload {
  if (typeof payload !== 'object' || payload === null) {
    return false;
  }

  const p = payload as Record<string, unknown>;

  return (
    typeof p.exportedAt === 'number' &&
    typeof p.exportVersion === 'number' &&
    typeof p.certId === 'string' &&
    Array.isArray(p.resourceRegistrations) &&
    Array.isArray(p.functionalDomains) &&
    Array.isArray(p.edges) &&
    Array.isArray(p.tenantPaths) &&
    Array.isArray(p.algorithmVersions) &&
    Array.isArray(p.schemaMappings)
  );
}

/**
 * Serializes a payload to deterministic JSON with sorted keys.
 * Used for signing and canonical representation.
 *
 * @param payload - The payload to serialize
 * @returns JSON string with consistent key ordering
 */
export function canonicalizePayload(payload: RecoveryExportPayload): string {
  return JSON.stringify(payload, Object.keys(payload).sort());
}

```
