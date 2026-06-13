---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/__tests__/subtree-querier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.918109+00:00
---

# core/protocol-types/src/identity-adapters/local/__tests__/subtree-querier.test.ts

```ts
/**
 * Subtree query tests.
 */

import { describe, expect, test } from 'bun:test';
import { CertChainStore } from '../cert-chain-store-facade';
import { MemoryAdapter } from '../../../adapters/memory-adapter';
import { querySubtree } from '../subtree-querier';

async function seedTree(): Promise<CertChainStore> {
  const adapter = new MemoryAdapter();
  const store = new CertChainStore(adapter);

  // Root + 2 children + 2 grandchildren under the first child.
  const now = Date.now();
  const cert = (
    certId: string,
    overrides: { parentCertId?: string; childIndex?: number; resourceId?: string } = {},
  ) => ({
    certId,
    publicKey: `pem-${certId}`,
    domainFlags: [],
    capabilityToken: '',
    created: now,
    revoked: false,
    ...overrides,
  });
  await store.put('root', cert('root'));
  await store.put('child-a', cert('child-a', { parentCertId: 'root', childIndex: 0, resourceId: 'a' }));
  await store.put('child-b', cert('child-b', { parentCertId: 'root', childIndex: 1, resourceId: 'b' }));
  await store.put('gc-a1', cert('gc-a1', { parentCertId: 'child-a', childIndex: 0, resourceId: 'a1' }));
  await store.put('gc-a2', cert('gc-a2', { parentCertId: 'child-a', childIndex: 1, resourceId: 'a2' }));
  return store;
}

describe('querySubtree', () => {
  test('1. depth=1 returns direct children only', async () => {
    const store = await seedTree();
    const out = await querySubtree(store, 'root', 1);
    expect(out.root).toBe('root');
    expect(out.children.map((c) => c.certId).sort()).toEqual(['child-a', 'child-b']);
    expect(out.children.every((c) => c.grandchildren === undefined)).toBe(true);
  });

  test('2. depth=2 expands grandchildren under the first level', async () => {
    const store = await seedTree();
    const out = await querySubtree(store, 'root', 2);
    const a = out.children.find((c) => c.certId === 'child-a');
    expect(a?.grandchildren?.map((gc) => gc.certId).sort()).toEqual(['gc-a1', 'gc-a2']);
  });

  test('3. childIndex + resourceId are forwarded verbatim', async () => {
    const store = await seedTree();
    const out = await querySubtree(store, 'root', 1);
    const a = out.children.find((c) => c.certId === 'child-a');
    expect(a?.childIndex).toBe(0);
    expect(a?.resourceId).toBe('a');
  });

  test('4. missing root throws', async () => {
    const store = await seedTree();
    await expect(querySubtree(store, 'never', 1)).rejects.toThrow();
  });

  test('5. leaf root returns empty children', async () => {
    const store = await seedTree();
    const out = await querySubtree(store, 'gc-a1', 1);
    expect(out.children).toEqual([]);
  });
});

```
