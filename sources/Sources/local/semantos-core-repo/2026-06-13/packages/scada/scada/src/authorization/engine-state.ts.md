---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/engine-state.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.471615+00:00
---

# packages/scada/scada/src/authorization/engine-state.ts

```ts
/**
 * Engine state — internal mutable bookkeeping shared between the
 * facade and its flow modules.
 *
 * The facade owns one `EngineState` instance and passes it to the
 * `issueCommand`, `evaluateInterlocks`, `acknowledgeAlarm`, and
 * `shiftHandover` flow modules. Keeping the maps in a single record
 * (instead of a constellation of fields on the facade class) lets the
 * flow modules stay framework-agnostic and individually testable.
 */

import type {
  AlarmCell,
  CommandCell,
  InterlockPolicy,
  OperatorRole,
  SCADACapabilityToken,
  TelemetryCell,
} from '../types';

export interface OperatorRecord {
  role: OperatorRole;
  active: boolean;
}

export interface EngineState {
  /** Active capability tokens indexed by operator ID. */
  capabilities: Map<string, SCADACapabilityToken[]>;
  /** Consumed capability token IDs (LINEAR — no replay). */
  consumedTokens: Set<string>;
  /** Registered operator identities. */
  operators: Map<string, OperatorRecord>;
  /** Active interlock policies indexed by equipment ID. */
  interlocksByEquipment: Map<string, InterlockPolicy[]>;
  /** Current telemetry state for interlock evaluation. */
  telemetryState: Map<string, TelemetryCell>;
  /** Command DAG — previous command per equipment. */
  lastCommandByEquipment: Map<string, string>;
  /** All command cells for audit. */
  commandCells: Map<string, CommandCell>;
  /** Alarm store. */
  alarms: Map<string, AlarmCell>;
}

/** Construct a fresh, empty engine state. */
export function makeEngineState(): EngineState {
  return {
    capabilities: new Map(),
    consumedTokens: new Set(),
    operators: new Map(),
    interlocksByEquipment: new Map(),
    telemetryState: new Map(),
    lastCommandByEquipment: new Map(),
    commandCells: new Map(),
    alarms: new Map(),
  };
}

```
