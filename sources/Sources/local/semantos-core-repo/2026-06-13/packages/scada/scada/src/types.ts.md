---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.468765+00:00
---

# packages/scada/scada/src/types.ts

```ts
/**
 * SCADA Object Types — Phase 29
 *
 * Maps SCADA concepts to Semantos cell primitives with linearity semantics:
 * - TelemetryCell (AFFINE): sensor readings, no duplication
 * - CommandCell (LINEAR): control commands, consumed on execution
 * - AlarmCell (LINEAR): alarms that MUST be acknowledged
 * - EquipmentCell (RELEVANT): equipment records, cannot be deleted
 */

// ── Linearity Modes ────────────────────────────────────────────

export type CellLinearity = 'LINEAR' | 'AFFINE' | 'RELEVANT';

// ── Sensor Taxonomy (WHAT axis) ────────────────────────────────

export type SCADASensorType =
  | 'sensor.temperature.thermocouple'
  | 'sensor.temperature.rtd'
  | 'sensor.pressure.gauge'
  | 'sensor.pressure.differential'
  | 'sensor.flow.electromagnetic'
  | 'sensor.flow.ultrasonic'
  | 'sensor.flow.coriolis'
  | 'sensor.level.radar'
  | 'sensor.level.ultrasonic'
  | 'sensor.vibration.accelerometer'
  | 'sensor.gas.detector'
  | 'sensor.ph'
  | 'sensor.conductivity';

// ── Equipment Taxonomy (WHAT axis) ─────────────────────────────

export type SCADAEquipmentType =
  | 'actuator.valve.gate'
  | 'actuator.valve.globe'
  | 'actuator.valve.ball'
  | 'actuator.valve.butterfly'
  | 'actuator.motor.fixed-speed'
  | 'actuator.motor.variable-speed'
  | 'actuator.relay.circuit-breaker'
  | 'actuator.relay.contactor'
  | 'equipment.pump.centrifugal'
  | 'equipment.pump.positive-displacement'
  | 'equipment.compressor'
  | 'equipment.heat-exchanger'
  | 'equipment.reactor'
  | 'equipment.tank';

// ── Command Taxonomy ───────────────────────────────────────────

export type SCADACommandType =
  | 'valve.open'
  | 'valve.close'
  | 'valve.set-position'
  | 'motor.start'
  | 'motor.stop'
  | 'motor.set-speed'
  | 'setpoint.change'
  | 'mode.change'
  | 'alarm.acknowledge'
  | 'alarm.silence'
  | 'emergency.shutdown';

// ── Quality Flags (OPC UA) ─────────────────────────────────────

export type QualityFlag = 'GOOD' | 'UNCERTAIN' | 'BAD';

// ── Operational Mode (HOW axis) ────────────────────────────────

export type OperationalMode = 'MANUAL' | 'AUTOMATIC' | 'CASCADE' | 'OVERRIDE' | 'SHUTDOWN';

// ── Health Status ──────────────────────────────────────────────

export type HealthStatus = 'HEALTHY' | 'DEGRADED' | 'FAULTED' | 'OFFLINE';

// ── Alarm Severity ─────────────────────────────────────────────

export type AlarmSeverity = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

// ── Execution Status ───────────────────────────────────────────

export type ExecutionStatus = 'pending' | 'executed' | 'rejected' | 'timed-out';

// ── Operator Roles ─────────────────────────────────────────────

export type OperatorRole =
  | 'junior-operator'
  | 'senior-operator'
  | 'shift-supervisor'
  | 'plant-manager'
  | 'safety-officer';

/** Capability numbers each role is entitled to. */
export const ROLE_CAPABILITIES: Record<OperatorRole, number[]> = {
  'junior-operator': [1, 2],
  'senior-operator': [1, 2, 3, 4],
  'shift-supervisor': [1, 2, 3, 4, 5, 6],
  'plant-manager': [1, 2, 3, 4, 5, 6, 7, 8],
  'safety-officer': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
};

/**
 * Capability number semantics:
 * 1 = read telemetry
 * 2 = acknowledge alarms
 * 3 = operate valves
 * 4 = change setpoints
 * 5 = override interlocks (non-CRITICAL only)
 * 6 = mode changes
 * 7 = equipment commissioning/decommissioning
 * 8 = emergency shutdown
 * 9 = policy installation
 * 10 = policy modification
 */

// ── Core Cell Types ────────────────────────────────────────────

/** A telemetry reading as an AFFINE semantic cell. */
export interface TelemetryCell {
  cellId: string;
  sensorId: string;
  sensorType: SCADASensorType;
  value: number;
  unit: string;
  quality: QualityFlag;
  timestamp: string;
  samplingMethod: string;
  purpose: string;
  previousReadingCell?: string;
  linearity: 'AFFINE';
  hash?: string;
  consumed?: boolean;
}

/** A control command as a LINEAR capability cell. */
export interface CommandCell {
  cellId: string;
  commandType: SCADACommandType;
  targetEquipment: string;
  parameters: Record<string, unknown>;
  issuedBy: string;
  authorizedBy: Uint8Array;
  timestamp: string;
  executionStatus: ExecutionStatus;
  rejectionReason?: string;
  previousCommandCell?: string;
  linearity: 'LINEAR';
  consumed?: boolean;
}

/** An alarm requiring acknowledgment — LINEAR cell. */
export interface AlarmCell {
  cellId: string;
  alarmId: string;
  severity: AlarmSeverity;
  source: string;
  condition: string;
  value: number;
  timestamp: string;
  acknowledgedBy?: string;
  acknowledgedAt?: string;
  previousAlarmCell?: string;
  linearity: 'LINEAR';
  consumed?: boolean;
}

/** Equipment state model — RELEVANT cell. */
export interface EquipmentCell {
  cellId: string;
  equipmentId: string;
  equipmentType: SCADAEquipmentType;
  operationalMode: OperationalMode;
  healthStatus: HealthStatus;
  lastMaintenance?: string;
  installedPolicies: string[];
  childEquipment?: string[];
  previousStateCell?: string;
  linearity: 'RELEVANT';
}

// ── Result Type ────────────────────────────────────────────────

export type Result<T, E = string> =
  | { ok: true; value: T }
  | { ok: false; error: E };

// ── Command Authorization Types ────────────────────────────────

export interface CommandReceipt {
  commandCellId: string;
  executionStatus: ExecutionStatus;
  timestamp: string;
  operatorId: string;
  targetEquipment: string;
  commandType: SCADACommandType;
  interlocksPassed: number;
  auditTrail: AuditEntry[];
  /** Phase 29.5: Anchor transaction ID (if anchor emitter is configured). */
  anchorTxId?: string;
}

export interface AuditEntry {
  step: string;
  result: 'pass' | 'fail';
  detail: string;
  timestamp: string;
}

export interface InterlockViolation {
  policyId: string;
  policyName: string;
  reason: string;
  sensorId?: string;
  currentValue?: number;
  threshold?: number;
}

export interface CommandError {
  code: 'NO_IDENTITY' | 'NO_CAPABILITY' | 'EXPIRED_CAPABILITY' | 'CONSUMED_CAPABILITY'
    | 'INTERLOCK_VIOLATION' | 'INSUFFICIENT_ROLE' | 'DUAL_AUTH_REQUIRED' | 'EXECUTION_FAILED';
  message: string;
  violations?: InterlockViolation[];
}

// ── Shift Handover Types ───────────────────────────────────────

export interface ShiftHandoverReceipt {
  receiptCellId: string;
  outgoingOperator: string;
  incomingOperator: string;
  supervisor: string;
  capabilitiesTransferred: number;
  unacknowledgedAlarms: string[];
  timestamp: string;
}

export interface HandoverError {
  code: 'NO_SUPERVISOR_AUTH' | 'INVALID_OPERATOR' | 'TRANSFER_FAILED';
  message: string;
}

// ── Historian Types ────────────────────────────────────────────

export interface IntegrityReport {
  sensorId: string;
  cellCount: number;
  chainValid: boolean;
  hashesValid: boolean;
  gaps: Array<{ from: string; to: string }>;
  tamperDetected: boolean;
}

export interface AnomalyReport {
  sensorId: string;
  window: string;
  anomalies: Array<{
    cellId: string;
    timestamp: string;
    value: number;
    expectedRange: { min: number; max: number };
    semanticDistance: number;
    severity: AlarmSeverity;
  }>;
}

// ── Plant Model Types ──────────────────────────────────────────

export interface PlantStatusSummary {
  totalEquipment: number;
  healthy: number;
  degraded: number;
  faulted: number;
  offline: number;
  activeAlarms: { low: number; medium: number; high: number; critical: number };
  unacknowledgedAlarms: number;
  activeOperators: Array<{ id: string; role: OperatorRole; shiftEnd: string }>;
}

// ── Protocol Adapter Types ─────────────────────────────────────

export interface OPCUANode {
  nodeId: string;
  displayName: string;
  nodeClass: string;
}

// ── Capability Token ───────────────────────────────────────────

export interface SCADACapabilityToken {
  tokenId: string;
  operatorId: string;
  role: OperatorRole;
  capabilities: number[];
  shiftStart: string;
  shiftEnd: string;
  grantedBy: string;
  consumed: boolean;
  cellBytes: Uint8Array;
}

// ── Interlock Policy ───────────────────────────────────────────

export interface InterlockPolicy {
  policyId: string;
  name: string;
  description: string;
  targetAction: SCADACommandType;
  targetEquipment?: string;
  severity: AlarmSeverity;
  compiledBytes: Uint8Array;
  scriptWords: string;
}

```
