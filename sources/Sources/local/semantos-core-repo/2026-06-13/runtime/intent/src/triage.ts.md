---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/triage.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.345195+00:00
---

# runtime/intent/src/triage.ts

```ts
/**
 * triage — the cheap-filter in front of the expensive pipeline.
 *
 * The classifier examines a conversation message and returns one of
 * three outcomes (docs/INTENT-PIPELINE.md §"Triage and conversation
 * patches"):
 *
 *   NO_INTENT       — no downstream pipeline, just a conversation patch
 *   PROPOSES_INTENT — run full pipeline; derived patch companionOf-links
 *                     back to the conversation patch
 *   RATIFIES_INTENT — signed pointer at an earlier pending proposal;
 *                     no fresh SIR/IR/kernel run
 *
 * This module provides:
 *   - `Classifier` interface — pluggable (rules, cheap LLM, …)
 *   - `triage()` — wraps a classifier call with stage-event emission
 *   - `buildProposeIntent()` — helper to wire `companionOf` correctly
 *
 * The triage function does NOT own the conversation-patch write or
 * the pipeline invocation — those are the handleMessage orchestrator's
 * concern (one layer up). Triage is pure: message + context → outcome +
 * one `triage_decided` stage event.
 */

import type {
  Intent,
  IntentId,
  IntentSource,
  TriageOutcome,
  CorrelationId,
  HatContext,
  Logger,
  StageEvent,
  PatchId,
  Signature,
} from './types';

// ── Classifier interface ────────────────────────────────────

/**
 * A classifier is a pluggable decision function. The triage module
 * doesn't care whether the implementation is rules-based, an LLM
 * call, or a heuristic — only that it returns a shaped outcome.
 *
 * Implementations MUST be async — real classifiers will call out to
 * an LLM; rule-based stubs can just `return Promise.resolve(…)`.
 */
export interface ClassifierInput {
  /** The conversation message body. */
  body: unknown;
  /** The patch id of the just-written conversation patch. */
  conversationPatchId: PatchId;
  /** The object this conversation is attached to. */
  objectId: string;
  /** The authoring hat — drives per-role category access. */
  hat: HatContext;
  /** Provenance — where the message came from. */
  source: IntentSource;
  /**
   * Open pending-intent patch ids on this object. Supplied to the
   * classifier so it can recognise RATIFIES_INTENT outcomes (e.g. the
   * landlord's "approved" on an outstanding proposal).
   */
  pendingProposals: ReadonlyArray<{
    patchId: PatchId;
    summary: string;
  }>;
}

export interface Classifier {
  classify(input: ClassifierInput): Promise<TriageOutcome>;
}

// ── Always-NO_INTENT classifier (useful for tests + "chat only" mode) ──

export const neverIntentClassifier: Classifier = {
  async classify(): Promise<TriageOutcome> {
    return { kind: 'no_intent', reason: 'classifier disabled' };
  },
};

// ── Simple rules-based classifier — zero-cost baseline ──────
//
// Matches ratification-style phrases ("approved", "ok", "yes")
// against pending proposals; nothing else is treated as a proposal
// (rules can't extract semantic intent). For real PROPOSES detection,
// plug an LLM classifier in Slice 2c.

const RATIFY_PATTERNS = [
  /^\s*(approved|approve|yes|ok|ack|confirmed|accept(ed)?)\b/i,
  /\b(looks good|lgtm|sounds good|go ahead)\b/i,
];

export interface RulesClassifierOptions {
  /**
   * Signer for RATIFIES outcomes. Produces the attestation that
   * closes out the pending proposal.
   */
  sign: (preimage: Uint8Array) => Signature;
}

export function createRulesClassifier(opts: RulesClassifierOptions): Classifier {
  return {
    async classify(input): Promise<TriageOutcome> {
      const text = typeof input.body === 'string' ? input.body : '';
      const looksLikeRatify = RATIFY_PATTERNS.some(r => r.test(text));

      if (looksLikeRatify && input.pendingProposals.length > 0) {
        // Ratify the most recent pending proposal. (Real classifiers
        // should disambiguate across multiple by semantic linkage.)
        const latest = input.pendingProposals[input.pendingProposals.length - 1]!;
        const preimage = new TextEncoder().encode(
          `ratify\x1f${input.hat.hatId}\x1f${latest.patchId}\x1f${text}`,
        );
        return {
          kind: 'ratifies',
          pendingPatchId: latest.patchId,
          attestation: opts.sign(preimage),
        };
      }

      // Rules can't produce PROPOSES without domain knowledge.
      return { kind: 'no_intent', reason: 'rules-classifier: no match' };
    },
  };
}

// ── triage() — the stage-event-emitting wrapper ─────────────

export interface TriageDeps {
  classifier: Classifier;
  logger: Logger;
}

export interface TriageInput extends ClassifierInput {
  correlationId: CorrelationId;
}

export async function triage(
  input: TriageInput,
  deps: TriageDeps,
): Promise<TriageOutcome> {
  const start = performance.now();
  const outcome = await deps.classifier.classify(input);
  const durationMs = performance.now() - start;

  const event: StageEvent = {
    ts: new Date().toISOString(),
    correlationId: input.correlationId,
    intentId: outcome.kind === 'proposes' ? outcome.intent.id : null,
    stage: 'triage_decided',
    durationMs,
    hatId: input.hat.hatId,
    source: input.source,
    data: {
      outcome: outcome.kind,
      classifierLatencyMs: durationMs,
      ...(outcome.kind === 'no_intent' ? { reason: outcome.reason } : {}),
      ...(outcome.kind === 'ratifies' ? { pendingPatchId: outcome.pendingPatchId } : {}),
    },
  };
  deps.logger.emit(event);

  return outcome;
}

// ── buildProposeIntent — wires companionOf correctly ────────
//
// When a PROPOSES_INTENT outcome is realised by downstream code,
// the Intent must carry `companionOf` pointing at the conversation
// patch id. This helper saves callers from remembering to set it.

export interface BuildProposeIntentInput {
  /** The Intent body (without companionOf or source). */
  partial: Omit<Intent, 'id' | 'source' | 'confidence' | 'companionOf'> & {
    confidence?: number;
  };
  /** The conversation patch this intent is derived from. */
  conversationPatchId: PatchId;
  /** Source of the conversation message (nl/voice/ui). */
  source: IntentSource;
  /** Intent-id generator. */
  generateId: () => string;
  /** Correlation id to thread through (same as the conversation turn). */
  correlationId: CorrelationId;
}

export function buildProposeIntent(input: BuildProposeIntentInput): Intent {
  return {
    id: input.generateId() as IntentId,
    correlationId: input.correlationId,
    companionOf: input.conversationPatchId,
    source: input.source,
    confidence: input.partial.confidence ?? 0.7,
    ...input.partial,
  };
}

```
