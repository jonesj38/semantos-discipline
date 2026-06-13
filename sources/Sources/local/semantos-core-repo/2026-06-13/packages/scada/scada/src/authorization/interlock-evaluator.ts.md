---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/interlock-evaluator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.474503+00:00
---

# packages/scada/scada/src/authorization/interlock-evaluator.ts

```ts
/**
 * Interlock evaluator — runs per-equipment safety policies for a
 * proposed command and reports any violations.
 *
 * Phase 29.5 dual-mode behaviour preserved:
 *   - If a `PolicyRuntime` is configured, every policy is evaluated
 *     through the WASM 2-PDA kernel via OP_CALLHOST.
 *   - Otherwise, the legacy injected TS-shim evaluator runs (kept for
 *     differential testing).
 *
 * Pure-ish — operates only on the bits of `EngineState` it needs, plus
 * an optional runtime + injected evaluator.
 */

import type {
  CommandCell,
  InterlockPolicy,
  InterlockViolation,
  Result,
  SCADACommandType,
  TelemetryCell,
} from '../types';
import type { PolicyContext, PolicyRuntime } from '@semantos/policy-runtime';

import { microsecondTimestamp } from './cell-id';

export type InterlockShimEvaluator = (
  policy: InterlockPolicy,
  command: CommandCell,
  state: Map<string, TelemetryCell>,
) => Result<void, InterlockViolation>;

export interface EvaluateInterlocksDeps {
  interlocksByEquipment: Map<string, InterlockPolicy[]>;
  telemetryState: Map<string, TelemetryCell>;
  policyRuntime?: PolicyRuntime;
  shimEvaluator?: InterlockShimEvaluator;
}

export async function evaluateInterlocks(
  commandType: SCADACommandType,
  targetEquipment: string,
  deps: EvaluateInterlocksDeps,
): Promise<Result<void, InterlockViolation[]>> {
  const policies = deps.interlocksByEquipment.get(targetEquipment) ?? [];
  const relevant = policies.filter(p => p.targetAction === commandType);

  if (relevant.length === 0) {
    return { ok: true, value: undefined };
  }

  const violations: InterlockViolation[] = [];

  for (const policy of relevant) {
    if (deps.policyRuntime) {
      const ctx: PolicyContext = {
        fields: {
          '__sensor_id': policy.targetEquipment ?? targetEquipment,
          '__target_equipment': targetEquipment,
          'target_equipment': targetEquipment,
        },
        actor: { certId: '', capabilities: [] },
      };
      for (const [sensorId, cell] of deps.telemetryState) {
        ctx.fields[`sensor:${sensorId}`] = cell.value;
        ctx.fields[`quality:${sensorId}`] = cell.quality;
      }
      const result = await deps.policyRuntime.evaluate(policy.compiledBytes, ctx);
      if (!result.ok) {
        violations.push({
          policyId: policy.policyId,
          policyName: policy.name,
          reason: `${policy.name}: kernel rejected — ${result.rejectionDetail ?? result.rejectionCode}`,
        });
      }
    } else if (deps.shimEvaluator) {
      const dummyCommand: CommandCell = {
        cellId: 'eval-temp',
        commandType,
        targetEquipment,
        parameters: {},
        issuedBy: '',
        authorizedBy: new Uint8Array(0),
        timestamp: microsecondTimestamp(),
        executionStatus: 'pending',
        linearity: 'LINEAR',
      };
      const result = deps.shimEvaluator(policy, dummyCommand, deps.telemetryState);
      if (!result.ok) {
        violations.push(result.error);
      }
    }
  }

  if (violations.length > 0) {
    return { ok: false, error: violations };
  }
  return { ok: true, value: undefined };
}

```
