---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/state-machines/visit-fsm.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.491245+00:00
---

# cartridges/oddjobz/brain/tests/state-machines/visit-fsm.test.ts

```ts
/**
 * D-O4 — Visit FSM tests.
 *
 * Visit transitions are gateless at the cell layer (the
 * `cap.oddjobz.dispatch` spend lives on the Job FSM side per §O4),
 * so K2 surfaces as the bad-principal regression. K1 + K4 mirror the
 * Job FSM's pattern.
 */

import { describe, expect, test } from 'bun:test';

import {
  VISIT_FSM_STATES,
  VISIT_TRANSITIONS,
  allValidVisitTransitions,
  findVisitTransition,
  isVisitFsmState,
  makeConsumedCellSet,
  visitCellId,
  visitTransition,
} from '../../src/state-machines/index.js';
import type { OddjobzVisit, VisitStatus } from '../../src/cell-types/visit.js';

const STABLE_VISIT_ID = '21212121-4343-6565-8787-a9a9a9a9a9a9';
const STABLE_JOB_ID = '11111111-2222-3333-4444-555555555555';
const STABLE_NOW = '2026-05-01T00:00:00.000Z';

function makeVisitCell(state: (typeof VISIT_FSM_STATES)[number]): OddjobzVisit {
  return {
    visitId: STABLE_VISIT_ID,
    jobId: STABLE_JOB_ID,
    visitType: 'scheduled_work',
    status: state,
    createdAt: STABLE_NOW,
    updatedAt: STABLE_NOW,
  };
}

describe('§O4 — Visit FSM table shape', () => {
  test('VISIT_TRANSITIONS contains the §O4-inferred shape', () => {
    const pairs = allValidVisitTransitions();
    expect(pairs).toContainEqual({ from: 'scheduled', to: 'in_progress' });
    expect(pairs).toContainEqual({ from: 'in_progress', to: 'completed' });
    expect(pairs).toContainEqual({ from: 'scheduled', to: 'cancelled' });
    expect(pairs).toContainEqual({ from: 'in_progress', to: 'cancelled' });
  });

  test('every Visit transition is gateless at the cell layer', () => {
    for (const t of VISIT_TRANSITIONS) {
      expect(t.capRequired).toBeNull();
    }
  });

  test('isVisitFsmState identifies canonical', () => {
    expect(isVisitFsmState('scheduled')).toBe(true);
    expect(isVisitFsmState('in_progress')).toBe(true);
    expect(isVisitFsmState('completed')).toBe(true);
    expect(isVisitFsmState('cancelled')).toBe(true);
    expect(isVisitFsmState('unknown' as VisitStatus)).toBe(false);
  });

  test('findVisitTransition rejects non-table pairs', () => {
    expect(findVisitTransition('completed', 'scheduled')).toBeUndefined();
    expect(findVisitTransition('scheduled', 'completed')).toBeUndefined();
  });
});

describe('§O4 — Visit FSM happy-path', () => {
  test('scheduled → in_progress (service-signed clock-tick)', () => {
    const consumed = makeConsumedCellSet();
    const r = visitTransition({
      cell: makeVisitCell('scheduled'),
      to: 'in_progress',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('in_progress');
      expect(r.value.cell.actualStart).toBe(STABLE_NOW);
    }
  });

  test('in_progress → completed stamps actualEnd + outcome', () => {
    const consumed = makeConsumedCellSet();
    const r = visitTransition({
      cell: makeVisitCell('in_progress'),
      to: 'completed',
      principal: 'operator',
      nowIso: STABLE_NOW,
      outcome: 'completed',
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('completed');
      expect(r.value.cell.outcome).toBe('completed');
      expect(r.value.cell.actualEnd).toBe(STABLE_NOW);
    }
  });

  test('scheduled → cancelled stamps outcome=cancelled', () => {
    const consumed = makeConsumedCellSet();
    const r = visitTransition({
      cell: makeVisitCell('scheduled'),
      to: 'cancelled',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('cancelled');
      expect(r.value.cell.outcome).toBe('cancelled');
    }
  });
});

describe('§O4 — Visit FSM acceptance tests (K1/K2/K4)', () => {
  test('[§O4 K1] two in_progress → completed on the same cell; second fails', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeVisitCell('in_progress');
    const r1 = visitTransition({
      cell,
      to: 'completed',
      principal: 'operator',
      nowIso: STABLE_NOW,
      outcome: 'completed',
      consumed,
    });
    expect(r1.ok).toBe(true);
    const r2 = visitTransition({
      cell,
      to: 'completed',
      principal: 'operator',
      nowIso: STABLE_NOW,
      outcome: 'completed',
      consumed,
    });
    expect(r2.ok).toBe(false);
    if (!r2.ok) {
      expect(r2.error.kind).toBe('cell_already_consumed');
      expect(r2.error.consumedCellId).toBe(visitCellId(STABLE_VISIT_ID, 'in_progress'));
    }
  });

  test('[§O4 K2] scheduled → in_progress signed by operator is bad_signing_principal', () => {
    const consumed = makeConsumedCellSet();
    const r = visitTransition({
      cell: makeVisitCell('scheduled'),
      to: 'in_progress',
      principal: 'operator', // wrong — should be service
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('bad_signing_principal');
  });

  test('[§O4 K4] induced failure on scheduled → in_progress leaves cell unchanged', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeVisitCell('scheduled');
    const before = JSON.stringify(cell);
    const r1 = visitTransition({
      cell,
      to: 'in_progress',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      sideEffect: () => {
        throw new Error('simulated GPS-pin upload failure');
      },
    });
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error.kind).toBe('induced_io_failure');
    expect(JSON.stringify(cell)).toBe(before);
    expect(consumed.has(visitCellId(STABLE_VISIT_ID, 'scheduled'))).toBe(false);

    const r2 = visitTransition({
      cell,
      to: 'in_progress',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r2.ok).toBe(true);
    if (r2.ok) expect(r2.value.cell.status).toBe('in_progress');
  });
});

describe('§O4 — Visit FSM negative paths', () => {
  test('scheduled → completed (skip-in_progress) is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = visitTransition({
      cell: makeVisitCell('scheduled'),
      to: 'completed',
      principal: 'operator',
      outcome: 'completed',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });

  test('completed → scheduled (terminal regression) is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = visitTransition({
      cell: { ...makeVisitCell('completed'), outcome: 'completed' },
      to: 'scheduled',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });
});

describe('§O4 — Visit FSM property test', () => {
  test('random walk: status always canonical', () => {
    const consumed = makeConsumedCellSet();
    let cell: OddjobzVisit = makeVisitCell('scheduled');
    let seed = 0xfacefeed;
    const rand = () => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 0xffffffff;
    };
    for (let i = 0; i < 30; i++) {
      const to = VISIT_FSM_STATES[Math.floor(rand() * VISIT_FSM_STATES.length)]!;
      const spec = findVisitTransition(
        cell.status as (typeof VISIT_FSM_STATES)[number],
        to,
      );
      const principal = spec?.principalKinds[0] ?? 'operator';
      const r = visitTransition({
        cell,
        to,
        principal,
        nowIso: STABLE_NOW,
        outcome: 'completed',
        consumed,
      });
      if (r.ok) cell = r.value.cell;
      expect(VISIT_FSM_STATES).toContain(cell.status as (typeof VISIT_FSM_STATES)[number]);
    }
  });
});

```
