---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/signals/legacy-ingest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.110926+00:00
---

# runtime/services/src/services/signals/legacy-ingest.ts

```ts
/**
 * Legacy-ingest signal source — AS4.
 *
 * Subscribes to `legacy-ingest.proposal.created` events emitted by the
 * LI pipeline (cf. WALLET-LEGACY-INGEST §3 LI3) and translates them to
 * AttentionSignals. The score is the proposal's confidence times a
 * per-provider multiplier (Gmail-from-active-customers > archive cleanup).
 */
import type { AttentionSignalSource, AttentionSignal } from '../AttentionSignals';
import type { LoomObject } from '../../types/loom';

export type LegacyIngestProvider = 'gmail' | 'meta-pages' | 'whatsapp-cloud' | 'twilio-sms' | string;

export interface LegacyIngestProposal {
  readonly id: string;
  readonly provider: LegacyIngestProvider;
  readonly confidence: number;
  readonly summary: string;
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
  readonly receivedAt: number;
}

export interface LegacyIngestSubscription {
  /** Emit `proposal` events; returns an unsubscribe fn. */
  subscribe(emit: (proposal: LegacyIngestProposal) => void): () => void;
}

export interface LegacyIngestSourceOptions {
  pipeline: LegacyIngestSubscription;
  /** Per-provider multipliers, default 1.0. */
  providerMultiplier?: Partial<Record<LegacyIngestProvider, number>>;
  /** ms a proposal stays surfaced before its signal expires. Default 24h. */
  signalTtlMs?: number;
}

export function createLegacyIngestSource(opts: LegacyIngestSourceOptions): AttentionSignalSource {
  const ttl = opts.signalTtlMs ?? 24 * 60 * 60 * 1000;
  const multipliers = opts.providerMultiplier ?? {};
  return {
    id: 'legacy-ingest',
    displayName: 'Legacy Ingest',
    subscribe(emit: (signal: AttentionSignal) => void): () => void {
      return opts.pipeline.subscribe((proposal) => {
        const m = multipliers[proposal.provider] ?? 1.0;
        const score = Math.min(1.0, proposal.confidence * m);
        emit({
          sourceId: 'legacy-ingest',
          attachToObjectId: proposal.attachToObjectId,
          synthesizesObject: proposal.synthesizesObject,
          factor: {
            type: 'extension_signal',
            extensionId: `legacy-ingest.${proposal.provider}`,
            signal: proposal.summary,
          },
          score,
          expiresAt: proposal.receivedAt + ttl,
        });
      });
    },
  };
}

```
