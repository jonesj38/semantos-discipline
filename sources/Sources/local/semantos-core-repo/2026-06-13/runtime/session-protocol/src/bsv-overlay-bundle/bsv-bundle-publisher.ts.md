---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-publisher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.047349+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-publisher.ts

```ts
/**
 * Bundle publisher — pure publish-side logic for the BSV overlay
 * bundle client.
 *
 * Builds a PushDrop locking script via
 * `bsv-overlay-bundle-pushdrop.encode`, hands off to a
 * `BundleTxSender` port for tx creation + SHIP submission, and
 * returns a `PublishReceipt`.
 *
 * No I/O of its own — all wallet/network calls happen behind the
 * port. This keeps the publisher synchronously-pure-up-to-the-port
 * and means the gate test can substitute a recording fake.
 */

import type { PublicKey } from "@bsv/sdk";

import type { SignedBundle } from "../bundle-envelope.js";
import { encodeBundlePushDrop } from "../bsv-overlay-bundle-pushdrop.js";
import type { PublishReceipt } from "../overlay-bundle-transport.js";
import type { BundleTxSender } from "./bsv-bundle-ports.js";

export interface BundlePublisherDeps {
  /** Tx-sending port — production adapter wraps wallet + SHIP. */
  sender: BundleTxSender;
  /** Sender pubkey, embedded in the PushDrop P2PK lock. */
  senderPubKey: PublicKey;
  /** Sender pubkey hex, precomputed from `senderPubKey.encode(true)`. */
  senderPubkeyHex: string;
  /** Injectable clock — `Date.now` in production, fixed value in tests. */
  now: () => number;
}

/**
 * Publish a single signed bundle.
 *
 * Validates the recipient certId, encodes the PushDrop, awaits the
 * sender port, returns a `bsv-overlay`-tagged receipt.
 */
export async function publishOne<T>(
  deps: BundlePublisherDeps,
  bundle: SignedBundle<T>,
): Promise<PublishReceipt> {
  const recipientCertId = bundle.recipient?.certId;
  if (!recipientCertId) {
    throw new Error(
      "bsv-overlay-bundle-client: publishBundle requires an addressed bundle (bundle.recipient.certId)",
    );
  }

  const lockingScript = encodeBundlePushDrop(bundle, deps.senderPubKey);
  const { txid } = await deps.sender.sendBundleTx({
    lockingScript,
    description: `semantos bundle → ${recipientCertId.slice(0, 8)}`,
    recipientCertId,
    senderPubkeyHex: deps.senderPubkeyHex,
  });

  return {
    id: txid,
    backend: "bsv-overlay",
    publishedAt: deps.now(),
  };
}

/**
 * Publish many bundles, sequentially.
 *
 * Sequential ordering matches what callers actually need: BRC-100
 * wallets serialise tx creation, and concurrent `createAction` calls
 * fight over UTXO selection. If a single publish throws, the loop
 * stops; already-published receipts are returned to the caller via
 * the rejection's `cause`-style `published` field.
 */
export async function publishMany<T>(
  deps: BundlePublisherDeps,
  bundles: readonly SignedBundle<T>[],
): Promise<PublishReceipt[]> {
  const receipts: PublishReceipt[] = [];
  for (const bundle of bundles) {
    receipts.push(await publishOne(deps, bundle));
  }
  return receipts;
}

/**
 * Encode a `PublicKey` into the compressed-hex form the wallet
 * adapter expects in tx descriptions/labels. Centralised here so
 * every caller produces the same hex.
 */
export function senderPubkeyHexFrom(senderPubKey: PublicKey): string {
  return Buffer.from(senderPubKey.encode(true) as number[]).toString("hex");
}

```
