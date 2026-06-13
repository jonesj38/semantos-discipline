---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/pask-bridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.140494+00:00
---

# runtime/legacy-ingest/src/__tests__/pask-bridge.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { IngestPaskBridge, type PaskInteractFn } from '../pask-bridge';
import type { Proposal } from '../extractor/types';
import type { RatificationReceipt } from '../ratification/types';
import type { OddjobzMessagePatch } from '../conversation/turn-patch-store';

function makeProposal(overrides: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: 'prop-001',
    confidence: 0.82,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'msg-abc123',
      fetchedAt: 1_700_000_000_000,
      extractorVersion: 'email-rfc822-v0.2',
      promptHash: 'h1234abcd',
    },
    extractedAt: 1_700_000_001_000,
    program: {
      primaryNodeId: '$s0',
      programGovernance: {} as any,
      nodes: [
        {
          id: '$s0',
          category: {} as any,
          taxonomy: {} as any,
          identity: {} as any,
          governance: {} as any,
          action: 'create_quote_request',
          constraint: {} as any,
          target: { kind: 'identity', id: 'alice@example.com' } as any,
          provenance: {
            source: 'inferred',
            confidence: 0.82,
            inferenceRunId: 'msg-abc123',
            expressedAt: '2024-01-01T00:00:00.000Z',
            trustAtExpression: 'cosmetic',
          },
        },
      ],
    },
    summary: 'Quote request for fence installation',
    ...overrides,
  };
}

function makeReceipt(overrides: Partial<RatificationReceipt> = {}): RatificationReceipt {
  return {
    receiptId: 'receipt-001',
    proposalId: 'prop-001',
    providerId: 'gmail',
    providerItemId: 'msg-abc123',
    issuedAt: '2024-01-01T00:00:00.000Z',
    signedBy: { hatId: 'hat-1', certId: null },
    cellId: 'cell-001',
    hadCorrection: false,
    ...overrides,
  };
}

function makeMessagePatch(overrides: Partial<OddjobzMessagePatch> = {}): OddjobzMessagePatch {
  return {
    schema: 'oddjobz.message.v1',
    patchId: 'msg_0011223344556677',
    op: 'oddjobz.message.v1',
    providerId: 'gmail',
    sessionId: 'email:thread-1',
    channel: 'email',
    recipientId: 'alice@example.com',
    role: 'customer',
    text: 'Need a fence fixed',
    timestamp: 1_700_000_000_000,
    writtenAt: 1_700_000_000_111,
    target: {
      type: 'conversation-session',
      ref: 'email:thread-1',
    },
    ...overrides,
  };
}

