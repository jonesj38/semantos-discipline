---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.343018+00:00
---

# runtime/intent/src/index.ts

```ts
/**
 * @semantos/intent — universal intent pipeline.
 *
 * Public API for the substrate that takes an Intent (from NL, voice,
 * shell, UI, governance, network, scheduler, or host.exec) and runs
 * it through SIR → IR → bytes → cell engine → IntentResult, with
 * correlation-ID observability at every stage boundary.
 *
 * Design: docs/INTENT-PIPELINE.md.
 */

export type {
  // Branded IDs
  CorrelationId,
  IntentId,
  PatchId,
  CellId,
  // Core shapes
  Intent,
  IntentSource,
  IntentContext,
  IntentResult,
  IntentRejection,
  HatContext,
  UIHint,
  // Triage + ratification
  TriageOutcome,
  RatificationPatch,
  Signature,
  // Stage events
  StageName,
  StageEvent,
  Logger,
  // Kernel-surface placeholders (resolve in Slice 1.9/1.10)
  Cell,
  ScriptResult,
  Receipt,
} from './types';

// Logger sinks
export {
  createJsonlStderrLogger,
  createInMemoryLogger,
} from './logger';
export type { InMemoryLogger } from './logger';

// HatContext builder
export {
  buildHatContext,
  defaultTrustCeiling,
  isDevIdentityStub,
  NoActiveHatError,
  MissingCertError,
} from './hat-context';
export type {
  HatLike,
  IdentityLike,
  IdentityServiceLike,
  ExtensionContextLike,
  BuildHatContextInput,
} from './hat-context';

// SIR builder — pure Intent + HatContext → SIRProgram
export { buildSIR } from './sir-builder';

// Confidence scoring — composite signal for NL/voice producers
export { score as scoreConfidence } from './confidence';
export type { ConfidenceContext, ConfidenceBreakdown } from './confidence';

// Receipt + UIHint
export { buildReceipt } from './receipt';
export type { BuildReceiptInput } from './receipt';
export { deriveUIHint } from './ui-hint';
export type { DeriveUIHintInput } from './ui-hint';

// Pipeline orchestrator
export { processIntent } from './pipeline';
export type { PipelineDeps } from './pipeline';

// RM-091 — producer-boundary helper (mints correlationId, emits
// `intent_produced`, threads same id through reducer + Intent).
export { produceIntent } from './produce-intent';
export type {
  ProduceIntentInput,
  ProduceIntentDeps,
  ProduceIntentResult,
} from './produce-intent';

// Conversation-patch cheap-path primitive (Slice 2a)
export { writeConversationPatch } from './conversation-patch';
export type {
  ConversationPatchShape,
  ConversationPatchInput,
  ConversationPatchDeps,
  ConversationPatchResult,
} from './conversation-patch';

// Triage + ratification (Slice 2b)
export {
  triage,
  buildProposeIntent,
  createRulesClassifier,
  neverIntentClassifier,
} from './triage';
export type {
  Classifier,
  ClassifierInput,
  TriageInput,
  TriageDeps,
  BuildProposeIntentInput,
  RulesClassifierOptions,
} from './triage';

export { issueRatification } from './ratification';
export type {
  RatificationPatchShape,
  IssueRatificationInput,
  IssueRatificationDeps,
  IssueRatificationResult,
} from './ratification';

// handleMessage orchestrator — conversation + triage + dispatch
export {
  handleMessage,
  createInMemoryPendingRegistry,
} from './handle-message';
export type {
  HandleMessageInput,
  HandleMessageDeps,
  HandleMessageResult,
  PendingProposal,
  PendingProposalLookup,
} from './handle-message';

// A5 calendar guard — injectable time-bound-commitment arbiter.
export { extractProposedSlot } from './calendar-guard';
export type {
  CalendarGuard,
  ProposedSlot,
  ConflictReport,
  CalendarConflictRecord,
  FreeWindow,
  FreeWindowsQuery,
} from './calendar-guard';

// A8 voice (D-A7) — cert-bound voice-session stub. Future
// voice-transcription work consumes this contract; today it produces
// signed transcripts whose keyId equals the speaker's cert_id and
// whose sessionId is deterministic in (cert_id, startedAt).
export {
  // Disambiguated: `./voice` and `./hat-context` each define a
  // distinct `MissingCertError` class; both are re-exported from this
  // barrel. The hat-context one is the canonical top-level
  // `MissingCertError` (cert-context boot error, the foundational
  // one); the voice-session error is exposed as
  // `VoiceMissingCertError`. No consumer imports either via this
  // barrel today (verified repo-wide), so this is a non-breaking
  // hygiene fix that resolves the duplicate-export build failure
  // surfaced by the Wave Cap-Enforce / Canonical-Cartridge merge.
  MissingCertError as VoiceMissingCertError,
  VoiceContractError,
  addTranscript,
  canonicalTranscriptPreimage,
  createVoiceSession,
  deriveTranscriptId,
  deriveVoiceSessionId,
  transcriptBelongsToSession,
  verifyTranscript,
} from './voice';
export type {
  AddTranscriptOptions,
  CreateVoiceSessionOptions,
  Transcript,
  TranscriptId,
  VerifySignatureFn,
  VoiceIdentityProvider,
  VoiceSession,
  VoiceSessionId,
  VoiceSignature,
} from './voice';

```
