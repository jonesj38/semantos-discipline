---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/job-dedupe.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.149659+00:00
---

# runtime/legacy-ingest/src/__tests__/job-dedupe.test.ts

```ts
/**
 * D-RTC.6 follow-up — job-dedupe conformance tests.
 *
 * The keystone property: two proposals for the same physical job
 * (same WO#, summary wording drift from re-extract) collapse onto
 * ONE job_cell; genuinely distinct jobs do not.
 */

import { describe, test, expect } from 'bun:test';
import {
  deriveJobLookupKey,
  proposeJobCell,
  findOrProposeJob,
  computeJobCellId,
  normaliseWorkOrder,
  type JobsDedupeView,
} from '../job-dedupe';

function viewWith(seed: Record<string, string> = {}): JobsDedupeView & {
  calls: string[];
} {
  const calls: string[] = [];
  return {
    calls,
    async findJobByLookupKey(k) {
      calls.push(k);
      return seed[k] ?? null;
    },
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * normaliseWorkOrder
 * ────────────────────────────────────────────────────────────────────── */

describe('normaliseWorkOrder', () => {
  const cases: Array<[string | null | undefined, string]> = [
    ['07210', '07210'],
    ['WO 07210', '07210'],
    ['WO#07210', '07210'],
    ['Work Order 07210', '07210'],
    ['Job #07210', '07210'],
    ['#07210', '07210'],
    ['  07210  ', '07210'],
    ['2511014944', '2511014944'],
    ['RJR-2025-0142', 'rjr-2025-0142'],
    ['ref: 07210', '07210'],
    ['no. 07210', '07210'],
    [null, ''],
    [undefined, ''],
    ['', ''],
    ['   ', ''],
  ];
  for (const [raw, expected] of cases) {
    test(`"${raw}" → "${expected}"`, () => {
      expect(normaliseWorkOrder(raw)).toBe(expected);
    });
  }
});

/* ──────────────────────────────────────────────────────────────────────
 * deriveJobLookupKey
 * ────────────────────────────────────────────────────────────────────── */

describe('deriveJobLookupKey', () => {
  test('WO present → wo:<normalised>', () => {
    expect(
      deriveJobLookupKey({ workOrderNumber: 'WO 07210', siteRef: 'a'.repeat(64), issuanceDate: '2025-12-29' }),
    ).toBe('wo:07210');
  });

  test('WO drives the key regardless of site/date', () => {
    const k1 = deriveJobLookupKey({ workOrderNumber: '07210', siteRef: 'a'.repeat(64), issuanceDate: '2025-12-29' });
    const k2 = deriveJobLookupKey({ workOrderNumber: '07210', siteRef: 'b'.repeat(64), issuanceDate: '2026-01-15' });
    expect(k1).toBe(k2); // same WO ⇒ same job
  });

  test('no WO → ref:<normalised> (the thread-fold anchor)', () => {
    expect(
      deriveJobLookupKey({
        workOrderNumber: null,
        referenceNumber: 'Ref #2603066243',
        siteRef: 'c'.repeat(64),
        issuanceDate: '2026-02-01',
      }),
    ).toBe('ref:2603066243');
  });

  test('reference folds the SAME job across different issuance dates', () => {
    const k1 = deriveJobLookupKey({
      workOrderNumber: null,
      referenceNumber: '2603066243',
      siteRef: null,
      issuanceDate: '2026-03-30',
    });
    const k2 = deriveJobLookupKey({
      workOrderNumber: null,
      referenceNumber: '2603066243',
      siteRef: null,
      issuanceDate: '2026-04-06',
    });
    expect(k1).toBe(k2); // same ref ⇒ same job, no date fragmentation
  });

  test('no WO, no ref → addr:<normalised> (state/postcode-insensitive)', () => {
    const k1 = deriveJobLookupKey({
      workOrderNumber: null,
      referenceNumber: null,
      propertyAddress: '12 Foo St, Tewantin QLD 4565',
      siteRef: null,
      issuanceDate: '2026-02-01',
    });
    const k2 = deriveJobLookupKey({
      workOrderNumber: null,
      referenceNumber: null,
      propertyAddress: '12 Foo St  Tewantin',
      siteRef: null,
      issuanceDate: '2026-05-09',
    });
    expect(k1).toBe(k2);
    expect(k1.startsWith('addr:')).toBe(true);
  });

  test('no anchor at all → defensive unkeyed: sentinel (worker skips these)', () => {
    expect(
      deriveJobLookupKey({
        workOrderNumber: null,
        referenceNumber: null,
        propertyAddress: null,
        siteRef: null,
        issuanceDate: '2026-02-01',
      }),
    ).toBe('unkeyed:');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * proposeJobCell — deterministic id
 * ────────────────────────────────────────────────────────────────────── */

describe('proposeJobCell', () => {
  test('same WO → same proposedCellId (independent of summary drift)', () => {
    const a = proposeJobCell({ workOrderNumber: '06763', siteRef: 'x'.repeat(64), issuanceDate: '2025-08-06' });
    const b = proposeJobCell({ workOrderNumber: 'WO #06763', siteRef: 'y'.repeat(64), issuanceDate: '2025-09-01' });
    expect(a.proposedCellId).toBe(b.proposedCellId);
    expect(a.proposedCellId).toHaveLength(64);
    expect(a.proposedCellId).toMatch(/^[0-9a-f]+$/);
  });

  test('distinct WOs → distinct ids', () => {
    const a = proposeJobCell({ workOrderNumber: '06763', siteRef: null, issuanceDate: null });
    const b = proposeJobCell({ workOrderNumber: '07032', siteRef: null, issuanceDate: null });
    expect(a.proposedCellId).not.toBe(b.proposedCellId);
  });

  test('computeJobCellId is stable + namespaced', () => {
    expect(computeJobCellId('wo:06763')).toBe(computeJobCellId('wo:06763'));
    expect(computeJobCellId('wo:06763')).not.toBe(computeJobCellId('wo:06764'));
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * findOrProposeJob — the keystone dedupe behaviour
 * ────────────────────────────────────────────────────────────────────── */

describe('findOrProposeJob', () => {
  test('first proposal proposes; identical-WO second matches', async () => {
    const existing = 'f'.repeat(64);
    // First call: no match → propose.
    const view1 = viewWith();
    const r1 = await findOrProposeJob(
      { workOrderNumber: '06763', siteRef: 's'.repeat(64), issuanceDate: '2025-08-06' },
      view1,
    );
    expect(r1.kind).toBe('propose');

    // Second call (re-extract, different summary, same WO): the index
    // now has it → match.
    const view2 = viewWith({ 'wo:06763': existing });
    const r2 = await findOrProposeJob(
      { workOrderNumber: 'Job #06763', siteRef: 'different'.padEnd(64, '0'), issuanceDate: '2099-01-01' },
      view2,
    );
    expect(r2.kind).toBe('match');
    if (r2.kind === 'match') expect(r2.cellId).toBe(existing);
  });

  test('unkeyed proposals never match (always propose)', async () => {
    const view = viewWith({ 'unkeyed:': 'z'.repeat(64) });
    const r = await findOrProposeJob(
      { workOrderNumber: null, siteRef: null, issuanceDate: null },
      view,
    );
    expect(r.kind).toBe('propose');
    // The view should not even be consulted for unkeyed.
    expect(view.calls).toHaveLength(0);
  });

  test('no-WO jobs dedupe on referenceNumber (thread fold)', async () => {
    const existing = 'b'.repeat(64);
    const view = viewWith({ 'ref:2603066243': existing });
    const r = await findOrProposeJob(
      {
        workOrderNumber: null,
        referenceNumber: 'Ref# 2603066243',
        propertyAddress: null,
        siteRef: 'a'.repeat(64),
        issuanceDate: '2026-02-01',
      },
      view,
    );
    expect(r.kind).toBe('match');
    if (r.kind === 'match') expect(r.cellId).toBe(existing);
  });

  test('same ref across different issuance dates collapses to ONE job', async () => {
    const existing = 'b'.repeat(64);
    const view = viewWith({ 'ref:2603066243': existing });
    const r = await findOrProposeJob(
      {
        workOrderNumber: null,
        referenceNumber: '2603066243',
        propertyAddress: null,
        siteRef: null,
        issuanceDate: '2026-03-15',
      },
      view,
    );
    expect(r.kind).toBe('match'); // folds — no date fragmentation
    if (r.kind === 'match') expect(r.cellId).toBe(existing);
  });

  test('no-WO/no-ref jobs dedupe on normalised address', async () => {
    const existing = 'd'.repeat(64);
    const view = viewWith({ 'addr:12 foo st tewantin': existing });
    const r = await findOrProposeJob(
      {
        workOrderNumber: null,
        referenceNumber: null,
        propertyAddress: '12 Foo St, Tewantin QLD 4565',
        siteRef: null,
        issuanceDate: '2026-02-01',
      },
      view,
    );
    expect(r.kind).toBe('match');
    if (r.kind === 'match') expect(r.cellId).toBe(existing);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * OJT corpus scenario — the actual bug this fixes
 * ────────────────────────────────────────────────────────────────────── */

describe('OJT bundle-fanout duplicate scenario', () => {
  test('WO 06763 extracted twice with different summaries → one job', async () => {
    // Simulates the exact OJT failure: re-extract produced two
    // proposals for WO 06763 with drifted summary wording.
    const liveIndex = new Map<string, string>();
    const view: JobsDedupeView = {
      async findJobByLookupKey(k) {
        return liveIndex.get(k) ?? null;
      },
    };

    // Proposal A (first pass).
    const a = await findOrProposeJob(
      { workOrderNumber: '06763', siteRef: 'redgum'.padEnd(64, '0'), issuanceDate: '2025-07-23' },
      view,
    );
    expect(a.kind).toBe('propose');
    if (a.kind === 'propose') liveIndex.set(a.lookupKey, 'JOBCELL_06763'.padEnd(64, '0'));

    // Proposal B (re-extract — "doorstop replacements" vs "replace
    // doorstops"; same WO).
    const b = await findOrProposeJob(
      { workOrderNumber: 'WO 06763', siteRef: 'redgum'.padEnd(64, '0'), issuanceDate: '2025-07-23' },
      view,
    );
    expect(b.kind).toBe('match');
    if (b.kind === 'match') {
      expect(b.cellId).toBe('JOBCELL_06763'.padEnd(64, '0'));
    }
  });
});

```
