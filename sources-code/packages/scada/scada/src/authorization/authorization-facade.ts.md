---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/authorization-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.473057+00:00
---

# packages/scada/scada/src/authorization/authorization-facade.ts

```ts
/**
 * Authorization facade — `CommandAuthorizationEngine` orchestrator.
 *
 * Delegates the actual work to the per-concern modules:
 *
 *   - capability-evaluator   — rule check (role × capability number)
 *   - role-mapper            — role → caps; supervisor predicate
 *   - signer-verifier        — wraps `signerPort` (off-by-default)
 *   - audit-logger           — DecisionEvent bus → AuditEntry[]
 *   - decision-cache         — atom-backed TTL cache (off-by-default)
 *   - interlock-evaluator    — Phase 29.5 kernel + legacy shim path
 *   - issue-command-flow     — multi-step command pipeline
 *   - shift-handover-flow    — capability transfer
 *   - alarm-flow             — LINEAR alarm acknowledgement
 *
 * Behaviour is byte-identical to the pre-split monolith
 * (`packages/scada/src/authorization.ts`); this module replaces the
 * implementation, leaving the legacy file as a deprecation re-export
 * shim. Field ordering on every emitted struct (CommandReceipt,
 * CommandCell, AuditEntry, ShiftHandoverReceipt) matches the original.
 */

import type {
  CommandCell,
  CommandReceipt,
  CommandError,
  TelemetryCell,
  AlarmCell,
  InterlockViolation,
  OperatorRole,
  SCADACapabilityToken,
  ShiftHandoverReceipt,
  HandoverError,
  InterlockPolicy,
  Result,
  SCADACommandType,
} from '../types';
import { ROLE_CAPABILITIES } from '../types';
import type { AnchorEmitter, PolicyRuntime } from '@semantos/policy-runtime';

import { acknowledgeAlarm as alarmAcknowledge } from './alarm-flow';
import { generateCellId } from './cell-id';
import { makeEngineState, type EngineState } from './engine-state';
import {
  evaluateInterlocks as evaluateInterlocksFlow,
  type InterlockShimEvaluator,
} from './interlock-evaluator';
import {
  issueCommand as issueCommandFlow,
  type IssueCommandInput,
} from './issue-command-flow';
import { shiftHandover as shiftHandoverFlow } from './shift-handover-flow';

export interface SCADAAuthorizationOptions {
  /** PolicyRuntime for kernel-level interlock enforcement (Phase 29.5). */
  runtime?: PolicyRuntime;
  /** AnchorEmitter for command anchoring (Phase 29.5). */
  anchorEmitter?: AnchorEmitter;
}

export class CommandAuthorizationEngine {
  private readonly state: EngineState = makeEngineState();
  private interlockEvaluator?: InterlockShimEvaluator;
  private readonly policyRuntime?: PolicyRuntime;
  private readonly anchorEmitter?: AnchorEmitter;

  constructor(options?: SCADAAuthorizationOptions) {
    this.policyRuntime = options?.runtime;
    this.anchorEmitter = options?.anchorEmitter;
  }

  // ── Configuration ──────────────────────────────────────────

  registerOperator(operatorId: string, role: OperatorRole): void {
    this.state.operators.set(operatorId, { role, active: true });
  }

  installInterlock(equipmentId: string, policy: InterlockPolicy): void {
    const existing = this.state.interlocksByEquipment.get(equipmentId) ?? [];
    existing.push(policy);
    this.state.interlocksByEquipment.set(equipmentId, existing);
  }

  updateTelemetry(reading: TelemetryCell): void {
    this.state.telemetryState.set(reading.sensorId, reading);
  }

  setInterlockEvaluator(evaluator: InterlockShimEvaluator): void {
    this.interlockEvaluator = evaluator;
  }

  registerAlarm(alarm: AlarmCell): void {
    this.state.alarms.set(alarm.alarmId, alarm);
  }

  getUnacknowledgedAlarms(): AlarmCell[] {
    return [...this.state.alarms.values()].filter(a => !a.consumed);
  }

  getAlarm(alarmId: string): AlarmCell | undefined {
    return this.state.alarms.get(alarmId);
  }

  getCommandCell(cellId: string): CommandCell | undefined {
    return this.state.commandCells.get(cellId);
  }

  // ── Capability Management ──────────────────────────────────

  grantShiftCapability(
    operatorId: string,
    role: OperatorRole,
    shiftStart: string,
    shiftEnd: string,
    grantedBy: string,
  ): SCADACapabilityToken {
    const capabilities = ROLE_CAPABILITIES[role];
    const tokenId = generateCellId();
    const token: SCADACapabilityToken = {
      tokenId,
      operatorId,
      role,
      capabilities: [...capabilities],
      shiftStart,
      shiftEnd,
      grantedBy,
      consumed: false,
      cellBytes: new Uint8Array(32), // placeholder cell bytes
    };

    const existing = this.state.capabilities.get(operatorId) ?? [];
    existing.push(token);
    this.state.capabilities.set(operatorId, existing);

    return token;
  }

  getActiveCapabilities(operatorId: string): SCADACapabilityToken[] {
    const tokens = this.state.capabilities.get(operatorId) ?? [];
    const now = new Date().toISOString();
    return tokens.filter(
      t =>
        !t.consumed &&
        !this.state.consumedTokens.has(t.tokenId) &&
        t.shiftEnd > now,
    );
  }

  // ── Command Execution ──────────────────────────────────────

  async issueCommand(
    command: IssueCommandInput,
    operatorIdentity: string,
    capabilityToken: SCADACapabilityToken,
  ): Promise<Result<CommandReceipt, CommandError>> {
    return issueCommandFlow(command, operatorIdentity, capabilityToken, {
      state: this.state,
      policyRuntime: this.policyRuntime,
      anchorEmitter: this.anchorEmitter,
      shimEvaluator: this.interlockEvaluator,
    });
  }

  async evaluateInterlocks(
    commandType: SCADACommandType,
    targetEquipment: string,
  ): Promise<Result<void, InterlockViolation[]>> {
    return evaluateInterlocksFlow(commandType, targetEquipment, {
      interlocksByEquipment: this.state.interlocksByEquipment,
      telemetryState: this.state.telemetryState,
      policyRuntime: this.policyRuntime,
      shimEvaluator: this.interlockEvaluator,
    });
  }

  acknowledgeAlarm(
    alarmId: string,
    operatorId: string,
    capabilityToken: SCADACapabilityToken,
  ): Result<AlarmCell, CommandError> {
    return alarmAcknowledge(alarmId, operatorId, capabilityToken, this.state);
  }

  shiftHandover(
    outgoingOperator: string,
    incomingOperator: string,
    supervisorId: string,
  ): Result<ShiftHandoverReceipt, HandoverError> {
    return shiftHandoverFlow(
      outgoingOperator,
      incomingOperator,
      supervisorId,
      this.state,
      (operatorId, role, shiftStart, shiftEnd, grantedBy) =>
        this.grantShiftCapability(operatorId, role, shiftStart, shiftEnd, grantedBy),
    );
  }
}

```
