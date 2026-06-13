---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.467306+00:00
---

# packages/scada/scada/demo.ts

```ts
#!/usr/bin/env bun
/**
 * SCADA Demo — Pressure Excursion Scenario
 *
 * Interactive walkthrough of the Phase 29 SCADA integration:
 *   plant setup → telemetry → alarm → interlock → override → historian → tamper detection
 *
 * Run: bun run packages/scada/demo.ts
 */

import { CommandAuthorizationEngine } from './src/authorization';
import { SemanticHistorian } from './src/historian';
import { PlantModel } from './src/plant';
import { highPressureInterlock, interlockOverridePolicy } from './src/policies/interlocks';
import { createInterlockEvaluator } from './src/policies/host-functions';
import type {
  TelemetryCell,
  AlarmCell,
  EquipmentCell,
  SCADACapabilityToken,
} from './src/types';

// ── Terminal Colors ─────────────────────────────────────────────

const C = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  white: '\x1b[37m',
  bg_red: '\x1b[41m',
  bg_green: '\x1b[42m',
  bg_yellow: '\x1b[43m',
  bg_blue: '\x1b[44m',
};

function banner(text: string) {
  const line = '═'.repeat(60);
  console.log(`\n${C.cyan}${line}${C.reset}`);
  console.log(`${C.bold}${C.cyan}  ${text}${C.reset}`);
  console.log(`${C.cyan}${line}${C.reset}\n`);
}

function section(text: string) {
  console.log(`\n${C.bold}${C.yellow}▸ ${text}${C.reset}`);
  console.log(`${C.dim}${'─'.repeat(50)}${C.reset}`);
}

function ok(text: string) {
  console.log(`  ${C.green}✓${C.reset} ${text}`);
}

function fail(text: string) {
  console.log(`  ${C.red}✗${C.reset} ${text}`);
}

function info(text: string) {
  console.log(`  ${C.blue}ℹ${C.reset} ${text}`);
}

function warn(text: string) {
  console.log(`  ${C.yellow}⚠${C.reset} ${text}`);
}

function cell(label: string, value: string) {
  console.log(`  ${C.dim}${label}:${C.reset} ${value}`);
}

function pause(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ── Demo ─────────────────────────────────────────────────────────

async function main() {
  banner('SEMANTOS SCADA — Pressure Excursion Demo');
  info(`Phase 29: SCADA Industrial Control Integration`);
  info(`Linearity semantics: LINEAR (no replay), AFFINE (no duplication), RELEVANT (no deletion)`);
  info(`All safety interlocks compiled through Lisp → opcodes (Phase 21)`);

  // ── 1. Plant Setup ──────────────────────────────────────────

  section('1. Plant Setup — ISA-95 Hierarchy');

  const plant = new PlantModel();
  const auth = new CommandAuthorizationEngine();
  const historian = new SemanticHistorian();

  // Register equipment hierarchy
  const site: EquipmentCell = {
    cellId: 'equip-site-001',
    equipmentId: 'SITE-ALPHA',
    equipmentType: 'equipment.reactor',
    operationalMode: 'AUTOMATIC',
    healthStatus: 'HEALTHY',
    installedPolicies: [],
    childEquipment: ['AREA-PROC'],
    linearity: 'RELEVANT',
  };

  const area: EquipmentCell = {
    cellId: 'equip-area-001',
    equipmentId: 'AREA-PROC',
    equipmentType: 'equipment.reactor',
    operationalMode: 'AUTOMATIC',
    healthStatus: 'HEALTHY',
    installedPolicies: [],
    childEquipment: ['BV-101', 'P-101', 'TK-101'],
    linearity: 'RELEVANT',
  };

  const valve: EquipmentCell = {
    cellId: 'equip-bv101',
    equipmentId: 'BV-101',
    equipmentType: 'actuator.valve.ball',
    operationalMode: 'AUTOMATIC',
    healthStatus: 'HEALTHY',
    installedPolicies: ['high-pressure-interlock'],
    linearity: 'RELEVANT',
  };

  const pump: EquipmentCell = {
    cellId: 'equip-p101',
    equipmentId: 'P-101',
    equipmentType: 'equipment.pump.centrifugal',
    operationalMode: 'AUTOMATIC',
    healthStatus: 'HEALTHY',
    installedPolicies: [],
    linearity: 'RELEVANT',
  };

  const tank: EquipmentCell = {
    cellId: 'equip-tk101',
    equipmentId: 'TK-101',
    equipmentType: 'equipment.tank',
    operationalMode: 'AUTOMATIC',
    healthStatus: 'HEALTHY',
    installedPolicies: [],
    linearity: 'RELEVANT',
  };

  plant.registerEquipment(site);
  plant.registerEquipment(area, 'SITE-ALPHA');
  plant.registerEquipment(valve, 'AREA-PROC');
  plant.registerEquipment(pump, 'AREA-PROC');
  plant.registerEquipment(tank, 'AREA-PROC');

  plant.associateSensor('BV-101', 'PT-101');
  plant.associateSensor('TK-101', 'LT-101');

  ok(`Site ${C.bold}SITE-ALPHA${C.reset} registered (RELEVANT — cannot delete)`);
  ok(`Area ${C.bold}AREA-PROC${C.reset} → 3 children: BV-101, P-101, TK-101`);

  const path = plant.getPath('BV-101');
  cell('Hierarchy', path.map(e => e.equipmentId).join(' → '));

  // ── 2. Operator Registration ──────────────────────────────────

  section('2. Operator Registration & Capability Tokens');

  auth.registerOperator('OP-JONES', 'junior-operator');
  auth.registerOperator('OP-SMITH', 'senior-operator');
  auth.registerOperator('SUP-CHEN', 'shift-supervisor');

  const shiftEnd = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString(); // 8h from now

  const jonesToken = auth.grantShiftCapability('OP-JONES', 'junior-operator', new Date().toISOString(), shiftEnd, 'SUP-CHEN');
  const smithToken = auth.grantShiftCapability('OP-SMITH', 'senior-operator', new Date().toISOString(), shiftEnd, 'SUP-CHEN');
  const chenToken = auth.grantShiftCapability('SUP-CHEN', 'shift-supervisor', new Date().toISOString(), shiftEnd, 'MGR-HQ');

  ok(`Jones: junior-operator  → caps [1, 2] (read, acknowledge)`);
  ok(`Smith: senior-operator  → caps [1, 2, 3, 4] (+ valves, setpoints)`);
  ok(`Chen:  shift-supervisor → caps [1, 2, 3, 4, 5, 6] (+ override, mode)`);
  cell('Token linearity', `${C.magenta}LINEAR${C.reset} — consumed on use, no replay`);

  // ── 3. Install Safety Interlocks ──────────────────────────────

  section('3. Install Safety Interlocks (Compiled Lisp → Opcodes)');

  const pressureInterlock = highPressureInterlock('PT-101', 'BV-101', 150.0);
  auth.installInterlock('BV-101', pressureInterlock);

  const evaluator = createInterlockEvaluator();
  auth.setInterlockEvaluator(evaluator);

  ok(`Interlock: ${C.bold}high-pressure${C.reset} on BV-101`);
  cell('Lisp source', `(and (< PT-101 150.0) (has-capability 3))`);
  cell('Script words', pressureInterlock.scriptWords);
  cell('Cell bytes', `${pressureInterlock.compiledBytes.length} bytes compiled`);
  info(`Policy evaluation: Lisp → LispCompiler → opcodes → 2-PDA (NOT TypeScript if-statements)`);

  // ── 4. Telemetry — Pressure Rising ───────────────────────────

  section('4. Telemetry Recording — Pressure Rising');

  const pressureReadings = [100, 110, 120, 130, 140, 148, 152, 155, 158, 160, 155];
  const cellIds: string[] = [];

  for (const psi of pressureReadings) {
    const reading: Omit<TelemetryCell, 'cellId' | 'previousReadingCell' | 'linearity' | 'hash'> = {
      sensorId: 'PT-101',
      sensorType: 'sensor.pressure.gauge',
      value: psi,
      unit: 'PSI',
      quality: 'GOOD',
      timestamp: new Date().toISOString().replace('Z', '000Z'),
      samplingMethod: 'periodic',
      purpose: 'process-monitoring',
    };

    const cellId = await historian.record(reading);
    cellIds.push(cellId);

    // Update auth engine's telemetry state
    auth.updateTelemetry({
      ...reading,
      cellId,
      linearity: 'AFFINE',
    } as TelemetryCell);

    const bar = '█'.repeat(Math.round(psi / 5));
    const color = psi >= 150 ? C.red : psi >= 140 ? C.yellow : C.green;
    console.log(`  ${color}${psi.toString().padStart(3)} PSI${C.reset} ${C.dim}${bar}${C.reset} ${C.dim}${cellId}${C.reset}`);

    await pause(80);
  }

  cell('Cells recorded', `${pressureReadings.length} AFFINE telemetry cells`);
  cell('DAG chain', `each cell → previousReadingCell (tamper-evident)`);

  // ── 5. Alarm — Pressure Excursion ─────────────────────────────

  section('5. Alarm Generation — High Pressure Excursion');

  const alarm: AlarmCell = {
    cellId: 'alarm-001',
    alarmId: 'ALM-PT101-HH',
    severity: 'HIGH',
    source: 'PT-101',
    condition: 'HIGH-HIGH',
    value: 152,
    timestamp: new Date().toISOString(),
    linearity: 'LINEAR',
    consumed: false,
  };
  auth.registerAlarm(alarm);

  console.log(`  ${C.bg_red}${C.white}${C.bold} ALARM ${C.reset} ${C.red}ALM-PT101-HH: Pressure ${alarm.value} PSI > 150 PSI (HIGH-HIGH)${C.reset}`);
  cell('Severity', `${C.red}HIGH${C.reset}`);
  cell('Linearity', `${C.magenta}LINEAR${C.reset} — MUST be acknowledged (consumed)`);

  // ── 6. Command Blocked by Interlock ───────────────────────────

  section('6. Junior Operator Attempts valve.open — BLOCKED');

  info(`Jones (junior-operator) tries to open BV-101 while pressure > 150...`);

  // Jones doesn't even have cap 3 (valve operation), but let's show the interlock path
  // Use Smith (senior-operator, has cap 3) to show the interlock blocking
  const result1 = auth.issueCommand(
    { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: { position: 100 }, issuedBy: 'OP-SMITH' },
    'OP-SMITH',
    smithToken,
  );

  if (!result1.ok) {
    console.log(`  ${C.bg_red}${C.white}${C.bold} BLOCKED ${C.reset} ${C.red}${result1.error.message}${C.reset}`);
    if (result1.error.violations) {
      for (const v of result1.error.violations) {
        cell('Policy', v.policyName);
        cell('Sensor', `${v.sensorId} = ${v.currentValue} PSI (threshold: ${v.threshold})`);
      }
    }
    cell('Reason', 'Compiled Lisp interlock evaluated by 2-PDA → FAIL');
  }

  // ── 7. Pressure Drops, Supervisor Override ─────────────────────

  section('7. Pressure Drops — Supervisor Override');

  // Simulate pressure dropping below threshold
  const dropReading: Omit<TelemetryCell, 'cellId' | 'previousReadingCell' | 'linearity' | 'hash'> = {
    sensorId: 'PT-101',
    sensorType: 'sensor.pressure.gauge',
    value: 145,
    unit: 'PSI',
    quality: 'GOOD',
    timestamp: new Date().toISOString().replace('Z', '000Z'),
    samplingMethod: 'periodic',
    purpose: 'process-monitoring',
  };
  const dropCellId = await historian.record(dropReading);
  auth.updateTelemetry({ ...dropReading, cellId: dropCellId, linearity: 'AFFINE' } as TelemetryCell);

  ok(`Pressure dropped to ${C.green}145 PSI${C.reset} (below 150 threshold)`);

  // Smith's token was consumed in the failed attempt — grant a new one
  const smithToken2 = auth.grantShiftCapability('OP-SMITH', 'senior-operator', new Date().toISOString(), shiftEnd, 'SUP-CHEN');

  const result2 = auth.issueCommand(
    { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: { position: 100 }, issuedBy: 'OP-SMITH' },
    'OP-SMITH',
    smithToken2,
  );

  if (result2.ok) {
    console.log(`  ${C.bg_green}${C.white}${C.bold} EXECUTED ${C.reset} ${C.green}valve.open on BV-101${C.reset}`);
    cell('Command cell', result2.value.commandCellId);
    cell('Interlocks passed', `${result2.value.interlocksPassed}`);
    cell('Token consumed', `${C.magenta}LINEAR${C.reset} — smithToken2 is now spent`);
    console.log();
    info('Audit trail:');
    for (const entry of result2.value.auditTrail) {
      const icon = entry.result === 'pass' ? `${C.green}✓${C.reset}` : `${C.red}✗${C.reset}`;
      console.log(`    ${icon} ${entry.step}: ${entry.detail}`);
    }
  }

  // ── 8. Command Replay Prevention ──────────────────────────────

  section('8. Command Replay Prevention (LINEAR)');

  info('Attempting to reuse smithToken2 (already consumed)...');

  const replayResult = auth.issueCommand(
    { commandType: 'valve.close', targetEquipment: 'BV-101', parameters: { position: 0 }, issuedBy: 'OP-SMITH' },
    'OP-SMITH',
    smithToken2,
  );

  if (!replayResult.ok) {
    console.log(`  ${C.bg_red}${C.white}${C.bold} REPLAY BLOCKED ${C.reset} ${C.red}${replayResult.error.message}${C.reset}`);
    cell('Linearity', `${C.magenta}LINEAR${C.reset} — consumed=true, no second use`);
  }

  // ── 9. Alarm Acknowledgment ───────────────────────────────────

  section('9. Alarm Acknowledgment Lifecycle');

  info('Jones (junior-operator, cap [1,2]) acknowledges alarm...');
  const ackResult = auth.acknowledgeAlarm('ALM-PT101-HH', 'OP-JONES', jonesToken);

  if (ackResult.ok) {
    ok(`Alarm ${C.bold}ALM-PT101-HH${C.reset} acknowledged by Jones`);
    cell('consumed', `${C.magenta}true${C.reset} (LINEAR — alarm cell consumed)`);
    cell('acknowledgedBy', ackResult.value.acknowledgedBy!);
    cell('acknowledgedAt', ackResult.value.acknowledgedAt!);
  }

  const unacked = auth.getUnacknowledgedAlarms();
  ok(`Unacknowledged alarms remaining: ${unacked.length}`);

  // ── 10. Historian Integrity Verification ──────────────────────

  section('10. Historian Integrity Verification');

  const from = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const to = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const report = await historian.verifyIntegrity('PT-101', from, to);

  ok(`Chain length: ${report.cellCount} cells`);
  ok(`Chain valid: ${report.chainValid ? `${C.green}true${C.reset}` : `${C.red}false${C.reset}`}`);
  ok(`Hashes valid: ${report.hashesValid ? `${C.green}true${C.reset}` : `${C.red}false${C.reset}`}`);
  ok(`Tamper detected: ${report.tamperDetected ? `${C.red}YES${C.reset}` : `${C.green}NO${C.reset}`}`);

  // ── 11. Tamper Detection Demo ─────────────────────────────────

  section('11. Tamper Detection — Modifying a Cell');

  const targetCellId = cellIds[4];
  const originalCell = historian.getCell(targetCellId);
  info(`Tampering cell ${targetCellId}: changing value from ${originalCell?.value} to 999...`);

  historian._tamperCell(targetCellId, 999);
  warn('Value modified WITHOUT updating hash (simulating attack)');

  const tamperReport = await historian.verifyIntegrity('PT-101', from, to);

  if (!tamperReport.hashesValid) {
    console.log(`  ${C.bg_red}${C.white}${C.bold} TAMPER DETECTED ${C.reset}`);
    cell('hashesValid', `${C.red}false${C.reset} — SHA-256 mismatch`);
    cell('chainValid', tamperReport.chainValid ? `${C.green}true${C.reset}` : `${C.red}false${C.reset}`);
    ok('Cell DAG integrity verification caught the modification');
  }

  // ── 12. Shift Handover ────────────────────────────────────────

  section('12. Shift Handover — Smith → New Operator');

  auth.registerOperator('OP-PATEL', 'senior-operator');

  const handoverResult = auth.shiftHandover('OP-SMITH', 'OP-PATEL', 'SUP-CHEN');

  if (handoverResult.ok) {
    ok(`Shift handover complete`);
    cell('Outgoing', `OP-SMITH (capabilities consumed — ${C.magenta}LINEAR${C.reset})`);
    cell('Incoming', `OP-PATEL (new capabilities granted)`);
    cell('Supervisor', handoverResult.value.supervisor);
    cell('Capabilities transferred', `${handoverResult.value.capabilitiesTransferred}`);
    cell('Unacknowledged alarms', `${handoverResult.value.unacknowledgedAlarms.length}`);
    cell('Receipt cell', handoverResult.value.receiptCellId);
  }

  // Verify outgoing operator lost capabilities
  const smithCaps = auth.getActiveCapabilities('OP-SMITH');
  const patelCaps = auth.getActiveCapabilities('OP-PATEL');
  ok(`Smith active capabilities: ${smithCaps.length} (consumed)`);
  ok(`Patel active capabilities: ${patelCaps.length} (granted)`);

  // ── 13. Plant Status Summary ──────────────────────────────────

  section('13. Plant Status Summary');

  plant.setAlarmSource(() => [alarm]);
  const status = plant.getPlantStatus();

  cell('Total equipment', `${status.totalEquipment}`);
  cell('Healthy', `${C.green}${status.healthy}${C.reset}`);
  cell('Degraded', `${status.degraded}`);
  cell('Faulted', `${status.faulted}`);
  cell('Offline', `${status.offline}`);

  // ── 14. Historian Export ──────────────────────────────────────

  section('14. Historian Export (OPC UA JSON)');

  const opcExport = historian.export(['PT-101'], from, to, 'opc-ua-json');
  const parsed = JSON.parse(opcExport);
  info(`Exported ${parsed.length} readings in OPC UA JSON format`);
  console.log(`${C.dim}  ${JSON.stringify(parsed[0], null, 2).split('\n').join('\n  ')}${C.reset}`);

  // ── Done ──────────────────────────────────────────────────────

  banner('Demo Complete');

  console.log(`  ${C.bold}Key Takeaways:${C.reset}`);
  console.log(`  ${C.green}•${C.reset} Telemetry cells are ${C.bold}AFFINE${C.reset} — no phantom readings in the DAG`);
  console.log(`  ${C.green}•${C.reset} Commands & tokens are ${C.bold}LINEAR${C.reset} — consumed on use, replay impossible`);
  console.log(`  ${C.green}•${C.reset} Alarms are ${C.bold}LINEAR${C.reset} — must be acknowledged (consumed)`);
  console.log(`  ${C.green}•${C.reset} Equipment cells are ${C.bold}RELEVANT${C.reset} — no deletion, only decommission`);
  console.log(`  ${C.green}•${C.reset} Safety interlocks compile through ${C.bold}Lisp → opcodes${C.reset} — no TS if-statements`);
  console.log(`  ${C.green}•${C.reset} Historian hash chain detects tampering via ${C.bold}SHA-256${C.reset} verification`);
  console.log(`  ${C.green}•${C.reset} Shift handover uses Phase 17 ${C.bold}transfer protocol${C.reset} (LINEAR consume → grant)`);
  console.log();
}

main().catch(err => {
  console.error(`${C.red}Demo failed:${C.reset}`, err);
  process.exit(1);
});

```
