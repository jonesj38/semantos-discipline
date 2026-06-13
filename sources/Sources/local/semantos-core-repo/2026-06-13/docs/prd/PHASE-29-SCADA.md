---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-29-SCADA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.660037+00:00
---

# Phase 29 — SCADA Industrial Control Integration

**Version**: 1.0
**Date**: March 2026
**Status**: Exploratory — independent track (can start after Phase 18)
**Duration**: 8 weeks (with 40% buffer: 11.2 weeks)
**Prerequisites**: Phase 18 complete (metering control plane — FSM governance, evidence trails). Phase 25.5 complete (OP_CALLHOST + HostFunctionRegistry — host function dispatch for domain predicates like `sensor-reading`, `sensor-quality`). Phase 16 recommended (edge + capability integration for secure command authorization). Phase 8.5 recommended (identity facets for operator roles). Phase 21 recommended (Lisp policy compiler for safety interlock authoring).
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + `COMMERCIAL-CONTEXT.md`
**Branch**: `phase-29-scada`

---

## Context

SCADA (Supervisory Control And Data Acquisition) systems monitor and control industrial processes — power grids, water treatment, oil pipelines, manufacturing lines. They are the nervous system of physical infrastructure. They are also, architecturally, stuck in the 1990s: proprietary protocols, flat permission models, no formal ownership semantics, and audit trails that are afterthoughts bolted onto historians.

Semantos addresses every one of these gaps:

- **Telemetry as semantic objects.** A sensor reading isn't a row in a time-series database. It's a cell with taxonomy coordinates (WHAT = measurement type, HOW = sampling method, WHY = safety/operational purpose), linearity semantics, and a provenance chain.
- **Command authorization via capability tokens.** Opening a valve isn't an API call with a password. It's a LINEAR capability cell consumed by the operator's identity facet. The capability is gone after use — no replay attacks, no shared credentials.
- **Safety interlocks as compiled policies.** "Don't open the bypass valve if pressure exceeds 150 PSI" isn't a comment in C code. It's a Lisp policy that compiles to opcodes the cell engine evaluates before the command executes.
- **Tamper-evident historian.** Each telemetry reading is a cell in a DAG. Each cell references the previous reading. Tampering with historical data breaks the DAG — the cell engine detects the inconsistency at the hash level (Phase 2 BCA derivation).
- **Operator identity with role facets.** An operator authenticates with an identity facet (Phase 8.5) that carries role-specific capabilities: shift supervisor can override alarms, junior operator cannot. The capability model is the same one Semantos uses for governance ballots and trade authorization.

### Why SCADA

SCADA is the highest-stakes application domain for semantic objects. A duplicated game sword is annoying. A duplicated trade is expensive. A duplicated control command to a gas pipeline valve can be catastrophic. LINEAR semantics aren't a nice-to-have — they are a safety requirement.

The IEC 62443 standard for industrial cybersecurity already calls for: role-based access control, audit trails, integrity verification, and least-privilege command authorization. Semantos provides all of these as structural properties of the runtime, not as compliance checklists.

### Three-Axis Taxonomy for Industrial Control

```
WHAT (measurement/control):  sensor.temperature.thermocouple
                              sensor.pressure.differential
                              sensor.flow.electromagnetic
                              actuator.valve.gate
                              actuator.motor.variable-speed
                              actuator.relay.circuit-breaker

HOW (operational mode):       normal → warning → alarm → emergency → shutdown
                              manual → automatic → cascade → override

WHY (purpose):                safety.process-protection
                              safety.personnel-protection
                              operational.efficiency
                              operational.quality-control
                              compliance.environmental
                              compliance.iec-62443
```

### The Compression Gradient (Industrial Domain)

