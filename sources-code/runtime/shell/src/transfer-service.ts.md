---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/transfer-service.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.367572+00:00
---

# runtime/shell/src/transfer-service.ts

```ts
/**
 * TransferService — the Metered Content Transfer primitive as SHELL SUBSTRATE.
 *
 * The shell owns ONE TransferService (like it owns ConversationStore + the
 * StorageAdapter). It is injected into ShellContext so every verb handler and
 * every cartridge can move content — `ctx.transfer.share(bytes, name)` /
 * `ctx.transfer.fetch(magnet)` — without knowing the wire, the discovery chain,
 * or the payment channel. Cartridges DON'T reimplement transfer; they invoke
 * this, exactly as conversation/streams are shell-native.
 *
 * Lazy by design: it opens no socket until the first share/fetch, so adding it
 * to the context is free for shells that never transfer anything.
 *
 * Layering note: the data plane (UDP multicast) is a node concern, so the live
 * default lives here in the node shell; a browser PWA drives this remotely over
 * the REPL/RPC channel rather than running the engine in-page.
 */

import {
  MeteredTransfer,
  createMeteredTransfer,
  LayeredBrainClient,
  InMemorySeederRegistry,
  FileBrainClient,
  syncCells,
  wssSwarmTransport,
  type SwarmTransport,
  type SwarmBrainClient,
  type SeederRegistry,
  type ManifestResolver,
  type WalletSpec,
  type TransferStatus,
  type FetchOptions,
  type CellSource,
  type CellSink,
  type SyncResult,
} from '@semantos/session-protocol';

export interface TransferServiceOptions {
  /** Build the data-plane transport. Default: node UDP multicast (lazy). */
  makeTransport?: () => SwarmTransport | Promise<SwarmTransport>;
  /** Cross-internet relay URL (ws://host:port). When set, the default transport
   *  is a WSS relay room instead of LAN multicast — works off-LAN through NATs. */
  relay?: string;
  /** Relay room (the swarm group). Default 'swarm'. */
  room?: string;
  /** Discovery brain leg. Default: FileBrainClient(trackerDir). */
  brain?: SwarmBrainClient;
  /** Tracker dir for the default FileBrainClient. */
  trackerDir?: string;
  /** Overlay seeder registry (SLAP). Default: in-memory. */
  registry?: SeederRegistry;
  /** Manifest content-availability resolver (overlay / UHRP). */
  manifestResolver?: ManifestResolver;
  /** Wallet seam for paid transfers. Default: free. */
  wallet?: WalletSpec;
  /** Seeder pubkey to pay. */
  payTo?: string;
  /** Price committed per cell. Default 1 sat. */
  pricePerCellSats?: number;
}

async function defaultNodeTransport(): Promise<SwarmTransport> {
  // Lazy import so the module graph doesn't pull node:dgram unless transfer is
  // actually used (keeps browser/test imports of ShellContext clean).
  const { udpMulticastTransport } = await import('@semantos/session-protocol');
  return udpMulticastTransport({ family: 'udp4', label: 'shell-transfer' });
}

export class TransferService {
  private mt?: MeteredTransfer;

  constructor(private readonly o: TransferServiceOptions = {}) {}

  /** Build (once) the underlying metered-transfer engine. */
  private async engine(): Promise<MeteredTransfer> {
    if (this.mt) return this.mt;
    const makeTransport = this.o.makeTransport
      ?? (this.o.relay
        ? () => wssSwarmTransport({ url: this.o.relay!, room: this.o.room ?? 'swarm' })
        : defaultNodeTransport);
    const transport = await makeTransport();
    const brain = new LayeredBrainClient({
      inner: this.o.brain ?? new FileBrainClient(this.o.trackerDir ?? '/tmp/semantos-transfer'),
      registry: this.o.registry ?? new InMemorySeederRegistry(),
      manifestResolver: this.o.manifestResolver,
    });
    this.mt = await createMeteredTransfer({
      transport,
      brain,
      wallet: this.o.wallet,
      payTo: this.o.payTo,
      pricePerCellSats: this.o.pricePerCellSats,
    });
    return this.mt;
  }

  /** Share content → magnet (infohash). */
  async share(bytes: Uint8Array, name: string): Promise<string> {
    return (await this.engine()).share(bytes, name);
  }

  /** Fetch content by magnet, resolving on completion. */
  async fetch(magnet: string, opts?: FetchOptions): Promise<Uint8Array> {
    return (await this.engine()).fetch(magnet, opts);
  }

  /** Reconcile a peer's cells into a sink over the metered transfer plane. */
  async sync(args: { from: CellSource; to: CellSink; sinceCursor?: string; name?: string }): Promise<SyncResult> {
    const seeder = await this.engine();
    return syncCells({ from: args.from, to: args.to, seeder, leecher: seeder, sinceCursor: args.sinceCursor, name: args.name });
  }

  /** In-flight transfers (empty until the engine is started). */
  list(): TransferStatus[] {
    return this.mt ? this.mt.list() : [];
  }

  status(magnet: string): TransferStatus | undefined {
    return this.mt?.status(magnet);
  }

  /** Whether the engine has been started (a transfer has run). */
  get started(): boolean {
    return this.mt !== undefined;
  }

  async stop(): Promise<void> {
    if (this.mt) await this.mt.stop();
    this.mt = undefined;
  }
}

```
