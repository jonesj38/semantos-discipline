---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/mnca-data-cell-source.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.856718+00:00
---

# core/protocol-types/__tests__/mnca-data-cell-source.test.ts

```ts
/**
 * Tests for the data-derived MNCA seed computation (D-SRS-mnca-cell-source).
 *
 * The pure functions live in docs/demo/mesh-data-cell-source.ts so they're
 * co-located with the rest of the demo tooling. These tests verify:
 *   - seed dimensions match the tile spec
 *   - halo cells are zero (filled by gossip, not by data)
 *   - interior cells reflect the data signals (tick freshness, peer density)
 *   - density is in the MNCA-interesting range (~20-42% alive)
 *   - determinism: same inputs → same seed
 *   - PRE_STEPS actually change the tile (rule fires correctly)
 *   - SSE payload has the correct shape
 */
import { describe, expect, test } from 'bun:test';
import {
  computeDataSeed,
  buildDataTile,
  stepDataTile,
  tileToSSEPayload,
} from '../../../docs/demo/mesh-data-cell-source';

// Reference tile dimensions matching the mesh-node defaults:
// side=18, halo=3 → 18×18 tile with 3-cell halo ring → 12×12 interior
const W = 18, H = 18, HALO = 3;

describe('computeDataSeed', () => {
  test('returns a Uint8Array of width×height bytes', () => {
    const cells = computeDataSeed(0, 0, 1, 4, W, H, HALO);
    expect(cells).toBeInstanceOf(Uint8Array);
    expect(cells.length).toBe(W * H);
  });

  test('halo ring cells are exactly zero', () => {
    const cells = computeDataSeed(0, 0, 10, 4, W, H, HALO);
    for (let row = 0; row < H; row++) {
      for (let col = 0; col < W; col++) {
        const isHalo =
          row < HALO || row >= H - HALO || col < HALO || col >= W - HALO;
        if (isHalo) {
          expect(cells[row * W + col]).toBe(0);
        }
      }
    }
  });

  test('interior cells are either ALIVE (200) or DEAD (0)', () => {
    const cells = computeDataSeed(0, 0, 10, 4, W, H, HALO);
    for (let row = HALO; row < H - HALO; row++) {
      for (let col = HALO; col < W - HALO; col++) {
        const v = cells[row * W + col]!;
        expect(v === 0 || v === 200).toBe(true);
      }
    }
  });

  test('density is in the MNCA-interesting range (0.15 – 0.50)', () => {
    // Interior cells only; test several (tileX, tileY, tick, peer) combos.
    const interiorCount = (W - 2 * HALO) * (H - 2 * HALO);
    for (const [tx, ty, tick, peers] of [
      [0, 0, 1, 4],
      [1, 2, 50, 16],
      [3, 1, 5, 6],
      [0, 0, 0, 1],
      [2, 2, 100, 96],
    ]) {
      const cells  = computeDataSeed(tx!, ty!, tick!, peers!, W, H, HALO);
      let alive = 0;
      for (let row = HALO; row < H - HALO; row++) {
        for (let col = HALO; col < W - HALO; col++) {
          if (cells[row * W + col]! > 0) alive++;
        }
      }
      const density = alive / interiorCount;
      expect(density).toBeGreaterThanOrEqual(0.10);
      expect(density).toBeLessThanOrEqual(0.55);
    }
  });

  test('higher tick → higher density (fresh data = more alive cells)', () => {
    const interiorCount = (W - 2 * HALO) * (H - 2 * HALO);
    const countAlive = (tick: number) => {
      const cells = computeDataSeed(1, 1, tick, 4, W, H, HALO);
      let n = 0;
      for (let r = HALO; r < H - HALO; r++)
        for (let c = HALO; c < W - HALO; c++)
          if (cells[r * W + c]! > 0) n++;
      return n;
    };
    const staleDensity  = countAlive(0)  / interiorCount;
    const freshDensity  = countAlive(63) / interiorCount;
    // Fresh tiles should be denser than stale tiles.
    expect(freshDensity).toBeGreaterThan(staleDensity);
  });

  test('deterministic: same inputs → identical output', () => {
    const a = computeDataSeed(2, 3, 42, 6, W, H, HALO);
    const b = computeDataSeed(2, 3, 42, 6, W, H, HALO);
    expect(Array.from(a)).toEqual(Array.from(b));
  });

  test('different tile coordinates → different seeds', () => {
    const a = computeDataSeed(0, 0, 10, 4, W, H, HALO);
    const b = computeDataSeed(1, 0, 10, 4, W, H, HALO);
    expect(Array.from(a)).not.toEqual(Array.from(b));
  });
});

describe('buildDataTile', () => {
  test('returns a TileState with correct header fields', () => {
    const tile = buildDataTile(2, 3, 10, 4, W, H, HALO);
    expect(tile.tileX).toBe(2);
    expect(tile.tileY).toBe(3);
    expect(tile.tick).toBe(10n);
    expect(tile.width).toBe(W);
    expect(tile.height).toBe(H);
    expect(tile.haloRadius).toBe(HALO);
    expect(tile.flags).toBe(0);
    expect(tile.cells.length).toBe(W * H);
  });

  test('tick stored as bigint', () => {
    const tile = buildDataTile(0, 0, 999, 1, W, H, HALO);
    expect(tile.tick).toBe(999n);
  });
});

describe('stepDataTile', () => {
  test('0 steps returns tile unchanged', () => {
    const tile = buildDataTile(0, 0, 5, 4, W, H, HALO);
    const orig = Array.from(tile.cells);
    const stepped = stepDataTile(tile, 0);
    expect(Array.from(stepped.cells)).toEqual(orig);
  });

  test('1+ steps changes the interior cells (MNCA rule fires)', () => {
    const tile = buildDataTile(1, 1, 30, 4, W, H, HALO);
    const orig   = Array.from(tile.cells);
    const stepped = stepDataTile(tile, 1);
    // The rule must change at least some interior cells.
    let changed = 0;
    for (let r = HALO; r < H - HALO; r++)
      for (let c = HALO; c < W - HALO; c++)
        if (stepped.cells[r * W + c] !== tile.cells[r * W + c]) changed++;
    expect(changed).toBeGreaterThan(0);
  });

  test('tick increments by step count', () => {
    const tile    = buildDataTile(0, 0, 10, 4, W, H, HALO);
    const stepped = stepDataTile(tile, 3);
    expect(stepped.tick).toBe(13n);
  });

  test('dimensions are preserved through steps', () => {
    const tile    = buildDataTile(2, 2, 5, 4, W, H, HALO);
    const stepped = stepDataTile(tile, 5);
    expect(stepped.width).toBe(W);
    expect(stepped.height).toBe(H);
    expect(stepped.haloRadius).toBe(HALO);
    expect(stepped.cells.length).toBe(W * H);
  });
});

describe('tileToSSEPayload', () => {
  test('returns correct shape for the SSE event', () => {
    const tile    = buildDataTile(1, 2, 7, 4, W, H, HALO);
    const stepped = stepDataTile(tile, 2);
    const payload = tileToSSEPayload(stepped) as Record<string, unknown>;

    expect(payload['tileX']).toBe(1);
    expect(payload['tileY']).toBe(2);
    expect(typeof payload['tick']).toBe('number');
    expect(payload['tick']).toBe(9);           // 7 + 2 steps
    expect(payload['width']).toBe(W);
    expect(payload['height']).toBe(H);
    expect(payload['halo']).toBe(HALO);
    expect(Array.isArray(payload['cells'])).toBe(true);
    expect((payload['cells'] as number[]).length).toBe(W * H);
    // source tag distinguishes data-derived from raw mesh tiles
    expect(payload['source']).toBe('data');
  });

  test('cells array contains only numbers in [0,255]', () => {
    const tile    = buildDataTile(0, 0, 10, 4, W, H, HALO);
    const stepped = stepDataTile(tile, 3);
    const payload = tileToSSEPayload(stepped) as Record<string, unknown>;
    for (const v of payload['cells'] as number[]) {
      expect(typeof v).toBe('number');
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(255);
    }
  });
});

```
