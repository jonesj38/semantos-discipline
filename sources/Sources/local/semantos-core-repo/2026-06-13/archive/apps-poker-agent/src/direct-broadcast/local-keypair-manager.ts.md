---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/local-keypair-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.784055+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/local-keypair-manager.ts

```ts
/**
 * Local keypair manager — atom-backed BSV keypair for the
 * wallet-bypass broadcast path.
 *
 * One keypair per `DirectBroadcastEngine` instance. The atom shape
 * lets dashboards subscribe to "what address am I funding?" without
 * having to poke at engine internals.
 *
 * The keypair is generated lazily — `initLocalKeypair()` reads the
 * current atom value, generates a fresh pair if absent, and writes
 * it back. Idempotent.
 */

import { PrivateKey, type PublicKey } from '@bsv/sdk';
import { atom, get, set, type Atom } from '@semantos/state';

export interface LocalKeyPair {
  privateKey: PrivateKey;
  publicKey: PublicKey;
  fundingAddress: string;
  pubKeyHex: string;
  wif: string;
}

const registry = new Map<string, Atom<LocalKeyPair | null>>();

/** Per-engine atom bundle. `engineId` is opaque — the facade owns it. */
export function getLocalKeyAtom(engineId: string): Atom<LocalKeyPair | null> {
  const existing = registry.get(engineId);
  if (existing) return existing;
  const a = atom<LocalKeyPair | null>(null);
  registry.set(engineId, a);
  return a;
}

/** Test/teardown helper. */
export function resetLocalKeyAtoms(): void {
  registry.clear();
}

/**
 * Generate a fresh BSV keypair and seat it in the atom. Returns the
 * pair so the caller doesn't have to read the atom back.
 */
export function initLocalKeypair(engineId: string): LocalKeyPair {
  const a = getLocalKeyAtom(engineId);
  const existing = get(a);
  if (existing) return existing;

  const privateKey = PrivateKey.fromRandom();
  const publicKey = privateKey.toPublicKey();
  const pair: LocalKeyPair = {
    privateKey,
    publicKey,
    fundingAddress: publicKey.toAddress(),
    pubKeyHex: publicKey.toString(),
    wif: privateKey.toWif(),
  };
  set(a, pair);
  return pair;
}

/**
 * Force-set a specific keypair (e.g. when restoring from WIF in
 * tests). The wif/funding-address fields are recomputed.
 */
export function setLocalKeypair(engineId: string, privateKey: PrivateKey): LocalKeyPair {
  const publicKey = privateKey.toPublicKey();
  const pair: LocalKeyPair = {
    privateKey,
    publicKey,
    fundingAddress: publicKey.toAddress(),
    pubKeyHex: publicKey.toString(),
    wif: privateKey.toWif(),
  };
  set(getLocalKeyAtom(engineId), pair);
  return pair;
}

/** Return the active keypair or throw if `init` hasn't been called. */
export function requireLocalKeypair(engineId: string): LocalKeyPair {
  const pair = get(getLocalKeyAtom(engineId));
  if (!pair) throw new Error(`local keypair not initialized for engine "${engineId}"`);
  return pair;
}

```
