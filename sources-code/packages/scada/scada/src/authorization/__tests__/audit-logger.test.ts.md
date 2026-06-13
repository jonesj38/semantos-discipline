---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/__tests__/audit-logger.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.477068+00:00
---

# packages/scada/scada/src/authorization/__tests__/audit-logger.test.ts

```ts
/**
 * Unit tests — audit-logger.
 */

import { describe, expect, test } from 'bun:test';

import {
  eventToAuditEntry,
  makeAuditor,
  makeDecisionEventBus,
  type DecisionEvent,
} from '../audit-logger';

describe('eventToAuditEntry', () => {
  test('preserves field names + ordering matching legacy AuditEntry', () => {
    const event: DecisionEvent = {
      step: 'identity-verification',
      result: 'pass',
      detail: 'Operator op-1 verified as senior-operator',
      timestamp: '2030-01-01T00:00:00.000000Z',
      operatorId: 'op-1',
    };
    const entry = eventToAuditEntry(event);
    // The entry must include exactly the four legacy fields, in the
    // same order: step, result, detail, timestamp.
    expect(Object.keys(entry)).toEqual(['step', 'result', 'detail', 'timestamp']);
    expect(entry).toEqual({
      step: 'identity-verification',
      result: 'pass',
      detail: 'Operator op-1 verified as senior-operator',
      timestamp: '2030-01-01T00:00:00.000000Z',
    });
  });
});

describe('makeAuditor', () => {
  test('collects events into an audit trail', () => {
    const bus = makeDecisionEventBus();
    const auditor = makeAuditor(bus);

    bus.emit({
      step: 'identity-verification',
      result: 'pass',
      detail: 'a',
      timestamp: 't1',
      operatorId: 'op-1',
    });
    bus.emit({
      step: 'capability-verification',
      result: 'pass',
      detail: 'b',
      timestamp: 't2',
      operatorId: 'op-1',
    });

    expect(auditor.trail()).toEqual([
      { step: 'identity-verification', result: 'pass', detail: 'a', timestamp: 't1' },
      { step: 'capability-verification', result: 'pass', detail: 'b', timestamp: 't2' },
    ]);
    auditor.dispose();
  });

  test('dispose stops collection but keeps existing trail', () => {
    const bus = makeDecisionEventBus();
    const auditor = makeAuditor(bus);

    bus.emit({
      step: 'execution',
      result: 'pass',
      detail: 'a',
      timestamp: 't1',
      operatorId: 'op-1',
    });
    auditor.dispose();
    bus.emit({
      step: 'execution',
      result: 'pass',
      detail: 'after-dispose',
      timestamp: 't2',
      operatorId: 'op-1',
    });

    expect(auditor.trail()).toHaveLength(1);
  });
});

```
