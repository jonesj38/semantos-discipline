---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/state-machines/quote-fsm.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.491600+00:00
---

# cartridges/oddjobz/brain/tests/state-machines/quote-fsm.test.ts

```ts
/**
 * D-O4 — Quote FSM tests.
 *
 * The Quote FSM is gateless at the cell layer (the `cap.oddjobz.quote`
 * spend lives on the Job side per §O4) so the K2 acceptance test
 * surfaces here as the bad-principal regression. K1 (consumed-cell
 * rejected) and K4 (failure-atomic + retry) remain identical to the
 * Job FSM's pattern.
 */

import { describe, expect, test } from 'bun:test';

import {
  QUOTE_FSM_STATES,
  QUOTE_TRANSITIONS,
  allValidQuoteTransitions,
  findQuoteTransition,
  isQuoteFsmState,
  makeConsumedCellSet,
  quoteCellId,
  quoteTransition,
} from '../../src/state-machines/index.js';
import type { OddjobzQuote, QuoteStatus } from '../../src/cell-types/quote.js';

const STABLE_QUOTE_ID = '12121212-3434-5656-7878-9a9a9a9a9a9a';
const STABLE_JOB_ID = '11111111-2222-3333-4444-555555555555';
const STABLE_NOW = '2026-05-01T00:00:00.000Z';

function makeQuoteCell(state: (typeof QUOTE_FSM_STATES)[number]): OddjobzQuote {
  const base: OddjobzQuote = {
    quoteId: STABLE_QUOTE_ID,
    jobId: STABLE_JOB_ID,
    status: state,
    costMin: 50_00, // cents
    costMax: 200_00,
    createdAt: STABLE_NOW,
    updatedAt: STABLE_NOW,
  };
  // The cell-type validator requires acceptedAt / rejectedAt for the
  // accepted / rejected states; we don't construct cells in those
  // states from scratch here (we transition INTO them).
  return base;
}

describe('§O4 — Quote FSM table shape', () => {
  test('QUOTE_TRANSITIONS rows are present in declaration order', () => {
    const pairs = allValidQuoteTransitions();
    expect(pairs).toContainEqual({ from: 'draft', to: 'presented' });
    expect(pairs).toContainEqual({ from: 'presented', to: 'accepted' });
    expect(pairs).toContainEqual({ from: 'presented', to: 'rejected' });
    expect(pairs).toContainEqual({ from: 'presented', to: 'expired' });
  });

  test('every Quote FSM transition is gateless (capRequired === null)', () => {
    for (const t of QUOTE_TRANSITIONS) {
      expect(t.capRequired).toBeNull();
    }
  });

  test('isQuoteFsmState identifies canonical', () => {
    expect(isQuoteFsmState('draft')).toBe(true);
    expect(isQuoteFsmState('presented')).toBe(true);
    expect(isQuoteFsmState('accepted')).toBe(true);
    expect(isQuoteFsmState('rejected')).toBe(true);
    expect(isQuoteFsmState('weird-state' as QuoteStatus)).toBe(false);
  });

  test('findQuoteTransition returns undefined for non-table pairs', () => {
    expect(findQuoteTransition('draft', 'accepted')).toBeUndefined();
    expect(findQuoteTransition('accepted', 'draft')).toBeUndefined();
  });
});

describe('§O4 — Quote FSM happy-path transitions', () => {
  test('draft → presented (operator-signed, ungated)', () => {
    const consumed = makeConsumedCellSet();
    const r = quoteTransition({
      cell: makeQuoteCell('draft'),
      to: 'presented',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.cell.status).toBe('presented');
  });

  test('presented → accepted (service-signed; carries customer signature)', () => {
    const consumed = makeConsumedCellSet();
    const r = quoteTransition({
      cell: makeQuoteCell('presented'),
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('accepted');
      expect(r.value.cell.acceptedAt).toBe(STABLE_NOW);
    }
  });

  test('presented → rejected stamps rejectedAt', () => {
    const consumed = makeConsumedCellSet();
    const r = quoteTransition({
      cell: makeQuoteCell('presented'),
      to: 'rejected',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('rejected');
      expect(r.value.cell.rejectedAt).toBe(STABLE_NOW);
    }
  });
});

describe('§O4 — Quote FSM acceptance tests (K1/K2/K4)', () => {
  test('[§O4 K1] two presented → accepted on the same cell-id; second fails', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeQuoteCell('presented');
    const r1 = quoteTransition({
      cell,
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r1.ok).toBe(true);
    const r2 = quoteTransition({
      cell,
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r2.ok).toBe(false);
    if (!r2.ok) {
      expect(r2.error.kind).toBe('cell_already_consumed');
      expect(r2.error.consumedCellId).toBe(quoteCellId(STABLE_QUOTE_ID, 'presented'));
    }
  });

  test('[§O4 K2] presented → accepted signed by operator (not service) is bad_signing_principal', () => {
    const consumed = makeConsumedCellSet();
    const r = quoteTransition({
      cell: makeQuoteCell('presented'),
      to: 'accepted',
      principal: 'operator', // wrong — accepted is service-signed
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('bad_signing_principal');
  });

  test('[§O4 K4] induced failure on presented → accepted leaves cell unchanged; retry succeeds', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeQuoteCell('presented');
    const before = JSON.stringify(cell);
    const r1 = quoteTransition({
      cell,
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      sideEffect: () => {
        throw new Error('simulated SMS-send failure on customer-acceptance notification');
      },
    });
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error.kind).toBe('induced_io_failure');
    expect(JSON.stringify(cell)).toBe(before);
    expect(consumed.has(quoteCellId(STABLE_QUOTE_ID, 'presented'))).toBe(false);

    const r2 = quoteTransition({
      cell,
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r2.ok).toBe(true);
    if (r2.ok) {
      expect(r2.value.cell.status).toBe('accepted');
      expect(consumed.has(quoteCellId(STABLE_QUOTE_ID, 'presented'))).toBe(true);
    }
  });
});

describe('§O4 — Quote FSM negative paths', () => {
  test('draft → accepted (skip-presented) is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = quoteTransition({
      cell: makeQuoteCell('draft'),
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });
});

describe('§O4 — Quote FSM property test', () => {
  test('random walk over 30 attempts: status always canonical', () => {
    const consumed = makeConsumedCellSet();
    let cell: OddjobzQuote = makeQuoteCell('draft');
    let seed = 0xc0ffee01;
    const rand = () => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 0xffffffff;
    };
    for (let i = 0; i < 30; i++) {
      const to = QUOTE_FSM_STATES[Math.floor(rand() * QUOTE_FSM_STATES.length)]!;
      const spec = findQuoteTransition(
        cell.status as (typeof QUOTE_FSM_STATES)[number],
        to,
      );
      const principal = spec?.principalKinds[0] ?? 'operator';
      const r = quoteTransition({
        cell,
        to,
        principal,
        nowIso: STABLE_NOW,
        consumed,
      });
      if (r.ok) cell = r.value.cell;
      expect(QUOTE_FSM_STATES).toContain(cell.status as (typeof QUOTE_FSM_STATES)[number]);
    }
  });
});

```
