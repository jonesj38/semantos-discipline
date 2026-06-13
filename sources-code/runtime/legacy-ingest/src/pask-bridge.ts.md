---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/pask-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.133313+00:00
---

# runtime/legacy-ingest/src/pask-bridge.ts

```ts
/**
 * Ingest Pask bridge — emits ingest:* cells into the Pask constraint
 * graph as proposals move through the pipeline.
 *
 * Cell-ID namespace (extends PaskGraph.ts §DB1 convention):
 *   ingest:proposal:<proposal-id>         — the specific proposal
 *   ingest:customer:<email-hash>          — de-identified customer cell
 *   ingest:type:<intent>                  — intent category cell
 *   ingest:source:<provider-id>           — ingest origin cell
 *
 * Interaction strengths mirror the attentionSignals convention:
 *   seed       → 0.1  (initial discovery on proposal creation)
 *   tapped     → 0.5  (correction = engaged but not fully accepted)
 *   acted-on   → 3.0  (ratification = operator accepted the proposal)
 *   dismissed  → -1.0 (rejection = operator explicitly rejected)
 */

import type { Proposal } from './extractor/types';
import type { RatificationReceipt } from './ratification/types';
import type { OddjobzMessagePatch } from './conversation/turn-patch-store';

/** Minimal interact surface from PaskGraph — avoids hard import of the class. */
export interface PaskInteractFn {
  interact(args: {
    cellId: string;
    kind: string;
    strength: number;
    relatedCells?: string[];
    nowMs?: number;
  }): void;
}

const CELL_ID_MAX = 63;

function trimCell(id: string): string {
  if (id.length <= CELL_ID_MAX) return id;
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (Math.imul(31, h) + id.charCodeAt(i)) | 0;
  return `${id.slice(0, 48)}#${Math.abs(h).toString(16).padStart(8, '0').slice(0, 8)}`;
}

/** Stable, non-reversible hash of a customer email address for the cell ID. */
function hashCustomer(emailOrName: string): string {
  const s = emailOrName.trim().toLowerCase();
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h) + s.charCodeAt(i);
    h = h | 0;
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

/**
 * Extract the customer identifier from a proposal's SIRProgram.
 * Falls back to the provider-item-id if no customer target is present.
 */
function customerToken(proposal: Proposal): string {
  const target = proposal.program.nodes?.[0]?.target;
  if (target && typeof target === 'object' && 'id' in target && typeof target.id === 'string') {
    return hashCustomer(target.id);
  }
  return hashCustomer(proposal.provenance.providerItemId);
}

/** Derive the intent / type from the SIRProgram's primary action. */
function proposalType(proposal: Proposal): string {
  const action = proposal.program.nodes?.[0]?.action ?? 'unknown';
  // map action strings back to clean type labels
  return action
    .replace(/^create_/, '')
    .replace(/^log_/, '')
    .replace(/^attach_/, '')
    || 'unknown';
}

function proposalCellIds(proposal: Proposal): {
  proposalCell: string;
  customerCell: string;
  typeCell: string;
  sourceCell: string;
} {
  return {
    proposalCell: trimCell(`ingest:proposal:${proposal.proposalId}`),
    customerCell: trimCell(`ingest:customer:${customerToken(proposal)}`),
    typeCell:     trimCell(`ingest:type:${proposalType(proposal)}`),
    sourceCell:   trimCell(`ingest:source:${proposal.provenance.providerId}`),
  };
}

function messageCellIds(patch: OddjobzMessagePatch): {
  messageCell: string;
  sessionCell: string;
  participantCell: string;
  channelCell: string;
  sourceCell: string;
} {
  return {
    messageCell: trimCell(`ingest:message:${patch.patchId}`),
    sessionCell: trimCell(`ingest:session:${patch.sessionId}`),
    participantCell: trimCell(`ingest:participant:${hashCustomer(patch.recipientId)}`),
    channelCell: trimCell(`ingest:channel:${patch.channel}`),
    sourceCell: trimCell(`ingest:source:${patch.providerId}`),
  };
}

export class IngestPaskBridge {
  constructor(private readonly pask: PaskInteractFn) {}

  /**
   * Call when a Meta/widget/email turn is persisted into the unified
   * oddjobz.message.v1 trail. This seeds the raw conversation topology before
   * extraction/ratification resolves the turn onto a job/site/customer graph.
   */
  onMessagePatch(patch: OddjobzMessagePatch): void {
    const {
      messageCell,
      sessionCell,
      participantCell,
      channelCell,
      sourceCell,
    } = messageCellIds(patch);
    this.pask.interact({
      cellId: messageCell,
      kind: 'seed',
      strength: 0.05,
      relatedCells: [sessionCell, participantCell, channelCell, sourceCell],
      nowMs: patch.timestamp,
    });
  }

  /**
   * Call when a proposal is first created by the extraction runner.
   * Seeds the proposal cell and its customer/type/source relationships.
   */
  onProposalCreated(proposal: Proposal): void {
    const { proposalCell, customerCell, typeCell, sourceCell } = proposalCellIds(proposal);
    this.pask.interact({
      cellId: proposalCell,
      kind: 'seed',
      strength: 0.1,
      relatedCells: [customerCell, typeCell, sourceCell],
      nowMs: proposal.extractedAt,
    });
  }

  /**
   * Call after an operator ratifies a proposal (accept or auto-ratify).
   * Strong positive signal on the proposal and its related type/customer cells.
   */
  onRatified(proposal: Proposal, _receipt: RatificationReceipt): void {
    const { proposalCell, customerCell, typeCell, sourceCell } = proposalCellIds(proposal);
    const nowMs = Date.now();
    this.pask.interact({
      cellId: proposalCell,
      kind: 'acted-on',
      strength: 3.0,
      relatedCells: [customerCell, typeCell, sourceCell],
      nowMs,
    });
    // Reinforce the type and customer cells directly so future proposals
    // from the same customer/type profile accumulate h-state.
    this.pask.interact({
      cellId: customerCell,
      kind: 'acted-on',
      strength: 1.5,
      relatedCells: [typeCell],
      nowMs,
    });
    this.pask.interact({
      cellId: typeCell,
      kind: 'acted-on',
      strength: 1.0,
      relatedCells: [sourceCell],
      nowMs,
    });
  }

  /**
   * Call when an operator explicitly rejects a proposal.
   * Negative signal — these customer+type combinations should surface less
   * aggressively in future auto-ratify decisions.
   */
  onRejected(proposal: Proposal): void {
    const { proposalCell, customerCell, typeCell } = proposalCellIds(proposal);
    const nowMs = Date.now();
    this.pask.interact({
      cellId: proposalCell,
      kind: 'dismissed',
      strength: -1.0,
      relatedCells: [customerCell, typeCell],
      nowMs,
    });
  }

  /**
   * Call when an operator corrects a proposal before ratifying it.
   * Moderate positive signal: the operator engaged but the extraction was
   * imperfect. The correction content is captured separately by the
   * few-shot store; Pask records the engagement strength.
   */
  onCorrected(proposal: Proposal): void {
    const { proposalCell, customerCell, typeCell } = proposalCellIds(proposal);
    const nowMs = Date.now();
    this.pask.interact({
      cellId: proposalCell,
      kind: 'tapped',
      strength: 0.5,
      relatedCells: [customerCell, typeCell],
      nowMs,
    });
  }
}

```
