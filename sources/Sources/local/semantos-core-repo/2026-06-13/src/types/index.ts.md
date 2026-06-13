---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/types/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.398379+00:00
---

# src/types/index.ts

```ts
/**
 * Plexus Type System: Complete Re-exports
 *
 * Central export point for all Plexus semantic types.
 */

// Semantic Objects
export {
  SemanticType,
  isLinear,
  isAffine,
  isRelevant,
} from './semantic-objects.js';

export type {
  SemanticObject,
  LinearObject,
  AffineObject,
  RelevantObject,
  ConsumptionProof,
  RevocationProof,
} from './semantic-objects.js';

// Domain Flags
export {
  PLEXUS_WELL_KNOWN_MIN,
  PLEXUS_WELL_KNOWN_MAX,
  EXTENDED_STANDARD_MIN,
  EXTENDED_STANDARD_MAX,
  CLIENT_SOVEREIGN_MIN,
  CLIENT_SOVEREIGN_MAX,
  EDGE_CREATION,
  SIGNING,
  ENCRYPTION,
  MESSAGING,
  ATTESTATION,
  CHILD_CREATION,
  PERMISSION_GRANT,
  DATA_SOVEREIGNTY,
  SCHEMA_SIGNING,
  METERING,
  classifyFlag,
  isReserved,
  toProtocolId,
} from './domain-flags.js';

export type { DomainFlag } from './domain-flags.js';

// Capabilities
export {
  CapabilityType,
  createRecoveryCapability,
  createPermissionCapability,
  createDataAccessCapability,
  createComputeDelegationCapability,
  createMeteredAccessCapability,
  createTransferCapability,
} from './capability.js';

export type {
  CapabilityConstraints,
  CapabilityConsumptionProof,
  CapabilityToken,
} from './capability.js';

// Transfer Records
export {
  createTransferRecord,
} from './transfer.js';

export type {
  TransferMetadata,
  TransferRecord,
} from './transfer.js';

// Recovery Export
export {
  createRecoveryExportPayload,
} from './recovery.js';

export type {
  ResourceRegistration,
  FunctionalDomainRecord,
  EdgeRecord,
  TenantPathStep,
  AlgorithmVersionRecord,
  SchemaMapping,
  RecoveryExportPayload,
} from './recovery.js';

// Metering
export {
  ChannelState,
  createMeteringChannel,
  createTickProof,
  createSettlementRecord,
} from './metering.js';

export type {
  MeteringChannel,
  TickProof,
  SettlementRecord,
} from './metering.js';

```
