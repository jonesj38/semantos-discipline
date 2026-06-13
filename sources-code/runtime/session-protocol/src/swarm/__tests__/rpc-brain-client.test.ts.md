---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/rpc-brain-client.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.079757+00:00
---

# runtime/session-protocol/src/swarm/__tests__/rpc-brain-client.test.ts

```ts
/**
 * RpcSwarmBrainClient mapping + hot-path discipline — M8.
 *
 * (1) The four verbs map onto verb.dispatch and parse the Zig walker responses
 *     correctly (against a mock RpcChannel).
 * (2) The brain is touched only on cold paths — a full N-cell download makes a
 *     CONSTANT number of brain calls (locate once), never one per cell. This is
 *     the load-bearing architectural guarantee.
 */
import { describe, expect, test } from 'bun:test';
import { publishFile, bytesEqual, toHex } from '@semantos/protocol-types';
import { RpcSwarmBrainClient, type RpcChannel } from '../rpc-brain-client';
import { FakeBrainClient, type SwarmBrainClient, type SwarmReceipt } from '../brain-client';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { SwarmSession } from '../swarm-session';

function fileOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 17 + 5) & 0xff;
  return b;
}

describe('RpcSwarmBrainClient — verb mapping', () => {
  test('publish / locate / announce / settle map + parse correctly', async () => {
    const calls: Array<{ method: string; params: any }> = [];
    const published = publishFile(fileOf(3000), 'rpc/file');
    const channel: RpcChannel = {
      async call(method, params: any) {
        calls.push({ method, params });
        switch (params.verb) {
          case 'publish': return { infohash: params.params.infohash, stored: true, anchorStatus: 'pending' };
          case 'locate': return {
            manifestKnown: true,
            manifestCellHex: toHex(published.manifestCell),
            anchorStatus: 'confirmed',
            seeders: [{ address: 'fe80::9', bitfield: 'ff', lastSeen: 42 }],
          };
          case 'announce': return { ok: true };
          case 'settle': return { recorded: (params.params.receipts as unknown[]).length };
          default: return {};
        }
      },
    };
    const client = new RpcSwarmBrainClient(channel);

    // publish
    await client.publish({ infohash: published.infohash, manifestCell: published.manifestCell, semanticPath: 'rpc/file' });
    expect(calls[0]!.params).toMatchObject({ extensionId: 'swarm', verb: 'publish' });
    expect(calls[0]!.params.params.infohash).toBe(toHex(published.infohash));
    expect(calls[0]!.params.params.manifestCellHex.length).toBe(2048);

    // locate (confirmed anchor → proof bound to this infohash)
    const loc = await client.locate(published.infohash);
    expect(loc.manifestCell && bytesEqual(loc.manifestCell, published.manifestCell)).toBe(true);
    expect(loc.seeders[0]!.address).toBe('fe80::9');
    expect([...loc.seeders[0]!.bitfield!]).toEqual([0xff]);
    expect(loc.anchorProof?.stateHash).toBe(toHex(published.infohash));

    // (transfer namespace covered separately below)
    // announce sends a hex bitfield
    await client.announce({ infohash: published.infohash, address: 'fe80::1', bitfield: new Uint8Array([0x0f]) });
    const ann = calls.find(c => c.params.verb === 'announce')!;
    expect(ann.params.params.bitfieldHex).toBe('0f');

    // settle
    const receipts: SwarmReceipt[] = [{ cellIndex: 0, payerCertId: 'p', txAnchor: 'ab', amount: 5, currency: 'sat' }];
    expect((await client.settle({ infohash: published.infohash, receipts })).recorded).toBe(1);
  });

  test('locate of an unknown infohash returns a null manifest', async () => {
    const channel: RpcChannel = { async call() { return { manifestKnown: false }; } };
    const loc = await new RpcSwarmBrainClient(channel).locate(new Uint8Array(32));
    expect(loc.manifestCell).toBeNull();
    expect(loc.seeders).toEqual([]);
  });

  test('default namespace is "swarm"; "transfer" routes to the canonical primitive', async () => {
    const seen: string[] = [];
    const channel: RpcChannel = {
      async call(_m, params: any) { seen.push(params.extensionId); return { manifestKnown: false }; },
    };
    await new RpcSwarmBrainClient(channel).locate(new Uint8Array(32));
    await new RpcSwarmBrainClient(channel, 'transfer').locate(new Uint8Array(32));
    expect(seen).toEqual(['swarm', 'transfer']);
  });
});

/** Wraps a SwarmBrainClient and counts calls per method. */
class CountingBrain implements SwarmBrainClient {
  counts = { publish: 0, locate: 0, announce: 0, settle: 0 };
  constructor(private readonly inner: SwarmBrainClient) {}
  publish(a: any) { this.counts.publish++; return this.inner.publish(a); }
  locate(h: Uint8Array) { this.counts.locate++; return this.inner.locate(h); }
  announce(a: any) { this.counts.announce++; return this.inner.announce(a); }
  settle(a: any) { this.counts.settle++; return this.inner.settle(a); }
}

describe('hot-path discipline — no per-cell RPC', () => {
  test('a 40-cell download touches the brain a constant number of times', async () => {
    const file = fileOf(40 * 1016);
    const published = publishFile(file, 'hotpath/file');
    const brain = new CountingBrain(new FakeBrainClient());
    const bus = new SwarmBus();
    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain });
    const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leech'), brain });

    await seeder.seed(published);
    const got = await leecher.download(published.infohash);
    expect(bytesEqual(got, file)).toBe(true);

    // Cold path only: publish + announce on seed, locate once on download.
    expect(brain.counts.locate).toBe(1);
    expect(brain.counts.publish).toBe(1);
    const total = brain.counts.publish + brain.counts.locate + brain.counts.announce + brain.counts.settle;
    // Independent of the 40 cells transferred — NOT O(cells).
    expect(total).toBeLessThanOrEqual(4);

    await seeder.stop();
    await leecher.stop();
  });
});

```
