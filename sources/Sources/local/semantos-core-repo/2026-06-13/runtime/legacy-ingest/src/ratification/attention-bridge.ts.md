---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/ratification/attention-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.163382+00:00
---

# runtime/legacy-ingest/src/ratification/attention-bridge.ts

```ts
/**
 * Attention Surface bridge — LI4.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI4 deliverable 2;
 *            docs/design/HELM-ATTENTION-SURFACE.md §3 AS4.
 *
 * AS4's `legacy-ingest` AttentionSignalSource (in
 * runtime/services/src/services/signals/legacy-ingest.ts) declares a
 * `LegacyIngestSubscription` shape that emits proposal events. This
 * bridge implements that shape against the LI3 ProposalStore: every
 * pending proposal becomes a signal the operator sees in their
 * right-panel attention feed.
 *
 * The bridge polls the proposal store (default 30s) and dedupes
 * proposals by id so re-polls don't re-fire signals.
 */

import type { Proposal } from '../extractor/types';
import type { ProposalStore } from '../proposal-store';

/** Mirrors the AS4 LegacyIngestProposal shape — structural only. */
export interface LegacyIngestSignalProposal {
  readonly id: string;
  readonly provider: string;
  readonly confidence: number;
  readonly summary: string;
  readonly receivedAt: number;
}

export type LegacyIngestSubscriber = (proposal: LegacyIngestSignalProposal) => void;

export interface LegacyIngestSubscription {
  subscribe(emit: LegacyIngestSubscriber): () => void;
}

export interface AttentionBridgeOpts {
  store: ProposalStore;
  pollIntervalMs?: number;
}

export class AttentionBridge implements LegacyIngestSubscription {
  private readonly store: ProposalStore;
  private readonly pollIntervalMs: number;
  private readonly seen = new Set<string>();
  private subscribers: LegacyIngestSubscriber[] = [];
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(opts: AttentionBridgeOpts) {
    this.store = opts.store;
    this.pollIntervalMs = opts.pollIntervalMs ?? 30_000;
  }

  subscribe(emit: LegacyIngestSubscriber): () => void {
    this.subscribers.push(emit);
    if (this.subscribers.length === 1) this.start();
    return () => {
      this.subscribers = this.subscribers.filter(s => s !== emit);
      if (this.subscribers.length === 0) this.stop();
    };
  }

  async tick(): Promise<number> {
    const proposals = await this.store.list({ status: 'pending' });
    let emitted = 0;
    for (const p of proposals) {
      if (this.seen.has(p.proposalId)) continue;
      this.seen.add(p.proposalId);
      const signal = toSignalProposal(p);
      for (const s of this.subscribers) {
        try { s(signal); } catch { /* non-fatal */ }
      }
      emitted += 1;
    }
    return emitted;
  }

  forget(proposalId: string): void {
    this.seen.delete(proposalId);
  }

  private start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => void this.tick(), this.pollIntervalMs);
    void this.tick();
  }

  private stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.seen.clear();
  }
}

function toSignalProposal(p: Proposal): LegacyIngestSignalProposal {
  return {
    id: p.proposalId,
    provider: p.provenance.providerId,
    confidence: p.confidence,
    summary: p.summary,
    receivedAt: p.extractedAt,
  };
}

```