describe('IngestPaskBridge', () => {
  it('onMessagePatch seeds message topology before proposal extraction', () => {
    const calls: Parameters<PaskInteractFn['interact']>[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push([args]) };
    const bridge = new IngestPaskBridge(pask);

    bridge.onMessagePatch(makeMessagePatch());

    expect(calls).toHaveLength(1);
    const [args] = calls[0];
    expect(args.cellId).toBe('ingest:message:msg_0011223344556677');
    expect(args.kind).toBe('seed');
    expect(args.strength).toBe(0.05);
    expect(args.nowMs).toBe(1_700_000_000_000);
    expect(args.relatedCells).toContain('ingest:session:email:thread-1');
    expect(args.relatedCells).toContain('ingest:channel:email');
    expect(args.relatedCells).toContain('ingest:source:gmail');
    expect(args.relatedCells!.some((cell) => cell.startsWith('ingest:participant:'))).toBe(true);
  });

  it('onProposalCreated emits a seed interaction on the proposal cell', () => {
    const calls: Parameters<PaskInteractFn['interact']>[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push([args]) };
    const bridge = new IngestPaskBridge(pask);

    bridge.onProposalCreated(makeProposal());

    expect(calls).toHaveLength(1);
    const [args] = calls[0];
    expect(args.cellId).toMatch(/^ingest:proposal:prop-001$/);
    expect(args.kind).toBe('seed');
    expect(args.strength).toBe(0.1);
    expect(args.relatedCells).toBeDefined();
    expect(args.relatedCells!.some(c => c.startsWith('ingest:customer:'))).toBe(true);
    expect(args.relatedCells!.some(c => c.startsWith('ingest:type:'))).toBe(true);
    expect(args.relatedCells!.some(c => c.startsWith('ingest:source:'))).toBe(true);
  });

  it('onProposalCreated sets nowMs to proposal.extractedAt', () => {
    const calls: unknown[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push(args) };
    const bridge = new IngestPaskBridge(pask);
    const proposal = makeProposal({ extractedAt: 1_700_000_999 });
    bridge.onProposalCreated(proposal);
    const args = calls[0] as { nowMs: number };
    expect(args.nowMs).toBe(1_700_000_999);
  });

  it('onRatified emits acted-on interactions on proposal + customer + type cells', () => {
    const calls: unknown[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push(args) };
    const bridge = new IngestPaskBridge(pask);

    bridge.onRatified(makeProposal(), makeReceipt());

    // Should emit 3 interactions: proposal, customer, type
    expect((calls as unknown[]).length).toBe(3);
    const first = calls[0] as { cellId: string; kind: string; strength: number };
    expect(first.cellId).toMatch(/^ingest:proposal:/);
    expect(first.kind).toBe('acted-on');
    expect(first.strength).toBe(3.0);
  });

  it('onRejected emits dismissed on proposal cell', () => {
    const calls: unknown[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push(args) };
    const bridge = new IngestPaskBridge(pask);

    bridge.onRejected(makeProposal());

    expect(calls).toHaveLength(1);
    const args = calls[0] as { kind: string; strength: number };
    expect(args.kind).toBe('dismissed');
    expect(args.strength).toBe(-1.0);
  });

  it('onCorrected emits tapped on proposal cell with moderate strength', () => {
    const calls: unknown[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push(args) };
    const bridge = new IngestPaskBridge(pask);

    bridge.onCorrected(makeProposal());

    expect(calls).toHaveLength(1);
    const args = calls[0] as { kind: string; strength: number };
    expect(args.kind).toBe('tapped');
    expect(args.strength).toBe(0.5);
  });

  it('derives customer cell from target.id in SIRProgram', () => {
    const calls: unknown[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push(args) };
    const bridge = new IngestPaskBridge(pask);
    bridge.onProposalCreated(makeProposal());

    const args = calls[0] as { relatedCells: string[] };
    const customerCell = args.relatedCells.find(c => c.startsWith('ingest:customer:'));
    expect(customerCell).toBeDefined();
    // Same email address should always produce the same cell ID
    const calls2: unknown[] = [];
    const bridge2 = new IngestPaskBridge({ interact: (a) => calls2.push(a) });
    bridge2.onProposalCreated(makeProposal());
    const args2 = calls2[0] as { relatedCells: string[] };
    const customerCell2 = args2.relatedCells.find(c => c.startsWith('ingest:customer:'));
    expect(customerCell).toBe(customerCell2);
  });

  it('maps action to type cell: create_quote_request → ingest:type:quote_request', () => {
    const calls: unknown[] = [];
    const pask: PaskInteractFn = { interact: (args) => calls.push(args) };
    const bridge = new IngestPaskBridge(pask);
    bridge.onProposalCreated(makeProposal());
    const args = calls[0] as { relatedCells: string[] };
    const typeCell = args.relatedCells.find(c => c.startsWith('ingest:type:'));
    expect(typeCell).toBe('ingest:type:quote_request');
  });

  it('truncates long cell IDs to within 63 bytes', () => {
    const cells: string[] = [];
    const pask: PaskInteractFn = {
      interact: (args) => {
        cells.push(args.cellId);
        (args.relatedCells ?? []).forEach(c => cells.push(c));
      },
    };
    const bridge = new IngestPaskBridge(pask);
    const longId = 'x'.repeat(200);
    bridge.onProposalCreated(makeProposal({ proposalId: longId }));
    for (const cell of cells) {
      expect(cell.length).toBeLessThanOrEqual(63);
    }
  });
});

```
