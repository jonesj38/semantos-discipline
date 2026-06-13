---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/turn-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.521096+00:00
---

# cartridges/oddjobz/brain/src/conversation/turn-handler.ts

```ts
/**
 * R-2 — Full conversation turn handler.
 *
 * The single entry point for a live intake conversation. Composes:
 *
 *   1. runConversationTurn   — extract → merge → reduce → Intent
 *   2. generateReply         — evaluateConversationState → LLM reply
 *
 * This is the surface an HTTP handler or the Flutter app calls.
 * Returns everything needed to respond to the customer and persist
 * the turn — reply text, action, intent, and the updated state.
 *
 * Done signals: action.type is 'summarise_and_close', 'not_worth_pursuing',
 * or 'needs_site_visit' → set done=true so the caller can close the
 * session or hand off to the operator.
 */

import type { AccumulatedJobState } from './accumulated-job-state.js';
import type { BridgeContext } from './substrate-bridge.js';
import type { TurnExtractorOptions } from './turn-extractor.js';
import type { GrammarSpec, ReducerOptions } from '@semantos/intent/reducer/types';
import type { Intent } from '@semantos/intent';
import type { ConversationAction } from './state-manager.js';
import type { BusinessContext } from './business-context.js';
import { runConversationTurn } from './pipeline.js';
import {
  generateReply,
  DEFAULT_ESTIMATOR_FN,
  type ConversationTurn,
  type ReplyLlmFn,
  type EstimatorFn,
} from './reply-generator.js';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface TurnHandlerInput {
  /** Accumulated state at the start of this turn. */
  readonly currentState: AccumulatedJobState;
  /** Raw customer message. */
  readonly message: string;
  /** Prior conversation history (user + assistant turns). */
  readonly history: ReadonlyArray<ConversationTurn>;
  /** Running conversation summary — updated externally by the session manager. */
  readonly conversationSummary?: string;
  /** Session / hat context. */
  readonly bridge: BridgeContext;
  /** Operator name substituted into system injection strings. */
  readonly operatorName?: string;
  /** WP-6 — operator profile facts; build the default persona for any trade. */
  readonly businessContext?: BusinessContext;
  /** WP-6 — operator's active WP-5 prompt text; overrides the default persona. */
  readonly activePrompt?: string | null;
  /** LLM backend for reply generation. */
  readonly replyLlm: ReplyLlmFn;
  /** LLM / API options forwarded to the extraction step. */
  readonly extractorOptions?: TurnExtractorOptions;
  /** ROM estimator — defaults to the built-in band table. */
  readonly estimatorFn?: EstimatorFn;
  /** Grammar override for the reducer. */
  readonly grammar?: GrammarSpec;
  readonly reducerOptions?: ReducerOptions;
}

export interface TurnHandlerResult {
  /** What to send back to the customer. */
  readonly replyText: string;
  /** State manager decision — tells the caller what just happened. */
  readonly action: ConversationAction;
  /** Reduced intent for this turn — caller decides whether to call processIntent. */
  readonly intent: Intent;
  /** Accumulated state AFTER merging this turn's extraction. */
  readonly state: AccumulatedJobState;
  /**
   * True when the conversation is finished: either closed, not worth pursuing,
   * or a site visit has been requested. The caller should stop accepting
   * messages and hand off to the operator.
   */
  readonly done: boolean;
  /** The EXACT assembled system prompt the LLM saw this turn,
   *  forwarded from generateReply. The caller (intake-handler) hashes
   *  it into the conversation-turn patch for versioned prompt
   *  provenance — auditable bot, not a context-window black box. */
  readonly assembledPrompt: string;
}

const DONE_ACTIONS = new Set<ConversationAction['type']>([
  'summarise_and_close',
  'not_worth_pursuing',
  'needs_site_visit',
]);

// ── Implementation ────────────────────────────────────────────────────────────

export async function handleConversationTurn(
  input: TurnHandlerInput,
): Promise<TurnHandlerResult> {
  // Stage 1+2+3: extract → merge → reduce
  const { state, turn } = await runConversationTurn({
    currentState: input.currentState,
    latestMessage: input.message,
    conversationSummary: input.conversationSummary,
    bridge: input.bridge,
    extractorOptions: input.extractorOptions,
    grammar: input.grammar,
    reducerOptions: input.reducerOptions,
  });

  // Stage 4: evaluate state + generate reply
  const { replyText, action, assembledPrompt } = await generateReply({
    state,
    history: input.history,
    latestMessage: input.message,
    operatorName: input.operatorName,
    businessContext: input.businessContext,
    activePrompt: input.activePrompt,
    estimatorFn: input.estimatorFn ?? DEFAULT_ESTIMATOR_FN,
    llm: input.replyLlm,
  });

  // If the state machine just presented an estimate, mark it so the next
  // turn knows not to re-present. This must be set programmatically because
  // the LLM extractor sees the pre-action state and cannot infer it reliably.
  const finalState =
    action.type === 'present_estimate' && !state.estimatePresented
      ? Object.freeze({ ...state, estimatePresented: true })
      : state;

  return {
    replyText,
    action,
    intent: turn.reducerResult.intent,
    state: finalState,
    done: DONE_ACTIONS.has(action.type),
    assembledPrompt,
  };
}

```
