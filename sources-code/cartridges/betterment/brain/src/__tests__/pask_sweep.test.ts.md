---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/__tests__/pask_sweep.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.569869+00:00
---

# cartridges/betterment/brain/src/__tests__/pask_sweep.test.ts

```ts
/**
 * Pask sweep — day-over-day trend tests.
 *
 * Verifies the trajectory extension: with a window split, each primed theme
 * carries a `trend` whose direction reflects whether the point is escalating,
 * settling, steady, or new across the prior/current windows.  Without a split,
 * the function behaves exactly as before (no `trend`).
 */

import { describe, expect, test } from 'bun:test';
import {
  sweepPracticeHistory,
  type PaskSweepInput,
  type ReleaseCellInput,
  type SealCellInput,
} from '../pask_sweep.js';

const SPLIT = 1_000_000;
const PRIOR = SPLIT - 100; // before the split → prior window
const CURRENT = SPLIT + 100; // at/after the split → current window

function release(cellId: string, mintedAt: number, theme: string): ReleaseCellInput {
  return { cellId, mintedAt, payload: { rawText: `release about ${theme}`, themes: theme } };
}

// Four releases drive four distinct trend directions:
//   work   — 1 prior + 3 current, all unsealed → escalating (more charge, no closure)
//   fear   — 1 prior unsealed + 1 current sealed → settling (closure rising)
//   health — 1 prior + 1 current, unsealed, equal → steady
//   grief  — current only → new
const releases: ReleaseCellInput[] = [
  release('w1', PRIOR, 'work'),
  release('w2', CURRENT, 'work'),
  release('w3', CURRENT, 'work'),
  release('w4', CURRENT, 'work'),
  release('f1', PRIOR, 'fear'),
  release('f2', CURRENT, 'fear'),
  release('h1', PRIOR, 'health'),
  release('h2', CURRENT, 'health'),
  release('g1', CURRENT, 'grief'),
];

// Seal the current 'fear' release (f2) so fear's closure rises in the current window.
const seals: SealCellInput[] = [
  { cellId: 's1', mintedAt: CURRENT, payload: { sealedReleaseIds: 'f2' } },
];

function baseInput(extra?: Partial<PaskSweepInput>): PaskSweepInput {
  return {
    recentReleaseCells: releases,
    recentInsightCells: [],
    recentPatternCells: [],
    recentSealCells: seals,
    recentSessionCells: [],
    ...extra,
  };
}

function themeByConcept(result: ReturnType<typeof sweepPracticeHistory>, concept: string) {
  const t = result.primedThemes.find((p) => p.concept === concept);
  expect(t, `expected a primed theme for "${concept}"`).toBeDefined();
  return t!;
}

describe('sweepPracticeHistory — backward compatible (no split)', () => {
  test('omitting windowSplitMs emits no trend', () => {
    const result = sweepPracticeHistory(baseInput());
    expect(result.primedThemes.length).toBeGreaterThan(0);
    for (const theme of result.primedThemes) {
      expect(theme.trend).toBeUndefined();
    }
  });

  test('orders by stability ascending (least resolved first)', () => {
    const result = sweepPracticeHistory(baseInput());
    const stabilities = result.primedThemes.map((t) => t.stability);
    const sorted = [...stabilities].sort((a, b) => a - b);
    expect(stabilities).toEqual(sorted);
  });
});

describe('sweepPracticeHistory — day-over-day trend', () => {
  test('classifies each direction correctly', () => {
    const result = sweepPracticeHistory(baseInput({ windowSplitMs: SPLIT }));

    expect(themeByConcept(result, 'work').trend?.direction).toBe('escalating');
    expect(themeByConcept(result, 'fear').trend?.direction).toBe('settling');
    expect(themeByConcept(result, 'health').trend?.direction).toBe('steady');
    expect(themeByConcept(result, 'grief').trend?.direction).toBe('new');
  });

  test('escalating theme has positive weightDelta and non-positive stabilityDelta', () => {
    const result = sweepPracticeHistory(baseInput({ windowSplitMs: SPLIT }));
    const work = themeByConcept(result, 'work').trend!;
    expect(work.weightDelta).toBeGreaterThan(0);
    expect(work.stabilityDelta).toBeLessThanOrEqual(0);
  });

  test('settling theme has positive stabilityDelta', () => {
    const result = sweepPracticeHistory(baseInput({ windowSplitMs: SPLIT }));
    const fear = themeByConcept(result, 'fear').trend!;
    expect(fear.stabilityDelta).toBeGreaterThan(0);
  });

  test('new theme has zero prior charge', () => {
    const result = sweepPracticeHistory(baseInput({ windowSplitMs: SPLIT }));
    const grief = themeByConcept(result, 'grief').trend!;
    expect(grief.priorWeight).toBe(0);
    expect(grief.priorStability).toBe(0);
  });
});

describe('sweepPracticeHistory — empty history', () => {
  test('reports a clear field', () => {
    const result = sweepPracticeHistory({
      recentReleaseCells: [],
      recentInsightCells: [],
      recentPatternCells: [],
      recentSealCells: [],
      recentSessionCells: [],
      windowSplitMs: SPLIT,
    });
    expect(result.fieldIsClear).toBe(true);
    expect(result.primedThemes).toHaveLength(0);
  });
});

```
