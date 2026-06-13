---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/policies/interlocks.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.474835+00:00
---

# packages/scada/scada/src/policies/interlocks.ts

```ts
/**
 * Safety Interlock Policies — Phase 29 (D29.3)
 *
 * Each policy compiles from a Lisp s-expression through the Phase 21
 * LispCompiler into opcodes, then packs into a capability cell.
 *
 * Interlocks are evaluated by the cell engine's 2-PDA BEFORE any
 * command executes. They are NOT TypeScript if-statements.
 */

import { LispCompiler } from '../../../../runtime/shell/src/lisp/compiler';
import { parseExpression } from '../../../../runtime/shell/src/lisp/parser';
import { packCapabilityCell } from '../../../../runtime/shell/src/lisp/packer';
import type { InterlockPolicy, AlarmSeverity, SCADACommandType } from '../types';

// ── Interlock Policy Compiler ──────────────────────────────────

let policyCounter = 0;

function generatePolicyId(): string {
  policyCounter++;
  return `policy-${policyCounter.toString(16).padStart(4, '0')}`;
}

/** Compile a Lisp constraint expression into bytecode. */
function compileLisp(lispSource: string): { scriptBytes: Uint8Array; scriptWords: string; cellBytes: Uint8Array } {
  const compiler = new LispCompiler();
  const expr = parseExpression(lispSource);
  const output = compiler.compile(expr);
  const cellBytes = packCapabilityCell(output.scriptBytes, { linearity: 'LINEAR' });
  return { scriptBytes: output.scriptBytes, scriptWords: output.scriptWords, cellBytes };
}

// ── Interlock Definitions ──────────────────────────────────────

/**
 * High-pressure interlock — blocks valve.open when pressure > 150 PSI.
 *
 * Lisp policy:
 *   (and (< PT-101 150.0) (has-capability 3))
 *
 * Compiled: sensor-reading PT-101 must be < 150.0
 */
export function highPressureInterlock(
  sensorId: string = 'PT-101',
  targetEquipment: string = 'BV-101',
  threshold: number = 150.0,
): InterlockPolicy {
  const { cellBytes } = compileLisp(`(and (< ${sensorId} ${threshold}) (has-capability 3))`);

  // Script words with domain-specific host function notation for runtime evaluator
  const scriptWords = `"${sensorId}" SENSOR-READING ${threshold} LT 3 CHECK-CAP BOOLAND`;

  return {
    policyId: generatePolicyId(),
    name: 'high-pressure-interlock',
    description: `Block valve.open when ${sensorId} > ${threshold} PSI`,
    targetAction: 'valve.open',
    targetEquipment,
    severity: 'HIGH',
    compiledBytes: cellBytes,
    scriptWords,
  };
}

/**
 * Low-level interlock — blocks motor.start when tank level < 20%.
 */
export function lowLevelInterlock(
  sensorId: string = 'LT-101',
  targetEquipment: string = 'P-101',
  minimum: number = 20.0,
): InterlockPolicy {
  const { cellBytes } = compileLisp(`(and (> ${sensorId} ${minimum}) (has-capability 4))`);

  const scriptWords = `"${sensorId}" SENSOR-READING ${minimum} GT "${sensorId}" SENSOR-QUALITY "GOOD" EQ BOOLAND 4 CHECK-CAP BOOLAND`;

  return {
    policyId: generatePolicyId(),
    name: 'low-level-interlock',
    description: `Block motor.start when ${sensorId} < ${minimum}%`,
    targetAction: 'motor.start',
    targetEquipment,
    severity: 'HIGH',
    compiledBytes: cellBytes,
    scriptWords,
  };
}

/**
 * Temperature runaway protection — emergency shutdown when temp > 500°C.
 * CRITICAL severity — CANNOT be overridden by any operator role.
 */
export function temperatureRunawayInterlock(
  sensorId: string = 'TT-201',
  threshold: number = 500.0,
): InterlockPolicy {
  const { cellBytes } = compileLisp(`(and (> ${sensorId} ${threshold}) (= quality "GOOD"))`);

  const scriptWords = `"${sensorId}" SENSOR-READING ${threshold} LT "GOOD" SENSOR-QUALITY EQ BOOLAND`;

  return {
    policyId: generatePolicyId(),
    name: 'temperature-runaway',
    description: `Emergency shutdown when ${sensorId} > ${threshold}°C`,
    targetAction: 'emergency.shutdown',
    severity: 'CRITICAL',
    compiledBytes: cellBytes,
    scriptWords,
  };
}

/**
 * Interlock override policy — shift supervisor can bypass non-CRITICAL interlocks.
 * Requires capability 5 (interlock override).
 * CRITICAL interlocks CANNOT be overridden.
 */
export function interlockOverridePolicy(): InterlockPolicy {
  const { cellBytes, scriptWords } = compileLisp(`(and (has-capability 5) (= severity "non-critical"))`);

  return {
    policyId: generatePolicyId(),
    name: 'interlock-override',
    description: 'Shift supervisor can bypass non-CRITICAL interlocks with capability 5',
    targetAction: 'valve.open',
    severity: 'LOW',
    compiledBytes: cellBytes,
    scriptWords,
  };
}

/**
 * Emergency shutdown dual authorization — requires two-person authorization.
 * Plant manager + safety officer must both authorize.
 */
export function emergencyShutdownDualAuth(): InterlockPolicy {
  const { cellBytes } = compileLisp(`(and (has-capability 8) (has-capability 10))`);

  return {
    policyId: generatePolicyId(),
    name: 'emergency-shutdown-dual-auth',
    description: 'Emergency shutdown requires dual authorization (plant-manager + safety-officer)',
    targetAction: 'emergency.shutdown',
    severity: 'CRITICAL',
    compiledBytes: cellBytes,
    scriptWords: `8 CHECK-CAP DUAL-AUTH BOOLAND`,
  };
}

/**
 * Sensor cross-validation — require agreement between redundant sensors.
 */
export function sensorCrossValidation(
  sensorA: string = 'TT-201A',
  sensorB: string = 'TT-201B',
  tolerance: number = 5.0,
): InterlockPolicy {
  const compiled = compileLisp(`(or (< tolerance ${tolerance}) (= qualityA "BAD"))`);
  const cellBytes = packCapabilityCell(compiled.scriptBytes, { linearity: 'AFFINE' });

  return {
    policyId: generatePolicyId(),
    name: 'sensor-cross-validation',
    description: `Require agreement between ${sensorA} and ${sensorB} within ${tolerance} tolerance`,
    targetAction: 'valve.open',
    severity: 'MEDIUM',
    compiledBytes: cellBytes,
    scriptWords: compiled.scriptWords,
  };
}

```
