---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.468476+00:00
---

# packages/scada/scada/src/index.ts

```ts
/**
 * @semantos/scada — SCADA Industrial Control Integration
 *
 * Phase 29: Maps SCADA concepts to Semantos cell primitives.
 */

// Core types
export type {
  TelemetryCell,
  CommandCell,
  AlarmCell,
  EquipmentCell,
  SCADASensorType,
  SCADAEquipmentType,
  SCADACommandType,
  QualityFlag,
  OperationalMode,
  HealthStatus,
  AlarmSeverity,
  ExecutionStatus,
  OperatorRole,
  CommandReceipt,
  CommandError,
  InterlockViolation,
  AuditEntry,
  ShiftHandoverReceipt,
  HandoverError,
  IntegrityReport,
  AnomalyReport,
  PlantStatusSummary,
  OPCUANode,
  SCADACapabilityToken,
  InterlockPolicy,
  Result,
} from './types';
export { ROLE_CAPABILITIES } from './types';

// Authorization engine
export { CommandAuthorizationEngine } from './authorization';

// Historian
export { SemanticHistorian } from './historian';

// Plant model
export { PlantModel } from './plant';

// Interlock policies
export {
  highPressureInterlock,
  lowLevelInterlock,
  temperatureRunawayInterlock,
  interlockOverridePolicy,
  emergencyShutdownDualAuth,
  sensorCrossValidation,
} from './policies/interlocks';

// Host functions
export {
  createInterlockEvaluator,
  createTelemetryProvider,
  registerSCADAHostFunctions,
  createSCADAHostFunctionProvider,
} from './policies/host-functions';
export type {
  TelemetryStateProvider,
  DualAuthProvider,
} from './policies/host-functions';

// Protocol adapters
export type {
  OPCUAAdapter,
  ModbusAdapter,
  DNP3Adapter,
  MQTTAdapter,
} from './adapters/types';
export { SCADAMemoryAdapter } from './adapters/memory-adapter';

// CLI
export { parseSCADACommand, routeSCADACommand } from './cli/commands';
export type { SCADAContext, SCADACommand } from './cli/commands';

```
