---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/__tests__/p2p-key-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.800510+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/__tests__/p2p-key-manager.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { get } from '@semantos/state';
import {
  getKeyAtoms,
  getKeyID,
  getMyPubKey,
  getOpponentPubKey,
  initKeys,
  resetKeyAtoms,
} from '../p2p-key-manager';

afterEach(() => resetKeyAtoms());

function makeWallet(returnedPubKey: string) {
  return {
    getPublicKey: async () => returnedPubKey,
  } as any;
}

describe('getKeyAtoms', () => {
  test('1. returns the same bundle for the same gameId', () => {
    const a = getKeyAtoms('g-1');
    const b = getKeyAtoms('g-1');
    expect(a).toBe(b);
  });

  test('2. different gameIds → different bundles', () => {
    expect(getKeyAtoms('g-1')).not.toBe(getKeyAtoms('g-2'));
  });

  test('3. initial atom values are empty strings', () => {
    const { myPubKeyAtom, opponentPubKeyAtom, keyIdAtom } = getKeyAtoms('g-1');
    expect(get(myPubKeyAtom)).toBe('');
    expect(get(opponentPubKeyAtom)).toBe('');
    expect(get(keyIdAtom)).toBe('');
  });
});

describe('initKeys', () => {
  test('4. derives my pubkey via the wallet and writes through atoms', async () => {
    const wallet = makeWallet('myPubKeyHex');
    const r = await initKeys(wallet, 'g-1');
    expect(r.myPubKeyHex).toBe('myPubKeyHex');
    expect(r.keyID).toBe('game/poker/g-1/state');
    expect(r.selfLock).toBe(true);
    expect(getMyPubKey('g-1')).toBe('myPubKeyHex');
  });

  test('5. opponent key registers separately when supplied', async () => {
    const wallet = makeWallet('me');
    const r = await initKeys(wallet, 'g-1', 'oppKeyHex');
    expect(r.opponentPubKeyHex).toBe('oppKeyHex');
    expect(r.selfLock).toBe(false);
    expect(getOpponentPubKey('g-1')).toBe('oppKeyHex');
  });

  test('6. self-lock mode mirrors my key into the opponent slot', async () => {
    const wallet = makeWallet('me');
    await initKeys(wallet, 'g-1');
    expect(getOpponentPubKey('g-1')).toBe('me');
  });

  test('7. keyID format is the canonical game/poker/<id>/state', async () => {
    const wallet = makeWallet('me');
    await initKeys(wallet, 'XYZ');
    expect(getKeyID('XYZ')).toBe('game/poker/XYZ/state');
  });

  test('8. distinct gameIds keep their atoms isolated', async () => {
    const wallet1 = makeWallet('one');
    const wallet2 = makeWallet('two');
    await initKeys(wallet1, 'g-1');
    await initKeys(wallet2, 'g-2');
    expect(getMyPubKey('g-1')).toBe('one');
    expect(getMyPubKey('g-2')).toBe('two');
  });
});

```
