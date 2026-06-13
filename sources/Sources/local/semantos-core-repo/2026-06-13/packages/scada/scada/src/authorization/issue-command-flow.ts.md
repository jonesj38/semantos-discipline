---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/issue-command-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.471029+00:00
---

# packages/scada/scada/src/authorization/issue-command-flow.ts

```ts
/**
 * Issue-command flow — the multi-step command authorization pipeline:
 *
 *   1. identity-verification
 *   2. capability-verification (LINEAR token + role rule)
 *   3. interlock-evaluation
 *   4. execution + LINEAR token consumption
 *   5. anchor emission (Phase 29.5, optional)
 *
 * Mutates only the `EngineState` passed in; emits decision events onto
 * a fresh per-call bus so concurrent commands don't interleave audit
 * trails. The legacy `auditTrail` array shape is reproduced exactly via
 * `audit-logger`'s `eventToAuditEntry`.
 */

import type {
  CommandCell,
  CommandError,
  CommandReceipt,
  Result,
  SCADACapabilityToken,
} from '../types';
import type { AnchorEmitter, PolicyRuntime } from '@semantos/policy-runtime';

import {
  makeAuditor,
  makeDecisionEventBus,
  type DecisionEvent,
} from './audit-logger';
import { evaluateCapability } from './capability-evaluator';
import { generateCellId, microsecondTimestamp } from './cell-id';
import type { EngineState } from './engine-state';
import {
  evaluateInterlocks,
  type InterlockShimEvaluator,
} from './interlock-evaluator';

export type IssueCommandInput = Omit<
  CommandCell,
  'cellId' | 'timestamp' | 'executionStatus' | 'linearity' | 'authorizedBy' | 'previousCommandCell'
>;

export interface IssueCommandDeps {
  state: EngineState;
  policyRuntime?: PolicyRuntime;
  anchorEmitter?: AnchorEmitter;
  shimEvaluator?: InterlockShimEvaluator;
}

export async function issueCommand(
  command: IssueCommandInput,
  operatorIdentity: string,
  capabilityToken: SCADACapabilityToken,
  deps: IssueCommandDeps,
): Promise<Result<CommandReceipt, CommandError>> {
  const { state } = deps;
  const decisionBus = makeDecisionEventBus();
  const auditor = makeAuditor(decisionBus);
  const now = microsecondTimestamp();

  const emit = (event: Omit<DecisionEvent, 'operatorId' | 'timestamp'>): void => {
    decisionBus.emit({ ...event, operatorId: operatorIdentity, timestamp: now });
  };

  try {
    // Step 1: Verify operator identity
    const operator = state.operators.get(operatorIdentity);
    if (!operator || !operator.active) {
      return {
        ok: false,
        error: {
          code: 'NO_IDENTITY',
          message: `Operator ${operatorIdentity} not registered or inactive`,
        },
      };
    }
    emit({
      step: 'identity-verification',
      result: 'pass',
      detail: `Operator ${operatorIdentity} verified as ${operator.role}`,
    });

    // Step 2: Capability decision (linearity + expiry + role rule)
    const capDecision = evaluateCapability(
      capabilityToken,
      command.commandType,
      Date.now(),
      state.consumedTokens,
    );
    if (!capDecision.ok) {
      const code =
        capDecision.reason === 'CONSUMED_CAPABILITY'
          ? 'CONSUMED_CAPABILITY'
          : capDecision.reason === 'EXPIRED_CAPABILITY'
            ? 'EXPIRED_CAPABILITY'
            : 'INSUFFICIENT_ROLE';
      return { ok: false, error: { code, message: capDecision.detail } };
    }
    emit({
      step: 'capability-verification',
      result: 'pass',
      detail: `Token ${capabilityToken.tokenId} valid, capability ${capDecision.required} present`,
    });

    // Steps 3 & 4: Interlock evaluation
    const interlockResult = await evaluateInterlocks(
      command.commandType,
      command.targetEquipment,
      {
        interlocksByEquipment: state.interlocksByEquipment,
        telemetryState: state.telemetryState,
        policyRuntime: deps.policyRuntime,
        shimEvaluator: deps.shimEvaluator,
      },
    );

    if (!interlockResult.ok) {
      // Step 6: Reject — create rejection cell
      const rejectionCellId = generateCellId();
      const rejectionCell: CommandCell = {
        cellId: rejectionCellId,
        commandType: command.commandType,
        targetEquipment: command.targetEquipment,
        parameters: command.parameters,
        issuedBy: operatorIdentity,
        authorizedBy: capabilityToken.cellBytes,
        timestamp: now,
        executionStatus: 'rejected',
        rejectionReason: interlockResult.error.map(v => v.reason).join('; '),
        previousCommandCell: state.lastCommandByEquipment.get(command.targetEquipment),
        linearity: 'LINEAR',
        consumed: false,
      };
      state.commandCells.set(rejectionCellId, rejectionCell);
      emit({
        step: 'interlock-evaluation',
        result: 'fail',
        detail: interlockResult.error.map(v => v.reason).join('; '),
      });
      return {
        ok: false,
        error: {
          code: 'INTERLOCK_VIOLATION',
          message: `Interlock violation: ${interlockResult.error.map(v => v.reason).join('; ')}`,
          violations: interlockResult.error,
        },
      };
    }
    emit({
      step: 'interlock-evaluation',
      result: 'pass',
      detail: `All interlocks passed for ${command.targetEquipment}`,
    });

    // Step 5: Execute command — consume capability token (LINEAR), create command cell in DAG
    capabilityToken.consumed = true;
    state.consumedTokens.add(capabilityToken.tokenId);

    const commandCellId = generateCellId();
    const commandCell: CommandCell = {
      cellId: commandCellId,
      commandType: command.commandType,
      targetEquipment: command.targetEquipment,
      parameters: command.parameters,
      issuedBy: operatorIdentity,
      authorizedBy: capabilityToken.cellBytes,
      timestamp: now,
      executionStatus: 'executed',
      previousCommandCell: state.lastCommandByEquipment.get(command.targetEquipment),
      linearity: 'LINEAR',
      consumed: true,
    };
    state.commandCells.set(commandCellId, commandCell);
    state.lastCommandByEquipment.set(command.targetEquipment, commandCellId);

    emit({
      step: 'execution',
      result: 'pass',
      detail: `Command ${command.commandType} executed on ${command.targetEquipment}`,
    });

    // Step 7: Anchor emission (Phase 29.5)
    let anchorTxId: string | undefined;
    if (deps.anchorEmitter) {
      try {
        const cellPayload = new TextEncoder().encode(JSON.stringify(commandCell));
        const anchorResult = await deps.anchorEmitter.emit(cellPayload, {
          linearity: 'LINEAR',
          anchorPolicy: 'always',
          idempotencyKey: commandCellId,
        });
        anchorTxId = anchorResult.txid;
      } catch {
        // Anchor failure is non-fatal
      }
    }

    // Step 8: Receipt — exact field ordering preserved.
    const receipt: CommandReceipt = {
      commandCellId,
      executionStatus: 'executed',
      timestamp: now,
      operatorId: operatorIdentity,
      targetEquipment: command.targetEquipment,
      commandType: command.commandType,
      interlocksPassed: state.interlocksByEquipment.get(command.targetEquipment)?.length ?? 0,
      auditTrail: auditor.trail(),
      anchorTxId,
    };
    return { ok: true, value: receipt };
  } finally {
    auditor.dispose();
  }
}

```
