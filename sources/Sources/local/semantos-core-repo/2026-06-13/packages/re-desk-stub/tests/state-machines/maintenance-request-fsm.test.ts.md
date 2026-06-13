---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/tests/state-machines/maintenance-request-fsm.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.538174+00:00
---

# packages/re-desk-stub/tests/state-machines/maintenance-request-fsm.test.ts

```ts
/**
 * D-O11 phase O11a — MaintenanceRequest FSM tests.
 *
 * Acceptance tests covering:
 *
 *  - K1 — input cell consumed at most once (draft → dispatched twice
 *    on the same cell rejects with `cell_already_consumed`).
 *  - K2 — `draft → dispatched` requires `cap.re-desk.dispatch`; wrong
 *    or missing cap rejects with the appropriate kind.
 *  - K4 — failure-atomicity: a wrong-cap rejection on a dispatch
 *    attempt leaves the cell unchanged so a retry with the right cap
 *    succeeds.
 *
 * The FSM table shape is asserted verbatim against the chapter-29
 * worked example (declaration order = column order).
 */

import { describe, expect, test } from 'bun:test';
import { makeConsumedCellSet } from '@semantos/oddjobz';
import {
  capDispatchReDesk,
  mintReDeskCapability,
  parseTenantHatRef,
  isTenantHatRef,
  formatTenantHatRef,
  genesisDraft,
  maintenanceRequestTransition,
  maintenanceRequestCellId,
  MAINTENANCE_REQUEST_TRANSITIONS,
  findMaintenanceRequestTransition,
  type PresentedCap,
} from '../../src/index.js';

const STABLE_REQUEST_ID = '11111111-2222-3333-4444-555555555555';
const STABLE_NOW = '2026-05-01T09:00:00.000Z';
const STABLE_ENVELOPE_ID = 'env-test-id';

const STABLE_OWNER_ID = new Uint8Array([
  0x00, 0x70, 0x6d, 0x2d, 0x6f, 0x70, 0x65, 0x72,
  0x61, 0x74, 0x6f, 0x72, 0x2d, 0x69, 0x64, 0x21,
]);
const PM_CONTEXT_TAG = 0x20;

function structuralCap(domainFlag: number): PresentedCap {
  return { kind: 'structural', domainFlag };
}

function dispatchCapBytes(): PresentedCap {
  return {
    kind: 'cell',
    cell: mintReDeskCapability(capDispatchReDesk, PM_CONTEXT_TAG, STABLE_OWNER_ID),
  };
}

function makeDraft() {
  return genesisDraft({
    requestId: STABLE_REQUEST_ID,
    customer: 'tenant-acme',
    description: 'HVAC failure on level 4',
    dispatchTo: 'oddjobtodd.info#tradie-todd',
    nowIso: STABLE_NOW,
  });
}

describe('tenant-hat-ref parser', () => {
  test('parses canonical form', () => {
    const ref = parseTenantHatRef('oddjobtodd.info#tradie-todd');
    expect(ref.tenantDomain).toBe('oddjobtodd.info');
    expect(ref.hatId).toBe('tradie-todd');
  });

  test('round-trips canonical form', () => {
    const orig = 'oddjobtodd.info#tradie-todd';
    expect(formatTenantHatRef(parseTenantHatRef(orig))).toBe(orig);
  });

  test('rejects missing delimiter', () => {
    expect(() => parseTenantHatRef('no-delimiter')).toThrow();
  });

  test('rejects multiple delimiters', () => {
    expect(() => parseTenantHatRef('foo#bar#baz')).toThrow();
  });

  test('rejects uppercase letters', () => {
    expect(() => parseTenantHatRef('OddJob.com#tradie')).toThrow();
    expect(isTenantHatRef('OddJob.com#tradie')).toBe(false);
  });
});

describe('§O11 — MaintenanceRequest FSM table shape', () => {
  test('has the seven non-cancellation transitions in canonical order', () => {
    const happyPath = MAINTENANCE_REQUEST_TRANSITIONS.filter(
      (t) => t.to !== 'cancelled',
    ).map((t) => `${t.from}→${t.to}`);
    expect(happyPath).toEqual([
      'draft→dispatched',
      'dispatched→accepted',
      'accepted→in_progress',
      'in_progress→completed',
      'completed→invoiced',
      'invoiced→closed',
    ]);
  });

  test('draft → dispatched is the only cap-gated row', () => {
    const gatedRows = MAINTENANCE_REQUEST_TRANSITIONS.filter(
      (t) => t.capRequired !== null,
    );
    expect(gatedRows).toHaveLength(1);
    expect(gatedRows[0]?.capRequired).toBe('cap.re-desk.dispatch');
    expect(gatedRows[0]?.from).toBe('draft');
    expect(gatedRows[0]?.to).toBe('dispatched');
  });

  test('cancellation paths exist from dispatched + accepted', () => {
    expect(findMaintenanceRequestTransition('dispatched', 'cancelled')).toBeDefined();
    expect(findMaintenanceRequestTransition('accepted', 'cancelled')).toBeDefined();
    expect(findMaintenanceRequestTransition('in_progress', 'cancelled')).toBeUndefined();
  });
});

describe('§O11 — MaintenanceRequest genesis (∅ → draft)', () => {
  test('builds a fresh draft cell', () => {
    const cell = makeDraft();
    expect(cell.state).toBe('draft');
    expect(cell.requestId).toBe(STABLE_REQUEST_ID);
    expect(cell.dispatchTo).toBe('oddjobtodd.info#tradie-todd');
    expect(cell.envelopeId).toBeUndefined();
  });
});

describe('§O11 — MaintenanceRequest FSM transitions', () => {
  test('[§O11 K2] draft → dispatched succeeds with cap.re-desk.dispatch (operator)', () => {
    const consumed = makeConsumedCellSet();
    const r = maintenanceRequestTransition({
      cell: { ...makeDraft(), envelopeId: STABLE_ENVELOPE_ID },
      to: 'dispatched',
      presentedCap: dispatchCapBytes(),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.state).toBe('dispatched');
      expect(r.value.cell.dispatchedAt).toBe(STABLE_NOW);
      expect(consumed.has(maintenanceRequestCellId(STABLE_REQUEST_ID, 'draft'))).toBe(true);
    }
  });

  test('[§O11 K2] draft → dispatched without cap fails with cap_required', () => {
    const consumed = makeConsumedCellSet();
    const r = maintenanceRequestTransition({
      cell: { ...makeDraft(), envelopeId: STABLE_ENVELOPE_ID },
      to: 'dispatched',
      presentedCap: null,
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('cap_required');
  });

  test('[§O11 K2] draft → dispatched with WRONG cap (oddjobz quote) is rejected', () => {
    const consumed = makeConsumedCellSet();
    // Intentionally present an oddjobz cap (different domain flag).
    const r = maintenanceRequestTransition({
      cell: { ...makeDraft(), envelopeId: STABLE_ENVELOPE_ID },
      to: 'dispatched',
      presentedCap: structuralCap(0x0001_0101 /* oddjobz cap.quote */),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('wrong_cap');
  });

  test('[§O11 K1] dispatching the same draft cell twice is rejected on the second attempt', () => {
    const consumed = makeConsumedCellSet();
    const draft = { ...makeDraft(), envelopeId: STABLE_ENVELOPE_ID };
    const first = maintenanceRequestTransition({
      cell: draft,
      to: 'dispatched',
      presentedCap: dispatchCapBytes(),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(first.ok).toBe(true);

    const second = maintenanceRequestTransition({
      cell: draft, // same cell-id (re-presenting predecessor)
      to: 'dispatched',
      presentedCap: dispatchCapBytes(),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(second.ok).toBe(false);
    if (!second.ok) expect(second.error.kind).toBe('cell_already_consumed');
  });

  test('[§O11 K4] wrong-cap failure leaves consumed-set untouched (retry-safe)', () => {
    const consumed = makeConsumedCellSet();
    const draft = { ...makeDraft(), envelopeId: STABLE_ENVELOPE_ID };
    // First attempt: wrong cap (oddjobz cap.quote flag).
    const wrong = maintenanceRequestTransition({
      cell: draft,
      to: 'dispatched',
      presentedCap: structuralCap(0x0001_0101),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(wrong.ok).toBe(false);
    expect(consumed.has(maintenanceRequestCellId(STABLE_REQUEST_ID, 'draft'))).toBe(false);

    // Retry with the right cap — succeeds.
    const right = maintenanceRequestTransition({
      cell: draft,
      to: 'dispatched',
      presentedCap: dispatchCapBytes(),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(right.ok).toBe(true);
  });

  test('dispatched → accepted is service-signed and ungated', () => {
    const consumed = makeConsumedCellSet();
    const cell = {
      ...makeDraft(),
      state: 'dispatched' as const,
      envelopeId: STABLE_ENVELOPE_ID,
      dispatchedAt: STABLE_NOW,
    };
    const r = maintenanceRequestTransition({
      cell,
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: STABLE_ENVELOPE_ID,
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.cell.acceptedAt).toBe(STABLE_NOW);
  });

  test('completion patch with mismatched envelopeId is rejected (cross-cell binding)', () => {
    const consumed = makeConsumedCellSet();
    const cell = {
      ...makeDraft(),
      state: 'in_progress' as const,
      envelopeId: STABLE_ENVELOPE_ID,
      dispatchedAt: STABLE_NOW,
      acceptedAt: STABLE_NOW,
    };
    const r = maintenanceRequestTransition({
      cell,
      to: 'completed',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: 'env-DIFFERENT-id',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('wrong_cap');
  });

  test('full happy-path drives draft → closed', () => {
    const consumed = makeConsumedCellSet();
    const cell0 = { ...makeDraft(), envelopeId: STABLE_ENVELOPE_ID };

    const r1 = maintenanceRequestTransition({
      cell: cell0,
      to: 'dispatched',
      presentedCap: dispatchCapBytes(),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    if (!r1.ok) throw new Error('r1 failed: ' + r1.error.message);

    const r2 = maintenanceRequestTransition({
      cell: r1.value.cell,
      to: 'accepted',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: STABLE_ENVELOPE_ID,
    });
    if (!r2.ok) throw new Error('r2 failed: ' + r2.error.message);

    const r3 = maintenanceRequestTransition({
      cell: r2.value.cell,
      to: 'in_progress',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: STABLE_ENVELOPE_ID,
    });
    if (!r3.ok) throw new Error('r3 failed: ' + r3.error.message);

    const r4 = maintenanceRequestTransition({
      cell: r3.value.cell,
      to: 'completed',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: STABLE_ENVELOPE_ID,
    });
    if (!r4.ok) throw new Error('r4 failed: ' + r4.error.message);

    const r5 = maintenanceRequestTransition({
      cell: r4.value.cell,
      to: 'invoiced',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: STABLE_ENVELOPE_ID,
    });
    if (!r5.ok) throw new Error('r5 failed: ' + r5.error.message);

    const r6 = maintenanceRequestTransition({
      cell: r5.value.cell,
      to: 'closed',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
      envelopeId: STABLE_ENVELOPE_ID,
    });
    if (!r6.ok) throw new Error('r6 failed: ' + r6.error.message);

    expect(r6.value.cell.state).toBe('closed');
  });
});

```
