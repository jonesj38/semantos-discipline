---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/mnca-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.861936+00:00
---

# core/protocol-types/__tests__/mnca-integration.test.ts

```ts
/**
 * MNCA integration test — composes the tick-1 wire-format modules with
 * the MNCA cell-type registry to demonstrate that a single canonical
 * 1024-byte cell survives the full layer-collapse round-trip:
 *
 *   mint (typeHash) → route (routing region) → checksum
 *     → anchor (pushdrop locking script) → recover (parse)
 *     → forward one hop (mutate routing region, re-checksum)
 *
 * plus the relay-advertisement matching that the originator uses to
 * select a relay for the `mnca.perturb → mnca.tile.injection` path.
 *
 * This is the "one cell, every layer" thesis exercised end-to-end in
 * pure types — no transport, no chain, no hardware. It pins that the
 * four modules compose without stepping on each other's header bytes.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, HEADER_SIZE, HeaderOffsets } from '../src/constants';
import {
  RoutingMode,
  RoutingFlag,
  RoutingRegionOffsets,
  writeRoutingRegion,
  readRoutingRegion,
  setRoutingChecksum,
  verifyRoutingChecksum,
  isRouted,
  type RoutingRegion,
} from '../src/cell-routing';
import {
  buildPushdropLockingScript,
  parsePushdropLockingScript,
  COMPRESSED_PUBKEY_SIZE,
} from '../src/cell-pushdrop';
import {
  encodeRelayAdvertisement,
  decodeRelayAdvertisement,
  pathEndpointsMatch,
  isAdvertisementCurrent,
  RELAY_ADVERTISEMENT_VERSION_V1,
  type RelayAdvertisement,
} from '../src/overlay/relay-advertisement';
import {
  MncaCellTypeName,
  mncaTypeHash,
} from '../src/mnca/cell-types';

function bca(seed: number): Uint8Array {
  const b = new Uint8Array(16);
  for (let i = 0; i < 16; i++) b[i] = (i + seed * 17) & 0xff;
  return b;
}

function compressedPubkey(seed: number): Uint8Array {
  const b = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
  b[0] = 0x02;
  for (let i = 1; i < COMPRESSED_PUBKEY_SIZE; i++) b[i] = (i * 3 + seed) & 0xff;
  return b;
}

/** Build a canonical 1024-byte cell carrying a given typeHash + payload. */
function mintCell(typeHash: Uint8Array, payloadSeed: number): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  // typeHash goes at header offset 30 (32 bytes).
  cell.set(typeHash.subarray(0, 32), HeaderOffsets.typeHash);
  // Fill the payload region (offset 256..1024) with deterministic data.
  for (let i = HEADER_SIZE; i < CELL_SIZE; i++) cell[i] = (i + payloadSeed) & 0xff;
  return cell;
}

describe('MNCA integration — one cell across the layers', () => {
  test('mint → route (3 hops) → checksum → pushdrop → recover → forward', async () => {
    // ── L4 Compute: mint a perturb cell with the canonical typeHash. ──
    const perturbHash = mncaTypeHash(MncaCellTypeName.PERTURB);
    const cell = mintCell(perturbHash, 7);
    expect(Array.from(cell.subarray(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32))).toEqual(
      Array.from(perturbHash),
    );

    // ── L3 Network: write a 3-hop source route into the routing region. ──
    const hop1 = bca(1);
    const hop2 = bca(2);
    const finalDest = bca(99);
    const region: RoutingRegion = {
      routingMode: RoutingMode.SOURCE_ROUTED,
      priority: 7,
      routingVersion: 1,
      routingFlags: RoutingFlag.USES_PUSHDROP_PAYMENT | RoutingFlag.PRIORITY,
      segmentsLeft: 3,
      hopCountBudget: 8,
      flowLabel: 0xfeedface_0000_0001n & 0xffffffffffffffffn,
      nextHopBca: hop1,
      finalDestBca: finalDest,
      routingChecksum: 0,
    };
    writeRoutingRegion(cell, region);
    setRoutingChecksum(cell);
    expect(isRouted(cell)).toBe(true);
    expect(verifyRoutingChecksum(cell)).toBe(true);

    // The typeHash must be untouched by the routing write (it sits at
    // offset 30, well before the 160..223 routing region).
    expect(Array.from(cell.subarray(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32))).toEqual(
      Array.from(perturbHash),
    );

    // ── L6 Money / L1 Storage: wrap the cell as a pushdrop UTXO. ──
    const ownerPubkey = compressedPubkey(5);
    const lockingScript = buildPushdropLockingScript(cell, ownerPubkey);
    expect(lockingScript.length).toBe(1063);

    // ── Recover the cell from the locking script (SPV verifier path). ──
    const { cellBytes, pubkey } = parsePushdropLockingScript(lockingScript);
    expect(cellBytes.length).toBe(CELL_SIZE);
    expect(Array.from(cellBytes)).toEqual(Array.from(cell));
    expect(Array.from(pubkey)).toEqual(Array.from(ownerPubkey));

    // The routing region survived the pushdrop round-trip bit-exact.
    expect(verifyRoutingChecksum(cellBytes)).toBe(true);
    const recovered = readRoutingRegion(cellBytes);
    expect(recovered.segmentsLeft).toBe(3);
    expect(Array.from(recovered.nextHopBca)).toEqual(Array.from(hop1));

    // ── L3 Network: forward one hop — mutate routing region in place. ──
    const forwarded = cellBytes.slice(); // a relay works on its own copy
    const r = readRoutingRegion(forwarded);
    r.segmentsLeft = r.segmentsLeft - 1;
    r.hopCountBudget = r.hopCountBudget - 1;
    r.nextHopBca = hop2; // rotate to the next hop
    writeRoutingRegion(forwarded, r);
    setRoutingChecksum(forwarded);

    const afterHop = readRoutingRegion(forwarded);
    expect(afterHop.segmentsLeft).toBe(2);
    expect(afterHop.hopCountBudget).toBe(7);
    expect(Array.from(afterHop.nextHopBca)).toEqual(Array.from(hop2));
    expect(verifyRoutingChecksum(forwarded)).toBe(true);

    // The cell's payload + typeHash are unchanged by forwarding.
    expect(Array.from(forwarded.subarray(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32))).toEqual(
      Array.from(perturbHash),
    );
    for (let i = HEADER_SIZE; i < CELL_SIZE; i++) {
      expect(forwarded[i]).toBe(cell[i]);
    }
  });

  test('originator selects a relay via type-path advertisement matching', async () => {
    // The originator wants `mnca.perturb → mnca.tile.injection`.
    const inputHash = mncaTypeHash(MncaCellTypeName.PERTURB);
    const outputHash = mncaTypeHash(MncaCellTypeName.TILE_INJECTION);

    const nowMs = 1_715_000_000_000n;
    // A wrong output type for the non-matching relay (some other 32-byte hash).
    const wrongOutputHash = new Uint8Array(32).fill(0xaa);
    const mkAd = (priceSats: bigint, relaySeed: number, matches: boolean): RelayAdvertisement => ({
      version: RELAY_ADVERTISEMENT_VERSION_V1,
      relayBca: bca(relaySeed),
      typeHashPath: {
        typeHashes: matches ? [inputHash, outputHash] : [inputHash, wrongOutputHash],
      },
      pricePerCellSats: priceSats,
      subscriberSetReach: new Uint8Array(32),
      validNotBefore: nowMs - 1000n,
      validNotAfter: nowMs + 3_600_000n,
      flowLabel: 0n,
      nonce: bca(relaySeed + 50).slice(0, 16),
      signature: new Uint8Array(64),
    });

    // Two matching relays (50 / 30 sats) + one non-matching (10 sats but
    // wrong output type — must be ignored despite being cheapest).
    const ads = [mkAd(50n, 1, true), mkAd(30n, 2, true), mkAd(10n, 3, false)];

    // Round-trip each through the wire form (relay published → originator reads).
    const onWire = ads.map(encodeRelayAdvertisement).map(decodeRelayAdvertisement);

    // Originator filters: current + endpoints match the desired path.
    const viable = onWire.filter(
      (ad) =>
        isAdvertisementCurrent(ad, nowMs) && pathEndpointsMatch(ad, inputHash, outputHash),
    );
    expect(viable.length).toBe(2); // the 10-sat non-matcher is excluded

    // Pick the cheapest viable relay.
    viable.sort((a, b) => (a.pricePerCellSats < b.pricePerCellSats ? -1 : 1));
    const chosen = viable[0]!;
    expect(chosen.pricePerCellSats).toBe(30n);
    expect(Array.from(chosen.relayBca)).toEqual(Array.from(bca(2)));
  });

  test('a cell typed for one transform is rejected by a mismatched advertisement', async () => {
    const perturbHash = mncaTypeHash(MncaCellTypeName.PERTURB);
    const snapshotHash = mncaTypeHash(MncaCellTypeName.SNAPSHOT);
    const tileTickHash = mncaTypeHash(MncaCellTypeName.TILE_TICK);

    // An advertisement for tile.tick → snapshot does NOT serve a
    // perturb → snapshot request.
    const ad: RelayAdvertisement = {
      version: RELAY_ADVERTISEMENT_VERSION_V1,
      relayBca: bca(1),
      typeHashPath: { typeHashes: [tileTickHash, snapshotHash] },
      pricePerCellSats: 5n,
      subscriberSetReach: new Uint8Array(32),
      validNotBefore: 0n,
      validNotAfter: 2n ** 63n,
      flowLabel: 0n,
      nonce: new Uint8Array(16),
      signature: new Uint8Array(64),
    };
    expect(pathEndpointsMatch(ad, perturbHash, snapshotHash)).toBe(false);
    // But it does serve the path it actually advertised.
    expect(pathEndpointsMatch(ad, tileTickHash, snapshotHash)).toBe(true);
  });
});

```
