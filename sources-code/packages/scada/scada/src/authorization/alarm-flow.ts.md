---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/alarm-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.473648+00:00
---

# packages/scada/scada/src/authorization/alarm-flow.ts

```ts
/**
 * Alarm-acknowledgement flow — consumes a LINEAR alarm cell.
 *
 * CRITICAL alarms require shift-supervisor or higher (capability 5+).
 * Behaviour byte-identical to the legacy `acknowledgeAlarm`.
 */

import type {
  AlarmCell,
  CommandError,
  Result,
  SCADACapabilityToken,
} from '../types';

import { tokenHasCapability } from './capability-evaluator';
import { microsecondTimestamp } from './cell-id';
import type { EngineState } from './engine-state';

export function acknowledgeAlarm(
  alarmId: string,
  operatorId: string,
  capabilityToken: SCADACapabilityToken,
  state: EngineState,
): Result<AlarmCell, CommandError> {
  const alarm = state.alarms.get(alarmId);
  if (!alarm) {
    return {
      ok: false,
      error: { code: 'EXECUTION_FAILED', message: `Alarm ${alarmId} not found` },
    };
  }

  if (alarm.consumed) {
    return {
      ok: false,
      error: {
        code: 'CONSUMED_CAPABILITY',
        message: `Alarm ${alarmId} already acknowledged (LINEAR — consumed)`,
      },
    };
  }

  // CRITICAL alarms require shift-supervisor or higher (capability 5+)
  if (alarm.severity === 'CRITICAL' && !tokenHasCapability(capabilityToken, 5)) {
    return {
      ok: false,
      error: {
        code: 'INSUFFICIENT_ROLE',
        message: `CRITICAL alarm requires shift-supervisor or higher (capability 5)`,
      },
    };
  }

  alarm.consumed = true;
  alarm.acknowledgedBy = operatorId;
  alarm.acknowledgedAt = microsecondTimestamp();

  return { ok: true, value: alarm };
}

```
