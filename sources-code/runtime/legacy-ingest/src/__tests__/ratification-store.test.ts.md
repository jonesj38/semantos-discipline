---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/ratification-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.152378+00:00
---

# runtime/legacy-ingest/src/__tests__/ratification-store.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { ReceiptStore, CorrectionEdgeStore } from '../ratification/store';
import { GrantStoreCorrupt, GrantStoreLocked, type GrantPersistence } from '../grant-store';
import type { CorrectionEdge, RatificationReceipt } from '../ratification/types';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

function makeReceipt(over: Partial<RatificationReceipt> = {}): RatificationReceipt {
  return {
    receiptId: 'r1', proposalId: 'p1', providerId: 'gmail', providerItemId: 'm1',
    issuedAt: '2026-04-28T00:00:00Z',
    signedBy: { hatId: 'hat-1', certId: 'cert-1' },
    cellId: null, hadCorrection: false,
    ...over,
  };
}

function makeCorrection(over: Partial<CorrectionEdge> = {}): CorrectionEdge {
  return {
    correctionId: 'c1', proposalId: 'p1', providerId: 'gmail',
    original: { primaryNodeId: '$s0', nodes: [], programGovernance: {} as any } as any,
    corrected: { primaryNodeId: '$s0', nodes: [], programGovernance: {} as any } as any,
    reason: null,
    source: { extractorVersion: 'v1', promptHash: 'h1' },
    createdAt: '2026-04-28T00:00:00Z', pinned: false,
    ...over,
  };
}

describe('ReceiptStore', () => {
  let persistence: MemoryPersistence;
  let store: ReceiptStore;

  beforeEach(async () => {
    persistence = new MemoryPersistence();
    const kek = await makeKek();
    store = new ReceiptStore({ persistence, kekProvider: async () => kek });
  });

  test('round-trip preserves receipt', async () => {
    await store.put(makeReceipt());
    const got = await store.get('gmail', 'r1');
    expect(got?.proposalId).toBe('p1');
    expect(got?.signedBy.hatId).toBe('hat-1');
  });

  test('list across providers + scoped', async () => {
    await store.put(makeReceipt({ receiptId: 'r1', providerId: 'gmail' }));
    await store.put(makeReceipt({ receiptId: 'r2', providerId: 'meta' }));
    expect((await store.list()).length).toBe(2);
    expect((await store.list('gmail')).length).toBe(1);
  });

  test('on-disk bytes are encrypted', async () => {
    await store.put(makeReceipt({ proposalId: 'SECRET-EXAMPLE' }));
    const blob = [...persistence.store.values()][0];
    const text = new TextDecoder('utf-8', { fatal: false }).decode(blob);
    expect(text).not.toContain('SECRET-EXAMPLE');
  });

  test('locked store throws GrantStoreLocked', async () => {
    const locked = new ReceiptStore({
      persistence: new MemoryPersistence(), kekProvider: async () => null,
    });
    await expect(locked.put(makeReceipt())).rejects.toThrow(GrantStoreLocked);
  });

  test('tampered receipt fails closed', async () => {
    await store.put(makeReceipt());
    const [k, blob] = [...persistence.store.entries()][0];
    blob[40] ^= 0xff;
    persistence.store.set(k, blob);
    await expect(store.get('gmail', 'r1')).rejects.toThrow(GrantStoreCorrupt);
  });
});

describe('CorrectionEdgeStore', () => {
  let store: CorrectionEdgeStore;

  beforeEach(async () => {
    const kek = await makeKek();
    store = new CorrectionEdgeStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => kek,
    });
  });

  test('round-trip preserves correction', async () => {
    await store.put(makeCorrection({ reason: 'wrong intent' }));
    const got = await store.get('gmail', 'c1');
    expect(got?.reason).toBe('wrong intent');
  });

  test('pin / unpin toggle', async () => {
    await store.put(makeCorrection({ correctionId: 'c1' }));
    expect(await store.pin('gmail', 'c1')).toBe(true);
    expect((await store.get('gmail', 'c1'))?.pinned).toBe(true);
    expect(await store.unpin('gmail', 'c1')).toBe(true);
    expect((await store.get('gmail', 'c1'))?.pinned).toBe(false);
    expect(await store.pin('gmail', 'no-such')).toBe(false);
  });

  test('delete removes the correction', async () => {
    await store.put(makeCorrection());
    await store.delete('gmail', 'c1');
    expect(await store.get('gmail', 'c1')).toBeNull();
  });
});

```
