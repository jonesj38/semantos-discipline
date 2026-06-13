---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/__tests__/local-keypair-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.807260+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/__tests__/local-keypair-manager.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { PrivateKey } from '@bsv/sdk';
import { get } from '@semantos/state';
import {
  getLocalKeyAtom,
  initLocalKeypair,
  requireLocalKeypair,
  resetLocalKeyAtoms,
  setLocalKeypair,
} from '../local-keypair-manager';

afterEach(() => resetLocalKeyAtoms());

describe('local-keypair-manager', () => {
  test('1. initLocalKeypair seeds a fresh keypair on first call', () => {
    const pair = initLocalKeypair('e1');
    expect(pair.fundingAddress).toMatch(/^[13mn]/);
    expect(pair.pubKeyHex.length).toBeGreaterThan(60);
    expect(pair.wif.length).toBeGreaterThan(40);
  });

  test('2. initLocalKeypair is idempotent', () => {
    const a = initLocalKeypair('e1');
    const b = initLocalKeypair('e1');
    expect(a).toBe(b);
  });

  test('3. distinct engineIds get distinct keypairs', () => {
    const a = initLocalKeypair('e1');
    const b = initLocalKeypair('e2');
    expect(a.pubKeyHex).not.toBe(b.pubKeyHex);
  });

  test('4. setLocalKeypair overrides the existing pair', () => {
    initLocalKeypair('e1');
    const pk = PrivateKey.fromRandom();
    const pair = setLocalKeypair('e1', pk);
    expect(pair.privateKey).toBe(pk);
    expect(get(getLocalKeyAtom('e1'))).toBe(pair);
  });

  test('5. requireLocalKeypair throws when not initialized', () => {
    expect(() => requireLocalKeypair('not-set')).toThrow('not initialized');
  });

  test('6. resetLocalKeyAtoms wipes the registry', () => {
    initLocalKeypair('e1');
    resetLocalKeyAtoms();
    expect(get(getLocalKeyAtom('e1'))).toBeNull();
  });
});

```
