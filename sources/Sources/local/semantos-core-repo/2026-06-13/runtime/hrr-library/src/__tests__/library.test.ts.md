---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/hrr-library/src/__tests__/library.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.299378+00:00
---

# runtime/hrr-library/src/__tests__/library.test.ts

```ts
/**
 * WI-B2 library tests.
 *
 * Four RED→GREEN tests per the implementation plan:
 *   WI-B2-T-promote-on-stable-transition
 *   WI-B2-T-nearest-respects-domain
 *   WI-B2-T-capability-projection
 *   WI-B2-T-snapshot-roundtrip
 */

import { describe, it, expect, beforeEach } from 'bun:test';
import type { IRBinding } from '@semantos/semantos-ir';
import { encodePartialIntent } from '@semantos/hrr';
import { HrrLibrary } from '../library';
import type { IntentOutcomeEvent, StableTransitionEvent } from '../library';

// ── Test helpers ──────────────────────────────────────────────────────────────

function makeOutcomeEvent(
  cellId: string,
  domainFlag: number,
  juralCategory: string,
  bindings: IRBinding[] = [],
  overrides: Partial<IntentOutcomeEvent> = {},
): IntentOutcomeEvent {
  return {
    intentId: `intent-${cellId}`,
    domainFlag,
    lexicon: domainFlag === 7 ? 'jural' : 'control-systems',
    juralCategory,
    anfBindingsJson: JSON.stringify(bindings),
    compositeConfidence: 0.9,
    cellOutcomeHash: cellId, // use cellId as hash for simplicity in tests
    tsMs: Date.now(),
    hatId: 'hat-test',
    ...overrides,
  };
}

function makeTransitionEvent(
  cellId: string,
  overrides: Partial<StableTransitionEvent> = {},
): StableTransitionEvent {
  return {
    nodeIdx: 0,
    cellId,
    hState: 0.85,
    totalConstraintStrength: 1.0,
    interactionCount: 10,
    kernelId: 'kernel-test',
    tsMs: Date.now(),
    opPkh: 'aabbccdd11223344',
    ...overrides,
  };
}

const tradesDomain = 7;
const scadaDomain = 11;

// Representative IRProgram bindings for trades obligation
const obligationBindings: IRBinding[] = [
  { name: '$0', kind: 'comparison', op: '>=', field: 'amount' },
  { name: '$1', kind: 'comparison', op: '<=', field: 'due_date' },
  { name: '$2', kind: 'logical_and', operands: ['$0', '$1'] },
];

// Trades transfer with capability requirement
const transferBindingsWithCap: IRBinding[] = [
  { name: '$0', kind: 'capability', capabilityNumber: 5 },
  { name: '$1', kind: 'comparison', op: '>=', field: 'amount' },
];

// SCADA actuation
const scadaActuationBindings: IRBinding[] = [
  { name: '$0', kind: 'domainCheck', domainFlag: 11 },
  { name: '$1', kind: 'comparison', op: '>', field: 'pressure' },
];

// ── WI-B2-T-promote-on-stable-transition ──────────────────────────────────────

describe('WI-B2-T-promote-on-stable-transition', () => {
  let lib: HrrLibrary;
  beforeEach(() => { lib = new HrrLibrary(); });

  it('intent_outcome alone does not promote to library', () => {
    lib.onIntentOutcome(makeOutcomeEvent('cell-1', tradesDomain, 'obligation'));
    expect(lib.size).toBe(0);
    expect(lib.pendingSize).toBe(1);
  });

  it('stable_transition without preceding intent_outcome does not promote', () => {
    lib.onStableTransition(makeTransitionEvent('cell-1'));
    expect(lib.size).toBe(0);
  });

  it('intent_outcome then stable_transition promotes exactly one entry', () => {
    lib.onIntentOutcome(makeOutcomeEvent('cell-1', tradesDomain, 'obligation', obligationBindings));
    const promoted = lib.onStableTransition(makeTransitionEvent('cell-1'));
    expect(promoted).toBe(true);
    expect(lib.size).toBe(1);
    expect(lib.pendingSize).toBe(0);
  });

  it('promoted cell appears in nearest() results', () => {
    lib.onIntentOutcome(makeOutcomeEvent('cell-1', tradesDomain, 'obligation', obligationBindings));
    lib.onStableTransition(makeTransitionEvent('cell-1'));

    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'obligation', 5, new Set());
    expect(results.length).toBe(1);
    expect(results[0]!.cellId).toBe('cell-1');
    expect(results[0]!.similarity).toBeGreaterThan(0.99);
  });

  it('second stable_transition for same cell does not double-promote', () => {
    lib.onIntentOutcome(makeOutcomeEvent('cell-1', tradesDomain, 'obligation'));
    lib.onStableTransition(makeTransitionEvent('cell-1'));
    lib.onStableTransition(makeTransitionEvent('cell-1'));
    expect(lib.size).toBe(1);
  });

  it('malformed anfBindingsJson is dropped silently', () => {
    lib.onIntentOutcome(
      makeOutcomeEvent('cell-bad', tradesDomain, 'obligation', [], { anfBindingsJson: 'not-json' }),
    );
    expect(lib.pendingSize).toBe(0);
    expect(lib.size).toBe(0);
  });
});

// ── WI-B2-T-nearest-respects-domain ──────────────────────────────────────────

describe('WI-B2-T-nearest-respects-domain', () => {
  let lib: HrrLibrary;
  beforeEach(() => {
    lib = new HrrLibrary();
    // Populate trades obligation
    lib.onIntentOutcome(makeOutcomeEvent('trades-cell-1', tradesDomain, 'obligation', obligationBindings));
    lib.onStableTransition(makeTransitionEvent('trades-cell-1'));
    // Populate SCADA actuation (different domain)
    lib.onIntentOutcome(makeOutcomeEvent('scada-cell-1', scadaDomain, 'actuation', scadaActuationBindings));
    lib.onStableTransition(makeTransitionEvent('scada-cell-1'));
  });

  it('query in trades domain never returns SCADA entries', () => {
    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'obligation', 10, new Set());
    const ids = results.map(r => r.cellId);
    expect(ids).toContain('trades-cell-1');
    expect(ids).not.toContain('scada-cell-1');
  });

  it('query in SCADA domain never returns trades entries', () => {
    const query = encodePartialIntent({ domainFlag: scadaDomain, juralCategory: 'actuation', lexicon: 'control-systems' });
    const results = lib.nearest(query, scadaDomain, 'actuation', 10, new Set());
    const ids = results.map(r => r.cellId);
    expect(ids).toContain('scada-cell-1');
    expect(ids).not.toContain('trades-cell-1');
  });

  it('results are sorted by descending similarity', () => {
    // Add a second entry with a different action — scores lower against a query that includes action
    lib.onIntentOutcome(makeOutcomeEvent(
      'trades-cell-2', tradesDomain, 'obligation', [],
      { action: 'issue_invoice' }, // different action from trades-cell-1 (which has no action set)
    ));
    lib.onStableTransition(makeTransitionEvent('trades-cell-2'));

    // trades-cell-1 was stored without an action; query includes 'report_issue' → only trades-cell-1's
    // vector lacks the action slot, so both differ slightly from the query; the one without action
    // is closer to the no-action query baseline. We just verify sorted order is stable.
    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'obligation', 10, new Set());
    expect(results.length).toBe(2);
    // Both should be >= 0 similarity; sorted descending
    expect(results[0]!.similarity).toBeGreaterThanOrEqual(results[1]!.similarity);
  });

  it('k limits the number of results returned', () => {
    lib.onIntentOutcome(makeOutcomeEvent('trades-cell-3', tradesDomain, 'obligation', obligationBindings));
    lib.onStableTransition(makeTransitionEvent('trades-cell-3'));

    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'obligation', 1, new Set());
    expect(results.length).toBe(1);
  });
});

// ── WI-B2-T-capability-projection ────────────────────────────────────────────

describe('WI-B2-T-capability-projection', () => {
  let lib: HrrLibrary;
  beforeEach(() => {
    lib = new HrrLibrary();
    // cap-5 required entry
    lib.onIntentOutcome(makeOutcomeEvent('cap5-cell', tradesDomain, 'transfer', transferBindingsWithCap));
    lib.onStableTransition(makeTransitionEvent('cap5-cell'));
    // no-cap required entry
    lib.onIntentOutcome(makeOutcomeEvent('nocap-cell', tradesDomain, 'transfer', obligationBindings));
    lib.onStableTransition(makeTransitionEvent('nocap-cell'));
  });

  it('query without cap-5 excludes cap-5-required entries', () => {
    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'transfer', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'transfer', 10, new Set<number>());
    const ids = results.map(r => r.cellId);
    expect(ids).not.toContain('cap5-cell');
    expect(ids).toContain('nocap-cell');
  });

  it('query with cap-5 includes cap-5-required entries', () => {
    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'transfer', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'transfer', 10, new Set([5]));
    const ids = results.map(r => r.cellId);
    expect(ids).toContain('cap5-cell');
    expect(ids).toContain('nocap-cell');
  });

  it('entry with no capability requirements is always visible', () => {
    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const results = lib.nearest(query, tradesDomain, 'transfer', 10, new Set<number>());
    expect(results.map(r => r.cellId)).toContain('nocap-cell');
  });

  it('entry requiring multiple caps needs all caps present', () => {
    const multiCapBindings: IRBinding[] = [
      { name: '$0', kind: 'capability', capabilityNumber: 3 },
      { name: '$1', kind: 'capability', capabilityNumber: 7 },
    ];
    lib.onIntentOutcome(makeOutcomeEvent('multi-cap-cell', tradesDomain, 'transfer', multiCapBindings));
    lib.onStableTransition(makeTransitionEvent('multi-cap-cell'));

    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'transfer', lexicon: 'jural' });
    // Only cap 3 — entry should be excluded
    expect(lib.nearest(query, tradesDomain, 'transfer', 10, new Set([3])).map(r => r.cellId))
      .not.toContain('multi-cap-cell');
    // Both cap 3 and 7 — entry should be included
    expect(lib.nearest(query, tradesDomain, 'transfer', 10, new Set([3, 7])).map(r => r.cellId))
      .toContain('multi-cap-cell');
  });
});

// ── WI-B2-T-snapshot-roundtrip ────────────────────────────────────────────────

describe('WI-B2-T-snapshot-roundtrip', () => {
  it('serialise then deserialise preserves all entries', () => {
    const lib1 = new HrrLibrary();
    lib1.onIntentOutcome(makeOutcomeEvent('cell-a', tradesDomain, 'obligation', obligationBindings));
    lib1.onStableTransition(makeTransitionEvent('cell-a'));
    lib1.onIntentOutcome(makeOutcomeEvent('cell-b', scadaDomain, 'actuation', scadaActuationBindings));
    lib1.onStableTransition(makeTransitionEvent('cell-b'));

    const snapshot = lib1.serialise();

    const lib2 = new HrrLibrary();
    lib2.deserialise(snapshot);

    expect(lib2.size).toBe(2);
  });

  it('snapshot version is 1', () => {
    const lib = new HrrLibrary();
    expect(lib.serialise().version).toBe(1);
  });

  it('restored vectors produce same nearest() results as original', () => {
    const lib1 = new HrrLibrary();
    lib1.onIntentOutcome(makeOutcomeEvent('cell-a', tradesDomain, 'obligation', obligationBindings));
    lib1.onStableTransition(makeTransitionEvent('cell-a'));

    const snapshot = lib1.serialise();
    const lib2 = new HrrLibrary();
    lib2.deserialise(snapshot);

    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const r1 = lib1.nearest(query, tradesDomain, 'obligation', 1, new Set());
    const r2 = lib2.nearest(query, tradesDomain, 'obligation', 1, new Set());

    expect(r2.length).toBe(1);
    expect(r2[0]!.cellId).toBe(r1[0]!.cellId);
    expect(Math.abs(r2[0]!.similarity - r1[0]!.similarity)).toBeLessThan(1e-9);
  });

  it('deserialise merges with existing entries', () => {
    const lib1 = new HrrLibrary();
    lib1.onIntentOutcome(makeOutcomeEvent('cell-a', tradesDomain, 'obligation', obligationBindings));
    lib1.onStableTransition(makeTransitionEvent('cell-a'));
    const snapshot = lib1.serialise();

    const lib2 = new HrrLibrary();
    lib2.onIntentOutcome(makeOutcomeEvent('cell-b', scadaDomain, 'actuation', scadaActuationBindings));
    lib2.onStableTransition(makeTransitionEvent('cell-b'));
    lib2.deserialise(snapshot);

    expect(lib2.size).toBe(2);
  });

  it('snapshot round-trips through JSON stringify/parse correctly', () => {
    const lib1 = new HrrLibrary();
    lib1.onIntentOutcome(makeOutcomeEvent('cell-a', tradesDomain, 'obligation', obligationBindings));
    lib1.onStableTransition(makeTransitionEvent('cell-a'));

    const json = JSON.stringify(lib1.serialise());
    const lib2 = new HrrLibrary();
    lib2.deserialise(JSON.parse(json));

    const query = encodePartialIntent({ domainFlag: tradesDomain, juralCategory: 'obligation', lexicon: 'jural' });
    const results = lib2.nearest(query, tradesDomain, 'obligation', 1, new Set());
    expect(results[0]!.similarity).toBeGreaterThan(0.99);
  });
});

```
