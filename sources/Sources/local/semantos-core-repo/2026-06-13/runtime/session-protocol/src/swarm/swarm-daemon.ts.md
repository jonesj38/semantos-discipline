---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-daemon.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.054695+00:00
---

# runtime/session-protocol/src/swarm/swarm-daemon.ts

```ts
/**
 * SwarmDaemon — a JSON-RPC control surface over a SwarmClient. This is what a
 * UI (web / Tauri / CLI) drives: add a magnet, seed a file, list torrents,
 * remove. The engine (SwarmClient) does the work; the daemon is just routing +
 * file I/O + writing completed downloads to disk.
 *
 *   methods: seed {path,name?} → {infohash}
 *            add  {infohash,out?}            → {ok}
 *            list                            → {torrents:[...]}
 *            remove {infohash}               → {ok}
 *            wallet                          → {channels} (when a multi-channel serve policy is set)
 *
 * `SwarmDaemon.handle` is transport-free (unit-testable); `serveSwarmDaemon`
 * exposes it over HTTP JSON-RPC via Bun.serve.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { SwarmClient, type TorrentInfo } from './swarm-client';
import type { MultiChannelServePolicy } from './metered-flow';

export class SwarmDaemon {
  private readonly pendingWrites = new Map<string, string>(); // infohash → out path
  private readonly timer: ReturnType<typeof setInterval>;

  constructor(
    private readonly client: SwarmClient,
    /** Optional, for the wallet/channels view. */
    private readonly channels?: MultiChannelServePolicy,
  ) {
    this.timer = setInterval(() => this.flushWrites(), 200);
  }

  private flushWrites(): void {
    for (const [ih, out] of this.pendingWrites) {
      const bytes = this.client.data(ih);
      if (bytes) {
        writeFileSync(out, bytes);
        this.pendingWrites.delete(ih);
      }
    }
  }

  async handle(method: string, params: Record<string, unknown> = {}): Promise<unknown> {
    switch (method) {
      case 'seed': {
        const path = String(params.path);
        const bytes = new Uint8Array(readFileSync(path));
        const infohash = await this.client.seed(bytes, String(params.name ?? basename(path)));
        return { infohash };
      }
      case 'add': {
        const infohash = String(params.infohash);
        await this.client.add(infohash);
        if (params.out) this.pendingWrites.set(infohash, String(params.out));
        return { ok: true };
      }
      case 'list':
        return { torrents: this.client.list() satisfies TorrentInfo[] };
      case 'remove':
        return { ok: await this.client.remove(String(params.infohash)) };
      case 'wallet':
        return { channels: this.channels?.channelSummary().map(c => ({ flow: c.flowId, cells: c.cellsServed, owedSats: Number(c.owedSats) })) ?? [] };
      default:
        throw new Error(`unknown method: ${method}`);
    }
  }

  async stop(): Promise<void> {
    clearInterval(this.timer);
    await this.client.stop();
  }
}

export interface DaemonHandle {
  port: number;
  stop: () => Promise<void>;
}

/** Expose a SwarmDaemon over HTTP JSON-RPC (POST /rpc). */
export function serveSwarmDaemon(daemon: SwarmDaemon, port = 0): DaemonHandle {
  const server = Bun.serve({
    port,
    async fetch(req) {
      if (new URL(req.url).pathname !== '/rpc') return new Response('not found', { status: 404 });
      let body: { id?: number; method?: string; params?: Record<string, unknown> };
      try { body = await req.json(); } catch { return Response.json({ error: { code: -32700, message: 'parse error' } }, { status: 400 }); }
      try {
        const result = await daemon.handle(String(body.method), body.params ?? {});
        return Response.json({ jsonrpc: '2.0', id: body.id, result });
      } catch (e) {
        return Response.json({ jsonrpc: '2.0', id: body.id, error: { code: -32000, message: String((e as Error)?.message ?? e) } });
      }
    },
  });
  return { port: server.port, stop: async () => { server.stop(true); await daemon.stop(); } };
}

```
