---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/thread.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.143143+00:00
---

# runtime/legacy-ingest/src/__tests__/thread.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { collapseThreads, deduplicateByReferenceNumber } from '../extractor/thread';
import type { Proposal } from '../extractor/types';

function makeProposal(over: Partial<Proposal>): Proposal {
  return {
    proposalId: 'p',
    confidence: 0.5,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'm',
      fetchedAt: 0,
      extractorVersion: 'v1',
      promptHash: 'h',
    },
    extractedAt: 0,
    program: {} as any,
    summary: 'p',
    ...over,
  };
}

describe('collapseThreads', () => {
  test('standalone proposals pass through unchanged', () => {
    const a = makeProposal({ proposalId: 'a' });
    const b = makeProposal({ proposalId: 'b' });
    const r = collapseThreads([a, b]);
    expect(r.proposals.length).toBe(2);
    expect(r.foldedProposalIds).toEqual([]);
  });

  test('proposals sharing a thread key fold to highest-confidence primary', () => {
    const a = makeProposal({ proposalId: 'a', threadKey: 't1', confidence: 0.6 });
    const b = makeProposal({ proposalId: 'b', threadKey: 't1', confidence: 0.9 });
    const c = makeProposal({ proposalId: 'c', threadKey: 't1', confidence: 0.4 });
    const r = collapseThreads([a, b, c]);
    expect(r.proposals.length).toBe(1);
    const [primary] = r.proposals;
    expect(primary.proposalId).toBe('b');
    expect(primary.siblingProposalIds?.sort()).toEqual(['a', 'c']);
    expect(r.foldedProposalIds.sort()).toEqual(['a', 'c']);
    expect(primary.summary).toMatch(/\+2 messages in thread/);
  });

  test('mixed: thread + standalone', () => {
    const a = makeProposal({ proposalId: 'a', threadKey: 't1', confidence: 0.9 });
    const b = makeProposal({ proposalId: 'b', threadKey: 't1', confidence: 0.6 });
    const c = makeProposal({ proposalId: 'c' });
    const r = collapseThreads([a, b, c]);
    expect(r.proposals.length).toBe(2);
    const ids = r.proposals.map(p => p.proposalId).sort();
    expect(ids).toEqual(['a', 'c']);
    expect(r.foldedProposalIds).toEqual(['b']);
  });

  test('thread of 1 leaves the proposal alone (no sibling list)', () => {
    const a = makeProposal({ proposalId: 'a', threadKey: 't1' });
    const r = collapseThreads([a]);
    expect(r.proposals.length).toBe(1);
    expect(r.proposals[0].siblingProposalIds).toBeUndefined();
    expect(r.foldedProposalIds).toEqual([]);
  });
});

describe('deduplicateByReferenceNumber', () => {
  test('proposals without referenceNumber pass through unchanged', () => {
    const a = makeProposal({ proposalId: 'a' });
    const b = makeProposal({ proposalId: 'b' });
    const r = deduplicateByReferenceNumber([a, b]);
    expect(r.proposals.length).toBe(2);
    expect(r.mergedProposalIds).toEqual([]);
  });

  test('proposals sharing a referenceNumber fold to highest-confidence primary', () => {
    const a = makeProposal({ proposalId: 'a', referenceNumber: 'PM-1001', confidence: 0.7 });
    const b = makeProposal({ proposalId: 'b', referenceNumber: 'PM-1001', confidence: 0.9 });
    const c = makeProposal({ proposalId: 'c', referenceNumber: 'PM-1001', confidence: 0.5 });
    const r = deduplicateByReferenceNumber([a, b, c]);
    expect(r.proposals.length).toBe(1);
    const [primary] = r.proposals;
    expect(primary.proposalId).toBe('b');
    expect(primary.siblingProposalIds?.sort()).toEqual(['a', 'c']);
    expect(r.mergedProposalIds.sort()).toEqual(['a', 'c']);
    expect(primary.summary).toMatch(/\+2 scope updates for same reference/);
  });

  test('different referenceNumbers produce separate primaries', () => {
    const a = makeProposal({ proposalId: 'a', referenceNumber: 'PM-1001', confidence: 0.8 });
    const b = makeProposal({ proposalId: 'b', referenceNumber: 'PM-1002', confidence: 0.8 });
    const r = deduplicateByReferenceNumber([a, b]);
    expect(r.proposals.length).toBe(2);
    expect(r.mergedProposalIds).toEqual([]);
  });

  test('single proposal with referenceNumber passes through unchanged', () => {
    const a = makeProposal({ proposalId: 'a', referenceNumber: 'BA-555' });
    const r = deduplicateByReferenceNumber([a]);
    expect(r.proposals.length).toBe(1);
    expect(r.proposals[0].siblingProposalIds).toBeUndefined();
    expect(r.mergedProposalIds).toEqual([]);
  });

  test('preserves existing siblingProposalIds from thread collapse', () => {
    // Simulate a proposal already folded by collapseThreads
    const a = makeProposal({
      proposalId: 'a',
      referenceNumber: 'PM-2000',
      confidence: 0.9,
      siblingProposalIds: ['thread-sibling-1'],
    });
    const b = makeProposal({
      proposalId: 'b',
      referenceNumber: 'PM-2000',
      confidence: 0.6,
    });
    const r = deduplicateByReferenceNumber([a, b]);
    expect(r.proposals[0].siblingProposalIds?.sort()).toEqual(['b', 'thread-sibling-1']);
  });
});

```
