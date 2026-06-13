---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.129285+00:00
---

# runtime/legacy-ingest/src/index.ts

```ts
/**
 * @semantos/legacy-ingest — Paskian migration from legacy stores
 * (Gmail / Meta / WhatsApp / Google Calendar / Xero) into the substrate.
 *
 * LI1: provider-adapter interface, OAuth orchestration (state nonce +
 * PKCE + token exchange + refresh + revoke), encrypted-at-rest grant
 * store, `legacy connect|disconnect|status|providers` REPL verb.
 *
 * LI2: Gmail adapter end-to-end with paginated backfill + raw-blob
 * persistence + `legacy ingest|auto|status` extensions.
 *
 * LI3 (this commit): per-content-type extractor framework + email/rfc822
 * extractor + pre-classifier + thread-collapsing pass + encrypted
 * proposal store. The extractor turns raw items into typed Proposals
 * (SIRPrograms with provenance + confidence) for LI4 ratification.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md.
 */

export type {
  ProviderId,
  Cursor,
  RawItem,
  AccessToken,
  LegacyGrant,
  ListPageResult,
  LegacyProvider,
  OAuthPendingState,
} from './types';

export {
  audit,
  setAuditSink,
} from './audit';
export type { AuditEntry, AuditResult, AuditSink } from './audit';

export {
  LegacyGrantStore,
  GrantStoreLocked,
  GrantStoreCorrupt,
} from './grant-store';
export type {
  GrantPersistence,
  KekProvider,
  LegacyGrantStoreOpts,
} from './grant-store';

export {
  OAuthOrchestrator,
  OAuthError,
  ProviderRegistry,
} from './oauth';
export type {
  ClientConfig,
  FetchLike,
  OAuthOrchestratorOpts,
  PreparedGrant,
} from './oauth';

export {
  PendingStateStore,
  PendingStoreLocked,
} from './pending-state-store';
export type {
  PendingPersistence,
  PendingStateStoreOpts,
  KekProvider as PendingKekProvider,
} from './pending-state-store';

export { RefreshWorker } from './refresh-worker';
export type { RefreshWorkerOpts } from './refresh-worker';

export { LegacyBlobStore } from './blob-store';
export type { BlobStoreOpts } from './blob-store';

export { CursorStore } from './cursor-store';
export type { IngestCheckpoint, CursorStoreOpts } from './cursor-store';

export { IngestWorker } from './ingest-worker';
export type { IngestWorkerOpts, IngestProgress, BackfillOpts } from './ingest-worker';

export {
  GmailProvider,
  GmailApiError,
  GmailUnauthorized,
  GmailRateLimited,
} from './providers/gmail';
export type { GmailProviderOpts } from './providers/gmail';

export {
  MetaProvider,
  MetaTransport,
  MetaApiError,
  MetaWindowExpired,
} from './providers/meta';
export type {
  MetaProviderOpts,
  MetaTransportOpts,
  MetaChannel,
  MetaBusinessPlatform,
  MetaBusinessAsset,
  MetaMessageAttachment,
  MetaWebhookMessage,
  MetaWebhookVerification,
} from './providers/meta';

// ── LI3 — extractor framework + proposal store ──

export { ProposalStore } from './proposal-store';
export type { ProposalStoreOpts, ProposalQuery } from './proposal-store';

export { ExtractorRegistry } from './extractor/registry';
export {
  EmailExtractor,
  parseRfc822,
  EMAIL_EXTRACTOR_VERSION,
} from './extractor/email';
export type { EmailExtractionPayload, EmailExtractorOpts } from './extractor/email';
export {
  MessageExtractor,
  MESSAGE_EXTRACTOR_VERSION,
} from './extractor/message';
export type { MessageExtractionPayload, MessageExtractorOpts } from './extractor/message';
export {
  classifyForExtraction,
  OJT_SENDER_ALLOWLIST,
  OJT_SELF_FORWARD_ADDRESSES,
} from './extractor/pre-classifier';
export type { PreClassification, PreClassifyOptions } from './extractor/pre-classifier';
export { collapseThreads, deduplicateByReferenceNumber } from './extractor/thread';
export type { ThreadCollapseResult, ReferenceDedupeResult } from './extractor/thread';
export { ExtractionRunner } from './extractor/runner';
export type { ExtractionRunnerOpts, ExtractionRunSummary, RunOpts } from './extractor/runner';
export type {
  Proposal,
  ProposalProvenance,
  ProposalStatus,
  ContentExtractor,
  ExtractionOutcome,
  LLMAdapter,
} from './extractor/types';

// ── Attachment OCR ──

export { parseEmailMimeParts, extractAttachmentTexts } from './extractor/attachment';
export type {
  VisionAdapter,
  EmailMimePart,
  ParsedEmailParts,
  PdfTextParser,
} from './extractor/attachment';

// ── PDF byte-parser (D-DOG.1a) ──

export {
  PdfParser,
  PdftotextNotInstalled,
  PdfParseError,
  isLowQuality,
} from './extractor/pdf';
export type {
  PdfParseOpts,
  PdfParseResult,
  PdfTextCache,
  PdfQualityFloor,
  SpawnLike,
  SpawnedProcessLike,
} from './extractor/pdf';

// ── OpenRouter adapter (LLM + vision) ──

export { OpenRouterAdapter, OpenRouterError, OpenRouterRateLimited } from './extractor/openrouter';
export type { OpenRouterAdapterOpts } from './extractor/openrouter';

// ── Ollama adapter (LLM only — local sovereign default) ──

export {
  OllamaAdapter,
  OllamaError,
  OllamaConnectionError,
  OllamaModelNotFound,
  OllamaParseError,
  OllamaTimeout,
} from './extractor/ollama';
export type { OllamaAdapterOpts } from './extractor/ollama';

// ── Anthropic adapter (LLM + vision — BYOK direct) ──

export {
  AnthropicAdapter,
  AnthropicError,
  AnthropicAuthError,
  AnthropicRateLimited,
  AnthropicOverloaded,
  AnthropicConnectionError,
  AnthropicParseError,
  AnthropicTimeout,
  AnthropicTruncated,
} from './extractor/anthropic';
export type { AnthropicAdapterOpts } from './extractor/anthropic';

// ── LLM router (D-DOG.1d) — composes ollama / anthropic / openrouter ──

export {
  LlmRouter,
  LlmRouterAllBackendsFailed,
  LlmRouterMisconfigured,
} from './extractor/router';
export type {
  LlmBackend,
  LlmRouterOpts,
  LlmRouterAdapters,
  RoutedExtractResult,
  RoutedOcrResult,
} from './extractor/router';

// ── Widget chat server ──

export { WidgetServer, WidgetTransport } from './widget/server';
export type {
  WidgetServerOpts,
  StartResponse,
  TurnRequest,
  TurnResponse,
} from './widget/server';
export { MemorySessionStore } from './widget/session-store';
export type { SessionPersistence } from './widget/session-store';

// ── Meta webhook server ──

export { MetaWebhookServer } from './webhook/meta-server';
export type { MetaWebhookServerOpts } from './webhook/meta-server';

// ── Conversation engine (multi-turn intake for widget + Meta DM) ──

export type {
  ConversationChannel,
  ConversationTurn,
  ConversationTurnEvent,
  ConversationTurnSink,
  ConversationSession,
  ConversationFacts,
  ConversationState,
  ConversationTransport,
  TurnResult,
} from './conversation/types';
export { ConversationEngine } from './conversation/engine';
export type { ConversationEngineOpts } from './conversation/engine';
export { ConversationExtractor, CONVERSATION_EXTRACTOR_VERSION } from './conversation/extractor';
export {
  JsonlConversationTurnPatchSink,
  ODDJOBZ_MESSAGE_PATCH_SCHEMA,
  conversationTurnToOddjobzMessagePatch,
  defaultConversationTurnPatchPath,
  rawItemToOddjobzMessagePatch,
} from './conversation/turn-patch-store';
export type {
  ConversationTurnPatchSinkOpts,
  OddjobzMessagePatch,
} from './conversation/turn-patch-store';
export {
  ConversationDispatchRouter,
  routeConversationDispatch,
} from './conversation/dispatch-router';
export type {
  ConversationDispatchCandidate,
  ConversationDispatchDecision,
  ConversationDispatchLane,
  ConversationDispatchResolver,
  ConversationDispatchResolverInput,
  ConversationDispatchRouterOpts,
  ConversationDispatchSlot,
  ConversationDispatchTarget,
  ConversationDispatchTargetType,
  ConversationDispatchTransport,
  RouteConversationDispatchOpts,
} from './conversation/dispatch-router';
export {
  OddjobzConversationGraphResolver,
  defaultOddjobzGraphDir,
} from './conversation/graph-resolver';
export type {
  ConversationPaskQuery,
  OddjobzConversationGraphResolverOpts,
} from './conversation/graph-resolver';
export {
  JsonlConversationDispatchDecisionSink,
  ODDJOBZ_DISPATCH_DECISION_SCHEMA,
  defaultConversationDispatchDecisionPath,
  dispatchDecisionToRecord,
} from './conversation/dispatch-decision-store';
export type {
  ConversationDispatchDecisionSinkOpts,
  OddjobzDispatchDecisionRecord,
} from './conversation/dispatch-decision-store';
export type {
  ConversationExtractionPayload,
  ConversationExtractorOpts,
} from './conversation/extractor';

// ── Pask bridge — feeds ingest:* cells into the constraint graph ──

export { IngestPaskBridge } from './pask-bridge';
export type { PaskInteractFn } from './pask-bridge';

export {
  OddjobzAttentionPaskProjector,
  createOddjobzAttentionSource,
  installOddjobzAttentionPipeline,
} from './attention-projector';
export type {
  InstalledOddjobzAttentionPipeline,
  InstallOddjobzAttentionPipelineOpts,
  OddjobzAttentionSignal,
  OddjobzAttentionSignalRegistryLike,
  OddjobzAttentionSignalSource,
  OddjobzAttentionProjectorOpts,
  OddjobzAttentionReplaySummary,
} from './attention-projector';

// ── Policy engine — Pask-powered auto-ratification decisions ──

export { IngestPolicy } from './policy';
export type {
  PolicyConfig,
  PolicyDecision,
  PaskQueryAdapter,
} from './policy';

// ── LI4 — ratification queue + correction-feedback ──

export type {
  RatificationReceipt,
  CorrectionEdge,
  ProposalRejection,
  BulkRatifyOutcome,
} from './ratification/types';

export { ReceiptStore, CorrectionEdgeStore } from './ratification/store';
export type { ReceiptStoreOpts, CorrectionEdgeStoreOpts } from './ratification/store';

export { FewShotRetriever } from './ratification/few-shot';
export type { FewShotRetrieverOpts } from './ratification/few-shot';

export { RatificationOrchestrator, RatificationError } from './ratification/orchestrator';
export type {
  RatificationOrchestratorOpts,
  CellWriterFn,
  CellWithdrawFn,
} from './ratification/orchestrator';

export { AttentionBridge } from './ratification/attention-bridge';
export type {
  AttentionBridgeOpts,
  LegacyIngestSignalProposal,
  LegacyIngestSubscriber,
  LegacyIngestSubscription,
} from './ratification/attention-bridge';

// ── Operator-supplied OAuth client credentials ──

export {
  ClientConfigStore,
  CachedClientConfigProvider,
} from './client-config-store';
export type {
  StoredClientConfig,
  ClientConfigStoreOpts,
} from './client-config-store';

export { makeRouteLegacy } from './verb';
export type { LegacyVerbContext } from './verb';

// ── D-DOG.1.0b' — Layer-2 ratify seam (brain JSON-RPC cell-writer) ──

export {
  BrainRpcCellWriter,
  BrainRpcCellWriterError,
} from './cell-writer/brain-rpc';
export type {
  BrainRpcCellWriterOpts,
  RatifyProposalResult,
} from './cell-writer/brain-rpc';

// ── U2 — converged-seam CellWriter (RETIRE the ratify_proposal/JSONL
//    island; gmail/meta leads converge on the proven chat seam) ──
export {
  makeConvergedSeamCellWriter,
  proposalLeadName,
  sanitizeName as convergedSanitizeName,
} from './cell-writer/converged-seam';
export type {
  ConvergedSeamDeps,
  ConvergedFetchLike,
} from './cell-writer/converged-seam';

// ── D-Reingest-Typed-Cells (D-RTC.1-7) — typed-cell reingest pipeline ──

export { normalizeAddress } from './address-normalize';
export {
  proposeSiteCell,
  findOrPropose,
  computeSiteCellId,
  deriveLookupKey,
} from './site-dedupe';
export type {
  SitesView,
  SiteProposal,
  SiteMatch,
  SiteDedupeResult,
} from './site-dedupe';
export {
  deriveJobLookupKey,
  proposeJobCell,
  findOrProposeJob,
  computeJobCellId,
  normaliseWorkOrder,
} from './job-dedupe';
export type {
  JobsDedupeView,
  JobProposal,
  JobMatch,
  JobDedupeResult,
  JobIdentityArgs,
} from './job-dedupe';
export {
  classifyRole,
  classifyRoleHeuristic,
} from './role-classifier';
export type {
  ContactRole,
  ClassifyArgs,
  ClassifyResult,
  RoleLLMFallback,
} from './role-classifier';
export {
  ENTITY_TAGS,
  SPEC_CUSTOMER,
  SPEC_ATTACHMENT,
  SPEC_JOB,
  SPEC_SITE,
  encodeSite,
  encodeCustomer,
  encodeJob,
  encodeAttachment,
  linearityFor,
  mapLegacyRole,
} from './cell-encoder';
export type {
  EntityTag,
  LinearityClass,
  EntityTypeSpec,
  EntityEncodeRequest,
  SiteCellPayload,
  CustomerCellPayload,
  JobCellPayload,
  AttachmentCellPayload,
} from './cell-encoder';
export {
  runAttachmentPipeline,
  InMemoryAttachmentBlobStore,
  FsAttachmentBlobStore,
} from './attachment-pipeline';
export type {
  AttachmentBlobStore,
  AttachmentParentSummary,
  AttachmentPipelineResult,
  AttachmentPipelineOpts,
} from './attachment-pipeline';
export {
  reingestProposal,
} from './reingest-worker';
export type {
  EncodeDispatcher,
  ReingestReceipt as ReingestReceiptValue,
  ReingestSkip,
  ReingestOutcome,
  ReingestWorkerArgs,
} from './reingest-worker';
export {
  ReingestReceiptStore,
} from './reingest-receipt-store';
export type {
  ReingestReceipt,
  ReingestReceiptStoreOpts,
} from './reingest-receipt-store';
export {
  resolveJobReference,
  extractServiceTags,
  detectIntent,
  extractMoneyAmounts,
} from './chat-resolver';
export type {
  ChatIntent,
  JobSummary,
  JobsView,
  ResolverArgs,
  ResolverResult,
} from './chat-resolver';
export { BrainJobsView } from './brain-jobs-view';
export type {
  JobsFetcher,
  BrainJobsViewOpts,
} from './brain-jobs-view';
export { ChatResolverAdapter } from './chat-resolver-adapter';
export type { ChatResolverAdapterOpts } from './chat-resolver-adapter';
export { WssEncodeDispatcher } from './wss-encode-dispatcher';
export type { WssEncodeDispatcherOpts } from './wss-encode-dispatcher';

```
