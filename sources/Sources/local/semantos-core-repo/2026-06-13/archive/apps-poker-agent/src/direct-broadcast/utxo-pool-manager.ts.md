---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/utxo-pool-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.784334+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/utxo-pool-manager.ts

```ts
/**
 * UTXO pool manager — atom-backed pre-split funding pools, one per
 * stream.
 *
 * Internal layout:
 *   utxoPoolsAtom = atom<Map<number, FundingUtxo[]>>
 *
 * The map is mutated in place (consume / return / recycle) and
 * re-set on the atom so subscribers see the change. We never create
 * a fresh map every call — that would invalidate Object.is checks in
 * downstream selectors and burn churn for no benefit.
 *
 * Dust UTXOs (< MIN_USEFUL_SATS) are silently dropped at pick time;
 * recycled change outputs above that threshold are added back to the
 * pool.
 */

import { atom, get, set, type Atom } from '@semantos/state';

import { MIN_USEFUL_SATS, type FundingUtxo } from './types';

export type PoolMap = Map<number, FundingUtxo[]>;

const registry = new Map<string, Atom<PoolMap>>();

export function getUtxoPoolsAtom(engineId: string): Atom<PoolMap> {
  const existing = registry.get(engineId);
  if (existing) return existing;
  const a = atom<PoolMap>(new Map());
  registry.set(engineId, a);
  return a;
}

export function resetUtxoPoolAtoms(): void {
  registry.clear();
}

/** Initialize empty pools for `streams` consumer streams. */
export function initPools(engineId: string, streams: number): void {
  const a = getUtxoPoolsAtom(engineId);
  const map: PoolMap = new Map();
  for (let i = 0; i < streams; i++) map.set(i, []);
  set(a, map);
}

/** Add `utxos` to the given stream's pool. */
export function addToPool(engineId: string, streamId: number, utxos: FundingUtxo[]): void {
  const a = getUtxoPoolsAtom(engineId);
  const map = get(a);
  const pool = map.get(streamId) ?? [];
  pool.push(...utxos);
  map.set(streamId, pool);
  set(a, map);
}

/** Consume `count` UTXOs off the front of the pool. Throws if short. */
export function consumeUtxos(engineId: string, streamId: number, count: number): FundingUtxo[] {
  const map = get(getUtxoPoolsAtom(engineId));
  const pool = map.get(streamId);
  if (!pool || pool.length < count) {
    throw new Error(
      `Stream ${streamId}: need ${count} UTXOs, only ${pool?.length ?? 0} available`,
    );
  }
  return pool.splice(0, count);
}

/** Return previously-consumed UTXOs back to the pool's tail. */
export function returnUtxos(engineId: string, streamId: number, utxos: FundingUtxo[]): void {
  const map = get(getUtxoPoolsAtom(engineId));
  const pool = map.get(streamId);
  if (pool) pool.push(...utxos);
}

export interface PickFundingResult {
  utxo: FundingUtxo;
  /** Sats discarded as dust during the pick (logging hook). */
  discardedDust: number;
}

/**
 * Pop the first UTXO with at least MIN_USEFUL_SATS. Dust UTXOs are
 * dropped silently; their total satoshis are returned so the caller
 * can emit a `utxo-discarded` event if they care.
 */
export function pickFundingUtxo(
  engineId: string,
  streamId: number,
  op: string,
): PickFundingResult {
  const map = get(getUtxoPoolsAtom(engineId));
  const pool = map.get(streamId);
  if (!pool) {
    throw new Error(`Stream ${streamId} has no UTXO pool (${op})`);
  }
  let discardedDust = 0;
  while (pool.length > 0) {
    const utxo = pool.shift()!;
    if (utxo.satoshis >= MIN_USEFUL_SATS) {
      return { utxo, discardedDust };
    }
    discardedDust += utxo.satoshis;
  }
  throw new Error(`Stream ${streamId} has no more funding UTXOs for ${op}`);
}

/** Push a recycled change output back into the stream's pool. */
export function recycleUtxo(engineId: string, streamId: number, utxo: FundingUtxo): void {
  addToPool(engineId, streamId, [utxo]);
}

/** Snapshot of pool sizes for stats. */
export function getPoolSizes(engineId: string): number[] {
  const map = get(getUtxoPoolsAtom(engineId));
  const out: number[] = [];
  for (const [id, pool] of map) {
    out[id] = pool.length;
  }
  return Array.from(out, (n) => n ?? 0);
}

```
