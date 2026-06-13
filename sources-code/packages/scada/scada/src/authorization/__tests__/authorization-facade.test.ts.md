---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/__tests__/authorization-facade.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.476170+00:00
---

# packages/scada/scada/src/authorization/__tests__/authorization-facade.test.ts

```ts
/**
 * Integration tests — `CommandAuthorizationEngine` facade.
 *
 * Replays the legacy issueCommand / acknowledgeAlarm / shiftHandover
 * flows through the new modular implementation and pins the
 * structurally-significant fields (audit trail step ordering, receipt
 * shape, error codes).
 */

import { describe, expect, test } from 'bun:test';

import { CommandAuthorizationEngine } from '../authorization-facade';
import type { AlarmCell } from '../../types';

function makeEngine() {
  const engine = new CommandAuthorizationEngine();
  engine.registerOperator('op-1', 'senior-operator');
  engine.registerOperator('op-sup', 'shift-supervisor');
  engine.registerOperator('op-junior', 'junior-operator');
  return engine;
}

function farFutureShift() {
  return {
    start: new Date(Date.now() - 60_000).toISOString(),
    end: new Date(Date.now() + 1_000 * 60 * 60 * 24).toISOString(),
  };
}

describe('issueCommand', () => {
  test('happy path emits 4-step audit trail with legacy field ordering', async () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');

    const result = await engine.issueCommand(
      {
        commandType: 'valve.open',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'op-1',
      },
      'op-1',
      token,
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.executionStatus).toBe('executed');
    expect(result.value.commandType).toBe('valve.open');
    expect(result.value.targetEquipment).toBe('eq-1');
    expect(result.value.auditTrail.map(e => e.step)).toEqual([
      'identity-verification',
      'capability-verification',
      'interlock-evaluation',
      'execution',
    ]);
    for (const entry of result.value.auditTrail) {
      // Field ordering preserved — legacy struct literal: step, result, detail, timestamp.
      expect(Object.keys(entry)).toEqual(['step', 'result', 'detail', 'timestamp']);
      expect(entry.result).toBe('pass');
    }
  });

  test('rejects on no identity', async () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    const result = await engine.issueCommand(
      {
        commandType: 'valve.open',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'ghost',
      },
      'ghost',
      token,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('NO_IDENTITY');
  });

  test('rejects insufficient role', async () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability(
      'op-junior',
      'junior-operator',
      shift.start,
      shift.end,
      'op-sup',
    );
    const result = await engine.issueCommand(
      {
        commandType: 'emergency.shutdown',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'op-junior',
      },
      'op-junior',
      token,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('INSUFFICIENT_ROLE');
  });

  test('LINEAR — token cannot be reused', async () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');

    const first = await engine.issueCommand(
      {
        commandType: 'valve.open',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'op-1',
      },
      'op-1',
      token,
    );
    expect(first.ok).toBe(true);

    const second = await engine.issueCommand(
      {
        commandType: 'valve.close',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'op-1',
      },
      'op-1',
      token,
    );
    expect(second.ok).toBe(false);
    if (!second.ok) expect(second.error.code).toBe('CONSUMED_CAPABILITY');
  });

  test('rejects expired token', async () => {
    const engine = makeEngine();
    const token = engine.grantShiftCapability(
      'op-1',
      'senior-operator',
      '2020-01-01T00:00:00.000Z',
      '2020-01-02T00:00:00.000Z',
      'op-sup',
    );
    const result = await engine.issueCommand(
      {
        commandType: 'valve.open',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'op-1',
      },
      'op-1',
      token,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('EXPIRED_CAPABILITY');
  });

  test('rejection cell + interlock violation', async () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');

    engine.installInterlock('eq-1', {
      policyId: 'pol-1',
      name: 'always-fail',
      description: 'shim never approves',
      targetAction: 'valve.open',
      severity: 'HIGH',
      compiledBytes: new Uint8Array(),
      scriptWords: '',
    });
    engine.setInterlockEvaluator(() => ({
      ok: false,
      error: {
        policyId: 'pol-1',
        policyName: 'always-fail',
        reason: 'unit-test rejection',
      },
    }));

    const result = await engine.issueCommand(
      {
        commandType: 'valve.open',
        targetEquipment: 'eq-1',
        parameters: {},
        issuedBy: 'op-1',
      },
      'op-1',
      token,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe('INTERLOCK_VIOLATION');
      expect(result.error.violations?.[0]?.reason).toBe('unit-test rejection');
    }
  });
});

describe('acknowledgeAlarm', () => {
  function alarm(severity: AlarmCell['severity'] = 'HIGH'): AlarmCell {
    return {
      cellId: 'cell-a',
      alarmId: 'a-1',
      severity,
      source: 'sensor-1',
      condition: 'high',
      value: 9,
      timestamp: '2030-01-01T00:00:00.000Z',
      linearity: 'LINEAR',
      consumed: false,
    };
  }

  test('senior operator acks non-CRITICAL', () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    engine.registerAlarm(alarm('HIGH'));
    const result = engine.acknowledgeAlarm('a-1', 'op-1', token);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.consumed).toBe(true);
  });

  test('CRITICAL requires capability 5+', () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    engine.registerAlarm(alarm('CRITICAL'));
    const result = engine.acknowledgeAlarm('a-1', 'op-1', token);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('INSUFFICIENT_ROLE');
  });

  test('cannot ack twice (LINEAR)', () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    const token = engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    engine.registerAlarm(alarm('HIGH'));
    expect(engine.acknowledgeAlarm('a-1', 'op-1', token).ok).toBe(true);
    const second = engine.acknowledgeAlarm('a-1', 'op-1', token);
    expect(second.ok).toBe(false);
    if (!second.ok) expect(second.error.code).toBe('CONSUMED_CAPABILITY');
  });
});

describe('shiftHandover', () => {
  test('non-supervisor blocked', () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    const result = engine.shiftHandover('op-1', 'op-junior', 'op-1');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe('NO_SUPERVISOR_AUTH');
  });

  test('transfers active capabilities; LINEAR-consumes outgoing', () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    const result = engine.shiftHandover('op-1', 'op-junior', 'op-sup');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.capabilitiesTransferred).toBe(2);
    expect(engine.getActiveCapabilities('op-1')).toHaveLength(0);
    expect(engine.getActiveCapabilities('op-junior')).toHaveLength(2);
  });

  test('reports unack alarms', () => {
    const engine = makeEngine();
    const shift = farFutureShift();
    engine.registerAlarm({
      cellId: 'cell-x',
      alarmId: 'a-pending',
      severity: 'MEDIUM',
      source: 's',
      condition: 'c',
      value: 1,
      timestamp: '2030-01-01T00:00:00.000Z',
      linearity: 'LINEAR',
      consumed: false,
    });
    engine.grantShiftCapability('op-1', 'senior-operator', shift.start, shift.end, 'op-sup');
    const result = engine.shiftHandover('op-1', 'op-junior', 'op-sup');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.unacknowledgedAlarms).toEqual(['a-pending']);
  });
});

```
