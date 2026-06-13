---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/p2p-key-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.767890+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/p2p-key-manager.ts

```ts
/**
 * P2P key manager — derives + tracks the alternating pubkey pair that
 * controls every CellToken transition.
 *
 * The protocol is simple: each player derives a deterministic pubkey
 * via the wallet, registers their opponent's pubkey, and the live
 * UTXO bounces between them by alternating its locking key.
 *
 * State exposed as atoms:
 *   - `myPubKeyAtom`        : my derived pubkey (hex)
 *   - `opponentPubKeyAtom`  : opponent's pubkey (hex) — equals my
 *                              key in single-player mode
 *   - `keyIdAtom`           : keyID used for getPublicKey + sign
 *
 * Atoms are registered per-game via `getKeyAtoms(gameId)` so multiple
 * concurrent state-machine instances don't cross-pollinate.
 */

import { atom, get, set, type Atom } from '@semantos/state';

import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';
import { CELLTOKEN_COUNTERPARTY, CELLTOKEN_PROTOCOL } from './types';

export interface KeyAtoms {
  gameId: string;
  myPubKeyAtom: Atom<string>;
  opponentPubKeyAtom: Atom<string>;
  keyIdAtom: Atom<string>;
}

const registry = new Map<string, KeyAtoms>();

/**
 * Get (or create) the key atom bundle for a given gameId. Idempotent
 * — repeat calls return the same instance so subscribers stay live.
 */
export function getKeyAtoms(gameId: string): KeyAtoms {
  const existing = registry.get(gameId);
  if (existing) return existing;
  const bundle: KeyAtoms = {
    gameId,
    myPubKeyAtom: atom<string>(''),
    opponentPubKeyAtom: atom<string>(''),
    keyIdAtom: atom<string>(''),
  };
  registry.set(gameId, bundle);
  return bundle;
}

/** Test/teardown helper — wipes the registry. */
export function resetKeyAtoms(): void {
  registry.clear();
}

export interface InitKeysResult {
  myPubKeyHex: string;
  opponentPubKeyHex: string;
  keyID: string;
  /** True when no opponent was supplied — both keys are mine. */
  selfLock: boolean;
}

/**
 * Resolve the keyID, derive my pubkey via the wallet, and register
 * the opponent's pubkey (if any). Writes through to the per-game
 * atoms so subscribers see the values appear atomically.
 */
export async function initKeys(
  wallet: WalletClient,
  gameId: string,
  opponentPubKey?: string,
): Promise<InitKeysResult> {
  const keyID = `game/poker/${gameId}/state`;
  const myPubKeyHex = await wallet.getPublicKey({
    protocolID: CELLTOKEN_PROTOCOL,
    keyID,
    counterparty: CELLTOKEN_COUNTERPARTY,
  });
  const opponentPubKeyHex = opponentPubKey ?? myPubKeyHex;

  const atoms = getKeyAtoms(gameId);
  set(atoms.keyIdAtom, keyID);
  set(atoms.myPubKeyAtom, myPubKeyHex);
  set(atoms.opponentPubKeyAtom, opponentPubKeyHex);

  return {
    myPubKeyHex,
    opponentPubKeyHex,
    keyID,
    selfLock: !opponentPubKey,
  };
}

/** Read helpers — sugar for callers that don't want to import @semantos/state. */
export function getMyPubKey(gameId: string): string {
  return get(getKeyAtoms(gameId).myPubKeyAtom);
}

export function getOpponentPubKey(gameId: string): string {
  return get(getKeyAtoms(gameId).opponentPubKeyAtom);
}

export function getKeyID(gameId: string): string {
  return get(getKeyAtoms(gameId).keyIdAtom);
}

```
