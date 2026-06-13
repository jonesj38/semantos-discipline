---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.050490+00:00
---

# runtime/session-protocol/src/swarm/index.ts

```ts
/**
 * Paid swarm — BitTorrent-style file distribution over the semantos substrate.
 *
 * Data plane (this package): chunk → manifest/infohash → HAVE gossip →
 * rarest-first → fetch + per-cell merkle verify → reassemble, with a prepay
 * paid loop. Transport-agnostic: programs against `SwarmTransport` (UDP
 * multicast today, WSS later). The brain (Zig cartridge) is the cold-path
 * tracker / persistent seeder / settlement ledger via `SwarmBrainClient`.
 *
 * Manifest + file/proof primitives are the canonical, Zig-shared surface and
 * live in `@semantos/protocol-types` (swarm-manifest / swarm-file).
 */

export {
  type SwarmTransport,
  type FrameHandler,
  type UdpSwarmTransportOptions,
  udpSwarmTransport,
  SwarmBus,
  inMemorySwarmTransport,
} from './swarm-transport';

export {
  type SwarmBrainClient,
  type SeederInfo,
  type LocateResult,
  type AnchorProof,
  type SwarmReceipt,
  FakeBrainClient,
} from './brain-client';

export {
  RpcSwarmBrainClient,
  type RpcChannel,
} from './rpc-brain-client';

export {
  WssRpcChannel,
  type WssRpcChannelOptions,
  type WebSocketLike,
  type WebSocketFactory,
} from './wss-rpc-channel';

export { FileBrainClient } from './file-brain-client';

export {
  LayeredBrainClient,
  InMemorySeederRegistry,
  overlayManifestResolver,
  mergeSeeders,
  isManifestFor,
  type LayeredBrainClientOptions,
  type SeederRegistry,
  type ManifestResolver,
  type LookupLike,
} from './layered-brain-client';

export {
  multicastGroupForRef,
  multicastGroupForInfohash,
  multicastGroupForTxid,
  type RendezvousOptions,
  type Rendezvous,
} from './transfer-rendezvous';

export {
  SEEDER_AD_VERSION,
  encodeSeederAd,
  decodeSeederAd,
  overlaySeederRegistry,
  type SeederAdvertisement,
  type OverlaySubmit,
  type OverlayQuery,
  type OverlaySeederRegistryIo,
} from './seeder-advertisement';

export {
  syncCells,
  packCellBatch,
  unpackCellBatch,
  cellHash,
  MemoryCellStore,
  CELL_BYTES,
  type CellSource,
  type CellSink,
  type SyncResult,
  type SyncOptions,
} from './brain-sync';

export {
  makeBcaResolver,
  deriveContactBcaBytes,
  contactSeederInfo,
  type BcaNetwork,
  type ContactRef,
  type ContactBcaResolver,
} from './contact-bca';

export {
  contactSeederRegistry,
  InMemorySeedPresence,
  type ContactRoster,
  type SeedPresence,
  type ContactSeederRegistryOptions,
} from './contact-seeder-registry';

export {
  transferEdge,
  deriveTransferKey,
  sealForEdge,
  openFromEdge,
  isSealed,
  type TransferEdge,
} from './transfer-cipher';

export {
  SwarmClient,
  SharedTransport,
  type SwarmClientOptions,
  type TorrentInfo,
  type TorrentKind,
  type TorrentStatus,
} from './swarm-client';
export { SwarmDaemon, serveSwarmDaemon, type DaemonHandle } from './swarm-daemon';
export {
  MeteredTransfer,
  createMeteredTransfer,
  type MeteredTransferOptions,
  type TransferStrategy,
  type TransferStatus,
  type FetchOptions,
} from './metered-transfer';
export { udpMulticastTransport, type UdpMulticastOptions } from './udp-multicast-transport';
export {
  serveSwarmRelay,
  wssSwarmTransport,
  type SwarmRelayHandle,
  type WssSwarmTransportOptions,
  type WssFactory,
  type WebSocketLike as WssWebSocketLike,
} from './swarm-wss-relay';
export {
  brc100WalletPort,
  resolveWalletPort,
  walletIdentityPubHex,
  type WalletSpec,
} from './swarm-wallet';

export {
  WalletEconomicPort,
  whatsOnChainLookup,
  type PaymentWallet,
  type TxLookup,
  type TxOutputView,
} from './wallet-economic-port';

export {
  MeteredFlowPayer,
  MeteredFlowVerifier,
  MeteredFlowServePolicy,
  MultiChannelServePolicy,
  type ChannelRegistration,
  meteredFlowPayPolicy,
  protoWalletPort,
} from './metered-flow';

export {
  SwarmSession,
  type SwarmSessionOptions,
  type ServePolicy,
  type PayPolicy,
} from './swarm-session';

export {
  PaidSeeder,
  makePayPolicy,
  quotePricePerCell,
} from './paid-seeder';

export {
  AccessGrantServePolicy,
  makeGrantPayPolicy,
  andServePolicies,
  andPayPolicies,
  type AccessGrantVerifier,
  type AccessGrantVerification,
  type AccessGrantProver,
  type GrantRecord,
  type GrantResolver,
  type AccessGrantServePolicyOptions,
} from './access-grant-serve';

export {
  BrainAccessGrantVerifier,
  type BrainAccessGrantVerifierOptions,
} from './brain-access-grant-verifier';

export {
  BrainRpcChannel,
  type BrainRpcChannelOptions,
} from './brain-rpc-channel';

export {
  signAccessChallenge,
  granteePubkeyOf,
  bsvAccessGrantProver,
  randomGranteeProver,
} from './bsv-access-grant-signer';

export {
  segmentBuffer,
  MediaSegmenter,
  encodeBroadcastPlaylist,
  decodeBroadcastPlaylist,
  broadcastContentHash,
  publishBroadcast,
  consumeBroadcast,
  type MediaSegment,
  type SegmenterOptions,
  type BroadcastSegmentRef,
  type BroadcastPlaylist,
  type BroadcastPublishResult,
  type SegmentFetcher,
  type ConsumeOptions,
} from './media-broadcast';

export {
  seedBroadcast,
  swarmBroadcastFetcher,
  consumeSwarmBroadcast,
  type BroadcastSessionFactory,
} from './swarm-broadcast';

export {
  bitfieldBytes,
  emptyBitfield,
  hasCell,
  setHave,
  clearHave,
  bitfieldFor,
  haveCount,
  missingCells,
  isComplete,
  mergeBitfields,
  encodeHave,
  decodeHave,
  havePayloadSize,
  type HavePayload,
} from './have-bitfield';

export {
  availabilityMap,
  rarestFirst,
  holdersOf,
  randomFirstPiece,
  isEndgame,
  endgameTargets,
  type SelectionInput,
  type EndgameRequest,
} from './piece-selection';

export {
  MSG_SWARM_HAVE,
  MSG_SWARM_REQUEST,
  MSG_SWARM_CELL,
  MSG_SWARM_PAY,
  encodeRequest,
  decodeRequest,
  encodeCell,
  decodeCell,
  encodePay,
  decodePay,
  frameSwarm,
  parseSwarm,
  isSwarmMsgType,
  type SwarmRequest,
  type SwarmCell,
  type SwarmPay,
  type SwarmPayment,
  type SwarmGrantProof,
} from './swarm-wire';

```
