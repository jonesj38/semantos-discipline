---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/policies/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.475159+00:00
---

# packages/scada/scada/src/policies/host-functions.ts

```ts
/**
 * Domain Constraint Host Functions — Phase 29 (D29.3), updated Phase 29.5
 *
 * Host functions registered with the cell engine for evaluating
 * SCADA-specific constraints in compiled interlock policies.
 *
 * These bridge between the cell engine's opcode evaluation and
 * the runtime telemetry/command state.
 *
 * Phase 29.5 adds registerSCADAHostFunctions() for OP_CALLHOST dispatch
 * through the real kernel. The TS-shim evaluator (evaluatePolicyScriptWords)
 * is kept temporarily for differential testing and will be deleted at cutover.
 */

import type { TelemetryCell, CommandCell, InterlockPolicy, InterlockViolation, Result } from '../types';
import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine/bindings/host-functions';
import type { HostFunctionProvider } from '@semantos/policy-runtime';

/**
 * Telemetry state provider — returns current sensor readings
 * for policy evaluation.
 */
export interface TelemetryStateProvider {
  /** Get the current reading value for a sensor ID. */
  sensorReading(sensorId: string): number | undefined;

  /** Get the quality flag for a sensor ID. */
  sensorQuality(sensorId: string): 'GOOD' | 'UNCERTAIN' | 'BAD' | undefined;
}

/**
 * Dual authorization provider — checks for second authorizer.
 */
export interface DualAuthProvider {
  /** Check if a second authorizer with the given role has approved. */
  hasDualAuthorization(requiredRole: string): boolean;
}

/**
 * Create a TelemetryStateProvider from a Map of current readings.
 */
export function createTelemetryProvider(
  state: Map<string, TelemetryCell>,
): TelemetryStateProvider {
  return {
    sensorReading(sensorId: string): number | undefined {
      return state.get(sensorId)?.value;
    },
    sensorQuality(sensorId: string): 'GOOD' | 'UNCERTAIN' | 'BAD' | undefined {
      return state.get(sensorId)?.quality;
    },
  };
}

/**
 * Evaluate an interlock policy against the current telemetry state.
 *
 * This is the host-function bridge: the compiled policy opcodes reference
 * sensor-reading and sensor-quality host functions. This evaluator
 * interprets the policy semantics using the constraint metadata
 * embedded during compilation.
 *
 * In a full implementation, this would invoke the WASM cell engine's
 * 2-PDA with the policy's compiled bytecode. Here we evaluate the
 * policy constraints directly using the same semantics.
 */
export function createInterlockEvaluator(
  dualAuthProvider?: DualAuthProvider,
): (
  policy: InterlockPolicy,
  command: CommandCell,
  state: Map<string, TelemetryCell>,
) => Result<void, InterlockViolation> {
  return (
    policy: InterlockPolicy,
    command: CommandCell,
    state: Map<string, TelemetryCell>,
  ): Result<void, InterlockViolation> => {
    const provider = createTelemetryProvider(state);

    // Parse policy semantics from the compiled script words.
    // The script words encode the constraint in a human-readable
    // Forth-like notation that mirrors the 2-PDA evaluation order.
    const result = evaluatePolicyScriptWords(
      policy,
      command,
      provider,
      dualAuthProvider,
    );

    return result;
  };
}

/**
 * Evaluate compiled policy script words against current state.
 *
 * The script words are the human-readable representation of the
 * compiled opcodes. We parse them to extract the constraint
 * semantics and evaluate against current telemetry.
 */
function evaluatePolicyScriptWords(
  policy: InterlockPolicy,
  command: CommandCell,
  telemetry: TelemetryStateProvider,
  dualAuth?: DualAuthProvider,
): Result<void, InterlockViolation> {
  const words = policy.scriptWords;

  // High-pressure interlock: blocks when sensor reading exceeds threshold
  if (words.includes('SENSOR-READING') && words.includes('LT')) {
    // Extract sensor ID and threshold from script words
    const match = words.match(/"([^"]+)"\s+SENSOR-READING\s+(\d+(?:\.\d+)?)\s+/);
    if (match) {
      const sensorId = match[1];
      const threshold = parseFloat(match[2]);
      const reading = telemetry.sensorReading(sensorId);
      if (reading !== undefined && reading >= threshold) {
        return {
          ok: false,
          error: {
            policyId: policy.policyId,
            policyName: policy.name,
            reason: `${policy.name}: sensor ${sensorId} reading ${reading} exceeds threshold ${threshold}`,
            sensorId,
            currentValue: reading,
            threshold,
          },
        };
      }
    }
  }

  // Low-level interlock: blocks when sensor reading below minimum
  if (words.includes('SENSOR-READING') && words.includes('GT')) {
    const match = words.match(/"([^"]+)"\s+SENSOR-READING\s+(\d+(?:\.\d+)?)\s+/);
    if (match) {
      const sensorId = match[1];
      const minimum = parseFloat(match[2]);
      const reading = telemetry.sensorReading(sensorId);
      if (reading !== undefined && reading <= minimum) {
        return {
          ok: false,
          error: {
            policyId: policy.policyId,
            policyName: policy.name,
            reason: `${policy.name}: sensor ${sensorId} reading ${reading} below minimum ${minimum}`,
            sensorId,
            currentValue: reading,
            threshold: minimum,
          },
        };
      }
    }
  }

  // Sensor quality check: blocks when sensor has BAD quality
  if (words.includes('SENSOR-QUALITY') && words.includes('"GOOD"')) {
    const qualMatch = words.match(/"([^"]+)"\s+SENSOR-QUALITY/);
    if (qualMatch) {
      const sensorId = qualMatch[1];
      const quality = telemetry.sensorQuality(sensorId);
      if (quality === 'BAD') {
        return {
          ok: false,
          error: {
            policyId: policy.policyId,
            policyName: policy.name,
            reason: `${policy.name}: sensor ${sensorId} has BAD quality`,
            sensorId,
          },
        };
      }
    }
  }

  // Dual authorization check
  if (words.includes('DUAL-AUTH')) {
    if (!dualAuth || !dualAuth.hasDualAuthorization('safety-officer')) {
      return {
        ok: false,
        error: {
          policyId: policy.policyId,
          policyName: policy.name,
          reason: `${policy.name}: dual authorization required but not provided`,
        },
      };
    }
  }

  return { ok: true, value: undefined };
}

// ── Phase 29.5: Kernel-routed host function registration ────

/**
 * Register SCADA host functions with the HostFunctionRegistry
 * for OP_CALLHOST dispatch through the real WASM 2-PDA.
 *
 * Host functions read from the frozen HostFunctionContext.fields map,
 * which is populated by CommandAuthorizationEngine before each evaluation.
 */
export function registerSCADAHostFunctions(
  registry: HostFunctionRegistry,
  telemetry: TelemetryStateProvider,
  dualAuth?: DualAuthProvider,
): void {
  // sensor-reading: return the current numeric reading for a sensor
  registry.register('sensor-reading', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const sensorId = fields?.['__sensor_id'] as string | undefined;
    if (!sensorId) return 0;
    return telemetry.sensorReading(sensorId) ?? 0;
  });

  // sensor-quality: return 1 if GOOD, 0 otherwise
  registry.register('sensor-quality', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const sensorId = fields?.['__sensor_id'] as string | undefined;
    if (!sensorId) return 0;
    const quality = telemetry.sensorQuality(sensorId);
    return quality === 'GOOD' ? 1 : 0;
  });

  // dual-auth: return 1 if dual authorization is granted
  registry.register('dual-auth', (ctx: HostFunctionContext): number => {
    if (!dualAuth) return 0;
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const requiredRole = (fields?.['__dual_auth_role'] as string) ?? 'safety-officer';
    return dualAuth.hasDualAuthorization(requiredRole) ? 1 : 0;
  });

  // target-eq?: check if the target equipment matches
  registry.register('target-eq?', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const expected = fields?.['__target_equipment'] as string | undefined;
    const actual = fields?.['target_equipment'] as string | undefined;
    if (!expected || !actual) return 0;
    return expected === actual ? 1 : 0;
  });

  // pressure-below-limit?: check if pressure is below threshold
  registry.register('pressure-below-limit?', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const sensorId = fields?.['__sensor_id'] as string | undefined;
    const threshold = fields?.['__threshold'] as number | undefined;
    if (!sensorId || threshold === undefined) return 1; // no constraint = pass
    const reading = telemetry.sensorReading(sensorId);
    if (reading === undefined) return 1;
    return reading < threshold ? 1 : 0;
  });

  // temperature-below-limit?: check if temperature is below threshold
  registry.register('temperature-below-limit?', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const sensorId = fields?.['__sensor_id'] as string | undefined;
    const threshold = fields?.['__threshold'] as number | undefined;
    if (!sensorId || threshold === undefined) return 1;
    const reading = telemetry.sensorReading(sensorId);
    if (reading === undefined) return 1;
    return reading < threshold ? 1 : 0;
  });

  // level-above-minimum?: check if level is above minimum
  registry.register('level-above-minimum?', (ctx: HostFunctionContext): number => {
    const fields = ctx.fields as Record<string, unknown> | undefined;
    const sensorId = fields?.['__sensor_id'] as string | undefined;
    const minimum = fields?.['__threshold'] as number | undefined;
    if (!sensorId || minimum === undefined) return 1;
    const reading = telemetry.sensorReading(sensorId);
    if (reading === undefined) return 1;
    return reading > minimum ? 1 : 0;
  });
}

/**
 * SCADA host function provider for PolicyRuntime integration.
 */
export function createSCADAHostFunctionProvider(
  telemetry: TelemetryStateProvider,
  dualAuth?: DualAuthProvider,
): HostFunctionProvider {
  return {
    register(registry: HostFunctionRegistry): void {
      registerSCADAHostFunctions(registry, telemetry, dualAuth);
    },
  };
}

```
