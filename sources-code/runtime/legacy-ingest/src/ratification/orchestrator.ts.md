---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/ratification/orchestrator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.164214+00:00
---

# runtime/legacy-ingest/src/ratification/orchestrator.ts

```ts
/**
 * Ratification orchestrator — LI4.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI4.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import { audit } from '../audit';
import type { Proposal } from '../extractor/types';
import type { ProposalStore } from '../proposal-store';
import type { ReceiptStore, CorrectionEdgeStore } from './store';
import type {
  BulkRatifyOutcome,
  CorrectionEdge,
  ProposalRejection,
  RatificationReceipt,
} from './types';
import type { IngestPaskBridge } from '../pask-bridge';

export type CellWriterFn = (opts: {
  program: SIRProgram;
  proposal: Proposal;
}) => Promise<string | null>;

export type CellWithdrawFn = (cellId: string) => Promise<boolean>;

export interface RatificationOrchestratorOpts {
  proposalStore: ProposalStore;
  receiptStore: ReceiptStore;
  correctionStore: CorrectionEdgeStore;
  hatProvider: () => { hatId: string; certId: string | null } | null;
  writeCell?: CellWriterFn;
  withdrawCell?: CellWithdrawFn;
  now?: () => Date;
  generateId?: () => string;
  /** Optional Pask bridge — when present, ratification events feed the constraint graph. */
  paskBridge?: IngestPaskBridge;
}

export class RatificationError extends Error {
  constructor(message: string, readonly code: string) {
    super(message);
    this.name = 'RatificationError';
  }
}

export class RatificationOrchestrator {
  private readonly opts: RatificationOrchestratorOpts;

  constructor(opts: RatificationOrchestratorOpts) {
    this.opts = opts;
  }

  async ratify(providerId: string, proposalId: string): Promise<RatificationReceipt> {
    const proposal = await this.opts.proposalStore.get(providerId, proposalId);
    if (!proposal) throw new RatificationError(`proposal ${proposalId} not found`, 'not_found');
    if (proposal.status !== 'pending') {
      throw new RatificationError(
        `proposal ${proposalId} is ${proposal.status}, not pending`, 'wrong_status',
      );
    }
    return this.completeRatification(proposal, proposal.program, false);
  }

  async correct(
    providerId: string,
    proposalId: string,
    correctedProgram: SIRProgram,
    reason: string | null = null,
  ): Promise<{ receipt: RatificationReceipt; correction: CorrectionEdge }> {
    const proposal = await this.opts.proposalStore.get(providerId, proposalId);
    if (!proposal) throw new RatificationError(`proposal ${proposalId} not found`, 'not_found');
    if (proposal.status !== 'pending') {
      throw new RatificationError(
        `proposal ${proposalId} is ${proposal.status}, not pending`, 'wrong_status',
      );
    }
    const correction: CorrectionEdge = {
      correctionId: this.id(),
      proposalId: proposal.proposalId,
      providerId: proposal.provenance.providerId,
      original: proposal.program,
      corrected: correctedProgram,
      reason,
      source: {
        extractorVersion: proposal.provenance.extractorVersion,
        promptHash: proposal.provenance.promptHash,
      },
      createdAt: this.now().toISOString(),
      pinned: false,
    };
    await this.opts.correctionStore.put(correction);
    this.opts.paskBridge?.onCorrected(proposal);
    const receipt = await this.completeRatification(proposal, correctedProgram, true, 'corrected');
    await audit('ratification.correct', 'ok', {
      providerId,
      detail: `proposal=${proposalId} correction=${correction.correctionId}`,
    });
    return { receipt, correction };
  }

  async reject(providerId: string, proposalId: string, reason: string): Promise<ProposalRejection> {
    const proposal = await this.opts.proposalStore.get(providerId, proposalId);
    if (!proposal) throw new RatificationError(`proposal ${proposalId} not found`, 'not_found');
    if (proposal.status !== 'pending') {
      throw new RatificationError(
        `proposal ${proposalId} is ${proposal.status}, not pending`, 'wrong_status',
      );
    }
    await this.opts.proposalStore.update({
      ...proposal, status: 'rejected', rejectReason: reason,
    });
    const rejection: ProposalRejection = {
      proposalId, providerId, reason, rejectedAt: this.now().toISOString(),
    };
    this.opts.paskBridge?.onRejected(proposal);
    await audit('ratification.reject', 'ok', {
      providerId, detail: `proposal=${proposalId} reason=${reason}`,
    });
    return rejection;
  }

  async bulkRatify(opts: {
    providerId?: string;
    minConfidence: number;
    dryRun?: boolean;
  }): Promise<BulkRatifyOutcome> {
    const candidates = await this.opts.proposalStore.list({
      providerId: opts.providerId,
      status: 'pending',
      minConfidence: opts.minConfidence,
    });
    let ratified = 0;
    let errors = 0;
    if (!opts.dryRun) {
      for (const proposal of candidates) {
        try {
          await this.completeRatification(proposal, proposal.program, false, 'auto-ratified');
          ratified += 1;
        } catch {
          errors += 1;
        }
      }
    }
    const outcome: BulkRatifyOutcome = {
      proposed: candidates.length,
      ratified: opts.dryRun ? 0 : ratified,
      skippedSuperseded: 0,
      skippedNonPending: 0,
      errors,
      dryRun: opts.dryRun ?? false,
    };
    await audit('ratification.bulk', 'ok', {
      providerId: opts.providerId,
      detail: `min-conf=${opts.minConfidence} matched=${candidates.length} ratified=${ratified} dry=${opts.dryRun ?? false}`,
    });
    return outcome;
  }

  async unratify(providerId: string, receiptId: string): Promise<{ withdrawn: boolean }> {
    const receipt = await this.opts.receiptStore.get(providerId, receiptId);
    if (!receipt) throw new RatificationError(`receipt ${receiptId} not found`, 'not_found');
    const proposal = await this.opts.proposalStore.get(providerId, receipt.proposalId);
    if (!proposal) throw new RatificationError('underlying proposal missing', 'orphan');
    await this.opts.proposalStore.update({ ...proposal, status: 'pending' });
    let withdrawn = false;
    if (receipt.cellId && this.opts.withdrawCell) {
      try {
        withdrawn = await this.opts.withdrawCell(receipt.cellId);
      } catch {
        withdrawn = false;
      }
    }
    await audit('ratification.unratify', 'ok', {
      providerId, detail: `receipt=${receiptId} withdrawn=${withdrawn}`,
    });
    return { withdrawn };
  }

  private async completeRatification(
    proposal: Proposal,
    program: SIRProgram,
    hadCorrection: boolean,
    nextStatus: 'ratified' | 'corrected' | 'auto-ratified' = 'ratified',
  ): Promise<RatificationReceipt> {
    const hat = this.opts.hatProvider();
    if (!hat) throw new RatificationError('no active hat — cannot sign receipt', 'no_hat');

    let cellId: string | null = null;
    if (this.opts.writeCell) {
      try {
        cellId = await this.opts.writeCell({ program, proposal });
      } catch (err) {
        throw new RatificationError(
          `cell-writer threw: ${err instanceof Error ? err.message : String(err)}`,
          'cell_write_error',
        );
      }
    }

    const receipt: RatificationReceipt = {
      receiptId: this.id(),
      proposalId: proposal.proposalId,
      providerId: proposal.provenance.providerId,
      providerItemId: proposal.provenance.providerItemId,
      issuedAt: this.now().toISOString(),
      signedBy: hat,
      cellId,
      hadCorrection,
    };
    await this.opts.receiptStore.put(receipt);
    await this.opts.proposalStore.update({ ...proposal, status: nextStatus });
    if (!hadCorrection) {
      this.opts.paskBridge?.onRatified(proposal, receipt);
    }

    await audit('ratification.complete', 'ok', {
      providerId: proposal.provenance.providerId,
      detail: `proposal=${proposal.proposalId} cell=${cellId ?? 'none'} status=${nextStatus}`,
    });

    return receipt;
  }

  private now(): Date {
    return this.opts.now ? this.opts.now() : new Date();
  }

  private id(): string {
    if (this.opts.generateId) return this.opts.generateId();
    const bytes = new Uint8Array(16);
    globalThis.crypto.getRandomValues(bytes);
    return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
  }
}

```
