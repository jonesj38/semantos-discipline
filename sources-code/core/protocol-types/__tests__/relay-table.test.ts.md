---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/relay-table.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.859770+00:00
---

# core/protocol-types/__tests__/relay-table.test.ts

```ts
/**
 * Relay service table + originator selection tests.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §13.4.
 */
import { describe, expect, test } from 'bun:test';
import {
  RelayServiceTable,
  emitAdvertisements,
  selectRelay,
  type RelayServiceEntry,
} from '../src/mnca/relay-table';
import {
  decodeRelayAdvertisement,
  encodeRelayAdvertisement,
  pathEndpointsMatch,
  isAdvertisementCurrent,
} from '../src/overlay/relay-advertisement';

function th(seed: number): Uint8Array {
  const h = new Uint8Array(32);
  for (let i = 0; i < 32; i++) h[i] = (i * 3 + seed) & 0xff;
  return h;
}
function reach(seed: number): Uint8Array {
  const r = new Uint8Array(32);
  for (let i = 0; i < 32; i++) r[i] = (i + seed) & 0xff;
  return r;
}
function bca(seed: number): Uint8Array {
  const b = new Uint8Array(16);
  for (let i = 0; i < 16; i++) b[i] = (i + seed * 7) & 0xff;
  return b;
}

// Deterministic stubs (no real crypto in protocol-types).
function stubNonceFactory(): () => Uint8Array {
  let counter = 0;
  return () => {
    const n = new Uint8Array(16);
    n[0] = counter++ & 0xff;
    return n;
  };
}
function stubSign(signingInput: Uint8Array): Uint8Array {
  // Deterministic 64-byte "signature": first byte = input length & 0xff.
  const sig = new Uint8Array(64);
  sig[0] = signingInput.length & 0xff;
  sig[1] = (signingInput.length >> 8) & 0xff;
  return sig;
}

const PERTURB = th(10);
const INJECTION = th(20);
const TICK = th(30);

describe('RelayServiceTable', () => {
  test('add / list / has / size', () => {
    const t = new RelayServiceTable();
    expect(t.size).toBe(0);
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 50n, subscriberSetReach: reach(1) });
    t.add({ inputTypeHash: INJECTION, outputTypeHash: TICK, pricePerCellSats: 30n, subscriberSetReach: reach(2) });
    expect(t.size).toBe(2);
    expect(t.has(PERTURB, INJECTION)).toBe(true);
    expect(t.has(TICK, PERTURB)).toBe(false);
    const list = t.list();
    expect(list.length).toBe(2);
    expect(list[0]!.pricePerCellSats).toBe(50n);
  });

  test('re-adding the same (input,output) pair overwrites the price', () => {
    const t = new RelayServiceTable();
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 50n, subscriberSetReach: reach(1) });
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 25n, subscriberSetReach: reach(1) });
    expect(t.size).toBe(1);
    expect(t.list()[0]!.pricePerCellSats).toBe(25n);
  });

  test('remove returns true when present, false otherwise', () => {
    const t = new RelayServiceTable();
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 50n, subscriberSetReach: reach(1) });
    expect(t.remove(PERTURB, INJECTION)).toBe(true);
    expect(t.remove(PERTURB, INJECTION)).toBe(false);
    expect(t.size).toBe(0);
  });

  test('stores copies — mutating the input after add does not corrupt the entry', () => {
    const t = new RelayServiceTable();
    const input = th(10);
    t.add({ inputTypeHash: input, outputTypeHash: INJECTION, pricePerCellSats: 50n, subscriberSetReach: reach(1) });
    input[0] ^= 0xff; // mutate caller's array
    expect(t.has(th(10), INJECTION)).toBe(true); // entry unaffected
  });

  test('rejects wrong-sized fields and negative price', () => {
    const t = new RelayServiceTable();
    expect(() => t.add({ inputTypeHash: new Uint8Array(31), outputTypeHash: INJECTION, pricePerCellSats: 1n, subscriberSetReach: reach(1) })).toThrow();
    expect(() => t.add({ inputTypeHash: PERTURB, outputTypeHash: new Uint8Array(33), pricePerCellSats: 1n, subscriberSetReach: reach(1) })).toThrow();
    expect(() => t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 1n, subscriberSetReach: new Uint8Array(16) })).toThrow();
    expect(() => t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: -1n, subscriberSetReach: reach(1) })).toThrow();
  });
});

describe('emitAdvertisements', () => {
  test('produces one signed ad per table entry with correct endpoints + window', () => {
    const t = new RelayServiceTable();
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 50n, subscriberSetReach: reach(1) });
    t.add({ inputTypeHash: INJECTION, outputTypeHash: TICK, pricePerCellSats: 30n, subscriberSetReach: reach(2) });

    const ads = emitAdvertisements(t, {
      relayBca: bca(1),
      validFromMs: 1_000n,
      validForMs: 3_600_000n,
      nonceFactory: stubNonceFactory(),
      signFn: stubSign,
    });
    expect(ads.length).toBe(2);

    // First ad matches the first entry's endpoints.
    expect(pathEndpointsMatch(ads[0]!, PERTURB, INJECTION)).toBe(true);
    expect(ads[0]!.pricePerCellSats).toBe(50n);
    expect(ads[0]!.validNotBefore).toBe(1_000n);
    expect(ads[0]!.validNotAfter).toBe(3_601_000n);
    expect(Array.from(ads[0]!.relayBca)).toEqual(Array.from(bca(1)));

    // Each ad carries the stub signature and round-trips through the wire form.
    for (const ad of ads) {
      expect(ad.signature.length).toBe(64);
      const wire = encodeRelayAdvertisement(ad);
      const back = decodeRelayAdvertisement(wire);
      expect(back.pricePerCellSats).toBe(ad.pricePerCellSats);
      expect(Array.from(back.signature)).toEqual(Array.from(ad.signature));
    }

    // Nonces are distinct across the two ads (anti-replay).
    expect(ads[0]!.nonce[0]).not.toBe(ads[1]!.nonce[0]);
  });

  test('emitted ads are current within their window', () => {
    const t = new RelayServiceTable();
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 1n, subscriberSetReach: reach(1) });
    const ads = emitAdvertisements(t, {
      relayBca: bca(1),
      validFromMs: 1_000n,
      validForMs: 1_000n,
      nonceFactory: stubNonceFactory(),
      signFn: stubSign,
    });
    expect(isAdvertisementCurrent(ads[0]!, 1_500n)).toBe(true);
    expect(isAdvertisementCurrent(ads[0]!, 2_000n)).toBe(false); // == validNotAfter, excluded
  });

  test('rejects bad relayBca, validForMs, nonce, signature sizes', () => {
    const t = new RelayServiceTable();
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: 1n, subscriberSetReach: reach(1) });
    const base = { relayBca: bca(1), validFromMs: 0n, validForMs: 1_000n, nonceFactory: stubNonceFactory(), signFn: stubSign };
    expect(() => emitAdvertisements(t, { ...base, relayBca: new Uint8Array(15) })).toThrow();
    expect(() => emitAdvertisements(t, { ...base, validForMs: 0n })).toThrow();
    expect(() => emitAdvertisements(t, { ...base, nonceFactory: () => new Uint8Array(8) })).toThrow();
    expect(() => emitAdvertisements(t, { ...base, signFn: () => new Uint8Array(32) })).toThrow();
  });

  test('empty table yields no ads', () => {
    const ads = emitAdvertisements(new RelayServiceTable(), {
      relayBca: bca(1),
      validFromMs: 0n,
      validForMs: 1_000n,
      nonceFactory: stubNonceFactory(),
      signFn: stubSign,
    });
    expect(ads.length).toBe(0);
  });
});

describe('selectRelay — originator demand side', () => {
  function mkTable(price: bigint): RelayServiceTable {
    const t = new RelayServiceTable();
    t.add({ inputTypeHash: PERTURB, outputTypeHash: INJECTION, pricePerCellSats: price, subscriberSetReach: reach(1) });
    return t;
  }
  function adsFrom(price: bigint, relaySeed: number, validFromMs: bigint, validForMs: bigint) {
    return emitAdvertisements(mkTable(price), {
      relayBca: bca(relaySeed),
      validFromMs,
      validForMs,
      nonceFactory: stubNonceFactory(),
      signFn: stubSign,
    });
  }

  test('picks the cheapest viable relay', () => {
    const now = 10_000n;
    const ads = [
      ...adsFrom(50n, 1, now - 1n, 100_000n),
      ...adsFrom(30n, 2, now - 1n, 100_000n),
      ...adsFrom(70n, 3, now - 1n, 100_000n),
    ];
    const sel = selectRelay(ads, PERTURB, INJECTION, now);
    expect(sel.viable.length).toBe(3);
    expect(sel.chosen!.pricePerCellSats).toBe(30n);
    expect(Array.from(sel.chosen!.relayBca)).toEqual(Array.from(bca(2)));
    // viable is sorted cheapest-first.
    expect(sel.viable.map((a) => a.pricePerCellSats)).toEqual([30n, 50n, 70n]);
  });

  test('excludes stale advertisements', () => {
    const now = 10_000n;
    const fresh = adsFrom(50n, 1, now - 1n, 100_000n);
    const stale = adsFrom(10n, 2, 0n, 5_000n); // expired well before now
    const sel = selectRelay([...fresh, ...stale], PERTURB, INJECTION, now);
    expect(sel.viable.length).toBe(1);
    expect(sel.chosen!.pricePerCellSats).toBe(50n); // cheap-but-stale 10n excluded
  });

  test('excludes wrong-endpoint advertisements', () => {
    const now = 10_000n;
    // A cheap relay that serves INJECTION → TICK, not PERTURB → INJECTION.
    const wrong = (() => {
      const t = new RelayServiceTable();
      t.add({ inputTypeHash: INJECTION, outputTypeHash: TICK, pricePerCellSats: 5n, subscriberSetReach: reach(9) });
      return emitAdvertisements(t, { relayBca: bca(9), validFromMs: now - 1n, validForMs: 100_000n, nonceFactory: stubNonceFactory(), signFn: stubSign });
    })();
    const right = adsFrom(50n, 1, now - 1n, 100_000n);
    const sel = selectRelay([...wrong, ...right], PERTURB, INJECTION, now);
    expect(sel.viable.length).toBe(1);
    expect(sel.chosen!.pricePerCellSats).toBe(50n);
  });

  test('returns null chosen when nothing matches', () => {
    const sel = selectRelay([], PERTURB, INJECTION, 10_000n);
    expect(sel.chosen).toBeNull();
    expect(sel.viable.length).toBe(0);
  });
});

```
