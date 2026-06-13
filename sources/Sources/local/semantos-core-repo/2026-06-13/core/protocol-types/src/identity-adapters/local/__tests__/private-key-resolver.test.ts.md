---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/__tests__/private-key-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.916912+00:00
---

# core/protocol-types/src/identity-adapters/local/__tests__/private-key-resolver.test.ts

```ts
/**
 * Atom-backed private-key cache tests + chain re-derivation.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { get } from '@semantos/state';
import {
  cacheKey,
  clearKeyCache,
  getKey,
  privateKeyCacheAtom,
  resolvePrivateKey,
} from '../private-key-resolver';
import { CertChainStore } from '../cert-chain-store-facade';
import { KeyDerivationService } from '../../KeyDerivationService';
import { MemoryAdapter } from '../../../adapters/memory-adapter';

afterEach(() => clearKeyCache());

describe('atom-backed cache', () => {
  test('1. starts empty', () => {
    expect(get(privateKeyCacheAtom).size).toBe(0);
  });

  test('2. cacheKey + getKey round-trip', () => {
    cacheKey('cert-1', new Uint8Array([1, 2, 3]));
    expect(getKey('cert-1')).toEqual(new Uint8Array([1, 2, 3]));
  });

  test('3. setting one key does not mutate the prior atom snapshot', () => {
    cacheKey('cert-1', new Uint8Array([1]));
    const before = get(privateKeyCacheAtom);
    cacheKey('cert-2', new Uint8Array([2]));
    expect(before.has('cert-2')).toBe(false);
    expect(get(privateKeyCacheAtom).has('cert-2')).toBe(true);
  });

  test('4. clearKeyCache resets to empty', () => {
    cacheKey('cert-1', new Uint8Array([1]));
    clearKeyCache();
    expect(get(privateKeyCacheAtom).size).toBe(0);
  });
});

describe('resolvePrivateKey', () => {
  async function setup() {
    const adapter = new MemoryAdapter();
    const store = new CertChainStore(adapter);
    const kd = new KeyDerivationService();
    return { adapter, store, kd };
  }

  test('5. cache hit short-circuits the chain walk', async () => {
    const { store, kd } = await setup();
    cacheKey('cached-cert', new Uint8Array([99]));
    const out = await resolvePrivateKey(store, kd, 'cached-cert');
    expect(out).toEqual(new Uint8Array([99]));
  });

  test('6. throws CERT_NOT_FOUND when the cert is missing', async () => {
    const { store, kd } = await setup();
    await expect(resolvePrivateKey(store, kd, 'missing')).rejects.toThrow(
      /Cannot resolve key/,
    );
  });

  test('7. re-derives a root key from email when the cache is cold', async () => {
    const { store, kd } = await setup();
    const rootKey = kd.generateRootKey('alice@example.com');
    const certId = kd.generateCertId(rootKey);
    const publicKey = kd.generatePublicKey(rootKey);
    await store.put(certId, {
      certId,
      email: 'alice@example.com',
      publicKey,
      domainFlags: [],
      capabilityToken: '',
      created: Date.now(),
      revoked: false,
    });

    const resolved = await resolvePrivateKey(store, kd, certId);
    expect(resolved).toEqual(rootKey);
    expect(getKey(certId)).toEqual(rootKey); // populated the cache
  });
});

```
