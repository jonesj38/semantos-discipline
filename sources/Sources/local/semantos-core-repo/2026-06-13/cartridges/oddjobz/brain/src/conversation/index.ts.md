---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.515334+00:00
---

# cartridges/oddjobz/brain/src/conversation/index.ts

```ts
/**
 * D-O7 — conversation module entrypoint.
 *
 * The five conversation modules salvaged from OJT under the D-O7
 * reframing brief:
 *
 *   - `state-manager.ts`         — operator-tuned cascade picking
 *                                  the next conversation action.
 *   - `accumulated-job-state.ts` — accumulated state shape +
 *                                  sub-score computation + merger.
 *   - `hat-scoping.ts`           — K3 cryptographic hat isolation
 *                                  (PR #279), replaces OJT's filter-
 *                                  based scoping.
 *   - `analyzer.ts`              — periodic conversation analyser
 *                                  (drop | keep_warm | escalate).
 *   - `substrate-bridge.ts`      — typed BridgeContext that threads
 *                                  hat + ids through to D-O6b
 *                                  persistence helpers.
 *
 * See `docs/design/D-O7-OJT-SALVAGE-REPORT.md` for the per-file
 * salvage verdict + Findings #1–#6.
 */

export {
  evaluateConversationState,
  generateSystemInjection,
  detectNeedsSiteVisit,
  buildSummary,
  THRESHOLDS,
  type ConversationAction,
  type EstimatorRequest,
} from './state-manager.js';

export {
  emptyJobState,
  calculateSubScores,
  mergeExtraction,
  mergeScopeDescription,
  type AccumulatedJobState,
  type EstimateAckStatus,
  type MessageExtraction,
  type MergeResult,
  type SubScores,
} from './accumulated-job-state.js';

export {
  buildHat,
  assertHatScopedCap,
  hatCarriesCap,
  presentedContextTag,
  selectHatForCap,
  sameHat,
  CARPENTER_CONTEXT_TAG,
  MUSICIAN_CONTEXT_TAG,
  DEFAULT_HAT_CONTEXT_TAG,
  type OddjobzHat,
  type BuildHatInput,
  type HatScopeFailure,
} from './hat-scoping.js';

export {
  analyzeConversations,
  decideForSession,
  DEFAULT_ANALYZER_CONFIG,
  type AnalyzerConfig,
  type AnalyzerDecision,
  type AnalyzerResult,
  type ConversationSnapshot,
} from './analyzer.js';

export {
  buildBridgeContext,
  type BridgeContext,
} from './substrate-bridge.js';

/* I-13 — Intent reducer wiring: conversation turn → Intent */
export {
  processConversationTurn,
  type ChatTurnInput,
  type ChatTurnResult,
} from './chat-service.js';

export { TRADES_GRAMMAR_SPEC } from './trades-grammar-spec.js';

/* I-14 — LLM turn extractor: raw text → TaggedFact[] + MessageExtraction */
export {
  extractConversationTurn,
  parseExtractionResponse,
  type TurnExtractionResult,
  type TurnExtractorOptions,
} from './turn-extractor.js';

/* L-4 — Conversation turn pipeline: message → state → Intent */
export {
  runConversationTurn,
  type PipelineInput,
  type PipelineResult,
} from './pipeline.js';

/* R-1 — Reply generator: state → ConversationAction → reply text */
export {
  generateReply,
  DEFAULT_ESTIMATOR_FN,
  type ReplyGeneratorInput,
  type ReplyGeneratorResult,
  type ReplyLlmFn,
  type EstimatorFn,
  type ConversationTurn,
} from './reply-generator.js';

/* R-2 — Full turn handler: message → reply + intent + done signal */
export {
  handleConversationTurn,
  type TurnHandlerInput,
  type TurnHandlerResult,
} from './turn-handler.js';

```