```
Safety engineer: "don't open the bypass valve if reactor pressure exceeds 150 PSI"
    ↓ (policy authoring)
(define-policy bypass-valve-interlock
  :subject operator
  :action open-valve
  :constraint (and
    (target-eq?)                           ;; context: target = "bypass-valve-BV-101"
    (pressure-below-limit?)                ;; context: sensor PT-101 < 150.0 PSI
    (has-capability 3))                    ;; capability 3 = "valve operation"
  :linearity LINEAR)
    ↓ (Lisp compiler)
"target-eq?" OP_CALLHOST "pressure-below-limit?" OP_CALLHOST BOOLAND 3 OP_CHECKCAPABILITY BOOLAND VERIFY
    ↓ (cell engine)
2-PDA evaluates → command authorized or rejected at opcode level
    ↓ (audit)
Command cell created in historian DAG — tamper-evident record
```

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `TYPES:PROTO` | `packages/protocol-types/src/index.ts` | Cell header types, linearity modes — map to telemetry/command cells |
| `IDENTITY:FACET` | `packages/loom/src/services/identity/` | Identity facets — map to operator roles |
| `CAPABILITY:TYPES` | `src/types/capability.ts` | Capability tokens — map to command authorizations |
| `LISP:COMPILER` | `packages/shell/src/lisp/compiler.ts` | Policy compiler — map to safety interlocks |
| `METERING:FSM` | `packages/metering/src/` | FSM governance — map to operational mode state machines |
| `EDGE:SECURE` | `src/kernel/edge.ts` | ECDH-secured edges — map to encrypted telemetry channels |
| `DAG:PERSIST` | `packages/plexus-vendor-sdk/src/graph/` | DAG persistence — map to historian data |
| `TRANSFER:CORE` | `src/kernel/transfer.ts` | Transfer protocol — map to shift handover |
| `EMBED:SERVICE` | `packages/loom/src/services/EmbeddingService.ts` | Embedding service — map to anomaly detection |
| `BCA:DERIVE` | `packages/cell-engine/src/bca.ts` | BCA derivation — hash-linked cell integrity |
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | HostFunctionRegistry class — register SCADA predicates (sensor-reading?, sensor-quality?, etc.) |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering domain predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |

---

## Deliverables

### D29.1 — SCADA Object Types

**File**: `packages/scada/src/types.ts`

Type definitions mapping SCADA concepts to Semantos primitives:

```typescript
/** A telemetry reading as a semantic cell */
interface TelemetryCell {
  cellId: string;
  sensorId: string;                        // e.g., "TT-101" (temperature transmitter)
  sensorType: SCADASensorType;             // taxonomy WHAT coordinate
  value: number;
  unit: string;                            // e.g., "PSI", "°C", "m³/h"
  quality: 'GOOD' | 'UNCERTAIN' | 'BAD';  // OPC UA quality flags
  timestamp: string;                       // ISO 8601 with microsecond precision
  samplingMethod: string;                  // taxonomy HOW coordinate
  purpose: string;                         // taxonomy WHY coordinate
  previousReadingCell?: string;            // DAG link to prior reading
  linearity: 'AFFINE';                    // readings can be consumed (acknowledged) but not duplicated
}

/** A control command as a LINEAR capability cell */
interface CommandCell {
  cellId: string;
  commandType: SCADACommandType;
  targetEquipment: string;                 // e.g., "BV-101" (bypass valve)
  parameters: Record<string, unknown>;     // command-specific params (setpoint, position, etc.)
  issuedBy: string;                        // operator identity facet
  authorizedBy: Uint8Array;               // capability cell proving operator has rights
  timestamp: string;
  executionStatus: 'pending' | 'executed' | 'rejected' | 'timed-out';
  previousCommandCell?: string;            // DAG link to prior command on this equipment
  linearity: 'LINEAR';                    // command consumed on execution — no replay
}

/** An alarm as a semantic cell requiring acknowledgment */
interface AlarmCell {
  cellId: string;
  alarmId: string;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  source: string;                          // sensor or equipment ID
  condition: string;                       // "pressure > 150 PSI"
  value: number;                           // triggering value
  timestamp: string;
  acknowledgedBy?: string;                 // operator identity who consumed this alarm
  acknowledgedAt?: string;
  previousAlarmCell?: string;              // DAG link
  linearity: 'LINEAR';                    // alarm MUST be consumed (acknowledged) — can't be silently dropped
}

/** Equipment state model */
interface EquipmentCell {
  cellId: string;
  equipmentId: string;                     // tag number, e.g., "P-101" (pump)
  equipmentType: SCADAEquipmentType;
  operationalMode: OperationalMode;
  healthStatus: 'HEALTHY' | 'DEGRADED' | 'FAULTED' | 'OFFLINE';
  lastMaintenance?: string;
  installedPolicies: string[];             // cell IDs of safety interlock policies
  childEquipment?: string[];               // hierarchical plant model
  previousStateCell?: string;              // DAG link
  linearity: 'RELEVANT';                  // equipment records must be kept — can't be destroyed
}

type OperationalMode = 'MANUAL' | 'AUTOMATIC' | 'CASCADE' | 'OVERRIDE' | 'SHUTDOWN';

type SCADASensorType =
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

type SCADAEquipmentType =
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

type SCADACommandType =
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
```

