---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/tile.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.899489+00:00
---

# core/protocol-types/src/mnca/tile.ts

```ts
/**
 * MNCA tile codec + reference rule.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` + the locked design
 * decisions (2026-05-22):
 *   - tile = cell (domain decomposition)
 *   - 1 byte per grid-cell, raw in the payload (no marshalling)
 *   - integer / fixed-point arithmetic (determinism across C6/Pi/Mac)
 *   - baked-in halo + full-tile gossip
 *
 * A tile is a square-ish sub-grid of the full MNCA. Its state lives RAW in
 * the 768-byte cell payload — the same bytes the cell-engine reads in
 * SRAM, that cross the wire, and that become pushdrop UTXO data. There is
 * no separate "MNCA grid representation": the canonical cell payload IS
 * the tile.
 *
 * Payload layout (offset is within the 768-byte payload region, i.e.
 * cell offset 256 + this):
 *
 *   0      u16 LE  tileX            tile column in the global tiling
 *   2      u16 LE  tileY            tile row
 *   4      u64 LE  tick             generation number
 *   12     u8      width  W         columns INCLUDING the halo ring
 *   13     u8      height H         rows INCLUDING the halo ring
 *   14     u8      haloRadius R     width of the border copied from neighbours
 *   15     u8      flags            reserved (0)
 *   16     W*H     state            row-major, 1 byte/cell, 0..255
 *
 * Constraint: 16 + W*H <= 768  →  W*H <= 752  (max ~27×27 incl. halo).
 * The interior (the cells this tile actually owns + evolves) is
 * (W-2R) × (H-2R); the outer R-ring is halo, refreshed from neighbours by
 * the gossip/exchange layer (NOT by this codec).
 *
 * Determinism: the reference rule is integer-only (no float). The same
 * tile bytes + the same MncaRuleParams produce the same next tile on every
 * hardware class — that's the compute-axis invariant the demo claims.
 * This TS implementation is the reference oracle the cell-engine WASM port
 * is checked against.
 */

import { PAYLOAD_SIZE } from '../constants';

export const TILE_HEADER_SIZE = 16 as const;
export const TILE_MAX_CELLS = PAYLOAD_SIZE - TILE_HEADER_SIZE; // 752

const OFF_TILE_X = 0;
const OFF_TILE_Y = 2;
const OFF_TICK = 4;
const OFF_WIDTH = 12;
const OFF_HEIGHT = 13;
const OFF_HALO = 14;
const OFF_FLAGS = 15;
const OFF_STATE = 16;

export interface TileState {
  tileX: number; // u16
  tileY: number; // u16
  tick: bigint; // u64
  width: number; // u8, includes halo
  height: number; // u8, includes halo
  haloRadius: number; // u8
  flags: number; // u8
  /** Row-major state, length width*height, 1 byte/cell. */
  cells: Uint8Array;
}

/** Largest square tile (incl. halo) that fits the payload. */
export function maxSquareTileSide(): number {
  return Math.floor(Math.sqrt(TILE_MAX_CELLS));
}

/** Encode a tile into a 768-byte payload region. */
export function encodeTilePayload(tile: TileState): Uint8Array {
  const { width, height, cells } = tile;
  if (width < 1 || width > 255 || height < 1 || height > 255) {
    throw new Error(`encodeTilePayload: width/height must be 1..255 (got ${width}×${height})`);
  }
  if (cells.length !== width * height) {
    throw new Error(`encodeTilePayload: cells length ${cells.length} != ${width}×${height}`);
  }
  if (TILE_HEADER_SIZE + cells.length > PAYLOAD_SIZE) {
    throw new Error(
      `encodeTilePayload: ${width}×${height} = ${cells.length} cells + ${TILE_HEADER_SIZE} header exceeds payload (${PAYLOAD_SIZE})`,
    );
  }
  if (tile.haloRadius < 0 || tile.haloRadius > 127) {
    throw new Error(`encodeTilePayload: haloRadius out of range (${tile.haloRadius})`);
  }
  if (2 * tile.haloRadius >= Math.min(width, height)) {
    throw new Error(
      `encodeTilePayload: haloRadius ${tile.haloRadius} leaves no interior in ${width}×${height}`,
    );
  }

  const payload = new Uint8Array(PAYLOAD_SIZE);
  const dv = new DataView(payload.buffer);
  dv.setUint16(OFF_TILE_X, tile.tileX & 0xffff, true);
  dv.setUint16(OFF_TILE_Y, tile.tileY & 0xffff, true);
  dv.setBigUint64(OFF_TICK, tile.tick, true);
  payload[OFF_WIDTH] = width;
  payload[OFF_HEIGHT] = height;
  payload[OFF_HALO] = tile.haloRadius & 0xff;
  payload[OFF_FLAGS] = tile.flags & 0xff;
  payload.set(cells, OFF_STATE);
  return payload;
}

