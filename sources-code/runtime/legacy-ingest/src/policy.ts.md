---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.135087+00:00
---

# runtime/legacy-ingest/src/policy.ts

```ts
/**
 * Ingest policy engine — combines Pask graph h-states with extraction
 * confidence to produce auto-ratification decisions.
 *
 * Decision logic:
 *   paskScore  = normalised h-state of the customer cell (0–1)
 *   combined   = paskScore * config.paskWeight + confidence * (1 - config.paskWeight)
 *   action     =
 *     combined >= config.autoRatifyThreshold AND confidence >= config.minConfidence
 *       → 'auto-ratify'
 *     combined >= config.flagReviewThreshold
 *       → 'flag-review'   (surfaces prominently in Attention Surface)
 *     else
 *       → 'skip'          (normal pending state, no special treatment)
 *
 * The thresholds are operator-configurable and drift over time as the
 * Pask graph accumulates interactions via IngestPaskBridge.
 */

import type { Proposal } from './extractor/types';

/** Minimal Pask query surface — pass your PaskGraph instance directly. */
export interface PaskQueryAdapter {
  stableThreads(opts: { limit: number; sourcePrefix: string }): Array<{
    cellId: string;
    hState: number;
    trafficCount: number;
  }>;
}

export interface PolicyConfig {
  /**
   * Combined score threshold for auto-ratification.
   * Default: 0.80 — a well-known customer (Pask) + high-confidence extraction.
   */
  autoRatifyThreshold?: number;
  /**
   * Combined score threshold below which proposals are flagged for review.
   * Default: 0.50 — moderate signal, bring to operator attention.
   */
  flagReviewThreshold?: number;
  /**
   * Hard minimum on extraction confidence — no auto-ratify below this
   * regardless of Pask score. Default: 0.70.
   */
  minConfidence?: number;
  /**
   * Weight given to the Pask h-state in the combined score.
   * Default: 0.40 — Pask is a secondary signal; confidence leads.
   */
  paskWeight?: number;
}

const DEFAULTS: Required<PolicyConfig> = {
  autoRatifyThreshold: 0.80,
  flagReviewThreshold: 0.50,
  minConfidence: 0.70,
  paskWeight: 0.40,
};

export interface PolicyDecision {
  action: 'auto-ratify' | 'flag-review' | 'skip';
  /** Combined score [0–1] used for the decision. */
  score: number;
  /** Normalised Pask h-state for the customer cell [0–1]. */
  paskScore: number;
  /** Extraction confidence from the LLM adapter. */
  confidence: number;
  reason: string;
}

export class IngestPolicy {
  private readonly cfg: Required<PolicyConfig>;

  constructor(
    private readonly pask: PaskQueryAdapter,
    config: PolicyConfig = {},
  ) {
    this.cfg = { ...DEFAULTS, ...config };
  }

  /**
   * Evaluate a proposal and return a policy decision.
   * This is a synchronous read — it doesn't mutate any state.
   */
  evaluate(proposal: Proposal): PolicyDecision {
    const customerCellId = customerCell(proposal);
    const paskScore = this.lookupHState(customerCellId);
    const { confidence } = proposal;

    const combined =
      paskScore * this.cfg.paskWeight +
      confidence * (1 - this.cfg.paskWeight);

    if (
      combined >= this.cfg.autoRatifyThreshold &&
      confidence >= this.cfg.minConfidence
    ) {
      return {
        action: 'auto-ratify',
        score: combined,
        paskScore,
        confidence,
        reason: `combined=${combined.toFixed(2)} (pask=${paskScore.toFixed(2)}, conf=${confidence.toFixed(2)}) ≥ threshold=${this.cfg.autoRatifyThreshold}`,
      };
    }

    if (combined >= this.cfg.flagReviewThreshold) {
      return {
        action: 'flag-review',
        score: combined,
        paskScore,
        confidence,
        reason: `combined=${combined.toFixed(2)} ≥ flag-threshold=${this.cfg.flagReviewThreshold}`,
      };
    }

    return {
      action: 'skip',
      score: combined,
      paskScore,
      confidence,
      reason: `combined=${combined.toFixed(2)} below all thresholds`,
    };
  }

  /**
   * Scan all ingest customer cells and return a ranked list of profiles
   * that would auto-ratify at the current thresholds. Useful for surfacing
   * "trusted senders" to the operator.
   */
  trustedCustomers(limit = 20): Array<{ cellId: string; paskScore: number; trafficCount: number }> {
    const threads = this.pask.stableThreads({
      limit: limit * 3,
      sourcePrefix: 'ingest:customer:',
    });
    return threads
      .filter(t => t.cellId.startsWith('ingest:customer:'))
      .map(t => ({
        cellId: t.cellId,
        paskScore: normaliseHState(t.hState),
        trafficCount: t.trafficCount,
      }))
      .filter(t => t.paskScore >= this.cfg.autoRatifyThreshold * this.cfg.paskWeight)
      .slice(0, limit);
  }

  private lookupHState(cellId: string): number {
    const threads = this.pask.stableThreads({
      limit: 200,
      sourcePrefix: 'ingest:customer:',
    });
    const cell = threads.find(t => t.cellId === cellId);
    return cell ? normaliseHState(cell.hState) : 0;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Map a Pask h-state to a [0, 1] score.
 * h-state accumulates with each positive interaction (acted-on = 3.0) and
 * decays with negative ones (dismissed = -1.0). A value of ~5 represents a
 * well-established, frequently-ratified customer profile.
 */
function normaliseHState(h: number): number {
  if (h <= 0) return 0;
  return Math.min(h / 5.0, 1.0);
}

function hashCustomer(s: string): string {
  const lower = s.trim().toLowerCase();
  let h = 5381;
  for (let i = 0; i < lower.length; i++) {
    h = ((h << 5) + h) + lower.charCodeAt(i);
    h = h | 0;
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

function customerCell(proposal: Proposal): string {
  const target = proposal.program.nodes?.[0]?.target;
  if (target && typeof target === 'object' && 'id' in target && typeof target.id === 'string') {
    return `ingest:customer:${hashCustomer(target.id)}`;
  }
  return `ingest:customer:${hashCustomer(proposal.provenance.providerItemId)}`;
}

```
