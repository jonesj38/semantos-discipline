---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-wallet-tx-sender.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.047621+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-wallet-tx-sender.ts

```ts
/**
 * Production adapter: BRC-100 wallet + SHIP broadcaster.
 *
 * Builds a `BundleTxSender` around a BRC-100 wallet's `createAction`
 * and a SHIP topic-manager submitter. The flow:
 *
 *   1. Serialise the locking script to hex.
 *   2. Call `wallet.createAction` with a single 1-sat output. The
 *      wallet handles input selection + signing.
 *   3. Parse the returned tx (BEEF or hex) into a `Transaction`.
 *   4. Submit to the SHIP broadcaster — best-effort; failures log
 *      but don't fail the publish (the tx is already signed +
 *      accepted by the wallet, so its txid is valid; overlay
 *      discovery may catch up on the next poll).
 *
 * No direct `@bsv/sdk` import outside of the parser — wallets and
 * SHIP submitters are both behind narrow interfaces, so the adapter
 * can be reused with metanet-desktop, bsv-desktop, future Plexus
 * SDK, wallet-toolbox, etc.
 */

import type { Transaction } from "@bsv/sdk";

import type { BundleTxSender } from "./bsv-bundle-ports.js";

/**
 * Binding interface for the BRC-100 wallet surface the tx-sender
 * adapter needs. Intentionally a *subset* of the project's
 * `WalletClient` — any object with `createAction` in the BRC-100
 * shape works.
 */
export interface BRC100WalletLike {
  createAction(req: {
    description: string;
    outputs: {
      lockingScript: string;
      satoshis: number;
      outputDescription?: string;
      basket?: string;
      tags?: string[];
    }[];
    labels?: string[];
  }): Promise<{ txid: string; tx?: string | number[]; rawTx?: string }>;
}

/** Binding for the SHIP submitter — production impl is `TopicManagerClient`. */
export interface ShipSubmitterLike {
  submit(tx: Transaction, topics: string[]): Promise<unknown>;
}

export interface WalletClientBundleTxSenderConfig {
  /** BRC-100 wallet — anything with a compatible `createAction`. */
  wallet: BRC100WalletLike;
  /** SHIP broadcaster — production impl is `TopicManagerClient`. */
  shipSubmitter: ShipSubmitterLike;
  /** BRC-87 topic the bundle ships on. Default: `tm_semantos_bundles`. */
  topic?: string;
  /** Output satoshis. Default 1. Overlay indexing doesn't care. */
  satoshis?: number;
  /** Wallet basket name for output tracking. Default: `semantos-bundles`. */
  basket?: string;
  /**
   * Tag outputs with the recipient certId so wallets can query their
   * own sent bundles by recipient. Default: true.
   */
  tagByRecipient?: boolean;
  /**
   * BEEF → Transaction parser. Injected so tests don't need to pull
   * in the whole `@bsv/sdk`. Default uses `Transaction.fromBEEF` /
   * `Transaction.fromHex`.
   */
  parseTx?: (txResponse: {
    txid: string;
    tx?: string | number[];
    rawTx?: string;
  }) => Transaction;
}

/**
 * Default Transaction parser — prefers BEEF (`tx` field, BRC-95),
 * falls back to hex (`rawTx`). Throws if neither is present.
 */
export function defaultParseTx(res: {
  txid: string;
  tx?: string | number[];
  rawTx?: string;
}): Transaction {
  // Delayed require-style import to keep the parse step swappable
  // while still pulling from `@bsv/sdk` in the production path.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { Transaction: Tx } = require("@bsv/sdk") as typeof import("@bsv/sdk");
  if (res.tx !== undefined) {
    const beef =
      typeof res.tx === "string"
        ? Buffer.from(res.tx, "hex")
        : Buffer.from(res.tx);
    return Tx.fromBEEF(Array.from(beef));
  }
  if (res.rawTx) return Tx.fromHex(res.rawTx);
  throw new Error(
    "bsv-overlay-bundle-client: wallet returned no tx or rawTx — cannot submit to SHIP",
  );
}

/**
 * Build a `BundleTxSender` around a BRC-100 wallet + SHIP submitter.
 */
export function createWalletClientBundleTxSender(
  config: WalletClientBundleTxSenderConfig,
): BundleTxSender {
  const {
    wallet,
    shipSubmitter,
    topic = "tm_semantos_bundles",
    satoshis = 1,
    basket = "semantos-bundles",
    tagByRecipient = true,
    parseTx = defaultParseTx,
  } = config;

  return {
    async sendBundleTx({
      lockingScript,
      description,
      recipientCertId,
      senderPubkeyHex,
    }) {
      const lockingScriptHex = lockingScript.toHex();

      const created = await wallet.createAction({
        description: description.slice(0, 50),
        outputs: [
          {
            lockingScript: lockingScriptHex,
            satoshis,
            outputDescription: `bundle → ${recipientCertId.slice(0, 12)}`,
            basket,
            tags: tagByRecipient ? [`recipient:${recipientCertId}`] : undefined,
          },
        ],
        labels: ["semantos-bundle", `from:${senderPubkeyHex.slice(0, 12)}`],
      });

      if (!created.txid) {
        throw new Error(
          "bsv-overlay-bundle-client: wallet.createAction returned no txid",
        );
      }

      // Best-effort SHIP submission. If the broadcaster rejects we
      // leave the bundle in the wallet's UTXO set with a valid txid —
      // a later call could re-broadcast. Keeping publish durable
      // matters more than failing loudly here.
      try {
        const tx = parseTx(created);
        await shipSubmitter.submit(tx, [topic]);
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn(
          `[bsv-overlay-bundle-client] SHIP submit failed for txid=${created.txid} — tx is signed but not yet on the overlay`,
          err,
        );
      }

      return { txid: created.txid };
    },
  };
}

```
