---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/metered-transfer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.075550+00:00
---

# runtime/session-protocol/src/swarm/__tests__/metered-transfer.test.ts

```ts
/**
 * MeteredTransfer — the transfer.* facade over the swarm engine.
 * Proves share→fetch round-trips and that fetch() resolves on completion,
 * over the in-memory transport (the same engine the daemon/torrent client use).
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { bytesEqual } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { createMeteredTransfer, MeteredTransfer } from '../metered-transfer';

function fileOf(n: number, seed: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 7 + seed) & 0xff;
  return b;
}

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('MeteredTransfer — transfer.* primitive', () => {
  test('share → fetch round-trips bytes, fetch resolves on completion', async () => {
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seeder = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'seeder'), brain });
    const leecher = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'leecher'), brain });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    const file = fileOf(12 * 1016 + 17, 3);
    const magnet = await seeder.share(file, 'doc.bin');
    expect(magnet).toMatch(/^[0-9a-f]{64}$/);
    expect(seeder.list()[0].kind).toBe('seed');

    const got = await leecher.fetch(magnet, { timeoutMs: 8000 });
    expect(bytesEqual(got, file)).toBe(true);
    expect(leecher.status(magnet)?.status).toBe('done');
  });

  test('createMeteredTransfer is a no-op pay setup when wallet is none (free transfer)', async () => {
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const mt = await createMeteredTransfer({
      transport: inMemorySwarmTransport(bus, 'n'),
      brain,
      wallet: { mode: 'none' },
    });
    cleanups.push(() => mt.stop());
    expect(mt).toBeInstanceOf(MeteredTransfer);
    const m = await mt.share(fileOf(2 * 1016, 1), 'a.bin');
    expect(mt.status(m)?.status).toBe('seeding');
  });

  test('fetch rejects on timeout when nobody is seeding', async () => {
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const leecher = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'lonely'), brain });
    cleanups.push(() => leecher.stop());
    // Publish a manifest the leecher can locate, but with no seeders online.
    const seeder = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'ghost'), brain });
    const magnet = await seeder.share(fileOf(3 * 1016, 5), 'ghost.bin');
    await seeder.stop(); // seeder gone — leecher will locate the manifest but get no cells
    await expect(leecher.fetch(magnet, { timeoutMs: 300, pollMs: 10 })).rejects.toThrow(/timed out/);
  });
});

```
