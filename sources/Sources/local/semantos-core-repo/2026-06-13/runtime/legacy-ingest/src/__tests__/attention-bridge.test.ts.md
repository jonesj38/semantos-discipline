---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/attention-bridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.141231+00:00
---

# runtime/legacy-ingest/src/__tests__/attention-bridge.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { ProposalStore } from '../proposal-store';
import { AttentionBridge, type LegacyIngestSignalProposal } from '../ratification/attention-bridge';
import type { GrantPersistence } from '../grant-store';
import type { Proposal } from '../extractor/types';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

async function makeStore(): Promise<ProposalStore> {
  const kek = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  return new ProposalStore({ persistence: new MemoryPersistence(), kekProvider: async () => kek });
}

function makeProposal(over: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: 'p1', confidence: 0.7, status: 'pending',
    provenance: {
      providerId: 'gmail', providerItemId: 'm1',
      fetchedAt: 0, extractorVersion: 'v1', promptHash: 'h1',
    },
    extractedAt: 1234,
    program: {} as any,
    summary: 'summary',
    ...over,
  };
}

describe('AttentionBridge', () => {
  let store: ProposalStore;
  let bridge: AttentionBridge;
  let received: LegacyIngestSignalProposal[];

  beforeEach(async () => {
    store = await makeStore();
    // Long pollIntervalMs so internal start() doesn't auto-tick during test windows.
    bridge = new AttentionBridge({ store, pollIntervalMs: 1_000_000 });
    received = [];
  });

  test('emits one signal per pending proposal on tick', async () => {
    await store.put(makeProposal({ proposalId: 'a' }));
    await store.put(makeProposal({ proposalId: 'b', confidence: 0.95 }));
    bridge.subscribe(p => received.push(p));
    await bridge.tick();
    expect(received.length).toBe(2);
    expect(received.map(r => r.id).sort()).toEqual(['a', 'b']);
  });

  test('skips non-pending proposals', async () => {
    await store.put(makeProposal({ proposalId: 'a', status: 'pending' }));
    await store.put(makeProposal({ proposalId: 'b', status: 'ratified' }));
    bridge.subscribe(p => received.push(p));
    await bridge.tick();
    expect(received.map(r => r.id)).toEqual(['a']);
  });

  test('dedup: re-tick does not re-emit already-seen proposals', async () => {
    await store.put(makeProposal({ proposalId: 'a' }));
    bridge.subscribe(p => received.push(p));
    await bridge.tick();
    await bridge.tick();
    expect(received.length).toBe(1);
  });

  test('forget() drops dedup memory so the next tick re-emits', async () => {
    await store.put(makeProposal({ proposalId: 'a' }));
    bridge.subscribe(p => received.push(p));
    await bridge.tick();
    bridge.forget('a');
    await bridge.tick();
    expect(received.length).toBe(2);
  });

  test('multiple subscribers all receive each proposal', async () => {
    await store.put(makeProposal({ proposalId: 'a' }));
    bridge.subscribe(p => received.push({ ...p, summary: '1:' + p.summary }));
    bridge.subscribe(p => received.push({ ...p, summary: '2:' + p.summary }));
    await bridge.tick();
    expect(received.length).toBe(2);
    expect(received.map(r => r.summary).sort()).toEqual(['1:summary', '2:summary']);
  });

  test('subscriber error does not break sibling subscribers', async () => {
    await store.put(makeProposal({ proposalId: 'a' }));
    bridge.subscribe(() => { throw new Error('boom'); });
    bridge.subscribe(p => received.push(p));
    await bridge.tick();
    expect(received.length).toBe(1);
  });
});

```
