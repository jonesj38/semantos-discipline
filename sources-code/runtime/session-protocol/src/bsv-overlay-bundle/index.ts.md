---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.048176+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/index.ts

```ts
/**
 * BSV-overlay bundle client — barrel.
 *
 * The public API exported from `@semantos/session-protocol` is
 * unchanged after the prompt-40 split. This barrel just re-exports
 * the per-concern modules so the legacy
 * `bsv-overlay-bundle-client.ts` shim and external consumers keep
 * working.
 *
 * Every module file in this directory starts with `bsv-` to match
 * the phase35b `G35A.12` gate, which restricts `@bsv/sdk` imports
 * to `signer.ts` plus basenames starting with `bsv-`.
 */

export {
  createBsvOverlayBundleClient,
  type BsvOverlayBundleClientConfig,
} from "./bsv-bundle-client-facade.js";

export {
  publishOne,
  publishMany,
  senderPubkeyHexFrom,
  type BundlePublisherDeps,
} from "./bsv-bundle-publisher.js";

export {
  runSubscriberCycle,
  type BundleHandler,
  type SubscriberCycleDeps,
  type SubscriberLogger,
} from "./bsv-bundle-subscriber.js";

export {
  startBundlePoller,
  type StartPollerArgs,
  type PollerHandle,
  type IntervalHandle,
  type IntervalScheduler,
} from "./bsv-bundle-poller.js";

export {
  createBundleDedupe,
  type BundleDedupe,
  type DedupeEvent,
  type DedupeListener,
} from "./bsv-bundle-dedupe.js";

export type {
  BundleTxSender,
  BundleLookupPoller,
  PolledBundleResult,
} from "./bsv-bundle-ports.js";

export {
  createWalletClientBundleTxSender,
  defaultParseTx,
  type BRC100WalletLike,
  type ShipSubmitterLike,
  type WalletClientBundleTxSenderConfig,
} from "./bsv-wallet-tx-sender.js";

export {
  createLookupServiceBundlePoller,
  defaultParseOutputs,
  type BundleLookupQuery,
  type BundleLookupAnswer,
  type LookupResolverLike,
  type LookupServiceBundlePollerConfig,
} from "./bsv-lookup-service-poller.js";

```
