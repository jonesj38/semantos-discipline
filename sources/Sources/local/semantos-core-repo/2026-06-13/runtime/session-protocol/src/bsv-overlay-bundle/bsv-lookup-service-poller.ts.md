---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-lookup-service-poller.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.049000+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-lookup-service-poller.ts

```ts
/**
 * Production adapter: BRC-24 SLAP lookup → `BundleLookupPoller`.
 *
 * Wraps a BRC-24 resolver against `ls_semantos_bundles_by_recipient`,
 * decodes each output with `decodeBundlePushDrop`, and yields only
 * outputs whose magic + JSON round-trip cleanly and whose recipient
 * certId matches the queried recipient.
 *
 * The adapter does NOT track a cursor — every poll asks the service
 * for the full set of outputs addressed to this recipient. The
 * client-level dedupe (by outpoint) handles the repetition. This
 * keeps the adapter stateless and idempotent across restarts.
 * Cursor-based optimisation can be layered in later without
 * changing the port.
 */

import type { BundleLookupPoller, PolledBundleResult } from "./bsv-bundle-ports.js";

/** Binding for the BRC-24 lookup surface — production impl wraps `LookupServiceClient`. */
export interface BundleLookupQuery {
  /** The service name. Production uses `ls_semantos_bundles_by_recipient`. */
  service: string;
  /** Query shape — the client passes `{ recipientCertId }`. */
  query: { recipientCertId: string };
}

export interface BundleLookupAnswer {
  /** Always `"output-list"` in production. */
  type: "output-list" | "freeform";
  /** Output records — each carries BEEF + outputIndex. */
  outputs?: { beef: number[]; outputIndex: number }[];
}

export interface LookupResolverLike {
  query(q: BundleLookupQuery): Promise<BundleLookupAnswer>;
}

export interface LookupServiceBundlePollerConfig {
  /** BRC-24 resolver — `LookupServiceClient`'s internal resolver works. */
  resolver: LookupResolverLike;
  /** Lookup service name. Default `ls_semantos_bundles_by_recipient`. */
  service?: string;
  /**
   * BEEF → outputs parser. Injected so tests can skip `@bsv/sdk`.
   * Returns one entry per output in the BEEF tx.
   */
  parseOutputs?: (
    beef: number[],
    outputIndex: number,
  ) => {
    txid: string;
    lockingScript: import("@bsv/sdk").LockingScript;
  } | null;
}

/**
 * Default BEEF → output parser. Decodes the BEEF, plucks the output
 * at `outputIndex`, returns its `txid` + `lockingScript`. Returns
 * `null` if the BEEF is malformed or the index is out of range —
 * the poller uses `null` as "skip this entry."
 */
export function defaultParseOutputs(
  beef: number[],
  outputIndex: number,
): { txid: string; lockingScript: import("@bsv/sdk").LockingScript } | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { Transaction: Tx } = require("@bsv/sdk") as typeof import("@bsv/sdk");
    const tx = Tx.fromBEEF(beef);
    const out = tx.outputs[outputIndex];
    if (!out) return null;
    return { txid: tx.id("hex"), lockingScript: out.lockingScript };
  } catch {
    return null;
  }
}

/**
 * Build a `BundleLookupPoller` around a BRC-24 resolver.
 */
export function createLookupServiceBundlePoller(
  config: LookupServiceBundlePollerConfig,
): BundleLookupPoller {
  const {
    resolver,
    service = "ls_semantos_bundles_by_recipient",
    parseOutputs = defaultParseOutputs,
  } = config;

  // Delayed import so tests can stub it. We use a function ref
  // rather than re-importing on every poll.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { decodeBundlePushDrop } = require(
    "../bsv-overlay-bundle-pushdrop.js",
  ) as typeof import("../bsv-overlay-bundle-pushdrop.js");

  return {
    async pollForRecipient(recipientCertId: string) {
      const answer = await resolver.query({
        service,
        query: { recipientCertId },
      });

      if (answer.type !== "output-list" || !answer.outputs) return [];

      const results: PolledBundleResult<unknown>[] = [];
      for (const { beef, outputIndex } of answer.outputs) {
        const parsed = parseOutputs(beef, outputIndex);
        if (!parsed) continue;
        const decoded = decodeBundlePushDrop(parsed.lockingScript);
        if (!decoded) continue;
        if (decoded.recipientCertId !== recipientCertId) continue;
        results.push({
          outpoint: `${parsed.txid}.${outputIndex}`,
          bundle: decoded.bundle,
        });
      }
      return results;
    },
  };
}

```
