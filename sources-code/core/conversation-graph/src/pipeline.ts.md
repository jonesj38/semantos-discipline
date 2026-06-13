---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.007402+00:00
---

# core/conversation-graph/src/pipeline.ts

```ts
/**
 * Generic conversation-turn pipeline — RM-031b.
 *
 * `runConversationTurn<S, F>` composes three injectable ports into a
 * single end-to-end turn handler, generic over:
 *   - `S` — the accumulated conversation state shape (per domain)
 *   - `F` — the per-turn fact / extraction shape
 *
 * Domain extensions (Oddjobz today; future Reddit / Discourse / SCG
 * projections) wire their concrete extractor (LLM call) + state-
 * merger + reducer-runner here and get a typed pipeline. The
 * substrate keeps no domain knowledge.
 *
 * Why this lives in core: every conversation-graph consumer needs
 * the SAME structural composition (extract → merge → reduce); only
 * the concrete implementations differ. Keeping the wiring here lets
 * a future SCG-aware Reddit demo (RM-051) compose its own pipeline
 * without re-inventing the orchestration loop.
 *
 * Why oddjobz's current pipeline.ts is NOT moved here: it has
 * hard-coded references to AccumulatedJobState + the `@anthropic-ai/sdk`
 * client + BridgeContext + an oddjobz-specific reducer adapter. The
 * generic shape below is what those concrete deps satisfy; oddjobz
 * can adopt it incrementally without a flag-day migration.
 *
 * See `docs/SCG-AND-PHASE-H-ROADMAP.md` RM-031b for sequencing.
 */

import { autoEmitReplyRelation } from './auto-emit.js';
import type { Database } from '@semantos/semantic-objects';
import type { RelationRow } from '@semantos/scg-relations';
import type { Turn } from './types.js';

/**
 * Stage 1 — extraction. Takes the prior accumulated state + raw
 * input + optional conversation summary, returns a per-turn fact bag
 * `F` (e.g. tagged facts + structured fields parsed from an LLM
 * response).
 */
export interface ConversationExtractor<S, F> {
  extract(input: {
    readonly currentState: S;
    readonly latestMessage: string;
    readonly conversationSummary?: string;
  }): Promise<F>;
}

/**
 * Stage 2 — state merge. Folds the extraction `F` into the existing
 * state `S`, returning the new state. Pure-by-convention; should not
 * persist anything itself.
 */
export interface ConversationStateMerger<S, F> {
  merge(state: S, extraction: F): S;
}

/**
 * Stage 3 — reducer. Whatever turns the (merged state + per-turn
 * fact bag) into a domain-specific reducer result `R`. Typically
 * wraps `@semantos/intent::reduceToIntent` with a domain-specific
 * input adapter.
 */
export interface ConversationReducer<S, F, R> {
  reduce(input: { readonly state: S; readonly extraction: F }): Promise<R>;
}

/** Configuration passed into `runConversationTurn`. */
export interface RunTurnInput<S> {
  readonly currentState: S;
  readonly latestMessage: string;
  readonly conversationSummary?: string;
  /**
   * Optional `Turn` for the substrate auto-emit hook. When supplied
   * AND `turn.quotedTurnId` is set, the pipeline emits a `REPLIES_TO`
   * relation via `autoEmitReplyRelation` AFTER all three stages
   * succeed. Pass undefined to skip the auto-emit (useful for read-
   * only previews or stages that don't persist).
   */
  readonly turn?: Turn;
  /** Forwarded to `autoEmitReplyRelation` when `turn` is supplied. */
  readonly capabilityCheck?: () => Promise<void> | void;
}

/** Result of `runConversationTurn`. */
export interface RunTurnResult<S, F, R> {
  /** Merged state after applying this turn's extraction. */
  readonly state: S;
  /** Raw extraction. */
  readonly extraction: F;
  /** Reducer output. */
  readonly reducer: R;
  /** REPLIES_TO relation emitted, when `turn.quotedTurnId` was set
   *  and the pipeline completed successfully. */
  readonly autoEmittedRelation: RelationRow | null;
}

/**
 * Generic conversation-turn pipeline. Returns the result of every
 * stage so callers can debug, audit, or branch on any of them.
 *
 * Throws if any stage throws (caller decides whether to retry or
 * degrade gracefully).
 */
export async function runConversationTurn<S, F, R>(
  ports: {
    db?: Database;
    extractor: ConversationExtractor<S, F>;
    merger: ConversationStateMerger<S, F>;
    reducer: ConversationReducer<S, F, R>;
  },
  input: RunTurnInput<S>,
): Promise<RunTurnResult<S, F, R>> {
  // Stage 1 — extraction
  const extractInput: {
    currentState: S;
    latestMessage: string;
    conversationSummary?: string;
  } = {
    currentState: input.currentState,
    latestMessage: input.latestMessage,
  };
  if (input.conversationSummary !== undefined) {
    extractInput.conversationSummary = input.conversationSummary;
  }
  const extraction = await ports.extractor.extract(extractInput);

  // Stage 2 — merge
  const state = ports.merger.merge(input.currentState, extraction);

  // Stage 3 — reduce
  const reducer = await ports.reducer.reduce({ state, extraction });

  // Substrate hook — auto-emit REPLIES_TO when the turn quoted a
  // prior turn AND a db is available.
  let autoEmittedRelation: RelationRow | null = null;
  if (input.turn && ports.db) {
    autoEmittedRelation = await autoEmitReplyRelation(ports.db, input.turn, {
      ...(input.capabilityCheck !== undefined
        ? { capabilityCheck: input.capabilityCheck }
        : {}),
    });
  }

  return { state, extraction, reducer, autoEmittedRelation };
}

```
