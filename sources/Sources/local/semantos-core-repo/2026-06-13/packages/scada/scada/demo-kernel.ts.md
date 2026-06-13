---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/demo-kernel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.467862+00:00
---

# packages/scada/scada/demo-kernel.ts

```ts
#!/usr/bin/env bun
/**
 * SCADA Kernel-Path Demo — Phase 29.5
 *
 * Demonstrates the full kernel-enforced authorization path:
 * 1. Interlock policy compilation (Lisp → bytecode)
 * 2. Host function registration (sensor-reading, dual-auth, etc.)
 * 3. Command authorization via PolicyRuntime (kernel 2-PDA evaluation)
 * 4. Anchor tx emission for executed commands
 *
 * Usage: bun run packages/scada/demo-kernel.ts
 */

import { loadCellEngine } from '../cell-engine/bindings/bun/loader';
import { HostFunctionRegistry } from '../cell-engine/bindings/host-functions';
import { registerBuiltinHostFunctions } from '../cell-engine/bindings/builtin-host-functions';
import { PolicyRuntime } from '../policy-runtime/src/runtime';
import { DevModeAnchorEmitter } from '../policy-runtime/src/anchor-emitter';
import { CommandAuthorizationEngine } from './src/authorization';
import {
  registerSCADAHostFunctions,
  createTelemetryProvider,
} from './src/policies/host-functions';
import { highPressureInterlock } from './src/policies/interlocks';
import type { TelemetryCell } from './src/types';

async function main() {
  console.log('=== SCADA Kernel-Path Demo (Phase 29.5) ===\n');

  // ── Step 1: Compile interlock policies ──
  console.log('── Interlock Policy Compilation ──\n');
  const pressureInterlock = highPressureInterlock('PT-101', 'BV-101', 150.0);
  console.log(`  Policy: ${pressureInterlock.name}`);
  console.log(`  Target: ${pressureInterlock.targetAction} on ${pressureInterlock.targetEquipment}`);
  console.log(`  Severity: ${pressureInterlock.severity}`);
  console.log(`  Script words: ${pressureInterlock.scriptWords}`);
  const hexBytes = Array.from(pressureInterlock.compiledBytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join(' ');
  console.log(`  Compiled bytes: ${hexBytes}`);
  console.log(`  Byte length: ${pressureInterlock.compiledBytes.length}`);

  // ── Step 2: Set up telemetry state ──
  console.log('\n── Telemetry State ──\n');
  const telemetryState = new Map<string, TelemetryCell>();

  function setReading(sensorId: string, value: number, quality: 'GOOD' | 'BAD') {
    telemetryState.set(sensorId, {
      cellId: `cell-${sensorId}`,
      sensorId,
      sensorType: 'pressure',
      value,
      unit: 'PSI',
      quality,
      timestamp: new Date().toISOString(),
      samplingMethod: 'periodic',
      purpose: 'process-monitoring',
      linearity: 'AFFINE',
    });
    console.log(`  ${sensorId}: ${value} PSI (${quality})`);
  }

  setReading('PT-101', 152.0, 'GOOD'); // above threshold

  // ── Step 3: Set up kernel runtime ──
  console.log('\n── Setting up Kernel Runtime ──\n');
  const registry = new HostFunctionRegistry();
  registerBuiltinHostFunctions(registry);

  const telemetryProvider = createTelemetryProvider(telemetryState);
  registerSCADAHostFunctions(registry, telemetryProvider);
  console.log(`  Registered host functions: ${registry.list().join(', ')}`);

  let engine;
  try {
    engine = await loadCellEngine({ profile: 'embedded', hostRegistry: registry });
    console.log('  CellEngine loaded (embedded profile)');
  } catch (err) {
    console.log(`  CellEngine load failed: ${err}`);
    console.log('  (Expected if WASM binary not built — continuing with legacy evaluator)\n');
    engine = null;
  }

  const anchorEmitter = new DevModeAnchorEmitter();
  const runtime = engine ? new PolicyRuntime(engine, registry) : undefined;

  // ── Step 4: Authorization with interlock enforcement ──
  console.log('\n── Command Authorization ──\n');

  const authEngine = new CommandAuthorizationEngine({
    runtime,
    anchorEmitter,
  });

  // Register operator and grant capability
  authEngine.registerOperator('smith', 'senior-operator');
  const token = authEngine.grantShiftCapability(
    'smith', 'senior-operator',
    new Date(Date.now() - 3600000).toISOString(),
    new Date(Date.now() + 3600000).toISOString(),
    'supervisor-chen',
  );
  console.log(`  Operator: smith (senior-operator)`);
  console.log(`  Token: ${token.tokenId}`);
  console.log(`  Capabilities: [${token.capabilities.join(', ')}]`);

  // Install interlock
  authEngine.installInterlock('BV-101', pressureInterlock);

  // Update telemetry
  for (const [, cell] of telemetryState) {
    authEngine.updateTelemetry(cell);
  }

  // Attempt valve.open while pressure is above threshold
  console.log('\n  Attempt 1: valve.open on BV-101 (pressure=152 PSI > 150 threshold)');
  const result1 = await authEngine.issueCommand(
    { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
    'smith',
    token,
  );

  if (result1.ok) {
    console.log(`  Result: EXECUTED (unexpected!)`);
    if (result1.value.anchorTxId) {
      console.log(`  Anchor txid: ${result1.value.anchorTxId}`);
    }
  } else {
    console.log(`  Result: REJECTED — ${result1.error.message}`);
  }

  // Drop pressure and retry
  console.log('\n  Dropping pressure...');
  setReading('PT-101', 145.0, 'GOOD');
  for (const [, cell] of telemetryState) {
    authEngine.updateTelemetry(cell);
  }

  // Need a new token (previous one may have been consumed or is same ref)
  const token2 = authEngine.grantShiftCapability(
    'smith', 'senior-operator',
    new Date(Date.now() - 3600000).toISOString(),
    new Date(Date.now() + 3600000).toISOString(),
    'supervisor-chen',
  );

  console.log(`\n  Attempt 2: valve.open on BV-101 (pressure=145 PSI < 150 threshold)`);
  const result2 = await authEngine.issueCommand(
    { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
    'smith',
    token2,
  );

  if (result2.ok) {
    console.log(`  Result: EXECUTED`);
    console.log(`  Command cell: ${result2.value.commandCellId}`);
    console.log(`  Interlocks passed: ${result2.value.interlocksPassed}`);
    if (result2.value.anchorTxId) {
      console.log(`  Anchor txid: ${result2.value.anchorTxId}`);
    }
    console.log(`  Audit trail:`);
    for (const entry of result2.value.auditTrail) {
      console.log(`    [${entry.step}] ${entry.result}: ${entry.detail}`);
    }
  } else {
    console.log(`  Result: REJECTED — ${result2.error.message}`);
  }

  // LINEAR replay prevention
  console.log('\n  Attempt 3: replay with consumed token');
  const result3 = await authEngine.issueCommand(
    { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
    'smith',
    token2,
  );
  console.log(`  Result: ${result3.ok ? 'EXECUTED (unexpected!)' : `REJECTED — ${result3.error.message}`}`);

  console.log('\n=== Demo complete ===');
}

main().catch(console.error);

```
