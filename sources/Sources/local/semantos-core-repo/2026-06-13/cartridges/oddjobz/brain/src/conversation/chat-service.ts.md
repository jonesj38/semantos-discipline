---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/chat-service.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.517784+00:00
---

# cartridges/oddjobz/brain/src/conversation/chat-service.ts

```ts
/**
 * I-13 — OddJobz chat service (semantos-core).
 *
 * Replaces oddjobtodd/src/lib/services/chatService.ts.
 * Wires the trivium/quadrivium intent reducer into the conversation turn
 * pipeline: extraction → accumulated state → reduceToIntent → Intent.
 *
 * This is the outward-facing surface that the oddjobz app (or any
 * consumer of @semantos/oddjobz) calls to process a conversation turn.
 * It does NOT drive processIntent directly — that is the runtime/intent
 * pipeline's job. This service produces an Intent; the caller decides
 * whether to invoke processIntent (e.g. in an API route handler).
 *
 * Dependency direction:
 *   @semantos/oddjobz → @semantos/intent → @semantos/semantos-sir
 *   NOT: @semantos/intent → @semantos/oddjobz (would be circular)
 */

import { reduceToIntent, type ReducerResult } from '@semantos/intent/reducer';
import type { ReducerOptions, GrammarSpec, ReducerInputState, TaggedFact } from '@semantos/intent/reducer/types';
import { produceIntent } from '@semantos/intent';
import type { CorrelationId, Logger } from '@semantos/intent';
import type { AccumulatedJobState } from './accumulated-job-state.js';
import type { BridgeContext } from './substrate-bridge.js';
import { TRADES_GRAMMAR_SPEC } from './trades-grammar-spec.js';

// ---------------------------------------------------------------------------
// ChatTurnInput — what the service receives for one conversation turn
// ---------------------------------------------------------------------------

export interface ChatTurnInput {
  /** The merged accumulated state for this conversation up to (not including) this turn. */
  accumulatedState: AccumulatedJobState;
  /**
   * Tagged facts from the LLM extraction for this turn. The extraction
   * prompt (see extraction-prompt.ts buildTradesTaggedFactsSection) asks
   * the LLM to emit these alongside the structured fields; the caller
   * parses them from the raw LLM response and passes them here.
   */
  taggedFacts: ReadonlyArray<TaggedFact>;
  /** Optional estimated cost from the extraction (AUD cents). */
  estimatedCostMin?: number | null;
  estimatedCostMax?: number | null;
  /** Optional preferred scheduling datetime (ISO-8601). */
  preferredDatetime?: string | null;
  /** Session / hat context. */
  bridge: BridgeContext;
  /** Optional grammar override (defaults to TRADES_GRAMMAR_SPEC). */
  grammar?: GrammarSpec;
  /** Optional reducer options (confidence thresholds, prior rejection relay). */
  reducerOptions?: ReducerOptions;
  /** RM-091 — observability sink. When supplied, the turn emits an
   *  `intent_produced` event on entry and reuses the same correlationId
   *  for every downstream reducer pass event (RM-090). When omitted the
   *  call is silent (current default). */
  logger?: Logger;
  /** RM-091 — pre-existing correlationId (e.g. carried from a parent
   *  conversation turn or producer). Mint a fresh one when absent. */
  correlationId?: CorrelationId;
  /** RM-091 — raw input string the producer received. Used only for
   *  trace digest; the full string never enters the trace. Defaults to
   *  the turn's scope description so existing callers don't break. */
  rawInput?: string;
}

export interface ChatTurnResult {
  reducerResult: ReducerResult;
  /** The ReducerInputState assembled for this turn — useful for debugging. */
  reducerInput: ReducerInputState;
  /** RM-091 — correlationId the turn ran under. Caller threads this
   *  onto `processIntent` so the whole turn is one grep. */
  correlationId?: CorrelationId;
}

// ---------------------------------------------------------------------------
// processConversationTurn
// ---------------------------------------------------------------------------

/**
 * Process one conversation turn through the intent reducer.
 * Returns a ReducerResult carrying the Intent + per-pass diagnostics.
 *
 * The caller (e.g. an API route handler) then decides whether to call
 * processIntent(result.intent, ctx, deps) to mint a cell.
 */
export async function processConversationTurn(input: ChatTurnInput): Promise<ChatTurnResult> {
  const grammar = input.grammar ?? TRADES_GRAMMAR_SPEC;
  const reducerInput = buildReducerInput(input, grammar.domainFlag);

  // RM-091 — when the caller supplies a logger, route through the
  // producer-boundary helper so the turn gets `intent_produced` +
  // shared correlationId. Silent callers (no logger) keep the existing
  // shape so we don't break callers that haven't migrated.
  if (input.logger) {
    const produced = await produceIntent({
      rawInput: input.rawInput ?? input.accumulatedState.scopeDescription ?? '',
      source: 'nl',
      reducerInput,
      grammar,
      reducerOptions: input.reducerOptions,
      logger: input.logger,
      ...(input.correlationId !== undefined ? { correlationId: input.correlationId } : {}),
    });
    return {
      reducerResult: produced,
      reducerInput,
      correlationId: produced.correlationId,
    };
  }

  const reducerResult = await reduceToIntent(reducerInput, grammar, input.reducerOptions);
  return { reducerResult, reducerInput };
}

// ---------------------------------------------------------------------------
// Adapter: ChatTurnInput → ReducerInputState
// ---------------------------------------------------------------------------

function buildReducerInput(input: ChatTurnInput, domainFlag: number): ReducerInputState {
  const { accumulatedState: state } = input;
  return {
    conversationSummary: state.scopeDescription ?? undefined,
    taggedFacts: input.taggedFacts,
    suburb: state.suburb,
    urgency: state.urgency,
    jobType: state.jobType,
    scopeDescription: state.scopeDescription ?? undefined,
    estimatedCostMin: input.estimatedCostMin ?? null,
    estimatedCostMax: input.estimatedCostMax ?? null,
    preferredDatetime: input.preferredDatetime ?? null,
    location: state.address ?? state.locationClue,
    conversationPhase: state.conversationPhase,
    domainFlag,
  };
}

```
