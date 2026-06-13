---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.055833+00:00
---

# runtime/session-protocol/src/swarm/swarm-client.ts

```ts
/**
 * SwarmClient — the multi-torrent session manager (a torrent client's engine).
 *
 * Runs MANY torrents (download + seed) over ONE shared transport. Every wire
 * frame carries its infohash and every SwarmSession self-filters, so one socket
 * serves all torrents: a SharedTransport fans each received frame to every
 * session's handler and each keeps only its own. A completed download keeps its
 * session alive (still answering REQUESTs) → it seeds what it fetched.
 *
 * This is the daemon's core; the JSON-RPC control surface (swarm-daemon.ts)
 * just drives add/remove/list/seed on it.
 */

import { publishFile, fromHex, toHex } from '@semantos/protocol-types';
import { SwarmSession, type PayPolicy, type ServePolicy } from './swarm-session';
import type { SwarmTransport, FrameHandler } from './swarm-transport';
import type { SwarmBrainClient } from './brain-client';

/** Wraps one real transport and hands out per-session views that share it. */
export class SharedTransport {
  private readonly viewHandlers = new Map<number, FrameHandler[]>();
  private nextId = 0;
  private started = false;

  constructor(private readonly real: SwarmTransport) {
    // One real onFrame fans out to every live view.
    this.real.onFrame((frame, from) => {
      for (const hs of this.viewHandlers.values()) for (const h of hs) h(frame, from);
    });
  }

  async start(): Promise<void> {
    if (!this.started) {
      this.started = true;
      await this.real.start();
    }
  }
  async stop(): Promise<void> {
    this.viewHandlers.clear();
    await this.real.stop();
  }

  /** A per-session transport view sharing the one real socket. */
  makeView(): { view: SwarmTransport; dispose: () => void } {
    const id = this.nextId++;
    const handlers: FrameHandler[] = [];
    this.viewHandlers.set(id, handlers);
    const view: SwarmTransport = {
      localAddress: () => this.real.localAddress(),
      start: () => this.start(), // idempotent — first session boots the socket
      stop: async () => {}, // a session ending must NOT kill the shared socket
      broadcast: frame => this.real.broadcast(frame),
      sendTo: (addr, frame) => this.real.sendTo(addr, frame),
      onFrame: h => handlers.push(h),
    };
    return { view, dispose: () => this.viewHandlers.delete(id) };
  }
}

export type TorrentKind = 'seed' | 'download';
export type TorrentStatus = 'seeding' | 'downloading' | 'done' | 'error';

export interface TorrentInfo {
  infohash: string;
  name: string;
  kind: TorrentKind;
  status: TorrentStatus;
  totalCells: number;
  haveCells: number;
  error?: string;
}

interface Entry {
  infohash: string;
  kind: TorrentKind;
  status: TorrentStatus;
  session: SwarmSession;
  dispose: () => void;
  bytes?: Uint8Array;
  error?: string;
}

export interface SwarmClientOptions {
  transport: SwarmTransport;
  brain: SwarmBrainClient;
  /** Applied to downloads (leecher pays). */
  payPolicy?: PayPolicy;
  /** Applied to seeds (seeder charges). */
  servePolicy?: ServePolicy;
}

export class SwarmClient {
  private readonly shared: SharedTransport;
  private readonly torrents = new Map<string, Entry>();

  constructor(private readonly opts: SwarmClientOptions) {
    this.shared = new SharedTransport(opts.transport);
  }

  /** Begin seeding a file. Returns its infohash (the magnet). */
  async seed(fileBytes: Uint8Array, name: string): Promise<string> {
    const published = publishFile(fileBytes, name);
    const ih = toHex(published.infohash);
    if (this.torrents.has(ih)) return ih;
    const { view, dispose } = this.shared.makeView();
    const session = new SwarmSession({ transport: view, brain: this.opts.brain, servePolicy: this.opts.servePolicy });
    await session.seed(published);
    this.torrents.set(ih, { infohash: ih, kind: 'seed', status: 'seeding', session, dispose });
    return ih;
  }

  /** Start downloading a torrent by infohash. Resolves once the download
   *  starts; progress/completion is observed via list()/data(). */
  async add(infohashHex: string): Promise<void> {
    if (this.torrents.has(infohashHex)) return;
    const { view, dispose } = this.shared.makeView();
    const session = new SwarmSession({ transport: view, brain: this.opts.brain, payPolicy: this.opts.payPolicy });
    const entry: Entry = { infohash: infohashHex, kind: 'download', status: 'downloading', session, dispose };
    this.torrents.set(infohashHex, entry);
    void session
      .download(fromHex(infohashHex))
      .then(bytes => { entry.bytes = bytes; entry.status = 'done'; }) // keeps seeding (session stays up)
      .catch(e => { entry.status = 'error'; entry.error = String((e as Error)?.message ?? e); });
  }

  /** Snapshot of every torrent the client is managing. */
  list(): TorrentInfo[] {
    return [...this.torrents.values()].map(e => {
      const p = e.session.progress();
      return {
        infohash: e.infohash,
        name: p.name,
        kind: e.kind,
        status: e.status,
        totalCells: p.totalCells,
        haveCells: p.heldCells,
        error: e.error,
      };
    });
  }

  /** Completed download bytes, if any. */
  data(infohashHex: string): Uint8Array | undefined {
    return this.torrents.get(infohashHex)?.bytes;
  }

  /** Stop + forget a torrent (stops seeding/leeching it). */
  async remove(infohashHex: string): Promise<boolean> {
    const e = this.torrents.get(infohashHex);
    if (!e) return false;
    e.dispose();
    await e.session.stop();
    this.torrents.delete(infohashHex);
    return true;
  }

  async stop(): Promise<void> {
    for (const e of this.torrents.values()) await e.session.stop();
    this.torrents.clear();
    await this.shared.stop();
  }
}

```
