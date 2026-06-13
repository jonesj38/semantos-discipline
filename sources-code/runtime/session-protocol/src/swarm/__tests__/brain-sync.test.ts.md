---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/brain-sync.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.079068+00:00
---

# runtime/session-protocol/src/swarm/__tests__/brain-sync.test.ts

```ts
/**
 * Phase E — brain-to-brain cell sync: the SECOND consumer of the transfer
 * primitive (not a torrent). Two brains' cell stores converge by moving the
 * delta over MeteredTransfer; a paid run proves the metered data plane carries
 * non-torrent payloads too.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { bytesEqual } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { createMeteredTransfer } from '../metered-transfer';
import {
  syncCells,
  packCellBatch,
  unpackCellBatch,
  cellHash,
  MemoryCellStore,
  CELL_BYTES,
} from '../brain-sync';
import { MeteredFlowVerifier, MeteredFlowServePolicy, PrivateKey } from '../metered-flow';

/** A deterministic, content-distinct 1024-byte cell. */
function cellOf(seed: number): Uint8Array {
  const c = new Uint8Array(CELL_BYTES);
  for (let i = 0; i < CELL_BYTES; i++) c[i] = (i * 31 + seed * 7) & 0xff;
  return c;
}

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('cell batch codec', () => {
  test('pack → unpack round-trips uniform 1024B cells', () => {
    const cells = [cellOf(1), cellOf(2), cellOf(3)];
    const back = unpackCellBatch(packCellBatch(cells));
    expect(back.length).toBe(3);
    cells.forEach((c, i) => expect(bytesEqual(back[i], c)).toBe(true));
  });
});

describe('brain-to-brain cell sync (the second consumer)', () => {
  test('two stores converge: the sink gains exactly the cells it lacked', async () => {
    const bus = new SwarmBus();
    const A = new MemoryCellStore(); // authority
    const B = new MemoryCellStore(); // syncs from A

    // A holds 5 cells; B already has 2 of them.
    const cells = [cellOf(10), cellOf(11), cellOf(12), cellOf(13), cellOf(14)];
    for (const c of cells) A.put(c);
    B.put(cells[0]); B.put(cells[1]); // shared prefix

    // The transfer's manifest discovery is shared (overlay/LayeredBrainClient in
    // production); a single FakeBrainClient stands in. The cell stores A/B — the
    // two brains being reconciled — stay separate.
    const discovery = new FakeBrainClient();
    const seeder = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'A'), brain: discovery });
    const leecher = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'B'), brain: discovery });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    const res = await syncCells({ from: A, to: B, seeder, leecher, timeoutMs: 8000 });
    expect(res.transferred).toBe(3); // only the missing 3 moved
    expect(B.size).toBe(5);          // B converged to A

    // Every A cell is now in B, byte-exact.
    for (const c of cells) {
      const h = cellHash(c);
      expect(await B.has(h)).toBe(true);
      expect(bytesEqual((await B.getCell(h))!, c)).toBe(true);
    }
  });

  test('a no-op sync (sink already has everything) moves nothing', async () => {
    const bus = new SwarmBus();
    const A = new MemoryCellStore();
    const B = new MemoryCellStore();
    [cellOf(1), cellOf(2)].forEach(c => { A.put(c); B.put(c); });

    const discovery = new FakeBrainClient();
    const seeder = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'A'), brain: discovery });
    const leecher = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'B'), brain: discovery });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    const res = await syncCells({ from: A, to: B, seeder, leecher });
    expect(res.transferred).toBe(0);
    expect(res.magnet).toBeUndefined();
  });

  test('PAID sync: the metered data plane carries a cell batch and the seeder is paid', async () => {
    const bus = new SwarmBus();
    const A = new MemoryCellStore();
    const B = new MemoryCellStore();
    const batch = [cellOf(20), cellOf(21), cellOf(22), cellOf(23)];
    for (const c of batch) A.put(c);

    const seederKey = PrivateKey.fromRandom();
    const leecherKey = PrivateKey.fromRandom();

    // Seeder charges per cell + verifies the leecher's MFP commitments (signed
    // by the leecher's wallet key); leecher funds a channel to the seeder.
    const servePolicy = new MeteredFlowServePolicy(
      new MeteredFlowVerifier(seederKey, 'swarm.cell', 1),
      leecherKey.toPublicKey().toString(),
      1,
    );
    const discovery = new FakeBrainClient();
    const seeder = await createMeteredTransfer({
      transport: inMemorySwarmTransport(bus, 'A'),
      brain: discovery,
      servePolicy,
    });
    const leecher = await createMeteredTransfer({
      transport: inMemorySwarmTransport(bus, 'B'),
      brain: discovery,
      wallet: { mode: 'headless', keyHex: leecherKey.toHex() },
      payTo: seederKey.toPublicKey().toString(),
      pricePerCellSats: 1,
    });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    const res = await syncCells({ from: A, to: B, seeder, leecher, timeoutMs: 12000 });
    expect(res.transferred).toBe(4);
    expect(B.size).toBe(4);
    // The seeder served the batch and holds a settlement commitment.
    expect(servePolicy.servedCount()).toBeGreaterThan(0);
    expect(servePolicy.finalCommitment()).not.toBeNull();
  });
});

```
