---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-client.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.076474+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-client.test.ts

```ts
/**
 * SwarmClient — many torrents over one shared transport (the daemon engine).
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { bytesEqual } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmClient } from '../swarm-client';

function fileOf(n: number, seed: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 7 + seed) & 0xff;
  return b;
}
async function waitFor(pred: () => boolean, ms = 6000): Promise<boolean> {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    if (pred()) return true;
    await new Promise(r => setTimeout(r, 20));
  }
  return false;
}

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('SwarmClient — multi-torrent over one socket', () => {
  test('a seeder client serves two torrents; a leecher client downloads both at once', async () => {
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seeder = new SwarmClient({ transport: inMemorySwarmTransport(bus, 'seeder'), brain });
    const leecher = new SwarmClient({ transport: inMemorySwarmTransport(bus, 'leecher'), brain });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    const f1 = fileOf(10 * 1016 + 5, 1);
    const f2 = fileOf(15 * 1016, 2);
    const ih1 = await seeder.seed(f1, 'one.bin');
    const ih2 = await seeder.seed(f2, 'two.bin');
    expect(seeder.list().length).toBe(2);

    await leecher.add(ih1);
    await leecher.add(ih2);

    const done = await waitFor(() => leecher.list().filter(t => t.status === 'done').length === 2);
    expect(done).toBe(true);
    expect(bytesEqual(leecher.data(ih1)!, f1)).toBe(true);
    expect(bytesEqual(leecher.data(ih2)!, f2)).toBe(true);

    // Both torrents tracked, with names from their manifests.
    const list = leecher.list().sort((a, b) => a.name.localeCompare(b.name));
    expect(list.map(t => t.name)).toEqual(['one.bin', 'two.bin']);
    expect(list.every(t => t.haveCells === t.totalCells)).toBe(true);
  });

  test('remove stops tracking a torrent', async () => {
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seeder = new SwarmClient({ transport: inMemorySwarmTransport(bus, 'seeder'), brain });
    cleanups.push(() => seeder.stop());
    const ih = await seeder.seed(fileOf(3 * 1016, 9), 'x.bin');
    expect(seeder.list().length).toBe(1);
    expect(await seeder.remove(ih)).toBe(true);
    expect(seeder.list().length).toBe(0);
    expect(await seeder.remove(ih)).toBe(false);
  });
});

```
