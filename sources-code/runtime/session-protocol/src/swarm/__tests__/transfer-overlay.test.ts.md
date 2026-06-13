---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/transfer-overlay.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.080687+00:00
---

# runtime/session-protocol/src/swarm/__tests__/transfer-overlay.test.ts

```ts
/**
 * Phase C — overlay advertise + txid↔multicast unification.
 *  - rendezvous: a content reference deterministically derives its IPv6 group.
 *  - seeder advertisement: codec round-trips; overlaySeederRegistry binds to the
 *    infohash, drops expired ads, and round-trips through a fake overlay into a
 *    LayeredBrainClient locate().
 */
import { describe, expect, test } from 'bun:test';
import { publishFile, toHex, bytesEqual } from '@semantos/protocol-types';
import {
  multicastGroupForInfohash,
  multicastGroupForTxid,
  multicastGroupForRef,
} from '../transfer-rendezvous';
import { encodeSeederAd, decodeSeederAd, overlaySeederRegistry } from '../seeder-advertisement';
import { LayeredBrainClient } from '../layered-brain-client';
import { FakeBrainClient } from '../brain-client';

function fileOf(n: number, seed: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 7 + seed) & 0xff;
  return b;
}

describe('rendezvous — content reference → IPv6 multicast group', () => {
  test('derivation is deterministic and IPv6 link-local (ff02)', () => {
    const ih = toHex(publishFile(fileOf(2 * 1016, 1), 'a.bin').infohash);
    const a = multicastGroupForInfohash(ih);
    const b = multicastGroupForInfohash(ih);
    expect(a.group).toBe(b.group);
    expect(a.group.startsWith('ff02:')).toBe(true);
    expect(a.shardIndex).toBeGreaterThanOrEqual(0);
    expect(a.shardIndex).toBeLessThan(256); // default shardBits=8
  });

  test('different content can map to different groups; scope is configurable', () => {
    const r1 = multicastGroupForRef(new Uint8Array([0x00, 0, 0, 0, 0, 0, 0, 0]), { shardBits: 8 });
    const r2 = multicastGroupForRef(new Uint8Array([0xff, 0, 0, 0, 0, 0, 0, 0]), { shardBits: 8 });
    expect(r1.shardIndex).toBe(0);
    expect(r2.shardIndex).toBe(255);
    expect(r1.group).not.toBe(r2.group);
    // site scope → ff05
    const site = multicastGroupForRef(new Uint8Array([1, 2, 3, 4]), { scope: 'site' });
    expect(site.group.startsWith('ff05:')).toBe(true);
  });

  test('txid derivation reverses display order (internal byte order)', () => {
    const txid = 'aa' + '00'.repeat(31); // display order
    const viaTxid = multicastGroupForTxid(txid);
    // internal order = reversed → first byte 0x00 → shardIndex 0
    expect(viaTxid.shardIndex).toBe(0);
  });
});

describe('seeder advertisement codec + overlay registry', () => {
  test('encode/decode round-trips all fields', () => {
    const pub = publishFile(fileOf(3 * 1016, 2), 'b.bin');
    const bca = new Uint8Array(16).fill(7);
    const ad = {
      infohash: pub.infohash,
      address: 'udp6://[ff02::1]:41999',
      bca,
      bitfield: new Uint8Array([1, 0, 1]),
      expiresAtMs: 1_700_000_000_000,
    };
    const decoded = decodeSeederAd(encodeSeederAd(ad))!;
    expect(decoded).not.toBeNull();
    expect(bytesEqual(decoded.infohash, pub.infohash)).toBe(true);
    expect(decoded.address).toBe(ad.address);
    expect(decoded.bca && bytesEqual(decoded.bca, bca)).toBe(true);
    expect(bytesEqual(decoded.bitfield, ad.bitfield)).toBe(true);
    expect(decoded.expiresAtMs).toBe(ad.expiresAtMs);
  });

  test('all-zero bca decodes to undefined; garbage decodes to null', () => {
    const pub = publishFile(fileOf(2 * 1016, 3), 'c.bin');
    const noBca = decodeSeederAd(encodeSeederAd({ infohash: pub.infohash, address: 'x', bitfield: new Uint8Array([1]), expiresAtMs: 0 }))!;
    expect(noBca.bca).toBeUndefined();
    expect(decodeSeederAd(new Uint8Array([9, 9, 9]))).toBeNull();
  });

  test('overlaySeederRegistry: advertise→lookup through a fake overlay, expiry drops stale', async () => {
    const pub = publishFile(fileOf(4 * 1016, 4), 'd.bin');
    const hashHex = toHex(pub.infohash);
    const store = new Map<string, Uint8Array[]>();
    let clock = 1000;

    const registry = overlaySeederRegistry({
      submit: async (bytes, h) => { const a = store.get(h) ?? []; a.push(bytes); store.set(h, a); },
      query: async h => store.get(h) ?? [],
      now: () => clock,
      ttlMs: 500,
    });

    await registry.advertise!(hashHex, { address: 'live-seeder', bitfield: new Uint8Array([1]) });
    let found = await registry.lookup(hashHex);
    expect(found.map(s => s.address)).toEqual(['live-seeder']);

    // Advance past TTL — the advertisement expires and is dropped.
    clock += 1000;
    found = await registry.lookup(hashHex);
    expect(found).toEqual([]);
  });

  test('overlay registry drives LayeredBrainClient seeder discovery', async () => {
    const pub = publishFile(fileOf(3 * 1016, 5), 'e.bin');
    const hashHex = toHex(pub.infohash);
    const store = new Map<string, Uint8Array[]>();
    const registry = overlaySeederRegistry({
      submit: async (bytes, h) => { const a = store.get(h) ?? []; a.push(bytes); store.set(h, a); },
      query: async h => store.get(h) ?? [],
    });

    const layered = new LayeredBrainClient({ inner: new FakeBrainClient(), registry });
    await layered.announce({ infohash: pub.infohash, address: 'announced-seeder', bitfield: new Uint8Array([1]) });
    const res = await layered.locate(pub.infohash);
    expect(res.seeders.map(s => s.address)).toEqual(['announced-seeder']);
  });
});

```
