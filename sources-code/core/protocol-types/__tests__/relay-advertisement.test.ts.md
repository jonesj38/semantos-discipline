---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/relay-advertisement.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.854131+00:00
---

# core/protocol-types/__tests__/relay-advertisement.test.ts

```ts
/**
 * Relay-advertisement overlay message tests.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §13.4. Pins the
 * canonical wire form so the relay (writer) and the originator (reader)
 * can't drift independently.
 */
import { describe, expect, test } from 'bun:test';
import {
  RELAY_ADVERTISEMENT_TOPIC,
  RELAY_ADVERTISEMENT_VERSION_V1,
  encodeRelayAdvertisement,
  decodeRelayAdvertisement,
  relayAdvertisementSigningInput,
  isAdvertisementCurrent,
  pathEndpointsMatch,
  type RelayAdvertisement,
} from '../src/overlay/relay-advertisement';

function fillBytes(n: number, seed: number): Uint8Array {
  const buf = new Uint8Array(n);
  for (let i = 0; i < n; i++) buf[i] = (i * 13 + seed) & 0xff;
  return buf;
}

function exampleAd(over: Partial<RelayAdvertisement> = {}): RelayAdvertisement {
  return {
    version: RELAY_ADVERTISEMENT_VERSION_V1,
    relayBca: fillBytes(16, 1),
    typeHashPath: {
      typeHashes: [fillBytes(32, 2), fillBytes(32, 3)],
    },
    pricePerCellSats: 50n,
    subscriberSetReach: fillBytes(32, 4),
    validNotBefore: 1_715_000_000_000n,
    validNotAfter: 1_715_003_600_000n,
    flowLabel: 0n,
    nonce: fillBytes(16, 5),
    signature: fillBytes(64, 6),
    ...over,
  };
}

describe('relay advertisement topic + version', () => {
  test('topic name is BRC-87-compliant and matches the brief', () => {
    expect(RELAY_ADVERTISEMENT_TOPIC).toBe('tm_mnca_relay_ads');
    expect(/^[a-z_]{1,50}$/.test(RELAY_ADVERTISEMENT_TOPIC)).toBe(true);
  });

  test('schema version is stable at 1', () => {
    expect(RELAY_ADVERTISEMENT_VERSION_V1).toBe(1);
  });
});

describe('relay advertisement encode/decode round-trip', () => {
  test('encode → decode preserves every field bit-exact (length-2 path)', () => {
    const ad = exampleAd();
    const buf = encodeRelayAdvertisement(ad);
    // Layout: 4 + 16 + 4 + 2*32 + 8 + 32 + 8 + 8 + 8 + 16 + 64 = 232 bytes.
    expect(buf.length).toBe(232);

    const decoded = decodeRelayAdvertisement(buf);
    expect(decoded.version).toBe(ad.version);
    expect(Array.from(decoded.relayBca)).toEqual(Array.from(ad.relayBca));
    expect(decoded.typeHashPath.typeHashes.length).toBe(2);
    expect(Array.from(decoded.typeHashPath.typeHashes[0]!)).toEqual(
      Array.from(ad.typeHashPath.typeHashes[0]!),
    );
    expect(Array.from(decoded.typeHashPath.typeHashes[1]!)).toEqual(
      Array.from(ad.typeHashPath.typeHashes[1]!),
    );
    expect(decoded.pricePerCellSats).toBe(50n);
    expect(Array.from(decoded.subscriberSetReach)).toEqual(Array.from(ad.subscriberSetReach));
    expect(decoded.validNotBefore).toBe(ad.validNotBefore);
    expect(decoded.validNotAfter).toBe(ad.validNotAfter);
    expect(decoded.flowLabel).toBe(ad.flowLabel);
    expect(Array.from(decoded.nonce)).toEqual(Array.from(ad.nonce));
    expect(Array.from(decoded.signature)).toEqual(Array.from(ad.signature));
  });

  test('encode → decode round-trips a longer typed path (length 4)', () => {
    const ad = exampleAd({
      typeHashPath: {
        typeHashes: [fillBytes(32, 10), fillBytes(32, 11), fillBytes(32, 12), fillBytes(32, 13)],
      },
    });
    const buf = encodeRelayAdvertisement(ad);
    // 232 bytes (N=2) + 2 extra hops * 32 bytes = 296 bytes.
    expect(buf.length).toBe(296);
    const decoded = decodeRelayAdvertisement(buf);
    expect(decoded.typeHashPath.typeHashes.length).toBe(4);
    for (let i = 0; i < 4; i++) {
      expect(Array.from(decoded.typeHashPath.typeHashes[i]!)).toEqual(
        Array.from(ad.typeHashPath.typeHashes[i]!),
      );
    }
  });

  test('decode rejects truncated buffers', () => {
    const ad = exampleAd();
    const buf = encodeRelayAdvertisement(ad);
    expect(() => decodeRelayAdvertisement(buf.subarray(0, buf.length - 1))).toThrow();
    expect(() => decodeRelayAdvertisement(new Uint8Array(10))).toThrow();
  });

  test('encode rejects paths shorter than 2', () => {
    expect(() =>
      encodeRelayAdvertisement(
        exampleAd({ typeHashPath: { typeHashes: [fillBytes(32, 7)] } }),
      ),
    ).toThrow();
  });

  test('encode rejects wrong-sized fields', () => {
    expect(() => encodeRelayAdvertisement(exampleAd({ relayBca: new Uint8Array(15) }))).toThrow();
    expect(() =>
      encodeRelayAdvertisement(exampleAd({ subscriberSetReach: new Uint8Array(31) })),
    ).toThrow();
    expect(() => encodeRelayAdvertisement(exampleAd({ nonce: new Uint8Array(15) }))).toThrow();
    expect(() => encodeRelayAdvertisement(exampleAd({ signature: new Uint8Array(63) }))).toThrow();
  });
});

describe('relay advertisement signing input', () => {
  test('signing input is everything except the 64-byte signature', () => {
    const ad = exampleAd();
    const full = encodeRelayAdvertisement(ad);
    const signed = relayAdvertisementSigningInput(ad);
    expect(signed.length).toBe(full.length - 64);
    // Signing input prefix matches the encoded form exactly.
    for (let i = 0; i < signed.length; i++) {
      expect(signed[i]).toBe(full[i]);
    }
  });

  test('signing input is independent of the signature field value', () => {
    const ad1 = exampleAd({ signature: fillBytes(64, 100) });
    const ad2 = exampleAd({ signature: fillBytes(64, 200) });
    const s1 = relayAdvertisementSigningInput(ad1);
    const s2 = relayAdvertisementSigningInput(ad2);
    expect(Array.from(s1)).toEqual(Array.from(s2));
  });
});

describe('advertisement validity', () => {
  test('isAdvertisementCurrent respects the [notBefore, notAfter) window', () => {
    const ad = exampleAd({ validNotBefore: 1000n, validNotAfter: 2000n });
    expect(isAdvertisementCurrent(ad, 999n)).toBe(false);
    expect(isAdvertisementCurrent(ad, 1000n)).toBe(true);
    expect(isAdvertisementCurrent(ad, 1500n)).toBe(true);
    expect(isAdvertisementCurrent(ad, 1999n)).toBe(true);
    expect(isAdvertisementCurrent(ad, 2000n)).toBe(false);
    expect(isAdvertisementCurrent(ad, 2001n)).toBe(false);
  });
});

describe('path endpoint matching', () => {
  test('pathEndpointsMatch is true when first/last typeHashes match', () => {
    const input = fillBytes(32, 50);
    const output = fillBytes(32, 51);
    const ad = exampleAd({ typeHashPath: { typeHashes: [input, output] } });
    expect(pathEndpointsMatch(ad, input, output)).toBe(true);
  });

  test('pathEndpointsMatch tolerates intermediate hops', () => {
    const input = fillBytes(32, 60);
    const output = fillBytes(32, 61);
    const mid = fillBytes(32, 62);
    const ad = exampleAd({ typeHashPath: { typeHashes: [input, mid, output] } });
    expect(pathEndpointsMatch(ad, input, output)).toBe(true);
  });

  test('pathEndpointsMatch is false when the endpoints differ', () => {
    const input = fillBytes(32, 70);
    const output = fillBytes(32, 71);
    const other = fillBytes(32, 72);
    const ad = exampleAd({ typeHashPath: { typeHashes: [input, output] } });
    expect(pathEndpointsMatch(ad, input, other)).toBe(false);
    expect(pathEndpointsMatch(ad, other, output)).toBe(false);
  });
});

```
