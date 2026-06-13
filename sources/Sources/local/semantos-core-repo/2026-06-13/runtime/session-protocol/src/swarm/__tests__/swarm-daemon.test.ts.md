---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-daemon.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.073758+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-daemon.test.ts

```ts
/**
 * SwarmDaemon — the JSON-RPC control surface, driven over real HTTP. Two
 * daemons (seeder + leecher) on a shared bus: seed a file, add the magnet,
 * watch it download + land on disk — all via add/seed/list RPC calls.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { publishFile, toHex } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmClient } from '../swarm-client';
import { SwarmDaemon, serveSwarmDaemon } from '../swarm-daemon';
import { LayeredBrainClient, type ManifestResolver } from '../layered-brain-client';

async function rpc(port: number, method: string, params: Record<string, unknown> = {}): Promise<any> {
  const r = await fetch(`http://localhost:${port}/rpc`, { method: 'POST', body: JSON.stringify({ id: 1, method, params }) });
  const j = (await r.json()) as { result?: unknown; error?: { message: string } };
  if (j.error) throw new Error(j.error.message);
  return j.result;
}
async function poll(pred: () => Promise<boolean>, ms = 6000): Promise<boolean> {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { if (await pred()) return true; await new Promise(r => setTimeout(r, 25)); }
  return false;
}

const cleanups: Array<() => Promise<void> | void> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('SwarmDaemon — JSON-RPC control API', () => {
  test('seed + add + list + download-to-disk over HTTP', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'swarm-daemon-'));
    cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seederD = new SwarmDaemon(new SwarmClient({ transport: inMemorySwarmTransport(bus, 'seeder'), brain }));
    const leecherD = new SwarmDaemon(new SwarmClient({ transport: inMemorySwarmTransport(bus, 'leecher'), brain }));
    const S = serveSwarmDaemon(seederD);
    const L = serveSwarmDaemon(leecherD);
    cleanups.push(() => S.stop(), () => L.stop());

    // seed a file via RPC
    const src = join(dir, 'in.bin');
    const data = Uint8Array.from({ length: 9 * 1016 }, (_, i) => (i * 5 + 1) & 0xff);
    writeFileSync(src, data);
    const { infohash } = await rpc(S.port, 'seed', { path: src, name: 'movie.bin' });
    expect(infohash.length).toBe(64);
    expect((await rpc(S.port, 'list')).torrents[0].name).toBe('movie.bin');

    // add the magnet on the leecher → download to out path
    const out = join(dir, 'out.bin');
    await rpc(L.port, 'add', { infohash, out });

    const done = await poll(async () => (await rpc(L.port, 'list')).torrents[0]?.status === 'done');
    expect(done).toBe(true);

    // the completed download lands on disk (flush timer)
    await poll(async () => existsSync(out));
    expect(new Uint8Array(readFileSync(out)).length).toBe(data.length);

    // remove it
    expect((await rpc(L.port, 'remove', { infohash })).ok).toBe(true);
    expect((await rpc(L.port, 'list')).torrents.length).toBe(0);
  });

  test('the torrent client resolves a magnet via LayeredBrainClient discovery', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'swarm-layered-'));
    cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
    const bus = new SwarmBus();

    const data = Uint8Array.from({ length: 7 * 1016 + 3 }, (_, i) => (i * 9 + 2) & 0xff);
    const pub = publishFile(data, 'global.bin');
    const magnet = toHex(pub.infohash);

    // Seeder daemon: its brain knows the manifest (it published it).
    const seederBrain = new FakeBrainClient();
    const seederD = new SwarmDaemon(new SwarmClient({ transport: inMemorySwarmTransport(bus, 'seeder'), brain: seederBrain }));

    // Leecher daemon: EMPTY inner brain — only the resolver leg (overlay/UHRP
    // stand-in) can supply the manifest, exactly the global-discovery path.
    const resolver: ManifestResolver = { async resolve(h) { return h === magnet ? pub.manifestCell : null; } };
    const leecherBrain = new LayeredBrainClient({ inner: new FakeBrainClient(), manifestResolver: resolver });
    const leecherD = new SwarmDaemon(new SwarmClient({ transport: inMemorySwarmTransport(bus, 'leecher'), brain: leecherBrain }));

    const S = serveSwarmDaemon(seederD);
    const L = serveSwarmDaemon(leecherD);
    cleanups.push(() => S.stop(), () => L.stop());

    const src = join(dir, 'g.bin');
    writeFileSync(src, data);
    const seeded = await rpc(S.port, 'seed', { path: src, name: 'global.bin' });
    expect(seeded.infohash).toBe(magnet);

    const out = join(dir, 'g.out');
    await rpc(L.port, 'add', { infohash: magnet, out });
    const done = await poll(async () => (await rpc(L.port, 'list')).torrents[0]?.status === 'done');
    expect(done).toBe(true);
    await poll(async () => existsSync(out));
    expect(new Uint8Array(readFileSync(out)).length).toBe(data.length);
  });
});

```