/** Decode a 768-byte payload region into a tile. */
export function decodeTilePayload(payload: Uint8Array): TileState {
  if (payload.length < TILE_HEADER_SIZE) {
    throw new Error(`decodeTilePayload: payload too short (${payload.length})`);
  }
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const width = payload[OFF_WIDTH]!;
  const height = payload[OFF_HEIGHT]!;
  const n = width * height;
  if (TILE_HEADER_SIZE + n > payload.length) {
    throw new Error(`decodeTilePayload: ${width}×${height} cells exceed payload (${payload.length})`);
  }
  return {
    tileX: dv.getUint16(OFF_TILE_X, true),
    tileY: dv.getUint16(OFF_TILE_Y, true),
    tick: dv.getBigUint64(OFF_TICK, true),
    width,
    height,
    haloRadius: payload[OFF_HALO]!,
    flags: payload[OFF_FLAGS]!,
    cells: payload.slice(OFF_STATE, OFF_STATE + n),
  };
}

/**
 * Reference MNCA rule parameters — a deterministic, integer, two-radius
 * totalistic rule (a "Larger than Life"-style birth/survival on the inner
 * neighbourhood, nudged by the outer neighbourhood — the "multi" in MNCA).
 *
 * THIS IS A SWAPPABLE REFERENCE, not the final dynamics — Todd owns the
 * rule's aesthetics. It exists to (a) prove the codec round-trips through a
 * compute step, (b) be the oracle for the cell-engine WASM port, and (c)
 * demonstrate cross-hardware determinism. All arithmetic is integer.
 */
export interface MncaRuleParams {
  /** A grid-cell counts as "alive" when its state >= this. */
  aliveThreshold: number;
  /** Inner (Moore) neighbourhood radius. */
  innerRadius: number;
  /** Outer neighbourhood radius (the "second neighbourhood"). */
  outerRadius: number;
  /** Dead cell is born when inner alive-count in [birthLo, birthHi]. */
  birthLo: number;
  birthHi: number;
  /** Alive cell survives when inner alive-count in [surviveLo, surviveHi]. */
  surviveLo: number;
  surviveHi: number;
  /** State increment when born / surviving (saturating at 255). */
  growStep: number;
  /** State decrement when dying (saturating at 0). */
  decayStep: number;
  /** Extra +growStep when outer alive-count >= outerBoost (the second-neighbourhood nudge). */
  outerBoost: number;
}

export const DEFAULT_MNCA_RULE: MncaRuleParams = {
  aliveThreshold: 128,
  innerRadius: 1,
  outerRadius: 3,
  birthLo: 3,
  birthHi: 3,
  surviveLo: 2,
  surviveHi: 3,
  growStep: 64,
  decayStep: 64,
  outerBoost: 12,
};

function clampU8(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}

/** Count "alive" cells in the ring/box of the given radius around (x,y), excluding the centre. */
function neighbourhoodAliveCount(
  cells: Uint8Array,
  width: number,
  x: number,
  y: number,
  radius: number,
  aliveThreshold: number,
): number {
  let count = 0;
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      if (dx === 0 && dy === 0) continue;
      const v = cells[(y + dy) * width + (x + dx)]!;
      if (v >= aliveThreshold) count++;
    }
  }
  return count;
}

/**
 * Advance the tile interior one MNCA generation. Reads the FULL tile
 * (interior + halo), writes the new interior into a fresh tile (the halo
 * ring is carried over unchanged — it gets refreshed by neighbour gossip).
 * Double-buffered: a CA must read the old state while writing the new.
 *
 * The new tile's `tick` is incremented by 1; tileX/tileY/dims/halo/flags
 * are preserved.
 */
export function stepTile(tile: TileState, params: MncaRuleParams = DEFAULT_MNCA_RULE): TileState {
  const { width, height, haloRadius: R, cells } = tile;
  const next = cells.slice(); // halo ring carried over unchanged
  const innerR = params.innerRadius;
  const outerR = params.outerRadius;

  // The interior we own + can fully evaluate must have all neighbourhood
  // samples in-bounds, so iterate where both the halo ring and the rule's
  // largest radius are satisfied.
  const margin = Math.max(R, innerR, outerR);
  for (let y = margin; y < height - margin; y++) {
    for (let x = margin; x < width - margin; x++) {
      const self = cells[y * width + x]!;
      const innerAlive = neighbourhoodAliveCount(cells, width, x, y, innerR, params.aliveThreshold);
      const outerAlive = neighbourhoodAliveCount(cells, width, x, y, outerR, params.aliveThreshold);
      const isAlive = self >= params.aliveThreshold;

      let delta: number;
      if (isAlive) {
        delta = innerAlive >= params.surviveLo && innerAlive <= params.surviveHi
          ? params.growStep
          : -params.decayStep;
      } else {
        delta = innerAlive >= params.birthLo && innerAlive <= params.birthHi
          ? params.growStep
          : -params.decayStep;
      }
      // Second-neighbourhood nudge: dense outer ring adds growth.
      if (outerAlive >= params.outerBoost) delta += params.growStep;

      next[y * width + x] = clampU8(self + delta);
    }
  }

  return {
    ...tile,
    tick: tile.tick + 1n,
    cells: next,
  };
}

/** Interior dimensions (the cells this tile owns, excluding the halo ring). */
export function interiorDims(tile: TileState): { width: number; height: number } {
  return {
    width: tile.width - 2 * tile.haloRadius,
    height: tile.height - 2 * tile.haloRadius,
  };
}

```