**Critical constraints**:
- Telemetry cells are AFFINE: they can be consumed (acknowledged, processed) but never duplicated. No phantom readings.
- Command cells are LINEAR: consumed on execution. A command cannot be replayed. The capability token is spent.
- Alarm cells are LINEAR: they MUST be acknowledged (consumed). An unacknowledged alarm cannot be silently discarded.
- Equipment cells are RELEVANT: they must be kept in the system. You cannot delete an equipment record. Decommissioning creates a new cell with `OFFLINE` status.
- All cells link to their predecessor via `previousCell` — creating a tamper-evident chain per sensor, per equipment, per operator.

---

### D29.2 — Command Authorization Engine

**File**: `packages/scada/src/authorization.ts`

Capability-based command authorization built on Phase 16 edges:

```typescript
class CommandAuthorizationEngine {
  /** Issue a command — validates operator capability, evaluates safety interlocks, executes */
  issueCommand(
    command: CommandCell,
    operatorIdentity: string,              // identity facet ID
    capabilityToken: Uint8Array            // LINEAR capability cell
  ): Result<CommandReceipt, CommandError>;

  /** Evaluate all safety interlocks for a command */
  evaluateInterlocks(
    command: CommandCell,
    currentState: Map<string, TelemetryCell>  // latest readings for relevant sensors
  ): Result<void, InterlockViolation[]>;

  /** Grant operator capability for a shift */
  grantShiftCapability(
    operatorId: string,
    role: OperatorRole,
    shiftStart: string,
    shiftEnd: string,
    grantedBy: string                      // shift supervisor identity
  ): Uint8Array;                           // LINEAR capability cell valid for shift duration

  /** Shift handover — transfer capabilities from outgoing to incoming operator */
  shiftHandover(
    outgoingOperator: string,
    incomingOperator: string,
    capabilities: Uint8Array[],
    supervisorAuthorization: Uint8Array
  ): Result<ShiftHandoverReceipt, HandoverError>;
}

type OperatorRole = 'junior-operator' | 'senior-operator' | 'shift-supervisor' | 'plant-manager' | 'safety-officer';

interface OperatorCapabilities {
  'junior-operator': number[];             // e.g., [1, 2] — can read telemetry, acknowledge alarms
  'senior-operator': number[];             // e.g., [1, 2, 3, 4] — plus operate valves, change setpoints
  'shift-supervisor': number[];            // e.g., [1, 2, 3, 4, 5, 6] — plus override interlocks, mode changes
  'plant-manager': number[];               // e.g., [1-8] — plus emergency shutdown
  'safety-officer': number[];              // e.g., [1-10] — all capabilities including policy modification
}
```

**Command execution flow**:
1. Verify operator identity (Phase 8.5 facet authentication)
2. Verify capability token is valid and unexpired (LINEAR — consumed on verification)
3. Load all safety interlock policies for the target equipment
4. Evaluate each interlock against current telemetry state (compiled Lisp → 2-PDA)
5. If all interlocks pass: execute command, create command cell in DAG
6. If any interlock fails: reject command, create rejection cell with violation details
7. Return receipt with full audit trail

**Shift handover** (maps to Phase 17 transfer protocol):
1. Outgoing operator's capability cells are transferred to incoming operator
2. Transfer requires supervisor authorization (third-party capability cell)
3. All active alarms are reviewed and acknowledged or transferred
4. Handover receipt cell created with timestamps, operator IDs, transferred capabilities

---

### D29.3 — Safety Interlock Policies (Lisp)

**File**: `packages/scada/src/policies/`

Safety interlocks as compiled Lisp constraints:

