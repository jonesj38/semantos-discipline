---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-poller.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.048443+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-poller.ts

```ts
/**
 * Bundle poller — interval-driven subscription lifecycle.
 *
 * Wraps `runSubscriberCycle` in a `setInterval`-style timer +
 * cancellation flag, exposing a single `start` function that returns
 * a stoppable handle. The handle:
 *   - cancels in-flight cycles via the `isCancelled` probe
 *   - clears the interval timer
 *   - clears the dedupe set so a re-subscribe starts fresh
 *
 * The first poll fires immediately (no waiting one full interval for
 * the subscriber's first delivery), then on every `pollIntervalMs`.
 *
 * `setInterval` / `clearInterval` are injectable so the gate test
 * can drive the loop with a manual clock.
 */

import { createBundleDedupe, type BundleDedupe } from "./bsv-bundle-dedupe.js";
import {
  runSubscriberCycle,
  type BundleHandler,
  type SubscriberLogger,
} from "./bsv-bundle-subscriber.js";
import type { BundleLookupPoller } from "./bsv-bundle-ports.js";

export type IntervalHandle = ReturnType<typeof setInterval>;

export interface IntervalScheduler {
  setInterval: (cb: () => void, ms: number) => IntervalHandle;
  clearInterval: (handle: IntervalHandle) => void;
}

const defaultScheduler: IntervalScheduler = {
  setInterval: (cb, ms) => setInterval(cb, ms),
  clearInterval: (h) => clearInterval(h),
};

export interface PollerHandle {
  /** Cancel the interval, abort any in-flight cycle, clear dedupe. */
  stop(): void;
  /** Test/observability hook — the dedupe instance backing this poller. */
  readonly dedupe: BundleDedupe;
}

export interface StartPollerArgs<T = unknown> {
  /** Lookup port — production adapter wraps BRC-24 SLAP resolver. */
  poller: BundleLookupPoller;
  /** User delivery callback. */
  handler: BundleHandler<T>;
  /** Recipient certId scoping the lookup. */
  recipientCertId: string;
  /** Interval between polls, in ms. */
  pollIntervalMs: number;
  /** Error sink. */
  logger: SubscriberLogger;
  /**
   * Optional dedupe instance. Default: a fresh `createBundleDedupe()`.
   * Inject when the caller wants to observe dedupe state from outside.
   */
  dedupe?: BundleDedupe;
  /** Injectable scheduler. Default: real `setInterval`/`clearInterval`. */
  scheduler?: IntervalScheduler;
}

/**
 * Start a poller. Fires one immediate cycle, then on every
 * `pollIntervalMs`. Returns a handle whose `stop()` is idempotent.
 */
export function startBundlePoller<T = unknown>(
  args: StartPollerArgs<T>,
): PollerHandle {
  const dedupe = args.dedupe ?? createBundleDedupe();
  const scheduler = args.scheduler ?? defaultScheduler;
  let cancelled = false;

  const cycle = (): Promise<void> =>
    runSubscriberCycle({
      poller: args.poller,
      dedupe,
      handler: args.handler,
      recipientCertId: args.recipientCertId,
      isCancelled: () => cancelled,
      logger: args.logger,
    });

  // Kick off an immediate poll so the subscriber doesn't wait a
  // full interval for the first delivery.
  void cycle();

  const timer = scheduler.setInterval(() => {
    void cycle();
  }, args.pollIntervalMs);

  let stopped = false;
  return {
    stop(): void {
      if (stopped) return;
      stopped = true;
      cancelled = true;
      scheduler.clearInterval(timer);
      dedupe.clear();
    },
    get dedupe() {
      return dedupe;
    },
  };
}

```
