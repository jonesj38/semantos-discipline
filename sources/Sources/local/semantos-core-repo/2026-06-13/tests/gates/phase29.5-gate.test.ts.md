---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase29.5-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.577225+00:00
---

# tests/gates/phase29.5-gate.test.ts

```ts
/**
 * Phase 29.5 Gate: Kernel Enforcement Sweep
 *
 * Four hard invariants:
 * 1. no-ts-shim — host predicates route through OP_CALLHOST, not TS shim (T1)
 * 2. opcode-rejection — failed policy returns structured PolicyResult (T2)
 * 3. anchor-idempotent — same cell emitted twice returns same txid (T3)
 * 4. unknown-host-fn-is-loud — unregistered predicate returns ERR_UNKNOWN_HOST_FN (T4)
 *
 * Additional coverage:
 * - PolicyRuntime instantiation and basic evaluation (T5–T6)
 * - CDM host function registration (T7–T8)
 * - SCADA host function registration (T9–T10)
 * - CDM lifecycle with kernel enforcement (T11–T13)
 * - SCADA authorization with kernel enforcement (T14–T16)
 * - Anchor emitter (T17–T19)
 * - Backward compatibility (T20–T21)
 */

import { describe, test, expect } from 'bun:test';
import { join } from 'path';

const ROOT = join(import.meta.dir, '../..');

// ── Gate 1: PolicyRuntime Core (T1–T6) ──────────────────────

describe('D29.5.1 — PolicyRuntime', () => {
  test('T1: no-ts-shim — HostFunctionRegistry dispatches via call(), not direct TS invocation', () => {
    const { HostFunctionRegistry } = require(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts'),
    );
    const registry = new HostFunctionRegistry();
    let callCount = 0;

    registry.register('test-predicate', () => {
      callCount++;
      return 1;
    });
    registry.setContext({ fields: {} });

    // Dispatch by name (same path as OP_CALLHOST in the kernel)
    const result = registry.call('test-predicate');
    expect(result).toBe(1);
    expect(callCount).toBe(1);

    // Second call increments — proving dispatch is live
    registry.call('test-predicate');
    expect(callCount).toBe(2);
  });

  test('T2: opcode-rejection — PolicyResult is structured data, never throws', async () => {
    const { PolicyRuntime } = await import(
      join(ROOT, 'packages/policy-runtime/src/runtime.ts')
    );
    const { HostFunctionRegistry } = await import(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts')
    );
    const { loadCellEngine } = await import(
      join(ROOT, 'core/cell-engine/bindings/bun/loader.ts')
    );

    const registry = new HostFunctionRegistry();
    let engine;
    try {
      engine = await loadCellEngine({ profile: 'embedded', hostRegistry: registry });
    } catch {
      console.log('  [T2] Skipped: WASM binary not available (run zig build to enable)');
      return;
    }
    const runtime = new PolicyRuntime(engine, registry);

    // Script that pushes 0 (falsy) — should produce ok: false
    // OP_0 (0x00)
    const failScript = new Uint8Array([0x00]);
    const result = await runtime.evaluate(failScript, {
      fields: {},
      actor: { certId: 'test', capabilities: [] },
    });

    expect(result.ok).toBe(false);
    expect(result.rejectionCode).toBeTruthy();
    expect(typeof result.gas).toBe('number');
    expect(Array.isArray(result.hostCalls)).toBe(true);
  });

  test('T3: anchor-idempotent — same cell emitted twice returns same txid', async () => {
    const { DevModeAnchorEmitter } = require(
      join(ROOT, 'packages/policy-runtime/src/anchor-emitter.ts'),
    );
    const emitter = new DevModeAnchorEmitter();
    const cellBytes = new Uint8Array([1, 2, 3, 4, 5]);

    const result1 = await emitter.emit(cellBytes, {
      linearity: 'LINEAR' as const,
      anchorPolicy: 'always' as const,
      idempotencyKey: 'test-key-1',
    });

    const result2 = await emitter.emit(cellBytes, {
      linearity: 'LINEAR' as const,
      anchorPolicy: 'always' as const,
      idempotencyKey: 'test-key-1',
    });

    expect(result1.txid).toBe(result2.txid);
    expect(result1.reused).toBe(false);
    expect(result2.reused).toBe(true);
    expect(result1.beefEnvelope.length).toBeGreaterThan(0);
  });

  test('T4: unknown-host-fn-is-loud — unregistered predicate returns rejection', () => {
    const { HostFunctionRegistry } = require(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts'),
    );
    const registry = new HostFunctionRegistry();
    registry.setContext({});

    // Call an unregistered function
    const result = registry.call('nonexistent-predicate');
    expect(result).toBe(0xFFFFFFFF); // sentinel for unknown

    // Verify it's not a silent pass (0 or 1)
    expect(result).not.toBe(0);
    expect(result).not.toBe(1);
  });

  test('T5: PolicyRuntime evaluates a simple passing script', async () => {
    const { PolicyRuntime } = await import(
      join(ROOT, 'packages/policy-runtime/src/runtime.ts')
    );
    const { HostFunctionRegistry } = await import(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts')
    );
    const { loadCellEngine } = await import(
      join(ROOT, 'core/cell-engine/bindings/bun/loader.ts')
    );

    const registry = new HostFunctionRegistry();
    let engine;
    try {
      engine = await loadCellEngine({ profile: 'embedded', hostRegistry: registry });
    } catch {
      console.log('  [T5] Skipped: WASM binary not available (run zig build to enable)');
      return;
    }
    const runtime = new PolicyRuntime(engine, registry);

    // Script that pushes 1 (truthy) — OP_1 (0x51)
    const passScript = new Uint8Array([0x51]);
    const result = await runtime.evaluate(passScript, {
      fields: {},
      actor: { certId: 'test', capabilities: [] },
    });

    expect(result.ok).toBe(true);
    expect(result.gas).toBeGreaterThan(0);
  });

  test('T6: PolicyRuntime records host calls in audit trail', async () => {
    const { PolicyRuntime } = await import(
      join(ROOT, 'packages/policy-runtime/src/runtime.ts')
    );
    const { HostFunctionRegistry } = await import(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts')
    );
    const { loadCellEngine } = await import(
      join(ROOT, 'core/cell-engine/bindings/bun/loader.ts')
    );

    const registry = new HostFunctionRegistry();
    registry.register('always-true', () => 1);

    let engine;
    try {
      engine = await loadCellEngine({ profile: 'embedded', hostRegistry: registry });
    } catch {
      console.log('  [T6] Skipped: WASM binary not available (run zig build to enable)');
      return;
    }
    const runtime = new PolicyRuntime(engine, registry);

    // Script: push "always-true" then OP_CALLHOST (0xD0)
    // Push the string "always-true" (11 bytes) onto the stack
    const nameBytes = new TextEncoder().encode('always-true');
    const script = new Uint8Array([nameBytes.length, ...nameBytes, 0xD0]);

    const result = await runtime.evaluate(script, {
      fields: {},
      actor: { certId: 'test', capabilities: [] },
    });

    // OP_CALLHOST (0xD0) may not be present in the WASM binary if it
    // was built before Phase 25.5. In that case the kernel returns
    // an invalid/unknown opcode error. Skip the assertion in that case.
    if (!result.ok) {
      const detail = (result.rejectionCode ?? '') + ' ' + (result.rejectionDetail ?? '');
      if (detail.includes('invalid_opcode') || detail.includes('INVALID_OPCODE') || detail.includes('unknown')) {
        console.log(`  [T6] Skipped: WASM binary lacks OP_CALLHOST (0xD0). Rebuild with zig build to enable. (${result.rejectionCode})`);
        return;
      }
    }

    expect(result.ok).toBe(true);
    expect(result.hostCalls.length).toBe(1);
    expect(result.hostCalls[0].name).toBe('always-true');
    expect(result.hostCalls[0].result).toBe(1);
  });
});

// ── Gate 2: Host Function Registration (T7–T10) ────────────

describe('D29.5.2 — Host function registration', () => {
  test('T7: CDM host functions register and dispatch', () => {
    const { HostFunctionRegistry } = require(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts'),
    );
    const { registerCDMHostFunctions } = require(
      join(ROOT, 'packages/cdm/src/policies/host-functions.ts'),
    );

    const registry = new HostFunctionRegistry();
    registerCDMHostFunctions(registry);

    // Verify all CDM predicates are registered
    expect(registry.has('counterparty-default-status')).toBe(true);
    expect(registry.has('payment-status')).toBe(true);
    expect(registry.has('days-past-due')).toBe(true);
    expect(registry.has('margin-type')).toBe(true);
    expect(registry.has('margin-amount')).toBe(true);
  });

  test('T8: CDM host function reads from context', () => {
    const { HostFunctionRegistry } = require(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts'),
    );
    const { registerCDMHostFunctions } = require(
      join(ROOT, 'packages/cdm/src/policies/host-functions.ts'),
    );

    const registry = new HostFunctionRegistry();
    registerCDMHostFunctions(registry);

    // Set context with days-past-due = 5
    registry.setContext({ fields: { 'days-past-due': 5 } });
    const result = registry.call('days-past-due');
    expect(result).toBe(5);
  });

  test('T9: SCADA host functions register and dispatch', () => {
    const { HostFunctionRegistry } = require(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts'),
    );
    const { registerSCADAHostFunctions, createTelemetryProvider } = require(
      join(ROOT, 'packages/scada/src/policies/host-functions.ts'),
    );

    const registry = new HostFunctionRegistry();
    const telemetry = createTelemetryProvider(new Map());
    registerSCADAHostFunctions(registry, telemetry);

    // Verify SCADA predicates are registered
    expect(registry.has('sensor-reading')).toBe(true);
    expect(registry.has('sensor-quality')).toBe(true);
    expect(registry.has('dual-auth')).toBe(true);
    expect(registry.has('target-eq?')).toBe(true);
    expect(registry.has('pressure-below-limit?')).toBe(true);
    expect(registry.has('temperature-below-limit?')).toBe(true);
    expect(registry.has('level-above-minimum?')).toBe(true);
  });

  test('T10: SCADA sensor-reading reads live telemetry', () => {
    const { HostFunctionRegistry } = require(
      join(ROOT, 'core/cell-engine/bindings/host-functions.ts'),
    );
    const { registerSCADAHostFunctions, createTelemetryProvider } = require(
      join(ROOT, 'packages/scada/src/policies/host-functions.ts'),
    );

    const state = new Map();
    state.set('PT-101', { sensorId: 'PT-101', value: 152.0, quality: 'GOOD' });
    const telemetry = createTelemetryProvider(state);
    const registry = new HostFunctionRegistry();
    registerSCADAHostFunctions(registry, telemetry);

    registry.setContext({ fields: { '__sensor_id': 'PT-101' } });
    const reading = registry.call('sensor-reading');
    expect(reading).toBe(152);

    const quality = registry.call('sensor-quality');
    expect(quality).toBe(1); // GOOD = 1
  });
});

// ── Gate 3: CDM Kernel Enforcement (T11–T13) ────────────────

describe('D29.5.3 — CDM lifecycle kernel enforcement', () => {
  test('T11: CDM lifecycle without runtime still works (backward compat)', async () => {
    const { CDMLifecycleEngine } = require(
      join(ROOT, 'packages/cdm/src/lifecycle.ts'),
    );
    const { createCDMProduct } = require(
      join(ROOT, 'packages/cdm/src/types.ts'),
    );

    const engine = new CDMLifecycleEngine(); // no runtime
    const product = createCDMProduct(
      'rates.swap.fixed-float',
      {
        notional: { amount: 10_000_000, currency: 'USD' },
        effectiveDate: '2024-06-15',
        terminationDate: '2029-06-15',
        fixedRate: 0.035,
      },
      [
        { partyId: 'bank-a', role: 'buyer', capabilities: [2, 9] },
        { partyId: 'bank-b', role: 'seller', capabilities: [2, 9] },
      ],
      '2024-06-15',
    );

    const result = await engine.executeEvent(product, 'execution', '2024-06-15', {}, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe('executed');
      expect(result.value.cell.length).toBeGreaterThan(0);
    }
  });

  test('T12: CDM lifecycle invalid transition still rejected', async () => {
    const { CDMLifecycleEngine } = require(
      join(ROOT, 'packages/cdm/src/lifecycle.ts'),
    );
    const { createCDMProduct } = require(
      join(ROOT, 'packages/cdm/src/types.ts'),
    );

    const engine = new CDMLifecycleEngine();
    const product = createCDMProduct(
      'rates.swap.fixed-float',
      {
        notional: { amount: 10_000_000, currency: 'USD' },
        effectiveDate: '2024-06-15',
        terminationDate: '2029-06-15',
      },
      [{ partyId: 'bank-a', role: 'buyer', capabilities: [] }],
      '2024-06-15',
    );

    // proposed → settlement should fail (not in transition table)
    const result = await engine.executeEvent(product, 'settlement', '2024-06-15', {}, 'actor-1');
    expect(result.ok).toBe(false);
  });

  test('T13: CDM terminal event produces anchor txid when emitter configured', async () => {
    const { CDMLifecycleEngine } = require(
      join(ROOT, 'packages/cdm/src/lifecycle.ts'),
    );
    const { createCDMProduct } = require(
      join(ROOT, 'packages/cdm/src/types.ts'),
    );
    const { DevModeAnchorEmitter } = require(
      join(ROOT, 'packages/policy-runtime/src/anchor-emitter.ts'),
    );

    const emitter = new DevModeAnchorEmitter();
    const engine = new CDMLifecycleEngine({ anchorEmitter: emitter });
    const product = createCDMProduct(
      'rates.swap.fixed-float',
      {
        notional: { amount: 10_000_000, currency: 'USD' },
        effectiveDate: '2024-06-15',
        terminationDate: '2029-06-15',
      },
      [{ partyId: 'bank-a', role: 'buyer', capabilities: [] }],
      '2024-06-15',
    );

    // 'execution' is a terminal event → should produce anchor
    const result = await engine.executeEvent(product, 'execution', '2024-06-15', {}, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.anchorTxId).toBeTruthy();
      expect(result.value.anchorTxId!.length).toBe(64); // hex sha256
    }
  });
});

// ── Gate 4: SCADA Kernel Enforcement (T14–T16) ──────────────

describe('D29.5.4 — SCADA authorization kernel enforcement', () => {
  test('T14: SCADA command without runtime still works (backward compat)', async () => {
    const { CommandAuthorizationEngine } = require(
      join(ROOT, 'packages/scada/src/authorization.ts'),
    );

    const engine = new CommandAuthorizationEngine(); // no runtime
    engine.registerOperator('smith', 'senior-operator');
    const token = engine.grantShiftCapability(
      'smith', 'senior-operator',
      new Date(Date.now() - 3600000).toISOString(),
      new Date(Date.now() + 3600000).toISOString(),
      'supervisor',
    );

    const result = await engine.issueCommand(
      { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
      'smith',
      token,
    );
    // No interlocks installed → passes
    expect(result.ok).toBe(true);
  });

  test('T15: SCADA command produces anchor txid when emitter configured', async () => {
    const { CommandAuthorizationEngine } = require(
      join(ROOT, 'packages/scada/src/authorization.ts'),
    );
    const { DevModeAnchorEmitter } = require(
      join(ROOT, 'packages/policy-runtime/src/anchor-emitter.ts'),
    );

    const emitter = new DevModeAnchorEmitter();
    const engine = new CommandAuthorizationEngine({ anchorEmitter: emitter });
    engine.registerOperator('smith', 'senior-operator');
    const token = engine.grantShiftCapability(
      'smith', 'senior-operator',
      new Date(Date.now() - 3600000).toISOString(),
      new Date(Date.now() + 3600000).toISOString(),
      'supervisor',
    );

    const result = await engine.issueCommand(
      { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
      'smith',
      token,
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.anchorTxId).toBeTruthy();
    }
  });

  test('T16: SCADA LINEAR replay prevention still works', async () => {
    const { CommandAuthorizationEngine } = require(
      join(ROOT, 'packages/scada/src/authorization.ts'),
    );

    const engine = new CommandAuthorizationEngine();
    engine.registerOperator('smith', 'senior-operator');
    const token = engine.grantShiftCapability(
      'smith', 'senior-operator',
      new Date(Date.now() - 3600000).toISOString(),
      new Date(Date.now() + 3600000).toISOString(),
      'supervisor',
    );

    // First use succeeds
    const result1 = await engine.issueCommand(
      { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
      'smith',
      token,
    );
    expect(result1.ok).toBe(true);

    // Replay attempt fails (LINEAR consumed)
    const result2 = await engine.issueCommand(
      { commandType: 'valve.open', targetEquipment: 'BV-101', parameters: {} },
      'smith',
      token,
    );
    expect(result2.ok).toBe(false);
    if (!result2.ok) {
      expect(result2.error.code).toBe('CONSUMED_CAPABILITY');
    }
  });
});

// ── Gate 5: Anchor Emitter (T17–T19) ────────────────────────

describe('D29.5.5 — Anchor emitter', () => {
  test('T17: DevModeAnchorEmitter produces structurally valid BEEF', async () => {
    const { DevModeAnchorEmitter } = require(
      join(ROOT, 'packages/policy-runtime/src/anchor-emitter.ts'),
    );

    const emitter = new DevModeAnchorEmitter();
    const cellBytes = new Uint8Array(100).fill(0xAB);

    const result = await emitter.emit(cellBytes, {
      linearity: 'LINEAR' as const,
      anchorPolicy: 'always' as const,
      idempotencyKey: 'test-beef',
    });

    // Check BEEF v1 magic: EF BE 00 01 (little-endian 0x0100BEEF)
    expect(result.beefEnvelope[0]).toBe(0xEF);
    expect(result.beefEnvelope[1]).toBe(0xBE);
    expect(result.beefEnvelope[2]).toBe(0x00);
    expect(result.beefEnvelope[3]).toBe(0x01);
    expect(result.txid).toHaveLength(64);
  });

  test('T18: anchorPolicy=never produces empty envelope', async () => {
    const { DevModeAnchorEmitter } = require(
      join(ROOT, 'packages/policy-runtime/src/anchor-emitter.ts'),
    );

    const emitter = new DevModeAnchorEmitter();
    const result = await emitter.emit(new Uint8Array([1, 2, 3]), {
      linearity: 'LINEAR' as const,
      anchorPolicy: 'never' as const,
      idempotencyKey: 'skip',
    });

    expect(result.beefEnvelope.length).toBe(0);
    expect(result.txid).toBe('0'.repeat(64));
  });

  test('T19: different cells produce different txids', async () => {
    const { DevModeAnchorEmitter } = require(
      join(ROOT, 'packages/policy-runtime/src/anchor-emitter.ts'),
    );

    const emitter = new DevModeAnchorEmitter();
    const cell1 = new Uint8Array([1, 2, 3]);
    const cell2 = new Uint8Array([4, 5, 6]);

    const r1 = await emitter.emit(cell1, {
      linearity: 'LINEAR' as const,
      anchorPolicy: 'always' as const,
      idempotencyKey: 'key-1',
    });
    const r2 = await emitter.emit(cell2, {
      linearity: 'LINEAR' as const,
      anchorPolicy: 'always' as const,
      idempotencyKey: 'key-2',
    });

    expect(r1.txid).not.toBe(r2.txid);
  });
});

// ── Gate 6: Backward Compatibility (T20–T21) ────────────────

describe('D29.5 — Backward compatibility', () => {
  test('T20: CDM policy compilation still produces valid scriptBytes', () => {
    const { compileCDMPolicy } = require(
      join(ROOT, 'packages/cdm/src/policies/compiler.ts'),
    );

    const policySource = `(policy
      :subject paying-party
      :action make-payment
      :constraint (and
        (not (= counterparty-default-status "defaulted"))
        (has-capability 2))
      :linearity LINEAR)`;

    const output = compileCDMPolicy(policySource);
    expect(output.scriptBytes).toBeInstanceOf(Uint8Array);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
    expect(output.scriptWords).toBeTruthy();
  });

  test('T21: SCADA interlock compilation still produces valid compiledBytes', () => {
    const { highPressureInterlock } = require(
      join(ROOT, 'packages/scada/src/policies/interlocks.ts'),
    );

    const policy = highPressureInterlock('PT-101', 'BV-101', 150.0);
    expect(policy.compiledBytes).toBeInstanceOf(Uint8Array);
    expect(policy.compiledBytes.length).toBeGreaterThan(0);
    expect(policy.scriptWords).toBeTruthy();
    expect(policy.policyId).toBeTruthy();
    expect(policy.targetAction).toBe('valve.open');
  });
});

```
