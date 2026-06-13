---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-29-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.656883+00:00
---

# Phase 29 Execution Prompt — SCADA Industrial Control Integration

> Paste this prompt into a fresh session to execute Phase 29.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phase 18 built the metering control plane with FSM governance, evidence chains, and dispute resolution. Phase 16 built edge + capability integration with ECDH-secured edges. Phase 8.5 built identity facets for role-based access. Phase 21 built the Lisp policy compiler. Phase 25.5 built the host function dispatch infrastructure — `OP_CALLHOST` (0xD0) in the Zig WASM engine and `HostFunctionRegistry` in TypeScript — so domain-specific predicates like `sensor-reading` and `sensor-quality` can be evaluated by the cell engine without adding opcodes. Phase 23 built the embedding service with anomaly detection capabilities.

This phase applies Semantos to SCADA (Supervisory Control And Data Acquisition) — the systems that monitor and control industrial processes like power grids, water treatment plants, oil pipelines, and manufacturing lines. SCADA is the highest-stakes application domain for semantic objects. A duplicated game sword is annoying. A duplicated trade is expensive. A duplicated control command to a gas pipeline valve can be catastrophic.

The mapping to Semantos is direct:

- **Telemetry readings** → AFFINE cells (can be processed/acknowledged, never duplicated — no phantom readings)
- **Control commands** → LINEAR capability cells (consumed on execution — no replay attacks)
- **Alarms** → LINEAR cells (MUST be acknowledged — cannot be silently dropped)
- **Equipment records** → RELEVANT cells (must be kept — cannot be deleted, only decommissioned)
- **Safety interlocks** → Compiled Lisp policies evaluated by the cell engine before any command executes
- **Operator roles** → Identity facets with capability tokens gating what actions each role can perform
- **Historian** → Cell DAG per sensor — tamper-evident chain where hash manipulation is detectable
- **Shift handover** → Phase 17 transfer of capability cells from outgoing to incoming operator

The IEC 62443 standard for industrial cybersecurity already calls for role-based access, audit trails, integrity verification, and least-privilege authorization. Semantos provides all of these as structural properties of the runtime.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-29-SCADA.md` — Full spec with D29.1–D29.7, gate tests, completion criteria

**Read second** (the capability and identity systems you build on):
- `src/types/capability.ts` — Capability tokens (command authorization maps to this)
- `packages/loom/src/services/identity/` — Identity facets (operator roles map to these)
- `src/kernel/edge.ts` — ECDH-secured edges (encrypted telemetry channels map to this)

**Read third** (the transfer and evidence systems):
- `src/kernel/transfer.ts` — Transfer protocol (shift handover maps to this)
- `packages/loom/src/types/evidence.ts` — Evidence chain (historian entries map to this)
- `packages/plexus-vendor-sdk/src/graph/` — DAG persistence (historian data storage)

**Read fourth** (the host function dispatch and Lisp policy system):
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry class (register SCADA-domain predicates here: `sensor-reading?`, `sensor-quality?`, `has-dual-authorization?`)
- `packages/cell-engine/bindings/builtin-host-functions.ts` — Built-in host functions (pattern for registering domain predicates)
- `packages/cell-engine/src/opcodes/hostcall.zig` — OP_CALLHOST implementation (0xD0)
- `packages/shell/src/lisp/compiler.ts` — LispCompiler (safety interlocks compile through this; `(sensor-reading "PT-101")` dispatches via OP_CALLHOST)
- `packages/shell/src/lisp/packer.ts` — Capability cell packing
- `packages/shell/src/lisp/types.ts` — ConstraintExpr types

**Read fifth** (the metering system — FSM pattern reference):
- `packages/metering/src/` — Payment channel FSM (operational mode state machine patterns)
- `configs/extensions/core.json` — How FSM flows are defined in extension config

**Read sixth** (the embedding service for anomaly detection):
- `packages/loom/src/services/EmbeddingService.ts` — embedQuery(), nearest() (anomaly detection)

**Read seventh** (the BCA derivation for hash chain integrity):
- `packages/cell-engine/src/bca.ts` — BCA derivation (hash-linked cell integrity)

**Read eighth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-29-scada`. Commits as `phase-29/D29.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. COMMANDS ARE LINEAR — NO REPLAY

A control command is a LINEAR capability cell. It is consumed when the command executes. The same command cell cannot be used twice. This is not a nonce check you implement in TypeScript — it is the cell engine rejecting DUP on LINEAR cells at the opcode level. Replay prevention is structural.

### 2. ALARMS ARE LINEAR — NO SILENT DROP

An alarm cell is LINEAR. It MUST be consumed (acknowledged). You cannot silently discard an alarm. The cell engine will not let an unacknowledged LINEAR alarm cell be garbage collected, overwritten, or ignored. If an operator doesn't acknowledge it, it stays.

### 3. EQUIPMENT IS RELEVANT — NO DELETION

Equipment cells are RELEVANT. You cannot destroy them. Decommissioning creates a new cell with `OFFLINE` status — the original cell persists in the DAG. There is no "delete equipment" operation. The cell engine rejects consumption of RELEVANT cells.

### 4. INTERLOCKS ARE COMPILED POLICIES, NOT IF-STATEMENTS

"Don't open the bypass valve if pressure exceeds 150 PSI" is NOT:
```typescript
if (pressure > 150) throw new Error('interlock violation');
```

It IS:
```lisp
(define-policy high-pressure-interlock
  :subject operator :action valve.open
  :constraint (and (= target "BV-101") (< (sensor-reading "PT-101") 150.0) (has-capability 3))
  :linearity LINEAR)
