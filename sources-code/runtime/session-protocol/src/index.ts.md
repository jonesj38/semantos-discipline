---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.035175+00:00
---

# runtime/session-protocol/src/index.ts

```ts
/**
 * @semantos/session-protocol — domain-neutral session skeleton.
 *
 * See docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md for the six-piece design.
 * This barrel is populated incrementally as D35A.1–D35A.6 land.
 */

export type {
  Identity,
  StateMachine,
  TransitionResult,
  SessionDescriptor,
  SessionHandle,
  AgentDescriptor,
  DomainCapability,
  FormationPolicy,
  MeteringHook,
  MeteringTick,
  TopicToGroup,
  TxidProvider,
  HeartbeatSink,
  PeerInfo,
} from "./types.js";

export type { Signer, Verifier } from "./signer.js";
export { BsvSdkSigner, BsvSdkVerifier, StubSigner } from "./signer.js";

// Signed-bundle envelope — generic wrapper for cross-party signed payloads.
export {
  SIGNED_BUNDLE_VERSION,
  canonicalJson,
  signBundle,
  verifyBundle,
  signerIdentityFromIdentity,
} from "./bundle-envelope.js";
export type {
  SignedBundle,
  SignerIdentity,
  RecipientIdentity,
  VerifyResult,
  VerifyErrorCode,
  SignBundleOptions,
  VerifyBundleOptions,
} from "./bundle-envelope.js";

// Cert-trust layer — Slice 5b. Receiver-side trust registry that
// resolves signer.certId to an allowlisted CertRecord and gates
// imports on known + unrevoked + pubkey-matches-cert.
export {
  createInMemoryKnownCertStore,
  verifyBundleWithTrust,
} from "./cert-trust.js";
export type {
  CertRecord,
  KnownCertStore,
  TrustVerifyResult,
  TrustVerifyErrorCode,
  VerifyBundleWithTrustOptions,
} from "./cert-trust.js";

// Handoff-policy layer — Slice 5c. Per-object sender/receiver ACLs
// layered on top of signer trust. Answers "may this trusted signer
// hand THIS object to this recipient?"
export { createAllowlistHandoffPolicy } from "./handoff-policy.js";
export type {
  HandoffContext,
  HandoffDecision,
  HandoffPolicy,
  AllowlistHandoffPolicyConfig,
} from "./handoff-policy.js";

// Bundle transport — Slice 5d. The wire signed+trusted+addressed
// bundles travel on. Transport-agnostic interface + in-memory
// reference implementation for tests/dev. Real transports (WebRTC,
// overlay, HTTP, Plexus edge) drop in under the same interface.
export {
  InMemoryTransportNetwork,
  createInMemoryTransport,
  TransportError,
} from "./bundle-transport.js";
export type {
  BundleTransport,
  ReceiveHandler,
  Unsubscribe,
  TransportErrorCode,
} from "./bundle-transport.js";

// HTTP bundle transport — Slice 5d / OJT-P3. First real transport.
// POST-based wire between peers identified by certId via a static
// peerRegistry. Interface-parity with InMemoryTransport.
export { createHttpTransport } from "./http-transport.js";
export type { HttpBundleTransportOptions } from "./http-transport.js";

// Overlay bundle transport — Slice 5e. BRC-22/24/87-aware wrapper
// around an overlay-network client. Loopback client for gate tests.
export {
  createLoopbackOverlayBundleClient,
  createOverlayBundleTransport,
  SEMANTOS_BUNDLES_TOPIC,
  SEMANTOS_BUNDLES_LOOKUP,
} from "./overlay-bundle-transport.js";
export type {
  OverlayBundleClient,
  PublishReceipt,
} from "./overlay-bundle-transport.js";

// BSV overlay bundle client — Slice 5f. Real BSV-backed
// OverlayBundleClient: PushDrop envelope + BRC-100 wallet createAction
// + BRC-22 SHIP broadcast + BRC-24 SLAP poll. Ships with narrow
// ports so gate tests inject fakes; production adapters wire to
// WalletClient + TopicManagerClient + LookupServiceClient.
export {
  createBsvOverlayBundleClient,
  createWalletClientBundleTxSender,
  createLookupServiceBundlePoller,
} from "./bsv-overlay-bundle-client.js";
export type {
  BsvOverlayBundleClientConfig,
  BundleTxSender,
  BundleLookupPoller,
  PolledBundleResult,
  BRC100WalletLike,
  ShipSubmitterLike,
  LookupResolverLike,
  WalletClientBundleTxSenderConfig,
  LookupServiceBundlePollerConfig,
} from "./bsv-overlay-bundle-client.js";
export {
  encodeBundlePushDrop,
  decodeBundlePushDrop,
  BUNDLE_PUSHDROP_MAGIC,
} from "./bsv-overlay-bundle-pushdrop.js";
export type { DecodedBundleOutput } from "./bsv-overlay-bundle-pushdrop.js";

// BRC-100 wallet-backed Signer — Slice 5h. Replaces StubSigner in
// production so bundles carry signatures derived from the user's
// actual wallet identity key via wallet.createSignature.
export { WalletClientSigner } from "./adapters/bsv-wallet-signer.js";
export type {
  WalletSigningLike,
  WalletClientSignerConfig,
} from "./adapters/bsv-wallet-signer.js";

export { defaultTopicToGroup } from "./topics.js";

export type {
  BCAProvider,
  PlexusCertBCAProviderConfig,
} from "./adapters/bca-provider.js";
export {
  DeterministicBCAProvider,
  PlexusCertBCAProvider,
} from "./adapters/bca-provider.js";
export { deriveBCABytes, bcaBytesToIPv6 } from "./signer.js";

export { SessionRuntime, agentDescriptor, jsonCodec } from "./runtime.js";
export type {
  SessionRuntimeConfig,
  EventCodec,
} from "./runtime.js";

export { broadcastToSession, subscribeToSession } from "./broadcast.js";

export {
  MulticastAdapter,
  PayloadTooLargeError,
  HEADER_SIZE,
  MSG_CELL,
  MSG_CONTROL,
  MSG_HEARTBEAT,
  encodeHeader,
  decodeHeader,
  deriveNodeIdShort,
} from "./adapters/multicast-adapter.js";
export type {
  MulticastAdapterConfig,
  MulticastPeerInfo,
  MulticastHeartbeat,
  ControlMessage,
  DuplicatePathEvent,
  NodeMetadataProvider,
} from "./adapters/multicast-adapter.js";

export {
  LoopbackAdapter,
  LoopbackNetwork,
  DEFAULT_LOOPBACK_NETWORK,
} from "./adapters/loopback-adapter.js";
export type { LoopbackAdapterConfig } from "./adapters/loopback-adapter.js";

// ── Paid swarm (BitTorrent-style file distribution) ──
export * from "./swarm/index.js";

```