```lisp
;; High-pressure interlock — block valve open if pressure exceeds limit
;; Context set before evaluation: { target: "BV-101", sensorId: "PT-101", sensorValue: <live>, threshold: 150.0 }
(define-policy high-pressure-interlock
  :subject operator
  :action valve.open
  :constraint (and
    (target-eq?)                            ;; context: target matches expected
    (pressure-below-limit?)                 ;; context: sensorValue < threshold (150 PSI)
    (sensor-quality-good?)                  ;; context: sensor health check
    (has-capability 3))                     ;; capability 3 = valve operation
  :linearity LINEAR)

;; Low-level interlock — block pump start if tank level below minimum
;; Context: { target: "P-101", sensorId: "LT-101", sensorValue: <live>, threshold: 20.0 }
(define-policy low-level-interlock
  :subject operator
  :action motor.start
  :constraint (and
    (target-eq?)                            ;; context: target = "P-101"
    (level-above-minimum?)                  ;; context: sensorValue > threshold (20%)
    (sensor-quality-good?)                  ;; context: sensor quality = GOOD
    (has-capability 4))                     ;; capability 4 = motor operation
  :linearity LINEAR)

;; Temperature runaway protection — emergency shutdown if temperature exceeds critical
;; Context: { sensorId: "TT-201", sensorValue: <live>, threshold: 500.0 }
(define-policy temperature-runaway
  :subject system                          ;; automatic, no operator required
  :action emergency.shutdown
  :constraint (and
    (temperature-above-critical?)           ;; context: sensorValue > threshold (500°C)
    (sensor-quality-good?))                 ;; context: only on valid reading
  :linearity LINEAR)

;; Override interlock — shift supervisor can bypass non-critical interlocks
(define-policy interlock-override
  :subject shift-supervisor
  :action override-interlock
  :constraint (and
    (not (= interlock-severity "CRITICAL"))  ;; cannot override CRITICAL interlocks
    (has-capability 5)                       ;; capability 5 = interlock override
    (time-after shift-start)
    (time-before shift-end))
  :linearity LINEAR)

;; Dual-authorization for emergency shutdown
(define-policy emergency-shutdown-dual-auth
  :subject plant-manager
  :action emergency.shutdown
  :constraint (and
    (has-capability 8)                     ;; capability 8 = emergency shutdown
    (has-dual-authorization "safety-officer"))  ;; requires two-person authorization
  :linearity LINEAR)

;; Sensor cross-validation — require agreement between redundant sensors
(define-policy sensor-cross-validation
  :subject system
  :action accept-reading
  :constraint (or
    ;; Both sensors agree within tolerance
    (< (abs (- (sensor-reading "TT-201A") (sensor-reading "TT-201B"))) 5.0)
    ;; One sensor is BAD quality — use the GOOD one
    (and (= (sensor-quality "TT-201A") "BAD")
         (= (sensor-quality "TT-201B") "GOOD"))
    (and (= (sensor-quality "TT-201B") "BAD")
         (= (sensor-quality "TT-201A") "GOOD")))
  :linearity AFFINE)
```

- CRITICAL interlocks cannot be overridden by any operator role
- Non-critical interlocks require shift-supervisor capability to override
- Emergency shutdown requires dual authorization (two identity facets)
- Sensor cross-validation handles redundant sensor disagreement
- Each policy compiles to capability cells via Phase 21

---

### D29.4 — Semantic Historian

**File**: `packages/scada/src/historian.ts`

Tamper-evident data historian built on the cell DAG:

```typescript
class SemanticHistorian {
  /** Record a telemetry reading — creates cell linked to previous reading */
  record(reading: TelemetryCell): string;  // returns cellId

  /** Query readings for a sensor within a time range */
  query(
    sensorId: string,
    from: string,                          // ISO 8601
    to: string,
    options?: { maxPoints?: number; aggregation?: 'none' | 'avg' | 'min' | 'max' }
  ): TelemetryCell[];

  /** Verify integrity of a reading chain — check DAG hash consistency */
  verifyIntegrity(
    sensorId: string,
    from: string,
    to: string
  ): IntegrityReport;

  /** Detect anomalies using embedding service (Phase 23) */
  detectAnomalies(
    sensorId: string,
    window: string,                        // e.g., "1h", "24h", "7d"
    threshold: number                      // semantic distance threshold
  ): AnomalyReport;

  /** Export readings in standard formats */
  export(
    sensorIds: string[],
    from: string,
    to: string,
    format: 'csv' | 'json' | 'opc-ua-json'
  ): string;
}

interface IntegrityReport {
  sensorId: string;
  cellCount: number;
  chainValid: boolean;                     // all DAG links intact
  hashesValid: boolean;                    // all BCA hashes verify
  gaps: Array<{ from: string; to: string }>;  // time gaps in the chain
  tamperDetected: boolean;
}

interface AnomalyReport {
  sensorId: string;
  window: string;
  anomalies: Array<{
    cellId: string;
    timestamp: string;
    value: number;
    expectedRange: { min: number; max: number };
    semanticDistance: number;               // embedding distance from "normal" cluster
    severity: 'LOW' | 'MEDIUM' | 'HIGH';
  }>;
}
```

