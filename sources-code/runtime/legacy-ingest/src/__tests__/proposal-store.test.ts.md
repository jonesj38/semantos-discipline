---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/proposal-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.147537+00:00
---

# runtime/legacy-ingest/src/__tests__/proposal-store.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { ProposalStore } from '../proposal-store';
import { GrantStoreCorrupt, GrantStoreLocked, type GrantPersistence } from '../grant-store';
import type { Proposal } from '../extractor/types';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

function makeProposal(over: Partial<Proposal>): Proposal {
  return {
    proposalId: 'p1',
    confidence: 0.7,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'm1',
      fetchedAt: 0,
      extractorVersion: 'v1',
      promptHash: 'h1',
    },
    extractedAt: 0,
    program: { primaryNodeId: '$s0', nodes: [], programGovernance: {} as any } as any,
    summary: 'sum',
    ...over,
  };
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

describe('ProposalStore', () => {
  let persistence: MemoryPersistence;
  let store: ProposalStore;

  beforeEach(async () => {
    persistence = new MemoryPersistence();
    const kek = await makeKek();
    store = new ProposalStore({ persistence, kekProvider: async () => kek });
  });

  test('round-trip preserves proposal', async () => {
    await store.put(makeProposal({ proposalId: 'p1' }));
    const got = await store.get('gmail', 'p1');
    expect(got?.proposalId).toBe('p1');
    expect(got?.confidence).toBe(0.7);
  });

  test('on-disk bytes are encrypted', async () => {
    await store.put(makeProposal({ summary: 'SECRET-EXAMPLE' }));
    const blob = [...persistence.store.values()][0];
    const text = new TextDecoder('utf-8', { fatal: false }).decode(blob);
    expect(text).not.toContain('SECRET-EXAMPLE');
  });

  test('list filters by status', async () => {
    await store.put(makeProposal({ proposalId: 'a', status: 'pending' }));
    await store.put(makeProposal({ proposalId: 'b', status: 'ratified' }));
    await store.put(makeProposal({ proposalId: 'c', status: 'rejected' }));
    const pending = await store.list({ status: 'pending' });
    expect(pending.length).toBe(1);
    expect(pending[0].proposalId).toBe('a');
    const open = await store.list({ status: ['pending', 'ratified'] });
    expect(open.length).toBe(2);
  });

  test('list filters by confidence range', async () => {
    await store.put(makeProposal({ proposalId: 'a', confidence: 0.3 }));
    await store.put(makeProposal({ proposalId: 'b', confidence: 0.6 }));
    await store.put(makeProposal({ proposalId: 'c', confidence: 0.9 }));
    const high = await store.list({ minConfidence: 0.7 });
    expect(high.map(p => p.proposalId)).toEqual(['c']);
    const lowMid = await store.list({ maxConfidence: 0.7 });
    expect(lowMid.map(p => p.proposalId).sort()).toEqual(['a', 'b']);
  });

  test('list across providers without filter', async () => {
    await store.put(makeProposal({
      proposalId: 'a',
      provenance: { providerId: 'gmail', providerItemId: 'i1', fetchedAt: 0, extractorVersion: 'v1', promptHash: 'h' },
    }));
    await store.put(makeProposal({
      proposalId: 'b',
      provenance: { providerId: 'meta', providerItemId: 'i2', fetchedAt: 0, extractorVersion: 'v1', promptHash: 'h' },
    }));
    const all = await store.list();
    expect(all.length).toBe(2);
  });

  test('updateStatus mutates in bulk', async () => {
    const a = makeProposal({ proposalId: 'a' });
    const b = makeProposal({ proposalId: 'b' });
    await store.put(a);
    await store.put(b);
    const n = await store.updateStatus([a, b], 'superseded');
    expect(n).toBe(2);
    expect((await store.get('gmail', 'a'))?.status).toBe('superseded');
  });

  test('locked store throws GrantStoreLocked', async () => {
    const locked = new ProposalStore({
      persistence: new MemoryPersistence(),
      kekProvider: async () => null,
    });
    await expect(locked.put(makeProposal({}))).rejects.toThrow(GrantStoreLocked);
  });

  test('tampered ciphertext fails closed', async () => {
    await store.put(makeProposal({}));
    const [k, blob] = [...persistence.store.entries()][0];
    blob[40] ^= 0xff;
    persistence.store.set(k, blob);
    await expect(store.get('gmail', 'p1')).rejects.toThrow(GrantStoreCorrupt);
  });
});

```
