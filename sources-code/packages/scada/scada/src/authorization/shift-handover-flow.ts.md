---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/shift-handover-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.473928+00:00
---

# packages/scada/scada/src/authorization/shift-handover-flow.ts

```ts
/**
 * Shift-handover flow — transfers active capability tokens from an
 * outgoing operator to an incoming one under supervisor authorization.
 *
 * Behaviour preserved verbatim from the legacy `shiftHandover`:
 *   - Supervisor must be a recognized supervisor role
 *     (shift-supervisor, plant-manager, safety-officer).
 *   - Both operators must be registered.
 *   - Active outgoing tokens are LINEAR-consumed and re-granted to the
 *     incoming operator, preserving role + shift window.
 *   - Receipt includes the count of capabilities transferred and any
 *     unacknowledged alarms.
 */

import type {
  AlarmCell,
  HandoverError,
  Result,
  SCADACapabilityToken,
  ShiftHandoverReceipt,
} from '../types';

import { generateCellId, microsecondTimestamp } from './cell-id';
import type { EngineState } from './engine-state';
import { isSupervisorRole } from './role-mapper';

export interface GrantCapabilityFn {
  (
    operatorId: string,
    role: SCADACapabilityToken['role'],
    shiftStart: string,
    shiftEnd: string,
    grantedBy: string,
  ): SCADACapabilityToken;
}

export function shiftHandover(
  outgoingOperator: string,
  incomingOperator: string,
  supervisorId: string,
  state: EngineState,
  grant: GrantCapabilityFn,
): Result<ShiftHandoverReceipt, HandoverError> {
  // Verify supervisor exists and has authorization
  const supervisor = state.operators.get(supervisorId);
  if (!supervisor || !isSupervisorRole(supervisor.role)) {
    return {
      ok: false,
      error: {
        code: 'NO_SUPERVISOR_AUTH',
        message: `${supervisorId} is not authorized to supervise shift handover`,
      },
    };
  }

  // Verify both operators exist
  const outgoing = state.operators.get(outgoingOperator);
  const incoming = state.operators.get(incomingOperator);
  if (!outgoing || !incoming) {
    return {
      ok: false,
      error: {
        code: 'INVALID_OPERATOR',
        message: `Operator(s) not registered`,
      },
    };
  }

  // Transfer capabilities: outgoing → incoming
  const outgoingCaps = state.capabilities.get(outgoingOperator) ?? [];
  const activeCaps = outgoingCaps.filter(
    t => !t.consumed && !state.consumedTokens.has(t.tokenId),
  );
  let transferred = 0;

  for (const cap of activeCaps) {
    cap.consumed = true;
    state.consumedTokens.add(cap.tokenId);
    grant(
      incomingOperator,
      cap.role,
      cap.shiftStart,
      cap.shiftEnd,
      supervisorId,
    );
    transferred++;
  }

  const unackAlarms = unacknowledgedAlarms(state).map(a => a.alarmId);

  return {
    ok: true,
    value: {
      receiptCellId: generateCellId(),
      outgoingOperator,
      incomingOperator,
      supervisor: supervisorId,
      capabilitiesTransferred: transferred,
      unacknowledgedAlarms: unackAlarms,
      timestamp: microsecondTimestamp(),
    },
  };
}

function unacknowledgedAlarms(state: EngineState): AlarmCell[] {
  return [...state.alarms.values()].filter(a => !a.consumed);
}

```