**Integrity model**:
- Each telemetry cell's `previousReadingCell` link creates a per-sensor hash chain
- Cell hashes use BCA derivation (Phase 2) — SHA-256 of cell contents
- Verifying integrity = walking the chain and re-computing hashes
- Any tampering (modified value, deleted reading, inserted fake reading) breaks the chain
- Gaps in the chain are detected by timestamp discontinuity

**Anomaly detection** (uses Phase 23 embedding service):
- Embed each reading as a vector: [value, rate-of-change, time-of-day, day-of-week, sensor-quality]
- Compute semantic distance from the "normal operating" cluster centroid
- Readings beyond the threshold are flagged as anomalies
- This is a proof-of-concept — production anomaly detection requires domain-specific ML models

---

### D29.5 — Plant Model

**File**: `packages/scada/src/plant.ts`

Hierarchical plant topology as a semantic graph:

```typescript
class PlantModel {
  /** Register equipment in the plant hierarchy */
  registerEquipment(equipment: EquipmentCell, parentId?: string): string;

  /** Get equipment by tag number */
  getEquipment(equipmentId: string): EquipmentCell | null;

  /** Get all child equipment (e.g., all instruments on a reactor) */
  getChildren(equipmentId: string): EquipmentCell[];

  /** Get equipment hierarchy path (e.g., Plant > Area > Unit > Equipment) */
  getPath(equipmentId: string): EquipmentCell[];

  /** Get all sensors associated with equipment */
  getSensors(equipmentId: string): TelemetryCell[];

  /** Get all interlocks installed on equipment */
  getInterlocks(equipmentId: string): string[];  // policy cell IDs

  /** Get plant-wide status summary */
  getPlantStatus(): PlantStatusSummary;
}

interface PlantStatusSummary {
  totalEquipment: number;
  healthy: number;
  degraded: number;
  faulted: number;
  offline: number;
  activeAlarms: { low: number; medium: number; high: number; critical: number };
  unacknowledgedAlarms: number;            // LINEAR alarm cells not yet consumed
  activeOperators: Array<{ id: string; role: OperatorRole; shiftEnd: string }>;
}
```

