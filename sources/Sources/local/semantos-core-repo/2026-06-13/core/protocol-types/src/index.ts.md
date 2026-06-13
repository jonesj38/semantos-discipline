---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.839767+00:00
---

# core/protocol-types/src/index.ts

```ts
/**
 * @semantos/protocol-types
 *
 * Bridge over @semantos/core — re-exports existing types, adds cell-engine-specific types.
 */

// ── Generated constants from constants.json ──
export {
  CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE,
  CONTINUATION_HEADER_SIZE, CONTINUATION_PAYLOAD_SIZE, VERSION,
  MAIN_STACK_CELLS, AUX_STACK_CELLS, MAIN_STACK_BYTES, AUX_STACK_BYTES,
  MAGIC_1, MAGIC_2, MAGIC_3, MAGIC_4,
  Linearity, CommercePhase, TaxonomyDimension, CellType,
  HeaderOffsets,
} from "./constants";

// ── Re-exports from @semantos/core barrel ──
export {
  SemanticType,
  isLinear, isAffine, isRelevant,
  type SemanticObject, type LinearObject, type AffineObject, type RelevantObject,
  type ConsumptionProof, type RevocationProof,
  CapabilityType,
  type CapabilityConstraints, type CapabilityToken,
  type DomainFlag,
  EDGE_CREATION, SIGNING, ENCRYPTION, MESSAGING, ATTESTATION,
  CHILD_CREATION, PERMISSION_GRANT, DATA_SOVEREIGNTY, SCHEMA_SIGNING, METERING,
  PLEXUS_WELL_KNOWN_MIN, PLEXUS_WELL_KNOWN_MAX,
  EXTENDED_STANDARD_MIN, EXTENDED_STANDARD_MAX,
  CLIENT_SOVEREIGN_MIN, CLIENT_SOVEREIGN_MAX,
  classifyFlag, isReserved, toProtocolId,
} from "@semantos/core";

// ── Cell-ops re-exports (moved from @semantos/core barrel) ──
export {
  KernelError,
  TypeClassification,
  type PlexusKernelWasm,
  type PlexusKernelHostImports,
  loadKernel,
} from "@semantos/cell-ops";

// ── Cell-header layout (new — not in @semantos/core) ──
export { CellHeaderLayout, serializeCellHeader, deserializeCellHeader, type FieldLayout, type CellHeader } from "./cell-header";

// ── Escalation descriptor (D-OCT-escalation-descriptor, step 1/5 of octave-escalation unification) ──
// Spec: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5.
// NO behaviour change — wire shape, accessors, and tests only.
export {
  ESCALATION_DESCRIPTOR_SIZE,
  EscalationDescriptorOffsets,
  PAYLOAD_OFFSET as ESCALATION_PAYLOAD_OFFSET,
  Rung,
  OctaveLevel,
  readRung,
  writeRung,
  readOctaveLevel,
  writeOctaveLevel,
  readChildCount,
  writeChildCount,
  readTotalBytes,
  writeTotalBytes,
  readDescriptor as readEscalationDescriptor,
  writeDescriptor as writeEscalationDescriptor,
  escalationDescriptorOffsetUnrouted,
  escalationDescriptorOffsetRouted,
  CANONICAL_DESCRIPTOR_BYTES,
  CANONICAL_TOTAL_BYTES,
  type EscalationDescriptor,
} from "./escalation-descriptor";

// ── Cell-routing region (cell-routing-v1; MNCA-LAYER-COLLAPSE-BRIEF §2.1) ──
export {
  RoutingRegionOffsets,
  ROUTING_REGION_START,
  ROUTING_REGION_END,
  ROUTING_REGION_SIZE,
  ROUTING_CHECKSUM_COVERAGE_START,
  ROUTING_CHECKSUM_COVERAGE_END,
  ROUTING_VERSION_V1,
  RoutingMode,
  RoutingFlag,
  readRoutingRegion,
  writeRoutingRegion,
  computeRoutingChecksum,
  setRoutingChecksum,
  verifyRoutingChecksum,
  isRouted,
  readRoutingMode,
  readPriority,
  hasRoutingFlag,
  crc32,
  type RoutingRegion,
  type RoutingFlagBit,
} from "./cell-routing";

// ── Paid-pubsub overlay (MNCA-LAYER-COLLAPSE-BRIEF §13.4) ──
export {
  RELAY_ADVERTISEMENT_TOPIC,
  RELAY_ADVERTISEMENT_VERSION_V1,
  encodeRelayAdvertisement,
  decodeRelayAdvertisement,
  relayAdvertisementSigningInput,
  isAdvertisementCurrent,
  pathEndpointsMatch,
  type RelayAdvertisement,
  type TypeHashPath,
} from "./overlay/relay-advertisement";

// ── BSV pushdrop codec (MNCA-LAYER-COLLAPSE-BRIEF §3.1) ──
export {
  OP_DROP,
  OP_CHECKSIG,
  OP_PUSHDATA1,
  OP_PUSHDATA2,
  OP_PUSHDATA4,
  COMPRESSED_PUBKEY_SIZE,
  UNCOMPRESSED_PUBKEY_SIZE,
  CANONICAL_CELL_PUSHDROP_SCRIPT_SIZE,
  pushPrefix,
  buildPushdropLockingScript,
  parsePushdropLockingScript,
  type ParsedPushdrop,
} from "./cell-pushdrop";

// ── MNCA cell-type registry (MNCA-LAYER-COLLAPSE-BRIEF §13.7) ──
// Identity (typeHash) lives in cartridges/mnca/cartridge.json per T3.b.
// computeMncaTypeHash / buildMncaTypeHashRegistry / mncaTypeHashHex were
// deleted — callers use buildTypeHash() from this same module applied
// to MNCA_TRIPLES[name], or look up via the manifest-driven cartridge
// registry from @semantos/experience-cartridge.
export {
  MNCA_TYPE_HASH_SIZE,
  MncaCellTypeName,
  MNCA_CELL_TYPE_NAMES,
  MncaTransformEdges,
  isMncaTransform,
  MNCA_TRIPLES,
  mncaTypeHash,
} from "./mnca/cell-types";

// ── BSV substrate cell-type catalog (LINEAR-CELL-SPV-STATE.md §2) ──
// Identity (typeHash + triples) lives in
// cartridges/bsv-anchor-bundle/cartridge.json `cellTypes[]` — manifest-
// driven, same pattern as MNCA. PR-C11-7e (catalog + SPV verify wire
// format), PR-C11-7e-3 (linear anchor + carriage wire formats).
export {
  BSV_CELL_TYPE_HASH_SIZE,
  BsvCellTypeName,
  BSV_CELL_TYPE_NAMES,
  BsvTransformEdges,
  isBsvTransform,
} from "./bsv/cell-types";

// ── SPV verify wire format (PR-C11-7e) ──
// Payload encoders/decoders for the `bsv.spv.verify.intent` + result
// cell pair. Inline-BEEF only in v1; carriage-chain form lands in 7e-3.
export {
  SPV_VERIFY_WIRE_VERSION,
  SPV_VERIFY_INTENT_PREFIX_BYTES,
  SPV_VERIFY_RESULT_BYTES,
  INLINE_BEEF_MAX_BYTES,
  SpvVerifyIntentFlag,
  SpvVerifyOutcome,
  SpvVerifyErrorTag,
  encodeSpvVerifyIntent,
  decodeSpvVerifyIntent,
  encodeSpvVerifyResult,
  decodeSpvVerifyResult,
  type SpvVerifyIntent,
  type SpvVerifyResult,
} from "./bsv/spv-verify";

// ── Partial-tx state-machine wire formats (PR-6 / LOCKSCRIPT-CLEAVAGE §6.3 + §8.3) ──
// Payload encoders/decoders for the `bsv.tx.partial.*` cell group:
// shell (LINEAR) + contribution / assemble / cancel (EPHEMERAL).
export {
  TX_PARTIAL_WIRE_VERSION,
  MAX_COUNTERPARTIES,
  MAX_INLINE_SIG_BYTES,
  HASH160_BYTES,
  COMPRESSED_PUBKEY_BYTES,
  CELL_HASH_BYTES,
  WORKFLOW_ID_BYTES,
  PartialShellStatus,
  PartialCancelReason,
  PARTIAL_CONTRIBUTION_PREFIX_BYTES,
  PARTIAL_ASSEMBLE_BYTES,
  PARTIAL_CANCEL_BYTES,
  encodePartialShell,
  decodePartialShell,
  encodePartialContribution,
  decodePartialContribution,
  encodePartialAssemble,
  decodePartialAssemble,
  encodePartialCancel,
  decodePartialCancel,
  type PartialShell,
  type PartialContribution,
  type PartialAssemble,
  type PartialCancel,
} from "./bsv/tx-partial";

// ── Sign request / response wire formats (PR-6 / §3.5 + §8.3) ──
// Substrate ↔ wallet sign-and-respond cell pair. The wallet sees only
// the digest + derivation context — never the handler script.
export {
  TX_SIGN_WIRE_VERSION,
  TX_SIGN_REQUEST_BYTES,
  TX_SIGN_RESPONSE_PREFIX_BYTES,
  encodeTxSignRequest,
  decodeTxSignRequest,
  encodeTxSignResponse,
  decodeTxSignResponse,
  type TxSignRequest,
  type TxSignResponse,
} from "./bsv/tx-sign";

// ── Assemble / broadcast trigger + result (PR-6 / §8.3) ──
// Broker plumbing: assemble.intent (consumes a partial.shell) → broadcast.intent
// (raw tx for ARC) → broadcast.result ({ outcome, txid, arcStatus, confirmations }).
export {
  TX_BROADCAST_WIRE_VERSION,
  INLINE_TX_MAX_BYTES,
  TX_ASSEMBLE_INTENT_BYTES,
  TX_BROADCAST_INTENT_PREFIX_BYTES,
  TX_BROADCAST_RESULT_BYTES,
  TxAssembleIntentFlag,
  TxBroadcastIntentFlag,
  TxBroadcastOutcome,
  TxBroadcastArcStatus,
  encodeTxAssembleIntent,
  decodeTxAssembleIntent,
  encodeTxBroadcastIntent,
  decodeTxBroadcastIntent,
  encodeTxBroadcastResult,
  decodeTxBroadcastResult,
  type TxAssembleIntent,
  type TxBroadcastIntent,
  type TxBroadcastResult,
} from "./bsv/tx-broadcast";

// ── Typed-segments payload codec + originator path-builder (§13.2 / §4.1) ──
export {
  SEGMENT_BCA_SIZE,
  SEGMENT_TYPE_HASH_SIZE,
  SEGMENT_TUPLE_SIZE,
  TYPED_SEGMENTS_HEADER_SIZE,
  maxSegments,
  encodeTypedSegments,
  decodeTypedSegments,
  buildRoutedCell,
  type TypedSegment,
  type DecodedTypedSegments,
  type BuildRoutedCellInput,
} from "./mnca/typed-segments";

// ── Relay hop-processing — consume-half of source routing (§4.2 / §13.3) ──
export {
  processHop,
  type HopResult,
  type HopRejectReason,
  type ProcessHopOptions,
} from "./mnca/hop-processing";

// ── Forwarding-payment plan — nLockTime refund, BSV-correct (§4.1 / §13.5) ──
export {
  buildForwardingPaymentPlan,
  buildPathPaymentPlans,
  totalPathCostSats,
  isRefundLockTimeInFuture,
  type FundingOutput,
  type RefundTemplate,
  type ForwardingPaymentPlan,
  type BuildForwardingPaymentPlanInput,
  type HopPayment,
  type BuildPathPaymentPlansInput,
} from "./mnca/forwarding-payment";

// ── Relay service table + originator selection — paid-pubsub matching (§13.4) ──
export {
  RelayServiceTable,
  emitAdvertisements,
  selectRelay,
  type RelayServiceEntry,
  type NonceFactory,
  type SignFn,
  type EmitAdvertisementsInput,
  type RelaySelection,
} from "./mnca/relay-table";

// ── MNCA tile codec + reference rule (locked design 2026-05-22) ──
export {
  TILE_HEADER_SIZE,
  TILE_MAX_CELLS,
  maxSquareTileSide,
  encodeTilePayload,
  decodeTilePayload,
  stepTile,
  interiorDims,
  DEFAULT_MNCA_RULE,
  type TileState,
  type MncaRuleParams,
} from "./mnca/tile";

// ── Snapshot anchoring — pushdrop + Tier-0 BRC-42 leaf (§3 / WALLET-TIER-CUSTODY) ──
export {
  buildSnapshotAnchorPlan,
  buildSnapshotAnchorBatch,
  totalAnchorCostSats,
  cellHasType,
  type LeafDeriver,
  type AnchorPlan,
  type BuildSnapshotAnchorPlanInput,
} from "./mnca/snapshot-anchor";

// ── MNCA on-chain anchor state machine (PR-8 / LOCKSCRIPT-CLEAVAGE §7.2) ──
// Cell-type wire formats for `mnca.anchor.create.intent`, `mnca.anchor`
// (LINEAR), `mnca.anchor.transition.intent`, `mnca.anchor.transition.result`.
// Handlers + host_mnca_verify_transition are the PR-8b follow-on.
export {
  MNCA_ANCHOR_WIRE_VERSION,
  COMPRESSED_PUBKEY_BYTES as MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES,
  CELL_HASH_BYTES as MNCA_ANCHOR_CELL_HASH_BYTES,
  TXID_BYTES,
  WORKFLOW_ID_BYTES as MNCA_ANCHOR_WORKFLOW_ID_BYTES,
  INLINE_COMPUTATION_PROOF_MAX_BYTES,
  MNCA_ANCHOR_CREATE_INTENT_BYTES,
  MNCA_ANCHOR_BYTES,
  // PR-8b-vi-1 — legacy v1 length + anchor_utxo_ref field size.
  MNCA_ANCHOR_BYTES_V1,
  ANCHOR_TXID_BYTES,
  MNCA_TRANSITION_INTENT_PREFIX_BYTES,
  MNCA_TRANSITION_RESULT_BYTES,
  AnchorStatus,
  TransitionOutcome,
  TransitionErrorTag,
  encodeMncaAnchorCreateIntent,
  decodeMncaAnchorCreateIntent,
  encodeMncaAnchor,
  decodeMncaAnchor,
  encodeMncaAnchorTransitionIntent,
  decodeMncaAnchorTransitionIntent,
  encodeMncaAnchorTransitionResult,
  decodeMncaAnchorTransitionResult,
  type MncaAnchorCreateIntent,
  type MncaAnchor,
  type MncaAnchorTransitionIntent,
  type MncaAnchorTransitionResult,
} from "./mnca/anchor";

// ── Cell-engine-specific interfaces (new) ──
export type { BCAInput, BCAOutput, BCAVerifyInput, ScriptContext, ScriptResult, LinearityOperation, LinearityResult, CapabilityTokenRef } from "./interfaces";

// ── BCA derivation (D-A0 canonical library) ──
// The canonical TypeScript mirror of core/cell-engine/src/bca.zig.
// Spec source: docs/spec/protocol-v0.5.md §4.3.
// Preferred import: @semantos/protocol-types/bca (named subpath).
// Also re-exported here for convenience — adapters that already import from
// @semantos/protocol-types can use deriveBca without a subpath change.
export {
  deriveBca,
  verifyBca,
  deriveBcaFromPubkey,
  hexToBytes as bcaHexToBytes,
  bytesToHex as bcaBytesToHex,
  BCA_COLLISION_COUNT_MAX,
  BCA_DEFAULT_SUBNET_PREFIX,
  BCA_DEFAULT_MODIFIER,
  BCA_DEFAULT_SEC,
  BCA_DATA_SIZE,
  BCA_MODIFIER_SIZE,
  BCA_SUBNET_PREFIX_SIZE,
  BCA_PUBLIC_KEY_SIZE,
  BCA_IPV6_ADDRESS_SIZE,
} from "./bca";
export type { BcaInput, BcaResult } from "./bca";

// ── WASM contract ──
export { REQUIRED_WASM_EXPORTS, type WasmExportName } from "./wasm-contract";

// ── Content-addressed store (Sovereign Node — Part 1) ──
export type {
  ContentStore,
  ContentRef,
  Hash,
  PutOptions as ContentPutOptions,
  Advertisement,
} from "./content-store";
export {
  hashBytes,
  verifyHash,
  makeHash,
  ContentNotFoundError,
  ContentHashMismatchError,
} from "./content-store";

// ── Storage abstraction (Phase 25A) ──
export type { StorageAdapter, StorageStat, StorageEvent } from "./storage";
export { MemoryAdapter } from "./adapters/memory-adapter";
// NodeFsAdapter omitted from barrel — requires Node.js fs/promises.
// Import directly: import { NodeFsAdapter } from './adapters/node-fs-adapter'
export { OpfsAdapter } from "./adapters/opfs-adapter";
export { IndexedDbAdapter } from "./adapters/indexed-db-adapter";
export { OverlayAdapter } from "./adapters/overlay-adapter";
export { createAdapter } from "./adapters/create-adapter";
export type { CreateAdapterOptions } from "./adapters/create-adapter";

// ── CellStore (Phase 25B) ──
export { CellStore, type CellRef, type CellValue, type PutOptions } from "./cell-store";

// ── Cell-store carriage primitives (chunk / pack / hash) ──
// Re-exported so cartridges can overflow large payloads (e.g. betterment
// release transcripts) across chained continuation cells without re-implementing
// the byte mechanics. Source: src/cell-store/{cell-chunker,cell-packer,content-hasher}.ts
// `./cell-store` is a thin shim exposing only CellStore; pull the carriage
// primitives straight from their modules under cell-store/.
export {
  chunkData,
  reassembleChunks,
  chunkCountFor,
  isChunked,
  type ChunkPlan,
} from "./cell-store/cell-chunker";
export {
  packContinuationCell,
  unpackContinuationCell,
  buildContinuationHeader,
  parseContinuationHeader,
  type ContinuationHeaderFields,
} from "./cell-store/cell-packer";
// NB: the bare `sha256` name is already taken by the paid-swarm export
// (synchronous merkle hash). `defaultSha256` is the content-hasher digest
// (async → lowercase hex) used for whole-payload integrity.
export { defaultSha256 } from "./cell-store/content-hasher";

// ── Paid swarm — manifest (canonical, Zig-shared) + file/proof helpers ──
export {
  sha256,
  SWARM_MANIFEST_VERSION,
  SWARM_MANIFEST_TYPE_NAME,
  SWARM_MANIFEST_TYPE_HASH,
  type SwarmManifest,
  type EncodeManifestCellOptions,
  toHex,
  fromHex,
  bytesEqual,
  canonicalizeManifest,
  computeInfohash,
  buildManifest,
  encodeManifestCell,
  parseManifestCell,
} from "./swarm-manifest";
export {
  SWARM_DATA_CELL_TYPE,
  type DataCellPlan,
  type PublishedFile,
  type CellMerkleProof,
  fileToDataCells,
  dataCellsToFile,
  publishFile,
  generateDataCellProof,
  verifyDataCell,
} from "./swarm-file";

// ── MFP — Metered Flow Protocol (payment channels) ──
export {
  MfpFlowAdapter,
  encodeCommitment,
  encodeBlockGrant,
  type WalletPort,
  type MfpFlowConfig,
  type MfpFlowState,
  type ChannelCommitment,
  type BlockGrant,
  type FlowStep,
  type FundMode,
  type FlowStatus,
} from "./mfp/flow-adapter";
export { mfpProtocolID, mfpKeyID, MFP_SECURITY_LEVEL, MFP_PROTOCOL_PREFIX } from "./mfp/protocol-id";

// ── SemanticFS (Phase 25C) ──
export { SemanticFS, InvalidSemanticPathError, FLAGS_TOMBSTONE, type SemanticFsOptions, type SemanticPutOptions, type ParsedSemanticPath } from "./semantic-fs";
export type { TaxonomyResolver, TaxonomyNode as TaxonomyResolverNode, EmbeddingProvider } from "./taxonomy-resolver";

// ── Anchor Adapter (Phase 26C) ──
export type { AnchorAdapter, AnchorProof, AnchorMetadata, AnchorItem, AnchorConfig, AnchorError, AnchorState } from "./anchor";
export { BsvAnchorAdapter } from "./adapters/bsv-anchor-adapter";
export { StubAnchorAdapter } from "./adapters/stub-anchor-adapter";
export { AnchorScheduler } from "./anchor-scheduler";
export { WalletClient, WalletClientError } from "./wallet-client";
export type { WalletClientConfig, WalletOutput, CreateActionInput, CreateActionRequest, CreateActionResult, InternalizeActionRequest, InternalizeOutput } from "./wallet-client";
// buildMerkleTree and recomputeMerkleRoot are internal to bsv-anchor-adapter

// ── Transition Validator (2PDA ↔ CellToken bridge) ──
export { TransitionValidator, type TransitionValidationResult, type TransitionInput, type CellEngineHandle } from "./transition-validator";

// ── CellToken & Overlay (Phase 25D) ──
export { CellToken } from "./cell-token";
export { createFileTransaction, extractFile, type FileTokenChainResult, type ExtractedFile } from "./cell-token-chain";
export { BsvOverlayAdapter, type BsvOverlayAdapterConfig } from "./adapters/bsv-overlay-adapter";
export { TopicManagerClient, SEMANTOS_TOPICS, topicForKey, validateTopicName, type TopicManagerClientConfig } from "./overlay/topic-manager-client";
export { LookupServiceClient, SEMANTOS_LOOKUP_SERVICES, validateLookupName, type LookupServiceClientConfig, type DecodedLookupOutput } from "./overlay/lookup-service-client";
export { ShardFrame, SHARD_FRAME_MAGIC, SHARD_FRAME_PROTOCOL, SHARD_FRAME_VERSION, SHARD_FRAME_HEADER_SIZE, SHARD_MAX_PAYLOAD_SIZE } from "./overlay/shard-frame";
export { ShardProxyClient, MULTICAST_SCOPE, type ShardProxyConfig, type PublishResult as ShardPublishResult, type MulticastScope } from "./overlay/shard-proxy-client";
export { UhrpResolver, UHRP_LOOKUP_SERVICE, type UhrpAdvertisement } from "./overlay/uhrp-resolver";
export { ProviderDiscovery, type ProviderInfo, type ProviderDiscoveryConfig } from "./overlay/provider-discovery";
export { PaymentMeter, type ProviderBalance } from "./overlay/payment-meter";
export { encryptCell, decryptCell } from "./overlay/encryption";
export { ShardSubscriptionManager, type ShardSubscriptionConfig, type ShardMetrics } from "./overlay/shard-subscription-manager";

// ── Identity adapter (Phase 26A) + canonical cert types (W1.5C-1) ──
// BRC-52 cert types, SignedBundle, IdentityProvider, and IdentityAdapter all
// live in ./identity. The subpath @semantos/protocol-types/identity is the
// canonical import; this barrel re-exports for convenience.
export type {
  // BRC-52 cert types (promoted from @plexus/contracts in W1.5C-1)
  Brc52Cert,
  Brc52Certificate,
  CertIdPreimage,
  CertificatePreimage,
  PlexusCert,
  CertRegistrationRequest,
  CertRegistrationResult,
  CertRegistrationErrorCode,
  Brc100Headers,
  SignedBundle,
  // Canonical IdentityProvider (W1.5C-1 unification)
  IdentityProvider,
  CertHandle,
  // Legacy kernel adapter (Phase 26A, unchanged)
  IdentityAdapter,
  IdentityMode,
  IdentityConfig,
  IdentityError,
  IdentityState,
} from "./identity";
export { canonicalCertPreimage, computeCertId, makeIdentityError, isBrc52Cert } from "./identity";
export { StubIdentityAdapter } from "./adapters/stub-identity-adapter";
export { createIdentityAdapter, resolveIdentityMode } from "./adapters/create-identity-adapter";
export type { CreateIdentityAdapterOptions } from "./adapters/create-identity-adapter";

// ── Anchor adapter extras (Phase 26C) ──
export type { AnchorMode } from "./anchor";
export { createAnchorAdapter } from "./anchor";
// ── Local identity adapter (Phase 26B) ──
export { LocalIdentityAdapter, type LocalIdentityConfig } from "./identity-adapters/LocalIdentityAdapter";
export { CertChainStore, type CertData } from "./identity-adapters/CertChainStore";
export {
  CapabilityTokenValidator,
  type CapabilityToken as LocalCapabilityToken,
  type Brc108CapabilityToken,
  type SpvContext,
  type CapabilityCheckResult,
  MonotoneSpendOracle,
  isCapabilityDomainFlag,
  PERMISSION_GRANT_DERIVATION,
  CHILD_CREATION_DERIVATION,
} from "./identity-adapters/CapabilityTokenValidator";
export { KeyDerivationService } from "./identity-adapters/KeyDerivationService";
export { RecoveryShareManager, type RecoveryShare, type RecoverySession } from "./identity-adapters/RecoveryShareManager";

// ── Network adapter (Phase 26D) ──
export type { NetworkAdapter, NetworkQuery, NetworkResult, NetworkEvent, PublishableObject, PublishOptions, PublishResult, NodeInfo } from "./network";
export { StubNetworkAdapter } from "./adapters/stub-network-adapter";
export { BsvOverlayNetworkAdapter, type BsvOverlayNetworkAdapterConfig } from "./adapters/bsv-overlay-network-adapter";

// ── Extension Config Types (moved from loom) ──
export {
  type ExtensionConfig,
  type Archetype,
  type VisibilityConfig,
  type AccessPolicy,
  type ObjectTypeDefinition,
  type PolicyBinding,
  type LinearityTransition,
  type CapabilityDefinition,
  type ScriptTemplate,
  type FieldDefinition,
  type TaxonomyTree,
  type TaxonomyDimensionDef,
  type TaxonomyNode,
  type ConfigOverlay,
  type PolicyDefinition,
  type ThemeOverride,
  type ConversationFlow,
  type FlowStep,
  type FlowAction,
  type CoordinationModeBinding,
  type DoContext,
  type TalkContext,
  type FindContext,
  type IntentContext,
  type ExtensionTier,
  validateExtensionConfig,
} from "./extension-config-types";

// ── Extension Loading (Phase 26F) ──
export type { ExtensionManifest } from "./extension-manifest";
export { validateExtensionManifest } from "./extension-manifest";
export { ExtensionLoader, ExtensionLoadError, mergeTaxonomyNodes } from "./extension-loader";
export type { ExtensionLoadErrorCode } from "./extension-loader";
export { ExtensionRegistry } from "./extension-registry";

// ── Extension Governance (Phase 36D) ──
export type {
  GovernancePolicy, GovernancePolicyPayload,
  TaxonomyNamespaceReservation, MarketplaceListingRequirements, EmergencyDeprecationPolicy,
  ManifestGovernanceConfig, VersionBumpRules, DeprecationStatus,
  GovernedConsumerBinding, GovernedConsumerBindingPayload,
  EncryptedCredentials, FieldOverride, LocalField, TaxonomyOverride,
  ConstraintViolation, ConstraintResult,
  CompatibilityResult,
  DisputeEscalationRule, GovernanceBallot,
  PublicationResult,
} from "./governance";

// ── Extension Grammar (Phase 36A) ──
export type {
  ExtensionGrammar, GrammarAuthor, GrammarExtends,
  SourceDeclaration, SourceProtocol, AuthType, SourceAuth, RateLimits,
  PaginationType, PaginationConfig, SourceEntity, SourceEndpoint,
  ResponseShape, SourceFieldType, SourceField, RelationshipType, SourceRelationship,
  ObjectTypeDeclaration, ObjectLinearity, PayloadSchemaField,
  TransitionDeclaration, TransitionGuard,
  EntityMapping, EntityTaxonomy, FieldMapping, FieldCoercion,
  FieldTransformType, FieldTransform, MappingCondition, TaxonomyExpression,
  CapabilityId, CapabilityRequirement,
  TaxonomyAxis, TaxonomyExtension, TaxonomyExtensionNode,
  MigrationRule,
  GrammarValidationError, GrammarValidationResult,
} from "./extension-grammar";
export { validateExtensionGrammar } from "./extension-grammar-validator";
export { loadExtensionGrammar, resolveGrammarExtends } from "./extension-grammar-loader";
export { grammarToExtensionConfig } from "./grammar-config-bridge";

// ── UDP transport (substrate abstraction) ──
// The multicast adapter has been promoted to @semantos/session-protocol
// (Phase 35A D35A.3). UdpTransport stays here because it's a substrate
// interface reusable by non-session adapters (ws-node-adapter, webrtc-adapter).
export { LoopbackUdpTransport, NodeUdpTransport, RealUdpTransport } from "./adapters/udp-transport";
export type { UdpTransport, RemoteInfo, MessageCallback } from "./adapters/udp-transport";

// ── Conversation Types (Phase 2) ──
export {
  ConversationType, ContextWeight,
  type EncryptionMetadata, type Thread, type ConversationMessage,
  type PlexusEdgeType, type TypedEdge, type ZoneState, type AgentPersona,
  type ContextConfig, type SerializedConversationStore,
} from "./conversation-types";

// ── Node Bootstrap (Phase 26E) ──
export type { NodeConfig, NodeConfigFile } from "./node-config";
export type { SemantosNode, NodeStatus } from "./types/semantos-node";
export { createNode } from "./node";
export { loadNodeConfig, type CliOverrides } from "./node-config-loader";

// ── Namespace partition (§8 Q2 single source of truth) ──
export {
  PLEXUS_RESERVED_MAX,
  EXTENDED_PLEXUS_MAX,
  OPERATOR_BASE,
  UINT32_MAX,
  isPlexusReserved,
  isExtendedPlexus,
  isOperatorSovereign,
  isValidNamespaceFlag,
  namespaceTier,
} from "./namespace";
export type { NamespaceTier } from "./namespace";

// ── T1: canonical structured typeHash primitive ──
// See docs/design/STRUCTURED-TYPEHASH-CANONICAL.md.
// Zig mirror: core/cell-engine/src/type_hash.zig (parity-tested).
export {
  buildTypeHash,
  isWildcard,
  namespacePrefix,
  typeHashToHex,
  TYPE_HASH_SIZE,
  TYPE_HASH_SEGMENT_COUNT,
  TYPE_HASH_SEGMENT_BYTES,
  WILDCARD_NAMESPACE_PREFIX,
} from "./type-hash";


```
