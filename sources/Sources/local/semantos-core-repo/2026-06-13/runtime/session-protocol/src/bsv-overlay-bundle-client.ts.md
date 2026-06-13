---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.034612+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle-client.ts

```ts
/**
 * @deprecated Re-export shim.
 *
 * The original 481-LOC `bsv-overlay-bundle-client.ts` was decomposed
 * in prompt 40 into per-concern modules under `./bsv-overlay-bundle/`:
 *
 *   - `ports.ts`                    — narrow `BundleTxSender` /
 *                                     `BundleLookupPoller` interfaces
 *   - `bundle-dedupe.ts`            — observable seen-outpoint set
 *   - `bundle-publisher.ts`         — `publishOne` / `publishMany`
 *   - `bundle-subscriber.ts`        — single-cycle poll / dedupe /
 *                                     dispatch
 *   - `bundle-poller.ts`            — interval driver + stoppable
 *                                     handle
 *   - `bundle-client-facade.ts`     — composes the above into
 *                                     `OverlayBundleClient`
 *   - `wallet-tx-sender.ts`         — BRC-100 + SHIP adapter
 *   - `lookup-service-poller.ts`    — BRC-24 SLAP adapter
 *
 * This file remains as a re-export shim so existing imports
 * (`from "./bsv-overlay-bundle-client.js"`) keep working without
 * source changes. New code should import from
 * `./bsv-overlay-bundle/` directly.
 */

export {
  createBsvOverlayBundleClient,
  createWalletClientBundleTxSender,
  createLookupServiceBundlePoller,
} from "./bsv-overlay-bundle/index.js";

export type {
  BsvOverlayBundleClientConfig,
  BundleTxSender,
  BundleLookupPoller,
  PolledBundleResult,
  BRC100WalletLike,
  ShipSubmitterLike,
  WalletClientBundleTxSenderConfig,
  LookupResolverLike,
  LookupServiceBundlePollerConfig,
  BundleLookupQuery,
  BundleLookupAnswer,
} from "./bsv-overlay-bundle/index.js";

```