- Plant hierarchy is a DAG in Plexus (Phase 15) with typed edges
- Equipment → sensor relationships are RELEVANT edges (can't be deleted)
- Interlock → equipment bindings are policy attachments (Phase 21)
- The model supports ISA-95 / IEC 62264 hierarchy: Enterprise > Site > Area > Unit > Equipment

---

### D29.6 — Protocol Adapters (Stubs)

**File**: `packages/scada/src/adapters/`

Stub adapters for standard SCADA protocols — interfaces only, not full implementations:

```typescript
/** OPC UA adapter — the modern standard */
interface OPCUAAdapter {
  connect(endpoint: string): Promise<void>;
  subscribe(nodeId: string, callback: (reading: TelemetryCell) => void): string;
  writeCommand(nodeId: string, command: CommandCell): Promise<CommandReceipt>;
  browse(startNode?: string): Promise<OPCUANode[]>;
}

/** Modbus adapter — legacy but ubiquitous */
interface ModbusAdapter {
  connect(host: string, port: number): Promise<void>;
  readHoldingRegisters(address: number, count: number): Promise<TelemetryCell[]>;
  writeRegister(address: number, value: number, authorization: Uint8Array): Promise<CommandReceipt>;
}

/** DNP3 adapter — power grid / water treatment */
interface DNP3Adapter {
  connect(host: string, port: number): Promise<void>;
  poll(stationAddress: number): Promise<TelemetryCell[]>;
  selectBeforeOperate(point: number, value: number, authorization: Uint8Array): Promise<CommandReceipt>;
}

/** MQTT adapter — IIoT telemetry */
interface MQTTAdapter {
  connect(broker: string): Promise<void>;
  subscribe(topic: string, callback: (reading: TelemetryCell) => void): string;
  publish(topic: string, command: CommandCell): Promise<CommandReceipt>;
}
```

- These are **interface definitions only** — concrete implementations are out of scope for this phase
- Each adapter wraps protocol-specific I/O with Semantos cell semantics
- Reads produce TelemetryCell objects; writes consume CommandCell objects
- All adapters route through the authorization engine before issuing commands
- A stub `MemoryAdapter` implements all four interfaces for testing

---

### D29.7 — Shell Integration

**File**: `packages/scada/src/cli/`

Shell commands for SCADA operations:

```bash
semantos scada plant status
  → Returns PlantStatusSummary

semantos scada telemetry read TT-101
  → Returns latest reading for temperature transmitter TT-101

semantos scada telemetry history TT-101 --from 2026-03-01 --to 2026-03-30
  → Returns reading history with integrity check

semantos scada telemetry verify TT-101 --from 2026-03-01 --to 2026-03-30
  → Verifies historian chain integrity for sensor

semantos scada command issue valve.open BV-101 --operator OP-001
  → Issues command, validates interlocks, returns receipt

semantos scada alarm list --unacknowledged
  → Lists unacknowledged alarm cells

semantos scada alarm acknowledge ALM-1774 --operator OP-001
  → Consumes alarm cell (LINEAR acknowledgment)

semantos scada shift handover --from OP-001 --to OP-002 --supervisor SUP-001
  → Transfers shift capabilities between operators

semantos scada anomaly detect TT-101 --window 24h --threshold 0.8
  → Runs embedding-based anomaly detection
```

---

## TDD Gate — Tests That Must Pass

### Test 1: Telemetry Cells (TypeScript)

```typescript
describe("D29.1 — Telemetry cells", () => {
  test("reading creates AFFINE cell with sensor metadata", () => {});
  test("readings form a per-sensor DAG chain", () => {});
  test("reading cannot be duplicated (AFFINE enforcement)", () => {});
  test("timestamp has microsecond precision", () => {});
  test("OPC UA quality flags map correctly", () => {});
});
```

### Test 2: Command Authorization (TypeScript)

```typescript
describe("D29.2 — Command authorization", () => {
  test("command with valid capability executes and consumes token", () => {});
  test("command without capability is rejected", () => {});
  test("expired capability token is rejected", () => {});
  test("capability replay (same token twice) fails — LINEAR consumed", () => {});
  test("junior operator cannot issue motor.start (insufficient capability)", () => {});
  test("shift supervisor can issue motor.start", () => {});
});
```

### Test 3: Safety Interlocks (TypeScript)

```typescript
describe("D29.3 — Safety interlocks", () => {
  test("high-pressure interlock blocks valve open when pressure > 150", () => {});
  test("high-pressure interlock allows valve open when pressure < 150", () => {});
  test("low-level interlock blocks pump start when level < 20%", () => {});
  test("BAD sensor quality blocks command that depends on that sensor", () => {});
  test("CRITICAL interlock cannot be overridden even by shift supervisor", () => {});
  test("non-critical interlock can be overridden with supervisor capability", () => {});
  test("emergency shutdown requires dual authorization", () => {});
});
```

### Test 4: Historian Integrity (TypeScript)

```typescript
describe("D29.4 — Historian integrity", () => {
  test("100 readings form a valid hash chain", () => {});
  test("modifying a reading's value breaks chain verification", () => {});
  test("inserting a fake reading breaks chain verification", () => {});
  test("deleting a reading creates a detectable gap", () => {});
  test("integrity report correctly identifies tampered chains", () => {});
  test("query returns readings in chronological order", () => {});
});
```

### Test 5: Alarm Acknowledgment (TypeScript)

```typescript
describe("D29.1 — Alarm lifecycle", () => {
  test("alarm creates LINEAR cell that must be acknowledged", () => {});
  test("acknowledging alarm consumes the cell", () => {});
  test("alarm cellId no longer resolves after acknowledgment", () => {});
  test("unacknowledged alarm persists in active alarm list", () => {});
  test("CRITICAL alarm requires shift supervisor to acknowledge", () => {});
});
```

### Test 6: Shift Handover (TypeScript)

```typescript
describe("D29.2 — Shift handover", () => {
  test("capabilities transfer from outgoing to incoming operator", () => {});
  test("outgoing operator loses capabilities after handover", () => {});
  test("handover requires supervisor authorization", () => {});
  test("handover receipt cell contains both operator IDs and timestamps", () => {});
  test("unacknowledged alarms are flagged during handover", () => {});
});
```

### Test 7: Full Scenario (Integration)

```typescript
describe("D29 — Full scenario: pressure excursion", () => {
  test("pressure rise → alarm → interlock blocks valve → supervisor override → command executes", () => {
    // 1. Record telemetry: pressure rising from 100 to 160 PSI
    // 2. Alarm cell created at 150 PSI threshold
    // 3. Operator attempts valve.open — interlock rejects (pressure > 150)
    // 4. Supervisor overrides non-critical interlock with capability 5
    // 5. Valve.open command executes, command cell created
    // 6. Alarm acknowledged by operator, alarm cell consumed
    // 7. Verify: 10+ telemetry cells, 1 alarm cell (consumed), 1 command cell, full historian chain
  });
});
```

---

## Phase Completion Criteria

You are **done with Phase 29** when ALL of the following are true:

1. `packages/scada/` exists with types, authorization engine, policies, historian, plant model, adapters
2. Telemetry cells are AFFINE (no duplication)
3. Command cells are LINEAR (consumed on execution, no replay)
4. Alarm cells are LINEAR (must be acknowledged/consumed)
5. Equipment cells are RELEVANT (cannot be deleted)
6. Safety interlocks compile via Phase 21 Lisp compiler and evaluate before command execution
7. Capability tokens gate command authorization per operator role
8. Historian maintains tamper-evident per-sensor DAG chains
9. Integrity verification detects tampering and gaps
10. Shift handover transfers capabilities via Phase 17 transfer protocol
11. Full pressure excursion integration test passes
12. Shell commands work via `semantos scada` verb
13. Protocol adapter interfaces defined (OPC UA, Modbus, DNP3, MQTT)
14. All gate tests pass: `bun test packages/__tests__/phase29-gate.test.ts`
15. `bun run check` passes
16. `bun run build` succeeds
17. No React imports in scada package
18. Errata sprint complete with `docs/prd/PHASE-29-ERRATA.md`
19. All commits follow `phase-29/D29.N:` naming convention
20. Branch is `phase-29-scada`

---

## What NOT to Do

1. **Do NOT implement actual protocol drivers.** OPC UA, Modbus, DNP3, MQTT adapters are interface stubs only. Real protocol implementations require hardware testing.
2. **Do NOT implement real-time process control.** The cell engine handles authorization and audit, not PID loops or millisecond control timing.
3. **Do NOT implement a full HMI/SCADA display.** The plant model provides data; visualization is a separate concern.
4. **Do NOT bypass the cell engine for performance.** If telemetry recording is too slow at cell-per-reading granularity, implement batching within the cell model (multiple readings per cell), not outside it.
5. **Do NOT implement cybersecurity penetration testing tools.** The capability model provides defense; testing it is a separate activity.
6. **Do NOT implement IEC 62443 certification automation.** The system supports the requirements; certification compliance verification is out of scope.
7. **Do NOT modify the cell engine or Lisp compiler.** The SCADA package consumes existing infrastructure. Domain-specific predicates (e.g., `sensor-reading`, `sensor-quality`, `has-dual-authorization`) are registered as host functions via Phase 25.5's `HostFunctionRegistry` and dispatched through `OP_CALLHOST`. Do NOT add opcodes or modify the compiler.
8. **Do NOT implement machine learning models for anomaly detection.** The embedding-based approach is a proof-of-concept. Production ML requires domain-specific training data.

---

## Next Phase

Phase 29 output feeds into future work on **digital twin simulation** (plant model as a semantic graph with simulated telemetry for training and testing), **IEC 62443 compliance reporting** (automated security assessment using the capability model), and **edge deployment** (28KB WASM cell engine running on embedded controllers for local interlock enforcement without network dependency).