```

The policy compiles to opcodes. The cell engine evaluates them before the command executes. If you write a single safety check as a TypeScript if-statement, you have violated this rule.

### 4.5. DOMAIN PREDICATES USE HOST FUNCTIONS — NOT HARDCODED LOGIC

SCADA-domain predicates like `sensor-reading`, `sensor-quality`, `has-dual-authorization`, and `target` are **host functions** registered via Phase 25.5's `HostFunctionRegistry`. In Lisp policies, `(sensor-reading "PT-101")` compiles to `push "PT-101" push "sensor-reading" OP_CALLHOST`. Do NOT hardcode sensor lookups or quality checks in TypeScript. Do NOT add new opcodes. Register predicates with `registry.register("sensor-reading", fn)` and the cell engine dispatches them via `OP_CALLHOST` (0xD0). The context object (frozen before evaluation) carries the current telemetry state.

### 5. SHIFT HANDOVER IS A PHASE 17 TRANSFER

Do NOT implement a separate handover protocol. Shift handover IS `transfer()` from Phase 17 — capability cells are transferred from outgoing operator to incoming operator, authorized by the shift supervisor's capability cell.

### 6. HISTORIAN IS A CELL DAG, NOT A DATABASE

The historian is NOT a time-series database with append operations. It is a per-sensor chain of cells where each cell's `previousReadingCell` links to the prior reading. Integrity verification = walking the chain and re-computing hashes (BCA derivation, Phase 2). If a hash doesn't match, the chain has been tampered with.

### 7. PROTOCOL ADAPTERS ARE STUBS

OPC UA, Modbus, DNP3, and MQTT adapters are interface definitions and a `MemoryAdapter` stub. They are NOT working protocol implementations. Real protocol drivers require hardware testing and are out of scope. The interfaces define the contract; the stub proves the pattern.

### 8. ANOMALY DETECTION IS A PROOF-OF-CONCEPT

The embedding-based anomaly detection (D29.4) uses Phase 23's `EmbeddingService`. It is a demonstration that the embedding infrastructure can detect outlier readings. It is NOT a production ML pipeline. Do not over-engineer it.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites

```bash
# Phase 18 metering exists (FSM pattern)
ls packages/metering/src/

# Phase 16 edge + capability exists
ls src/kernel/edge.ts
ls src/types/capability.ts

# Phase 8.5 identity facets exist
ls packages/loom/src/services/identity/

