---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/utxo-tracker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.768182+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/utxo-tracker.ts

```ts
/**
 * Live-UTXO tracker — atom-backed cache of the current hand's
 * CellToken UTXO.
 *
 * Mirrors the legacy `liveUtxo: LiveUtxo | null` field but exposes
 * the value as a `@semantos/state` atom so subscribers (e.g. the
 * arena dashboard) can react to ingest/spend events without polling.
 *
 * Atoms are scoped per-game to match `p2p-key-manager.ts`.
 */

import { atom, get, set, type Atom } from '@semantos/state';

import type { LiveUtxo } from './types';

export interface UtxoAtoms {
  gameId: string;
  liveUtxoAtom: Atom<LiveUtxo | null>;
}

const registry = new Map<string, UtxoAtoms>();

/** Per-game UTXO atom bundle. Idempotent. */
export function getUtxoAtoms(gameId: string): UtxoAtoms {
  const existing = registry.get(gameId);
  if (existing) return existing;
  const bundle: UtxoAtoms = {
    gameId,
    liveUtxoAtom: atom<LiveUtxo | null>(null),
  };
  registry.set(gameId, bundle);
  return bundle;
}

/** Test helper — wipes every UTXO atom. */
export function resetUtxoAtoms(): void {
  registry.clear();
}

export function setLiveUtxo(gameId: string, utxo: LiveUtxo | null): void {
  set(getUtxoAtoms(gameId).liveUtxoAtom, utxo);
}

export function getLiveUtxo(gameId: string): LiveUtxo | null {
  return get(getUtxoAtoms(gameId).liveUtxoAtom);
}

export function clearLiveUtxo(gameId: string): void {
  set(getUtxoAtoms(gameId).liveUtxoAtom, null);
}

/**
 * Convenience read for the consumer-facing `getLiveUtxo()` accessor —
 * strips the cellBytes + beef so the caller only sees what they need.
 */
export function snapshotLiveUtxo(
  gameId: string,
): { txid: string; vout: number; lockedToKey: string; version: number } | null {
  const utxo = getLiveUtxo(gameId);
  if (!utxo) return null;
  return {
    txid: utxo.txid,
    vout: utxo.vout,
    lockedToKey: utxo.lockedToKey,
    version: utxo.version,
  };
}

/** Whether the bound key controls the current UTXO (i.e. it's our turn). */
export function canSpendLiveUtxo(gameId: string, myPubKeyHex: string): boolean {
  const utxo = getLiveUtxo(gameId);
  return utxo !== null && utxo.lockedToKey === myPubKeyHex;
}

```
