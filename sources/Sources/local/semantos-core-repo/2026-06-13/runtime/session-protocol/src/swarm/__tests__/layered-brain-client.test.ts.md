---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/layered-brain-client.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.074352+00:00
---

# runtime/session-protocol/src/swarm/__tests__/layered-brain-client.test.ts

```ts
/**
 * LayeredBrainClient — the degrade-gracefully discovery chain:
 *   brain → overlay SLAP seeder registry → manifest content-availability.
 * Proves: brain-hit short-circuit, SLAP seeder augmentation, manifest backfill
 * (with infohash verification + forgery rejection), all-miss, announce→advertise,
 * and an end-to-end transfer driven purely by the resolver leg.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { bytesEqual, publishFile, toHex, type LookupServiceClient } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient, type SeederInfo } from '../brain-client';
import {
  LayeredBrainClient,
  InMemorySeederRegistry,
  overlayManifestResolver,
  mergeSeeders,
  isManifestFor,
  type ManifestResolver,
} from '../layered-brain-client';
import { createMeteredTransfer } from '../metered-transfer';

function fileOf(n: number, seed: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 7 + seed) & 0xff;
  return b;
}

/** A manifest resolver that returns a fixed cell for one infohash. */
function fixedResolver(map: Map<string, Uint8Array>): ManifestResolver {
  return { async resolve(h) { return map.get(h) ?? null; } };
}

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('LayeredBrainClient — discovery fallback chain', () => {
  test('brain hit short-circuits but registry still augments seeders', async () => {
    const inner = new FakeBrainClient();
    const pub = publishFile(fileOf(3 * 1016, 1), 'x.bin');
    await inner.publish({ infohash: pub.infohash, manifestCell: pub.manifestCell, semanticPath: 'x.bin' });
    await inner.announce({ infohash: pub.infohash, address: 'brain-seeder', bitfield: new Uint8Array([1]) });

    const registry = new InMemorySeederRegistry();
    await registry.advertise(toHex(pub.infohash), { address: 'overlay-seeder', bitfield: new Uint8Array([1]) });

    const layered = new LayeredBrainClient({ inner, registry });
    const res = await layered.locate(pub.infohash);
    expect(res.manifestCell && bytesEqual(res.manifestCell, pub.manifestCell)).toBe(true);
    expect(res.seeders.map(s => s.address).sort()).toEqual(['brain-seeder', 'overlay-seeder']);
  });

  test('manifest backfill: empty brain, resolver supplies a verified manifest', async () => {
    const pub = publishFile(fileOf(5 * 1016, 2), 'y.bin');
    const resolver = fixedResolver(new Map([[toHex(pub.infohash), pub.manifestCell]]));
    const layered = new LayeredBrainClient({ inner: new FakeBrainClient(), manifestResolver: resolver });

    const res = await layered.locate(pub.infohash);
    expect(res.manifestCell && bytesEqual(res.manifestCell, pub.manifestCell)).toBe(true);
  });

  test('forged manifest (wrong infohash) is rejected', async () => {
    const real = publishFile(fileOf(4 * 1016, 3), 'a.bin');
    const other = publishFile(fileOf(4 * 1016, 99), 'b.bin');
    // Resolver returns the WRONG manifest cell for `real`'s infohash.
    const resolver = fixedResolver(new Map([[toHex(real.infohash), other.manifestCell]]));
    const layered = new LayeredBrainClient({ inner: new FakeBrainClient(), manifestResolver: resolver });

    const res = await layered.locate(real.infohash);
    expect(res.manifestCell).toBeNull();
  });

  test('all-miss returns null manifest + empty seeders', async () => {
    const pub = publishFile(fileOf(2 * 1016, 4), 'z.bin');
    const layered = new LayeredBrainClient({
      inner: new FakeBrainClient(),
      registry: new InMemorySeederRegistry(),
      manifestResolver: fixedResolver(new Map()),
    });
    const res = await layered.locate(pub.infohash);
    expect(res.manifestCell).toBeNull();
    expect(res.seeders).toEqual([]);
  });

  test('announce writes through to the registry (global discoverability)', async () => {
    const pub = publishFile(fileOf(2 * 1016, 5), 'q.bin');
    const registry = new InMemorySeederRegistry();
    const layered = new LayeredBrainClient({ inner: new FakeBrainClient(), registry });
    await layered.announce({ infohash: pub.infohash, address: 'me', bitfield: new Uint8Array([1]) });
    const seeders = await registry.lookup(toHex(pub.infohash));
    expect(seeders.map(s => s.address)).toEqual(['me']);
  });

  test('overlayManifestResolver decodes the first ≥1024B cell from a SLAP answer', async () => {
    const pub = publishFile(fileOf(3 * 1016, 6), 'm.bin');
    // Fake LookupLike: queryByContent returns a marker; decodeLookupOutputs yields the cell.
    const fake = {
      async queryByContent(_h: string) { return { type: 'output-list', outputs: [] } as any; },
      decodeLookupOutputs(_a: any) {
        return [{ txid: 'deadbeef', vout: 0, cellBytes: pub.manifestCell, semanticPath: 'm.bin', contentHash: pub.infohash, ownerPubKey: {} as any }];
      },
    } satisfies Pick<LookupServiceClient, 'queryByContent' | 'decodeLookupOutputs'>;

    const resolver = overlayManifestResolver(fake);
    const got = await resolver.resolve(toHex(pub.infohash));
    expect(got && isManifestFor(got, pub.infohash)).toBe(true);
  });

  test('end-to-end: resolver-only discovery drives a real download', async () => {
    const bus = new SwarmBus();
    const file = fileOf(8 * 1016 + 11, 7);
    const pub = publishFile(file, 'real.bin');

    // Seeder has its own brain + is serving on the shared bus.
    const seeder = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'seeder'), brain: new FakeBrainClient() });
    cleanups.push(() => seeder.stop());
    const magnet = await seeder.share(file, 'real.bin');
    expect(magnet).toBe(toHex(pub.infohash));

    // Leecher's brain is EMPTY — only the manifest resolver can supply the manifest.
    const leecherBrain = new LayeredBrainClient({
      inner: new FakeBrainClient(),
      manifestResolver: fixedResolver(new Map([[magnet, pub.manifestCell]])),
    });
    const leecher = await createMeteredTransfer({ transport: inMemorySwarmTransport(bus, 'leecher'), brain: leecherBrain });
    cleanups.push(() => leecher.stop());

    const got = await leecher.fetch(magnet, { timeoutMs: 8000 });
    expect(bytesEqual(got, file)).toBe(true);
  });

  test('mergeSeeders dedups by address/bca, existing wins', () => {
    const a: SeederInfo[] = [{ address: 'x', bitfield: new Uint8Array([1]) }];
    const b: SeederInfo[] = [{ address: 'x', bitfield: new Uint8Array([9]) }, { address: 'y', bitfield: new Uint8Array([1]) }];
    const merged = mergeSeeders(a, b);
    expect(merged.map(s => s.address).sort()).toEqual(['x', 'y']);
    expect(merged.find(s => s.address === 'x')!.bitfield![0]).toBe(1); // existing kept
  });
});

```
