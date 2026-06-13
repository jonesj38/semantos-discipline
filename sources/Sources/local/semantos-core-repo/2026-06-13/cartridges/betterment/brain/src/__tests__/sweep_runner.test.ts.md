---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/__tests__/sweep_runner.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.570813+00:00
---

# cartridges/betterment/brain/src/__tests__/sweep_runner.test.ts

```ts
/**
 * sweep_runner — categorisation + result-shape tests.
 *
 * Exercises the pure `runSweep` core (the subprocess `main()` only runs under
 * `import.meta.main`).  Feeds the exact stdin-cell shape the Zig reactor builds
 * — `{ typeHashHex, cellId, mintedAtMs, payload }` — and asserts that betterment
 * cells are categorised by typeHashHex, unknown types are skipped, and the
 * PaskSweepResult carries trends when a window split is supplied.
 */

import { describe, expect, test } from 'bun:test';
import { runSweep } from '../sweep_runner.js';
import {
  releaseCellType,
  insightCellType,
  sealCellType,
} from '../cell-types/index.js';

const SPLIT = 2_000_000;
const PRIOR = SPLIT - 100;
const CURRENT = SPLIT + 100;

interface StdinCell {
  typeHashHex: string;
  cellId: string;
  mintedAtMs: number;
  payload: unknown;
}

function releaseCell(cellId: string, mintedAtMs: number, theme: string): StdinCell {
  return {
    typeHashHex: releaseCellType.typeHashHex,
    cellId,
    mintedAtMs,
    payload: { rawText: `about ${theme}`, themes: theme, day: '2026-06-08' },
  };
}

describe('runSweep — categorisation', () => {
  test('categorises betterment release cells and surfaces their themes', () => {
    const cells: StdinCell[] = [
      releaseCell('r1', PRIOR, 'avoidance'),
      releaseCell('r2', CURRENT, 'avoidance'),
      releaseCell('r3', CURRENT, 'avoidance'),
    ];
    const result = runSweep(cells, SPLIT);
    const theme = result.primedThemes.find((p) => p.concept === 'avoidance');
    expect(theme).toBeDefined();
    expect(theme!.trend?.direction).toBe('escalating');
  });

  test('skips cells with unknown typeHashHex without throwing', () => {
    const cells: StdinCell[] = [
      releaseCell('r1', CURRENT, 'grief'),
      { typeHashHex: 'ff'.repeat(32), cellId: 'x1', mintedAtMs: CURRENT, payload: { foo: 'bar' } },
    ];
    const result = runSweep(cells, SPLIT);
    expect(result.primedThemes.some((p) => p.concept === 'grief')).toBe(true);
  });

  test('routes insight + seal cell types into the sweep input', () => {
    const cells: StdinCell[] = [
      releaseCell('r1', CURRENT, 'closure'),
      {
        typeHashHex: insightCellType.typeHashHex,
        cellId: 'i1',
        mintedAtMs: CURRENT,
        payload: { content: 'a quiet recognition about closure', tags: 'closure' },
      },
      {
        typeHashHex: sealCellType.typeHashHex,
        cellId: 's1',
        mintedAtMs: CURRENT,
        payload: { sealedReleaseIds: 'r1' },
      },
    ];
    // Should not throw; 'closure' appears from both release + insight, but the
    // release is sealed, so its stability is lifted by the seal cell.
    const result = runSweep(cells, SPLIT);
    expect(result.sweepTimestamp).toBeGreaterThan(0);
    expect(Array.isArray(result.primedThemes)).toBe(true);
  });

  test('treats non-positive mintedAtMs as undefined (no crash)', () => {
    const cells: StdinCell[] = [releaseCell('r1', 0, 'drift')];
    const result = runSweep(cells, SPLIT);
    expect(Array.isArray(result.primedThemes)).toBe(true);
  });
});

```
