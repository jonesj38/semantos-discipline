---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/piece-selection.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.057530+00:00
---

# runtime/session-protocol/src/swarm/piece-selection.ts

```ts
/**
 * Rarest-first piece selection.
 *
 * Given the leecher's own bitfield and the bitfields it has observed from peers
 * on the wire, produce an ordered want-list: fetch the cells the fewest peers
 * hold first (so rare pieces propagate before their only holder leaves), skip
 * cells already held or in flight, and never request a cell no peer advertises.
 *
 * Bootstrap: the very first piece should be chosen at random rather than
 * strictly rarest, so a fresh swarm doesn't have every new leecher converge on
 * the same single rarest cell. Endgame: once only a few cells remain, request
 * each remaining cell from every holder to avoid stalling on one slow peer.
 *
 * Pure — operates on the aggregate the session has already observed. No
 * transport, no RPC.
 */

import { hasCell } from './have-bitfield';

export interface SelectionInput {
  /** Total data cells in the file. */
  totalCells: number;
  /** Cells the leecher already holds. */
  localBitfield: Uint8Array;
  /** Observed peer bitfields, keyed by peer BCA (string). */
  peerBitfields: Map<string, Uint8Array>;
  /** Cells already requested and awaiting delivery. */
  inFlight?: ReadonlySet<number>;
}

/** Per-cell availability: how many observed peers hold each missing cell. */
export function availabilityMap(input: SelectionInput): Map<number, number> {
  const { totalCells, localBitfield, peerBitfields, inFlight } = input;
  const avail = new Map<number, number>();
  for (let i = 0; i < totalCells; i++) {
    if (hasCell(localBitfield, i)) continue;
    if (inFlight?.has(i)) continue;
    let count = 0;
    for (const bf of peerBitfields.values()) if (hasCell(bf, i)) count++;
    if (count > 0) avail.set(i, count);
  }
  return avail;
}

/**
 * Ordered want-list, rarest cell first. Cells no peer holds are omitted (they
 * can't be fetched yet). Ties broken by ascending cell index for determinism.
 */
export function rarestFirst(input: SelectionInput): number[] {
  const avail = availabilityMap(input);
  return [...avail.entries()]
    .sort((a, b) => (a[1] - b[1]) || (a[0] - b[0]))
    .map(([index]) => index);
}

/** Set of peer BCAs that hold a given cell. */
export function holdersOf(index: number, peerBitfields: Map<string, Uint8Array>): string[] {
  const out: string[] = [];
  for (const [bca, bf] of peerBitfields) if (hasCell(bf, index)) out.push(bca);
  return out;
}

/**
 * Pick the bootstrap piece: a random fetchable (peer-held, not-local,
 * not-in-flight) cell. `rng` is injectable for deterministic tests; defaults to
 * Math.random. Returns null when nothing is fetchable.
 */
export function randomFirstPiece(input: SelectionInput, rng: () => number = Math.random): number | null {
  const candidates = [...availabilityMap(input).keys()];
  if (candidates.length === 0) return null;
  const idx = Math.min(candidates.length - 1, Math.floor(rng() * candidates.length));
  return candidates[idx]!;
}

/** True once the number of missing fetchable cells is at or below `threshold`. */
export function isEndgame(input: SelectionInput, threshold: number): boolean {
  return availabilityMap(input).size <= threshold && availabilityMap(input).size > 0;
}

export interface EndgameRequest {
  index: number;
  /** Every peer that holds this cell — request from all of them. */
  holders: string[];
}

/**
 * In endgame, return each remaining fetchable cell paired with all of its
 * holders so the session can duplicate-request the tail across every peer.
 */
export function endgameTargets(input: SelectionInput): EndgameRequest[] {
  const order = rarestFirst(input);
  return order.map(index => ({ index, holders: holdersOf(index, input.peerBitfields) }));
}

```
