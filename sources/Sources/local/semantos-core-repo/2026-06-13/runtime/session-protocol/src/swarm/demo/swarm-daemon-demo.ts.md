---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-daemon-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.083139+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-daemon-demo.ts

```ts
/**
 * Watch the torrent-client daemon work — two daemons (a seeder and a leecher)
 * over a shared bus, driven entirely through the JSON-RPC control API. Seeds
 * two files, downloads both on the leecher, prints the library as it fills.
 *
 *   bun run runtime/session-protocol/src/swarm/demo/swarm-daemon-demo.ts
 *
 * This is the engine a Vuze/qBittorrent-style UI drives: the same add/seed/
 * list/remove RPC, with a real socket swapped in for the in-memory bus.
 */

import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmClient } from '../swarm-client';
import { SwarmDaemon, serveSwarmDaemon } from '../swarm-daemon';

async function rpc(port: number, method: string, params: Record<string, unknown> = {}): Promise<any> {
  const r = await fetch(`http://localhost:${port}/rpc`, { method: 'POST', body: JSON.stringify({ id: 1, method, params }) });
  const j = (await r.json()) as { result?: any; error?: { message: string } };
  if (j.error) throw new Error(j.error.message);
  return j.result;
}

async function main() {
  console.log('━━━ paid-swarm client daemon (JSON-RPC control API) ━━━\n');
  const dir = mkdtempSync(join(tmpdir(), 'swarm-daemon-demo-'));
  const brain = new FakeBrainClient();
  const bus = new SwarmBus();
  const seeder = serveSwarmDaemon(new SwarmDaemon(new SwarmClient({ transport: inMemorySwarmTransport(bus, 'seeder'), brain })));
  const leecher = serveSwarmDaemon(new SwarmDaemon(new SwarmClient({ transport: inMemorySwarmTransport(bus, 'leecher'), brain })));
  console.log(`seeder daemon  : http://localhost:${seeder.port}/rpc`);
  console.log(`leecher daemon : http://localhost:${leecher.port}/rpc\n`);

  // Seed two files on the seeder daemon.
  const magnets: string[] = [];
  for (const [name, n] of [['ubuntu.iso', 40], ['movie.mp4', 80]] as const) {
    const path = join(dir, name);
    writeFileSync(path, Buffer.from(Uint8Array.from({ length: n * 1016 }, (_, i) => (i * 7 + n) & 0xff)));
    const { infohash } = await rpc(seeder.port, 'seed', { path });
    magnets.push(infohash);
    console.log(`seed  ${name.padEnd(11)} → magnet ${infohash.slice(0, 24)}…`);
  }
  console.log();

  // Add both magnets on the leecher daemon → concurrent downloads.
  for (const m of magnets) await rpc(leecher.port, 'add', { infohash: m, out: join(dir, `dl-${m.slice(0, 8)}`) });

  // Poll the library until both finish, printing progress.
  for (let tick = 0; tick < 200; tick++) {
    const { torrents } = await rpc(leecher.port, 'list');
    const line = torrents.map((t: any) => `${t.name || t.infohash.slice(0, 8)} ${t.haveCells}/${t.totalCells} ${t.status}`).join('  |  ');
    process.stdout.write(`\rlibrary: ${line}                `);
    if (torrents.length === 2 && torrents.every((t: any) => t.status === 'done')) break;
    await new Promise(r => setTimeout(r, 50));
  }
  console.log('\n');

  const final = (await rpc(leecher.port, 'list')).torrents;
  console.log(`✓ ${final.length} torrents downloaded over ONE shared socket; both now SEED what they fetched.`);

  await seeder.stop();
  await leecher.stop();
  process.exit(0);
}

void main();

```
