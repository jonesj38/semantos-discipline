---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/metered-transfer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.054416+00:00
---

# runtime/session-protocol/src/swarm/metered-transfer.ts

```ts
/**
 * MeteredTransfer — the substrate's data-plane primitive: metered, verified,
 * content-addressed transfer/sync. The torrent client, brain-to-brain cell sync,
 * and any future consumer all drive THIS surface; the swarm engine
 * (SwarmClient/SwarmSession) is its default strategy, not the product.
 *
 * Public verbs (the `transfer.*` family):
 *   share(bytes, name) → magnet     seed content, return its infohash magnet
 *   fetch(magnet)      → bytes       resolve+download to completion (paid if a
 *                                    wallet + payee are configured)
 *   list() / status(magnet)          observe in-flight transfers
 *
 * Additive by design: this file adds NO behaviour to the swarm engine — it
 * composes SwarmClient + a pluggable SwarmBrainClient (the discovery strategy,
 * e.g. LayeredBrainClient: brain → overlay SLAP → UHRP) + the MFP wallet seam.
 */

import type { MfpFlowConfig } from '@semantos/protocol-types';
import { SwarmClient, type TorrentInfo } from './swarm-client';
import type { SwarmTransport } from './swarm-transport';
import type { SwarmBrainClient } from './brain-client';
import type { PayPolicy, ServePolicy } from './swarm-session';
import { MeteredFlowPayer, meteredFlowPayPolicy } from './metered-flow';
import { resolveWalletPort, type WalletSpec } from './swarm-wallet';

/** Transfer strategies. 'swarm' = the BitTorrent-style rarest-first engine. */
export type TransferStrategy = 'swarm';

export interface MeteredTransferOptions {
  /** The data-plane transport (UDP multicast today, WSS-ready). */
  transport: SwarmTransport;
  /** Discovery/control plane — brain, file, RPC, or LayeredBrainClient. */
  brain: SwarmBrainClient;
  /** Wallet seam for paid fetches. Default { mode: 'none' } (free transfer). */
  wallet?: WalletSpec;
  /** Seeder pubkey to pay (opens an MFP channel to them). Required to pay. */
  payTo?: string;
  /** Price the leecher commits per cell. Default 1 sat. */
  pricePerCellSats?: number;
  /** Optional serve policy (this node charges when it seeds). */
  servePolicy?: ServePolicy;
  /** Transfer strategy. Default 'swarm'. */
  strategy?: TransferStrategy;
}

/** A consumer-facing view of one transfer (magnet = infohash hex). */
export interface TransferStatus {
  magnet: string;
  name: string;
  kind: 'seed' | 'download';
  status: 'seeding' | 'downloading' | 'done' | 'error';
  totalCells: number;
  haveCells: number;
  error?: string;
}

export interface FetchOptions {
  /** Give up after this long. Default 30s. */
  timeoutMs?: number;
  /** Completion poll interval. Default 10ms. */
  pollMs?: number;
}

function randomFlowId(): string {
  return Buffer.from(crypto.getRandomValues(new Uint8Array(8))).toString('hex');
}

function toStatus(t: TorrentInfo): TransferStatus {
  return {
    magnet: t.infohash,
    name: t.name,
    kind: t.kind,
    status: t.status,
    totalCells: t.totalCells,
    haveCells: t.haveCells,
    error: t.error,
  };
}

const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));

/**
 * Build a paid MeteredTransfer. Async because opening the MFP channel
 * (MeteredFlowPayer.open) is async — mirrors swarm-daemon-cli.ts exactly.
 */
export async function createMeteredTransfer(opts: MeteredTransferOptions): Promise<MeteredTransfer> {
  const wallet: WalletSpec = opts.wallet ?? { mode: 'none' };
  let payPolicy: PayPolicy | undefined;

  if (wallet.mode !== 'none' && opts.payTo) {
    const walletPort = resolveWalletPort(wallet);
    if (walletPort) {
      const cfg: MfpFlowConfig = {
        commodityId: 'swarm.cell',
        ratePerUnitSats: opts.pricePerCellSats ?? 1,
        counterparty: opts.payTo,
        flowId: randomFlowId(),
        fundMode: 'metered',
        vaultCapSats: 1_000_000n,
        channelChunkSats: 1_000_000n,
        refillThresholdSats: 0n,
      };
      const payer = new MeteredFlowPayer(cfg, walletPort);
      await payer.open();
      payPolicy = meteredFlowPayPolicy(payer);
    }
  }

  const client = new SwarmClient({
    transport: opts.transport,
    brain: opts.brain,
    payPolicy,
    servePolicy: opts.servePolicy,
  });
  return new MeteredTransfer(client);
}

export class MeteredTransfer {
  constructor(private readonly client: SwarmClient) {}

  /** Share content. Returns the magnet (infohash hex) others fetch by. */
  async share(bytes: Uint8Array, name: string): Promise<string> {
    return this.client.seed(bytes, name);
  }

  /** Fetch content by magnet, resolving once the transfer completes. */
  async fetch(magnet: string, opts: FetchOptions = {}): Promise<Uint8Array> {
    const timeoutMs = opts.timeoutMs ?? 30_000;
    const pollMs = opts.pollMs ?? 10;
    await this.client.add(magnet);

    const start = Date.now();
    for (;;) {
      const s = this.status(magnet);
      if (s?.status === 'done') {
        const bytes = this.client.data(magnet);
        if (bytes) return bytes;
      }
      if (s?.status === 'error') {
        throw new Error(`transfer.fetch(${magnet.slice(0, 16)}…) failed: ${s.error ?? 'unknown'}`);
      }
      if (Date.now() - start > timeoutMs) {
        throw new Error(`transfer.fetch(${magnet.slice(0, 16)}…) timed out after ${timeoutMs}ms`);
      }
      await sleep(pollMs);
    }
  }

  /** Snapshot of every transfer this node is managing. */
  list(): TransferStatus[] {
    return this.client.list().map(toStatus);
  }

  /** Status of one transfer, or undefined if not tracked. */
  status(magnet: string): TransferStatus | undefined {
    return this.list().find(t => t.magnet === magnet);
  }

  /** Stop + forget one transfer. */
  async remove(magnet: string): Promise<boolean> {
    return this.client.remove(magnet);
  }

  /** Stop all transfers + tear down the transport. */
  async stop(): Promise<void> {
    return this.client.stop();
  }

  /** Escape hatch for consumers that need the underlying engine. */
  get engine(): SwarmClient {
    return this.client;
  }
}

```
