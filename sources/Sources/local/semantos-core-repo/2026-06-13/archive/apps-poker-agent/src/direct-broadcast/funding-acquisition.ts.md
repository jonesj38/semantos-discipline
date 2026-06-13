---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/funding-acquisition.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.782736+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/funding-acquisition.ts

```ts
/**
 * Funding-acquisition flows — `waitForFunding`, `ingestFunding`,
 * `preSplit`. Extracted from the engine class so the network polling
 * + fan-out builder can be tested independently.
 *
 * The pre-split builder takes a single large UTXO and emits N
 * smaller funding UTXOs partitioned across `streams` consumer
 * pools. The actual partition write hits `addToPool` so the atom
 * subscribers see the pools light up.
 */

import { P2PKH, Transaction, type PrivateKey, type PublicKey } from '@bsv/sdk';

import { addToPool } from './utxo-pool-manager';
import type { FundingUtxo } from './types';

export interface PollFundingOptions {
  address: string;
  timeoutMs?: number;
  /** Sleep between polls. Default 5000ms. */
  pollMs?: number;
  /** Override fetch (test injection). */
  fetcher?: typeof fetch;
  log?: (label: string, msg: string) => void;
}

/**
 * Poll WhatsOnChain for unspent UTXOs at `address`. Returns the
 * largest one wrapped as a `FundingUtxo`. Throws on timeout.
 */
export async function pollWhatsOnChainFunding(
  opts: PollFundingOptions,
): Promise<FundingUtxo> {
  const fetchFn = opts.fetcher ?? fetch;
  const timeoutMs = opts.timeoutMs ?? 300_000;
  const pollMs = opts.pollMs ?? 5000;
  const log = opts.log ?? (() => {});
  log('FUND', `Waiting for funding at: ${opts.address}`);

  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const resp = await fetchFn(
        `https://api.whatsonchain.com/v1/bsv/main/address/${opts.address}/unspent`,
      );
      if (resp.ok) {
        const utxos = (await resp.json()) as Array<{
          tx_hash: string;
          tx_pos: number;
          value: number;
        }>;
        if (utxos.length > 0) {
          const best = utxos.sort((a, b) => b.value - a.value)[0];
          log('FUND', `Found UTXO: ${best.tx_hash}:${best.tx_pos} (${best.value} sats)`);
          const txResp = await fetchFn(
            `https://api.whatsonchain.com/v1/bsv/main/tx/${best.tx_hash}/hex`,
          );
          const txHex = await txResp.text();
          return {
            txid: best.tx_hash,
            vout: best.tx_pos,
            satoshis: best.value,
            sourceTx: Transaction.fromHex(txHex),
          };
        }
      }
    } catch (err) {
      log('FUND', `Poll error: ${(err as Error).message}`);
    }
    await sleep(pollMs);
  }
  throw new Error('Funding timeout — no UTXO received');
}

/** Ingest a UTXO directly when the caller already has the raw tx hex. */
export function ingestFundingTx(txHex: string, vout: number): FundingUtxo {
  const sourceTx = Transaction.fromHex(txHex);
  const txid = sourceTx.id('hex') as string;
  const satoshis = Number(sourceTx.outputs[vout].satoshis);
  return { txid, vout, satoshis, sourceTx };
}

export interface PreSplitOptions {
  engineId: string;
  privateKey: PrivateKey;
  publicKey: PublicKey;
  funding: FundingUtxo;
  streams: number;
  splitSatoshis: number;
  /** Fixed cap. Falls back to auto-calc when omitted. */
  count?: number;
}

export interface PreSplitResult {
  tx: Transaction;
  txid: string;
  splits: number;
}

const FEE_PER_BYTE = 1;
const INPUT_SIZE = 148;
const OUTPUT_SIZE = 34;
const OVERHEAD = 10;

/** Estimate fan-out fee — duplicates the legacy formula exactly. */
export function estimateFanOutFee(numOutputs: number): number {
  return (OVERHEAD + INPUT_SIZE + OUTPUT_SIZE * (numOutputs + 1)) * FEE_PER_BYTE;
}

/**
 * Build (but do **not** broadcast) a fan-out tx splitting the
 * funding UTXO into `splits` outputs. The caller owns broadcast +
 * pool partitioning; this keeps the function pure-ish for tests.
 */
export async function buildFanOutTx(opts: PreSplitOptions): Promise<{
  tx: Transaction;
  splits: number;
  fee: number;
  change: number;
}> {
  const maxSplitsByFee = Math.floor(
    (opts.funding.satoshis - estimateFanOutFee(1)) /
      (opts.splitSatoshis + OUTPUT_SIZE * FEE_PER_BYTE),
  );
  const splits = opts.count
    ? Math.min(opts.count, maxSplitsByFee)
    : Math.min(maxSplitsByFee, opts.streams * 200);

  if (splits < opts.streams) {
    const minSats = opts.streams * opts.splitSatoshis + estimateFanOutFee(opts.streams);
    throw new Error(
      `Not enough funding for ${opts.streams} streams. Need at least ${minSats} sats, got ${opts.funding.satoshis}.`,
    );
  }

  const fee = estimateFanOutFee(splits);
  const p2pkh = new P2PKH();
  const lockingScript = p2pkh.lock(opts.publicKey.toAddress());
  const tx = new Transaction();
  tx.addInput({
    sourceTXID: opts.funding.txid,
    sourceOutputIndex: opts.funding.vout,
    sourceTransaction: opts.funding.sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(opts.privateKey),
  });
  for (let i = 0; i < splits; i++) {
    tx.addOutput({ lockingScript, satoshis: opts.splitSatoshis });
  }
  const totalOut = splits * opts.splitSatoshis;
  const change = opts.funding.satoshis - totalOut - fee;
  if (change > 546) {
    tx.addOutput({ lockingScript, satoshis: change });
  }
  await tx.sign();
  return { tx, splits, fee, change };
}

/** Partition `splits` outputs of `tx` round-robin across stream pools. */
export function partitionFanOut(
  engineId: string,
  tx: Transaction,
  splits: number,
  streams: number,
  splitSatoshis: number,
): void {
  const txid = tx.id('hex') as string;
  for (let i = 0; i < splits; i++) {
    const streamIdx = i % streams;
    addToPool(engineId, streamIdx, [
      { txid, vout: i, satoshis: splitSatoshis, sourceTx: tx },
    ]);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

```
