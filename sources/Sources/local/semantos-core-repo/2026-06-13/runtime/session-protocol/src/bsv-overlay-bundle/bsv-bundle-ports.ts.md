---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.048718+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-ports.ts

```ts
/**
 * Narrow ports for the BSV overlay bundle client.
 *
 * The client doesn't talk to `@bsv/sdk` directly — it talks to two
 * narrow ports. Production code composes real adapters around
 * `WalletClient`, `TopicManagerClient`, `LookupServiceClient`. Gate
 * tests inject fakes and assert wire format + polling behaviour
 * without an RPC endpoint, funded keys, or network I/O.
 */

import type { SignedBundle } from "../bundle-envelope.js";

// ── Publishing port ─────────────────────────────────────────────

/**
 * Port for the "build tx + submit to overlay topic" half of
 * `publishBundle`. The production adapter binds
 * `WalletClient.createAction` + `TopicManagerClient.submit`; tests
 * pass a synchronous fake that records calls.
 *
 * The client hands the port a `lockingScript` and expects a stable
 * txid in return. Fee / basket / tags policy belongs in the adapter,
 * not the client — different wallets have different quirks.
 */
export interface BundleTxSender {
  /**
   * Build, sign, and submit a transaction carrying the bundle output.
   * Returns the txid the broadcaster / wallet settled on.
   */
  sendBundleTx(args: {
    /** The PushDrop locking script to embed as the bundle output. */
    lockingScript: import("@bsv/sdk").LockingScript;
    /** Human-readable description for wallet audit + logging. */
    description: string;
    /** Recipient certId — available for tagging / basketing. */
    recipientCertId: string;
    /** Sender pubkey hex — available for the tx description / logs. */
    senderPubkeyHex: string;
  }): Promise<{ txid: string }>;
}

// ── Lookup / poll port ─────────────────────────────────────────

/**
 * Port for the BRC-24 lookup side. The production adapter wraps
 * `LookupServiceClient` against `ls_semantos_bundles_by_recipient`;
 * tests return a scripted list of bundles per poll.
 *
 * Returning already-decoded `SignedBundle<T>` keeps the client pure —
 * decoding lives in the adapter alongside `decodeBundlePushDrop` so
 * the port contract is "give me addressed bundles, any shape
 * failures silently dropped."
 */
export interface BundleLookupPoller {
  /**
   * Fetch new bundles addressed to `recipientCertId` since the last
   * poll. The adapter tracks whatever cursor the overlay needs
   * (txid-after, time-after, etc.). The client only dedupes by
   * `outpoint`.
   *
   * A successful poll with zero results must return `[]`, never
   * throw — the loop keeps polling as long as the underlying query
   * succeeds.
   */
  pollForRecipient(recipientCertId: string): Promise<PolledBundleResult<unknown>[]>;
}

/** A single bundle emitted by `BundleLookupPoller`. */
export interface PolledBundleResult<T = unknown> {
  /** Unique overlay outpoint, used for dedupe across polls: `"${txid}.${vout}"`. */
  outpoint: string;
  /** The decoded bundle envelope, pre-decoded by the adapter. */
  bundle: SignedBundle<T>;
}

```