# Phase 25.5 host function dispatch exists
ls packages/cell-engine/bindings/host-functions.ts
ls packages/cell-engine/src/opcodes/hostcall.zig

# Phase 21 Lisp compiler exists
ls packages/shell/src/lisp/compiler.ts
ls packages/shell/src/lisp/packer.ts

# Phase 17 transfer protocol exists
ls src/kernel/transfer.ts

# Phase 23 embedding service exists
ls packages/loom/src/services/EmbeddingService.ts

# Phase 2 BCA derivation exists
ls packages/cell-engine/src/bca.ts

# Evidence chain types exist
ls packages/loom/src/types/evidence.ts

# DAG persistence exists
ls packages/plexus-vendor-sdk/src/graph/

# Full build passes
bun run check
bun run build
```

All must exist and pass. If anything fails, STOP.

### 0.3 Create Phase 29 branch

```bash
git checkout -b phase-29-scada
```

---

## Step 1: SCADA Object Types (D29.1)

Create `packages/scada/src/types.ts`.

**Requirements**:

Define the four core SCADA object types with their linearity semantics:

- `TelemetryCell` — AFFINE: sensor readings that can be consumed/processed but never duplicated
  - sensorId, sensorType (taxonomy WHAT), value, unit, quality (GOOD/UNCERTAIN/BAD), timestamp (microsecond), samplingMethod (taxonomy HOW), purpose (taxonomy WHY), previousReadingCell (DAG link)

- `CommandCell` — LINEAR: control commands consumed on execution, no replay
  - commandType, targetEquipment, parameters, issuedBy (operator identity), authorizedBy (capability cell), executionStatus (pending/executed/rejected/timed-out), previousCommandCell (DAG link)

- `AlarmCell` — LINEAR: alarms that MUST be acknowledged (consumed), cannot be silently dropped
  - alarmId, severity (LOW/MEDIUM/HIGH/CRITICAL), source, condition, value, acknowledgedBy, acknowledgedAt, previousAlarmCell (DAG link)

- `EquipmentCell` — RELEVANT: equipment records that must be kept, cannot be destroyed
  - equipmentId, equipmentType, operationalMode (MANUAL/AUTOMATIC/CASCADE/OVERRIDE/SHUTDOWN), healthStatus, installedPolicies (interlock cell IDs), childEquipment (hierarchy), previousStateCell (DAG link)

Define sensor types (`sensor.temperature.thermocouple`, `sensor.pressure.differential`, etc.), equipment types (`actuator.valve.gate`, `equipment.pump.centrifugal`, etc.), and command types (`valve.open`, `motor.start`, `emergency.shutdown`, etc.) — full taxonomy as specified in the PRD.

Create `packages/scada/package.json` with name `@semantos/scada`, dependencies on `@semantos/protocol-types`, `@semantos/constants`, loom services.

**Commit**: `phase-29/D29.1: SCADA object types — telemetry, commands, alarms, equipment with linearity semantics`

---

## Step 2: Command Authorization Engine (D29.2)

Create `packages/scada/src/authorization.ts`.

**Requirements**:

- `CommandAuthorizationEngine` class:
  - `issueCommand(command, operatorIdentity, capabilityToken)` — validates operator, evaluates interlocks, executes
  - `evaluateInterlocks(command, currentState)` — runs all safety policies for the target equipment
  - `grantShiftCapability(operatorId, role, shiftStart, shiftEnd, grantedBy)` — creates LINEAR capability cells valid for shift duration
  - `shiftHandover(outgoingOperator, incomingOperator, capabilities, supervisorAuthorization)` — transfers capabilities via Phase 17 transfer

- Operator role hierarchy with capability mappings:
  - `junior-operator`: [1, 2] — read telemetry, acknowledge alarms
  - `senior-operator`: [1, 2, 3, 4] — plus operate valves, change setpoints
  - `shift-supervisor`: [1, 2, 3, 4, 5, 6] — plus override interlocks, mode changes
  - `plant-manager`: [1, 2, 3, 4, 5, 6, 7, 8] — plus emergency shutdown
  - `safety-officer`: [1–10] — all capabilities including policy modification

**Command execution flow** (implement exactly):
1. Verify operator identity (Phase 8.5 facet authentication)
2. Verify capability token is valid and unexpired (LINEAR — consumed on verification)
3. Load all safety interlock policies for the target equipment
4. Evaluate each interlock against current telemetry (compiled Lisp → 2-PDA)
5. If ALL interlocks pass: execute command, create command cell in DAG
6. If ANY interlock fails: reject, create rejection cell with violation details
7. Return receipt with audit trail

**Shift handover flow** (maps to Phase 17 transfer):
1. Outgoing operator's capability cells transferred to incoming operator
2. Supervisor capability cell authorizes the transfer
3. Active alarms reviewed (all unacknowledged alarms flagged)
4. Handover receipt cell created in DAG

**Commit**: `phase-29/D29.2: command authorization engine with role hierarchy, interlocks, shift handover`

---

## Step 3: Safety Interlock Policies (D29.3)

Create `packages/scada/src/policies/`.

**Requirements**:

Write Lisp policies for safety interlocks:

- `high-pressure-interlock.policy` — blocks valve.open when pressure > 150 PSI
- `low-level-interlock.policy` — blocks motor.start when tank level < 20%
- `temperature-runaway.policy` — automatic emergency.shutdown when temperature > 500°C
- `interlock-override.policy` — shift supervisor can bypass non-CRITICAL interlocks
- `emergency-shutdown-dual-auth.policy` — emergency shutdown requires two-person authorization
- `sensor-cross-validation.policy` — require agreement between redundant sensors (or one BAD + one GOOD)

Each policy:
1. Authored as `.policy` Lisp file with domain-specific constraint primitives
2. Compiles via Phase 21 LispCompiler
3. Packs to capability cell
4. Installs on equipment via `EquipmentCell.installedPolicies`

**Domain constraint primitives** (implement as host functions registered with cell engine):
- `sensor-reading` — returns current value for a sensor ID
- `sensor-quality` — returns quality flag for a sensor ID
- `target` — returns the command's target equipment ID
- `has-dual-authorization` — checks for second authorizer's capability cell

Create `packages/scada/src/policies/host-functions.ts` — register these with the WASM loader.

**Critical rule**: CRITICAL interlocks (`temperature-runaway`) CANNOT be overridden by any operator role. The `interlock-override` policy explicitly checks `(not (= interlock-severity "CRITICAL"))`.

**Commit**: `phase-29/D29.3: safety interlock policies with host functions — pressure, level, temperature, override, dual-auth`

---

## Step 4: Semantic Historian (D29.4)

Create `packages/scada/src/historian.ts`.

**Requirements**:

- `SemanticHistorian` class:
  - `record(reading)` — creates telemetry cell linked to previous reading via DAG
  - `query(sensorId, from, to, options?)` — retrieves readings for a time range
  - `verifyIntegrity(sensorId, from, to)` — walks DAG chain, re-computes BCA hashes, detects tampering
  - `detectAnomalies(sensorId, window, threshold)` — embedding-based outlier detection (Phase 23)
  - `export(sensorIds, from, to, format)` — CSV, JSON, or OPC UA JSON export

- `IntegrityReport`:
  - cellCount, chainValid (all DAG links intact), hashesValid (all BCA hashes verify), gaps (time discontinuities), tamperDetected

- `AnomalyReport`:
  - Per-anomaly: cellId, timestamp, value, expectedRange, semanticDistance, severity

**Integrity model**:
- Each `TelemetryCell.previousReadingCell` creates a per-sensor hash chain
- Cell hashes use BCA derivation (Phase 2): SHA-256 of cell contents
- `verifyIntegrity()` walks the chain from latest to earliest, re-computing each hash
- If any hash doesn't match the stored hash → tampering detected
- If timestamps have gaps → gap detected
- If a cell's `previousReadingCell` points to a cell that doesn't exist → chain broken

**Anomaly detection** (proof-of-concept using Phase 23 embedding service):
- Embed readings as vectors: [normalized-value, rate-of-change, hour-of-day, day-of-week, quality-flag]
- Compute semantic distance from a "normal operating" centroid
- Readings beyond the threshold flagged as anomalies
- This is deliberately simple — a demonstration, not production ML

**Commit**: `phase-29/D29.4: semantic historian with integrity verification, anomaly detection, export`

---

## Step 5: Plant Model (D29.5)

Create `packages/scada/src/plant.ts`.

**Requirements**:

- `PlantModel` class:
  - `registerEquipment(equipment, parentId?)` — adds to hierarchical plant model
  - `getEquipment(equipmentId)` — lookup by tag number
  - `getChildren(equipmentId)` — all child equipment (e.g., instruments on a reactor)
  - `getPath(equipmentId)` — hierarchy path (Plant > Area > Unit > Equipment)
  - `getSensors(equipmentId)` — all sensors associated with equipment
  - `getInterlocks(equipmentId)` — all interlock policy cell IDs
  - `getPlantStatus()` — plant-wide summary

- `PlantStatusSummary`:
  - totalEquipment, healthy/degraded/faulted/offline counts
  - activeAlarms by severity
  - unacknowledgedAlarms count (LINEAR alarm cells not yet consumed)
  - activeOperators with roles and shift end times

The plant hierarchy follows ISA-95 / IEC 62264: Enterprise > Site > Area > Unit > Equipment. Relationships are RELEVANT edges in the Plexus DAG (cannot be deleted).

**Commit**: `phase-29/D29.5: plant model with hierarchical topology, sensor/interlock associations, status summary`

---

## Step 6: Protocol Adapters (D29.6)

Create `packages/scada/src/adapters/`.

**Requirements**:

Define interfaces for four standard SCADA protocols:

- `OPCUAAdapter` — connect, subscribe, writeCommand, browse
- `ModbusAdapter` — connect, readHoldingRegisters, writeRegister
- `DNP3Adapter` — connect, poll, selectBeforeOperate
- `MQTTAdapter` — connect, subscribe, publish

All interfaces:
- Reads produce `TelemetryCell` objects
- Writes consume `CommandCell` objects
- All writes route through `CommandAuthorizationEngine` before executing
- Return `CommandReceipt` for writes

Implement `MemoryAdapter` that fulfills all four interfaces:
- In-memory sensor state for testing
- Configurable sensor values (set a reading, next poll returns it)
- Command execution logs for verification
- No real protocol I/O

**Commit**: `phase-29/D29.6: protocol adapter interfaces (OPC UA, Modbus, DNP3, MQTT) with MemoryAdapter stub`

---

## Step 7: Shell Integration (D29.7)

Create `packages/scada/src/cli/`.

**Requirements**:

Wire SCADA commands into the semantic shell:

```bash
semantos scada plant status                                    → PlantStatusSummary
semantos scada telemetry read TT-101                           → latest reading
semantos scada telemetry history TT-101 --from ... --to ...    → reading history
semantos scada telemetry verify TT-101 --from ... --to ...     → integrity report
semantos scada command issue valve.open BV-101 --operator OP-001  → command receipt
semantos scada alarm list --unacknowledged                     → unacknowledged alarms
semantos scada alarm acknowledge ALM-1774 --operator OP-001    → consume alarm cell
semantos scada shift handover --from OP-001 --to OP-002 --supervisor SUP-001  → handover receipt
semantos scada anomaly detect TT-101 --window 24h --threshold 0.8  → anomaly report
```

Each command uses the `CommandAuthorizationEngine`, `SemanticHistorian`, and `PlantModel` — no direct cell manipulation in the CLI layer.

**Commit**: `phase-29/D29.7: shell integration with scada plant, telemetry, command, alarm, shift, anomaly commands`

---

## Step 8: Gate Tests

Create `packages/__tests__/phase29-gate.test.ts`.

### Telemetry Cell Tests (T1–T5)

```typescript
describe("D29.1 — Telemetry cells", () => {
  // T1: reading creates AFFINE cell with sensor metadata
  // T2: readings form a per-sensor DAG chain (previousReadingCell linked)
  // T3: reading cannot be duplicated (AFFINE — engine rejects DUP)
  // T4: timestamp has microsecond precision
  // T5: OPC UA quality flags (GOOD/UNCERTAIN/BAD) map correctly
});
```

### Command Authorization Tests (T6–T11)

```typescript
describe("D29.2 — Command authorization", () => {
  // T6: command with valid capability executes and consumes token
  // T7: command without capability is rejected
  // T8: expired capability token is rejected
  // T9: capability replay (same token twice) fails — LINEAR consumed
  // T10: junior operator cannot issue motor.start (insufficient capability)
  // T11: shift supervisor CAN issue motor.start
});
```

### Safety Interlock Tests (T12–T18)

```typescript
describe("D29.3 — Safety interlocks", () => {
  // T12: high-pressure interlock blocks valve.open when pressure > 150
  // T13: high-pressure interlock allows valve.open when pressure < 150
  // T14: low-level interlock blocks pump start when level < 20%
  // T15: BAD sensor quality blocks command depending on that sensor
  // T16: CRITICAL interlock cannot be overridden even by shift supervisor
  // T17: non-critical interlock CAN be overridden with supervisor capability
  // T18: emergency shutdown requires dual authorization (two identity facets)
});
```

### Historian Integrity Tests (T19–T24)

```typescript
describe("D29.4 — Historian integrity", () => {
  // T19: 100 readings form a valid hash chain
  // T20: modifying a reading's value breaks chain verification
  // T21: inserting a fake reading breaks chain verification
  // T22: deleting a reading creates a detectable gap
  // T23: integrity report correctly identifies tampered vs. clean chains
  // T24: query returns readings in chronological order within time range
});
```

### Alarm Lifecycle Tests (T25–T29)

```typescript
describe("D29.1 — Alarm lifecycle", () => {
  // T25: alarm creates LINEAR cell that must be acknowledged
  // T26: acknowledging alarm consumes the cell (cellId no longer resolves)
  // T27: unacknowledged alarm persists in active alarm list
  // T28: CRITICAL alarm requires shift-supervisor capability to acknowledge
  // T29: alarm cell cannot be silently dropped (LINEAR — engine rejects)
});
```

### Shift Handover Tests (T30–T34)

```typescript
describe("D29.2 — Shift handover", () => {
  // T30: capabilities transfer from outgoing to incoming operator
  // T31: outgoing operator loses capabilities after handover
  // T32: handover requires supervisor authorization
  // T33: handover receipt cell contains both operator IDs and timestamps
  // T34: unacknowledged alarms are flagged during handover
});
```

### Full Scenario Integration (T35)

```typescript
describe("D29 — Full scenario: pressure excursion", () => {
  // T35: pressure rise → alarm → interlock blocks valve → supervisor override → execute
  //   1. Record telemetry: pressure rising 100 → 160 PSI
  //   2. Alarm cell created at 150 threshold
  //   3. Operator attempts valve.open — interlock rejects (pressure > 150)
  //   4. Supervisor overrides non-critical interlock with capability 5
  //   5. Valve.open executes, command cell created in DAG
  //   6. Alarm acknowledged by operator, alarm cell consumed
  //   7. Verify: 10+ telemetry cells, 1 alarm (consumed), 1 command, full chain
});
```

### Anti-Lock Tests (T36–T37)

```typescript
describe("D29 — Anti-lock", () => {
  // T36: no React imports in scada package
  // T37: no direct cell engine modifications (only consumes existing APIs)
});
```

**Commit**: `phase-29/T1-T37: full gate test suite — telemetry, authorization, interlocks, historian, alarms, handover, integration`

---

## Step 9: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Walk through the full pressure excursion scenario end-to-end: verify every cell, every DAG link, every capability consumption
2. Walk through a shift handover: verify outgoing operator truly loses capabilities (attempt a command — should fail)
3. Verify CRITICAL interlock cannot be overridden: attempt override with every role including safety-officer. Must fail for CRITICAL.
4. Verify historian integrity with 1000 readings: tamper with reading #500, verify detection
5. Verify alarm acknowledgment: create 10 alarms, acknowledge 5, verify only 5 remain
6. Verify dual-authorization emergency shutdown: attempt with single authorization — must fail
7. Check that no safety check happens in TypeScript (all via policy evaluation on 2-PDA)
8. Check that shift capabilities are time-bounded (expired shift capability rejected)
9. Check that equipment cells truly cannot be deleted (RELEVANT — engine rejects consume)
10. Check that command replay truly fails (same LINEAR cell used twice)
11. Measure historian throughput: 10,000 readings should record in <10 seconds
12. Write errata doc as `docs/prd/PHASE-29-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/scada/` exists with types, authorization, policies, historian, plant model, adapters, CLI
- [ ] Telemetry cells are AFFINE (duplication rejected by engine)
- [ ] Command cells are LINEAR (consumed on execution, replay rejected)
- [ ] Alarm cells are LINEAR (must be acknowledged, silent drop impossible)
- [ ] Equipment cells are RELEVANT (deletion rejected by engine)
- [ ] Safety interlocks compile via Phase 21 Lisp compiler
- [ ] Interlocks evaluate on 2-PDA before command execution (NOT TypeScript if-statements)
- [ ] CRITICAL interlocks cannot be overridden by any role
- [ ] Capability tokens gate command authorization per operator role
- [ ] Historian maintains tamper-evident per-sensor DAG chains
- [ ] Integrity verification detects tampering, insertion, and gaps
- [ ] Shift handover transfers capabilities via Phase 17 transfer
- [ ] Outgoing operator loses capabilities after handover
- [ ] Emergency shutdown requires dual authorization
- [ ] Full pressure excursion integration test passes
- [ ] Plant model with hierarchical topology works
- [ ] Protocol adapter interfaces defined (OPC UA, Modbus, DNP3, MQTT)
- [ ] MemoryAdapter stub implements all four interfaces for testing
- [ ] Shell commands work via `semantos scada` verb
- [ ] Tests T1–T37 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in scada package
- [ ] Errata sprint complete with `docs/prd/PHASE-29-ERRATA.md`
- [ ] All commits follow `phase-29/D29.N:` naming convention
- [ ] Branch is `phase-29-scada`

---

## What NOT to Do

1. Do NOT implement actual protocol drivers — stubs and interfaces only
2. Do NOT implement real-time PID control — the cell engine handles authorization, not control loops
3. Do NOT implement a full HMI/SCADA display — plant model provides data, visualization is separate
4. Do NOT bypass the cell engine for performance — batch readings within cells if needed
5. Do NOT implement cybersecurity pen testing tools — defense only
6. Do NOT implement IEC 62443 certification automation — the system supports requirements, certification is separate
7. Do NOT modify the cell engine or Lisp compiler — consume existing infrastructure. SCADA-domain predicates are registered as host functions via Phase 25.5's `HostFunctionRegistry` — do NOT add opcodes or modify the compiler
8. Do NOT implement production ML anomaly detection — the embedding approach is a proof-of-concept

---

## After Phase 29: Industrial Safety Is Structural

After Phase 29, the same cell engine that prevents chess piece duplication and trade double-booking now prevents control command replay and alarm suppression. The linearity modes are not domain-specific — they are universal constraints:

```
LINEAR = exactly one use     → game items, trade ownership, control commands, alarms
AFFINE = at most one use     → consumables, partial termination, telemetry readings
RELEVANT = must keep         → quest markers, regulatory reports, equipment records
FUNGIBLE = freely copy       → currency, ammunition, aggregate metrics
```

Every domain maps onto the same four modes. Every safety constraint compiles through the same pipeline:

```
Safety engineer: "don't open the bypass valve if pressure > 150 PSI"
    ↓ (policy authoring)
(define-policy high-pressure-interlock ...)
    ↓ (Lisp compiler)
Forth words → capability cell
    ↓ (cell engine)
2-PDA evaluates → command authorized or rejected
    ↓ (historian)
Command cell in DAG → tamper-evident audit trail
```

Same pipeline. Same engine. Same thesis. Different stakes.
