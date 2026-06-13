---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/ratification-orchestrator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.142854+00:00
---

# runtime/legacy-ingest/src/__tests__/ratification-orchestrator.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { ProposalStore } from '../proposal-store';
import { ReceiptStore, CorrectionEdgeStore } from '../ratification/store';
import {
  RatificationOrchestrator,
  RatificationError,
  type CellWriterFn,
} from '../ratification/orchestrator';
import type { GrantPersistence } from '../grant-store';
import type { Proposal } from '../extractor/types';
import type { SIRProgram } from '@semantos/semantos-sir';

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

function makeProposal(over: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: 'p1', confidence: 0.8, status: 'pending',
    provenance: {
      providerId: 'gmail', providerItemId: 'm1',
      fetchedAt: 0, extractorVersion: 'v1', promptHash: 'h1',
    },
    extractedAt: 0,
    program: { primaryNodeId: '$s0', nodes: [], programGovernance: {} as any } as any,
    summary: 'Lead: Jane',
    ...over,
  };
}

const HAT = { hatId: 'hat-1', certId: 'cert-1' };
const NEW_PROGRAM: SIRProgram = { primaryNodeId: '$s0', nodes: [], programGovernance: {} as any } as any;

describe('RatificationOrchestrator', () => {
  let proposalStore: ProposalStore;
  let receiptStore: ReceiptStore;
  let correctionStore: CorrectionEdgeStore;
  let cellWrites: Array<{ proposalId: string }>;
  let writeCell: CellWriterFn;

  beforeEach(async () => {
    const persistence = new MemoryPersistence();
    const kek = await makeKek();
    proposalStore = new ProposalStore({ persistence, kekProvider: async () => kek });
    receiptStore = new ReceiptStore({ persistence, kekProvider: async () => kek });
    correctionStore = new CorrectionEdgeStore({ persistence, kekProvider: async () => kek });
    cellWrites = [];
    writeCell = async ({ proposal }) => {
      cellWrites.push({ proposalId: proposal.proposalId });
      return `cell-${proposal.proposalId}`;
    };
  });

  test('ratify writes receipt + flips status + writes cell via host', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1' }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => HAT, writeCell,
    });
    const r = await orch.ratify('gmail', 'p1');
    expect(r.cellId).toBe('cell-p1');
    expect(r.hadCorrection).toBe(false);
    expect(cellWrites.length).toBe(1);
    expect((await proposalStore.get('gmail', 'p1'))?.status).toBe('ratified');
  });

  test('ratify rejects non-pending proposal', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1', status: 'rejected' }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore, hatProvider: () => HAT,
    });
    await expect(orch.ratify('gmail', 'p1')).rejects.toThrow(RatificationError);
  });

  test('ratify requires an active hat', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1' }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore, hatProvider: () => null,
    });
    await expect(orch.ratify('gmail', 'p1')).rejects.toThrow(RatificationError);
  });

  test('correct produces a correction edge + ratifies + status=corrected', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1' }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => HAT, writeCell,
    });
    const r = await orch.correct('gmail', 'p1', NEW_PROGRAM, 'wrong intent');
    expect(r.receipt.hadCorrection).toBe(true);
    expect(r.correction.proposalId).toBe('p1');
    expect(r.correction.reason).toBe('wrong intent');
    expect((await proposalStore.get('gmail', 'p1'))?.status).toBe('corrected');
    expect((await correctionStore.list('gmail')).length).toBe(1);
  });

  test('reject flips status with reason and writes no receipt', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1' }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore, hatProvider: () => HAT,
    });
    const r = await orch.reject('gmail', 'p1', 'newsletter');
    expect(r.reason).toBe('newsletter');
    const after = await proposalStore.get('gmail', 'p1');
    expect(after?.status).toBe('rejected');
    expect(after?.rejectReason).toBe('newsletter');
    expect((await receiptStore.list('gmail')).length).toBe(0);
  });

  test('bulkRatify dry-run reports candidates without mutation', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'a', confidence: 0.9 }));
    await proposalStore.put(makeProposal({ proposalId: 'b', confidence: 0.95 }));
    await proposalStore.put(makeProposal({ proposalId: 'c', confidence: 0.4 }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => HAT, writeCell,
    });
    const dry = await orch.bulkRatify({ minConfidence: 0.85, dryRun: true });
    expect(dry.dryRun).toBe(true);
    expect(dry.proposed).toBe(2);
    expect(dry.ratified).toBe(0);
    expect((await proposalStore.get('gmail', 'a'))?.status).toBe('pending');
  });

  test('bulkRatify (live) ratifies matching proposals as auto-ratified', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'a', confidence: 0.9 }));
    await proposalStore.put(makeProposal({ proposalId: 'b', confidence: 0.95 }));
    await proposalStore.put(makeProposal({ proposalId: 'c', confidence: 0.4 }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => HAT, writeCell,
    });
    const live = await orch.bulkRatify({ minConfidence: 0.85 });
    expect(live.ratified).toBe(2);
    expect((await proposalStore.get('gmail', 'a'))?.status).toBe('auto-ratified');
    expect((await proposalStore.get('gmail', 'c'))?.status).toBe('pending');
  });

  test('unratify restores proposal to pending and asks host to withdraw cell', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1' }));
    let withdrawCalled = false;
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => HAT, writeCell,
      withdrawCell: async () => { withdrawCalled = true; return true; },
    });
    const receipt = await orch.ratify('gmail', 'p1');
    const r = await orch.unratify('gmail', receipt.receiptId);
    expect(r.withdrawn).toBe(true);
    expect(withdrawCalled).toBe(true);
    expect((await proposalStore.get('gmail', 'p1'))?.status).toBe('pending');
  });

  test('cell writer error surfaces as RatificationError', async () => {
    await proposalStore.put(makeProposal({ proposalId: 'p1' }));
    const orch = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => HAT,
      writeCell: async () => { throw new Error('disk full'); },
    });
    await expect(orch.ratify('gmail', 'p1')).rejects.toThrow(/cell-writer/);
  });
});

```
