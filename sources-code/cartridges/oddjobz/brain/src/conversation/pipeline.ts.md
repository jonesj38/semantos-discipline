---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.520501+00:00
---

# cartridges/oddjobz/brain/src/conversation/pipeline.ts

```ts
/**
 * L-4 — Conversation turn pipeline.
 *
 * Composes the three steps that convert a raw customer message into an
 * Intent in one call:
 *
 *   1. extractConversationTurn  — calls the LLM → MessageExtraction + TaggedFact[]
 *   2. mergeExtraction          — folds the extraction into AccumulatedJobState
 *   3. processConversationTurn  — runs the trivium/quadrivium reducer → Intent
 *
 * Callers that already have an extraction (e.g. from a webhook that runs
 * the LLM separately) should skip this and call processConversationTurn
 * directly. This pipeline is for the common case where the caller has
 * only a raw message and an accumulated state.
 *
 * The returned PipelineResult carries every intermediate artefact so
 * callers can debug, audit, or branch on any stage.
 */

import type { AccumulatedJobState } from './accumulated-job-state.js';
import { mergeExtraction } from './accumulated-job-state.js';
import type { BridgeContext } from './substrate-bridge.js';
import { extractConversationTurn, type TurnExtractionResult, type TurnExtractorOptions } from './turn-extractor.js';
import { processConversationTurn, type ChatTurnResult } from './chat-service.js';
import type { GrammarSpec, ReducerOptions } from '@semantos/intent/reducer/types';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface PipelineInput {
  /** The accumulated state at the START of this turn (before this message). */
  readonly currentState: AccumulatedJobState;
  /** The raw customer message text. */
  readonly latestMessage: string;
  /** Running conversation summary (a few sentences). Defaults to empty. */
  readonly conversationSummary?: string;
  /** Session / hat context (required by the reducer). */
  readonly bridge: BridgeContext;

  /** Optional estimated cost extracted by a prior stage (AUD cents). */
  readonly estimatedCostMin?: number | null;
  readonly estimatedCostMax?: number | null;
  /** Optional preferred scheduling datetime (ISO-8601). */
  readonly preferredDatetime?: string | null;

  /** LLM / API options forwarded to extractConversationTurn. */
  readonly extractorOptions?: TurnExtractorOptions;
  /** Grammar override — defaults to TRADES_GRAMMAR_SPEC. */
  readonly grammar?: GrammarSpec;
  /** Reducer options — confidence thresholds, prior rejection. */
  readonly reducerOptions?: ReducerOptions;
}

export interface PipelineResult {
  /** The merged accumulated state AFTER applying this turn's extraction. */
  readonly state: AccumulatedJobState;
  /** Raw extraction result from the LLM (fields + tagged facts). */
  readonly extraction: TurnExtractionResult;
  /** Full reducer result (Intent + per-pass diagnostics + composite confidence). */
  readonly turn: ChatTurnResult;
}

// ── Main ──────────────────────────────────────────────────────────────────────

/**
 * Run one conversation turn end-to-end: message → merged state → Intent.
 *
 * @throws if the LLM call or reducer throws (caller is responsible for
 *         catching and deciding whether to retry / degrade gracefully).
 */
export async function runConversationTurn(input: PipelineInput): Promise<PipelineResult> {
  // Stage 1: LLM extraction
  const extraction = await extractConversationTurn(
    {
      currentState: input.currentState,
      latestMessage: input.latestMessage,
      conversationSummary: input.conversationSummary,
    },
    input.extractorOptions,
  );

  // Stage 2: Merge extraction into accumulated state
  const { state } = mergeExtraction(input.currentState, extraction.extraction);

  // Stage 3: Intent reduction
  const turn = await processConversationTurn({
    accumulatedState: state,
    taggedFacts: extraction.taggedFacts,
    estimatedCostMin: input.estimatedCostMin,
    estimatedCostMax: input.estimatedCostMax,
    preferredDatetime: input.preferredDatetime,
    bridge: input.bridge,
    grammar: input.grammar,
    reducerOptions: input.reducerOptions,
  });

  return { state, extraction, turn };
}

```
