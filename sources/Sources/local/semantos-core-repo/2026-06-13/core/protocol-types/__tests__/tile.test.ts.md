---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/tile.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.855354+00:00
---

# core/protocol-types/__tests__/tile.test.ts

```ts
/**
 * MNCA tile codec + reference rule tests.
 *
 * Locked design (2026-05-22): tile = cell, 1 byte/grid-cell raw in the
 * payload, integer arithmetic, baked-in halo. These tests pin the payload
 * layout and the deterministic integer rule mechanics with hand-verifiable
 * scenarios (no circular oracle generation).
 */
import { describe, expect, test } from 'bun:test';
import { PAYLOAD_SIZE } from '../src/constants';
import {
  TILE_HEADER_SIZE,
  TILE_MAX_CELLS,
  maxSquareTileSide,
  encodeTilePayload,
  decodeTilePayload,
  stepTile,
  interiorDims,
  type TileState,
  type MncaRuleParams,
} from '../src/mnca/tile';

const W = 7;
const H = 7;

function zeroTile(over: Partial<TileState> = {}): TileState {
  return {
    tileX: 0,
    tileY: 0,
    tick: 0n,
    width: W,
    height: H,
    haloRadius: 1,
    flags: 0,
    cells: new Uint8Array(W * H),
    ...over,
  };
}
const idx = (x: number, y: number) => y * W + x;

// Test rule with the outer-neighbourhood boost DISABLED (outerBoost huge),
// for clean birth/survival/death mechanics. inner radius 1, outer radius 2.
const TR_NOBOOST: MncaRuleParams = {
  aliveThreshold: 1,
  innerRadius: 1,
  outerRadius: 2,
  birthLo: 3,
  birthHi: 3,
  surviveLo: 2,
  surviveHi: 3,
  growStep: 10,
  decayStep: 10,
  outerBoost: 99,
};
// Same rule but the outer boost fires at >=3 alive in the radius-2 box.
const TR_BOOST: MncaRuleParams = { ...TR_NOBOOST, outerBoost: 3 };

describe('tile codec layout', () => {
  test('header is 16 bytes; max cells = 752; max square side = 27', () => {
    expect(TILE_HEADER_SIZE).toBe(16);
    expect(TILE_MAX_CELLS).toBe(PAYLOAD_SIZE - 16);
    expect(TILE_MAX_CELLS).toBe(752);
    expect(maxSquareTileSide()).toBe(27);
  });

  test('encode → decode round-trips every field bit-exact', () => {
    const cells = new Uint8Array(W * H);
    for (let i = 0; i < cells.length; i++) cells[i] = (i * 5 + 3) & 0xff;
    const tile = zeroTile({ tileX: 12, tileY: 34, tick: 0xdead_beefn, haloRadius: 2, flags: 1, cells });
    const payload = encodeTilePayload(tile);
    expect(payload.length).toBe(PAYLOAD_SIZE);

    const decoded = decodeTilePayload(payload);
    expect(decoded.tileX).toBe(12);
    expect(decoded.tileY).toBe(34);
    expect(decoded.tick).toBe(0xdead_beefn);
    expect(decoded.width).toBe(W);
    expect(decoded.height).toBe(H);
    expect(decoded.haloRadius).toBe(2);
    expect(decoded.flags).toBe(1);
    expect(Array.from(decoded.cells)).toEqual(Array.from(cells));
  });

  test('interiorDims excludes the halo ring', () => {
    const tile = zeroTile({ width: 26, height: 26, haloRadius: 1, cells: new Uint8Array(26 * 26) });
    expect(interiorDims(tile)).toEqual({ width: 24, height: 24 });
  });

  test('rejects cells-length mismatch, oversize tiles, and no-interior halos', () => {
    expect(() => encodeTilePayload(zeroTile({ cells: new Uint8Array(W * H - 1) }))).toThrow();
    // 28×28 = 784 > 752.
    expect(() =>
      encodeTilePayload(zeroTile({ width: 28, height: 28, cells: new Uint8Array(28 * 28) })),
    ).toThrow();
    // haloRadius 4 on a 7-wide tile leaves no interior.
    expect(() => encodeTilePayload(zeroTile({ haloRadius: 4 }))).toThrow();
  });
});

describe('reference MNCA rule — hand-verifiable mechanics', () => {
  test('quiescent: an all-zero tile stays all-zero', () => {
    const next = stepTile(zeroTile(), TR_NOBOOST);
    expect(Array.from(next.cells)).toEqual(Array.from(new Uint8Array(W * H)));
  });

  test('birth: a dead centre with exactly 3 alive Moore neighbours is born', () => {
    const cells = new Uint8Array(W * H);
    // 3 of centre (3,3)'s Moore neighbours alive.
    cells[idx(2, 2)] = 1;
    cells[idx(2, 3)] = 1;
    cells[idx(2, 4)] = 1;
    const next = stepTile(zeroTile({ cells }), TR_NOBOOST);
    expect(next.cells[idx(3, 3)]).toBe(10); // 0 + growStep
  });

  test('survival: an alive centre with 2 alive neighbours grows', () => {
    const cells = new Uint8Array(W * H);
    cells[idx(3, 3)] = 200;
    cells[idx(2, 3)] = 1;
    cells[idx(4, 3)] = 1;
    const next = stepTile(zeroTile({ cells }), TR_NOBOOST);
    expect(next.cells[idx(3, 3)]).toBe(210); // 200 + growStep
  });

  test('death: an alive centre with no alive neighbours decays', () => {
    const cells = new Uint8Array(W * H);
    cells[idx(3, 3)] = 200;
    const next = stepTile(zeroTile({ cells }), TR_NOBOOST);
    expect(next.cells[idx(3, 3)]).toBe(190); // 200 - decayStep
  });

  test('outer neighbourhood adds growth (the "multi" in MNCA)', () => {
    // 2 alive inner neighbours (survive) → +10. Add one alive cell in the
    // radius-2-only frame so the outer count reaches the boost threshold.
    const cells = new Uint8Array(W * H);
    cells[idx(3, 3)] = 200;
    cells[idx(2, 3)] = 1;
    cells[idx(4, 3)] = 1;
    // Without the outer cell: outerAlive = 2 < 3 → no boost → 210.
    expect(stepTile(zeroTile({ cells }), TR_BOOST).cells[idx(3, 3)]).toBe(210);
    // With a radius-2-only alive cell at (1,3): outerAlive = 3 → boost → 220.
    const cells2 = cells.slice();
    cells2[idx(1, 3)] = 1;
    expect(stepTile(zeroTile({ cells: cells2 }), TR_BOOST).cells[idx(3, 3)]).toBe(220);
  });

  test('state saturates at 0 and 255', () => {
    const cells = new Uint8Array(W * H);
    cells[idx(3, 3)] = 250;
    cells[idx(2, 3)] = 1;
    cells[idx(4, 3)] = 1;
    // 250 + 10 saturates at 255 (not 260).
    expect(stepTile(zeroTile({ cells }), TR_NOBOOST).cells[idx(3, 3)]).toBe(255);
    const cells2 = new Uint8Array(W * H);
    cells2[idx(3, 3)] = 5; // alive (>=1), 0 neighbours → -10 saturates at 0.
    expect(stepTile(zeroTile({ cells: cells2 }), TR_NOBOOST).cells[idx(3, 3)]).toBe(0);
  });
});

describe('reference MNCA rule — invariants', () => {
  test('deterministic: same input → identical output across runs', () => {
    const cells = new Uint8Array(W * H);
    for (let i = 0; i < cells.length; i++) cells[i] = (i * 37) & 0xff;
    const a = stepTile(zeroTile({ cells }), TR_BOOST);
    const b = stepTile(zeroTile({ cells }), TR_BOOST);
    expect(Array.from(a.cells)).toEqual(Array.from(b.cells));
  });

  test('halo ring (the 2-wide frame) is carried over unchanged', () => {
    const cells = new Uint8Array(W * H);
    cells[idx(0, 0)] = 77; // corner — in the frame, never evaluated
    cells[idx(6, 6)] = 88;
    const next = stepTile(zeroTile({ cells }), TR_NOBOOST);
    expect(next.cells[idx(0, 0)]).toBe(77);
    expect(next.cells[idx(6, 6)]).toBe(88);
  });

  test('tick increments by 1; coords + dims preserved', () => {
    const next = stepTile(zeroTile({ tileX: 9, tileY: 4, tick: 5n }), TR_NOBOOST);
    expect(next.tick).toBe(6n);
    expect(next.tileX).toBe(9);
    expect(next.tileY).toBe(4);
    expect(next.width).toBe(W);
    expect(next.haloRadius).toBe(1);
  });

  test('does not mutate the input tile', () => {
    const cells = new Uint8Array(W * H);
    cells[idx(3, 3)] = 200;
    const tile = zeroTile({ cells });
    stepTile(tile, TR_NOBOOST);
    expect(tile.cells[idx(3, 3)]).toBe(200); // unchanged
    expect(tile.tick).toBe(0n);
  });
});

```
