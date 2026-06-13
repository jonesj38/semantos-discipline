---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-subscriber.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.047066+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-subscriber.ts

```ts
/**
 * Bundle subscriber — single-cycle polling logic.
 *
 * One pass: ask the `BundleLookupPoller` for fresh bundles addressed
 * to `recipientCertId`, fold each unseen result through the dedupe
 * instance, and dispatch surviving bundles to the user handler.
 *
 * Errors are surfaced via the injected `logger`, never thrown:
 *   - poller throws  → log + return (this cycle delivered nothing)
 *   - handler throws → log + continue with next bundle
 *
 * The cycle is `cancelled`-aware: callers pass a function that
 * returns the current cancellation state so a slow handler can't
 * deliver bundles after the subscription has been torn down.
 *
 * No interval / setInterval lives here — the poller module owns
 * driving this function on a clock.
 */

import type { SignedBundle } from "../bundle-envelope.js";
import type { BundleDedupe } from "./bsv-bundle-dedupe.js";
import type { BundleLookupPoller, PolledBundleResult } from "./bsv-bundle-ports.js";

export type BundleHandler<T = unknown> = (
  bundle: SignedBundle<T>,
) => void | Promise<void>;

export type SubscriberLogger = (message: string, err?: unknown) => void;

export interface SubscriberCycleDeps<T = unknown> {
  /** Lookup port — production adapter wraps BRC-24 SLAP resolver. */
  poller: BundleLookupPoller;
  /** Per-subscription dedupe set — outpoints already delivered. */
  dedupe: BundleDedupe;
  /** User-supplied delivery callback. */
  handler: BundleHandler<T>;
  /** Recipient certId scoping the lookup. */
  recipientCertId: string;
  /** Cancellation probe — `true` when the subscription is torn down. */
  isCancelled: () => boolean;
  /** Error sink. Default: `console.warn`. */
  logger: SubscriberLogger;
}

/**
 * Run one poll → dedupe → dispatch cycle.
 *
 * Resolves once every survivor has been awaited or the cycle was
 * cancelled mid-loop. Never throws — internal failures land in the
 * logger.
 */
export async function runSubscriberCycle<T>(
  deps: SubscriberCycleDeps<T>,
): Promise<void> {
  if (deps.isCancelled()) return;

  let results: PolledBundleResult<unknown>[] = [];
  try {
    results = await deps.poller.pollForRecipient(deps.recipientCertId);
  } catch (err) {
    deps.logger(
      `poll failed for ${deps.recipientCertId.slice(0, 8)}`,
      err,
    );
    return;
  }

  for (const { outpoint, bundle } of results) {
    if (deps.isCancelled()) return;
    if (!deps.dedupe.markSeen(outpoint)) continue;
    try {
      await deps.handler(bundle as SignedBundle<T>);
    } catch (err) {
      deps.logger(`handler threw for outpoint ${outpoint}`, err);
      // Continue — one bad handler call must not stop the loop.
    }
  }
}

```
